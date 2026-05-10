/*
 * bar: unified lemonbar controller. Replaces bar.sh + start.sh + watcher.sh.
 *
 * Architecture:
 *   - Single instance via flock on /tmp/lemonbar-bar.lock.
 *   - XRandR to detect primary monitor name + geometry.
 *   - Spawns lemonbar with that geometry, keeps its stdin pipe.
 *   - Spawns bspwm-desktops, reads its stdout (preformatted desktops string).
 *   - Subscribes to bspwm node/desktop events on a separate socket.
 *   - timerfd ticks every second to drive metric refresh.
 *   - select() multiplexes: timerfd + desktops pipe + bspwm event socket.
 *   - Metrics (CPU%, GHz, RAM, temp, date) cached with per-metric deadlines.
 *   - On fullscreen: XUnmapWindow lemonbar + top_padding 0.
 *     On exit fullscreen: XMapWindow lemonbar + top_padding BAR_HEIGHT.
 *
 * Build: gcc -O2 -Wall -o bar bar.c -lX11 -lXrandr
 */

#define _POSIX_C_SOURCE 200809L

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xrandr.h>

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/timerfd.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define LOCK_PATH         "/tmp/lemonbar-bar.lock"
#define BSPWM_DESKTOPS    "/lemonbar/bspwm-desktops"
#define LEMONBAR_BIN      "lemonbar"
#define LEMONBAR_FONT     "monospace:size=12"
#define LEMONBAR_BG       "#CC000000"
#define LEMONBAR_FG       "#FFFFFFFF"
#define BAR_HEIGHT        22

/* Refresh intervals (seconds) */
#define INT_CPU   2
#define INT_GHZ   5
#define INT_RAM   3
#define INT_TEMP  5
#define INT_DATE  60

/* ---------- state ---------- */

typedef struct {
    /* metric values rendered into the bar — buffers are oversized so gcc's
     * format-truncation analysis doesn't trip on theoretical worst cases. */
    char cpu_str[8];
    char ghz_str[24];
    char temp_str[32];
    char ram_str[64];
    char date_str[64];
    char desktops[4096]; /* from bspwm-desktops */

    /* CPU jiffies prev (for delta) */
    unsigned long prev_total, prev_idle;

    /* hwmon CPU sensor path resolved at startup; "" if none */
    char hwmon_temp[256];

    /* per-metric next-refresh deadlines (epoch seconds) */
    time_t next_cpu, next_ghz, next_ram, next_temp, next_date;
} State;

/* ---------- globals (for signal handlers and cleanup) ---------- */

static pid_t g_lemonbar_pid    = -1;
static pid_t g_desktops_pid    = -1;
static Display *g_dpy          = NULL;
static Window g_lemonbar_win   = None;
static int g_running           = 1;

/* ---------- small helpers ---------- */

static int xerror_swallow(Display *d, XErrorEvent *e) { (void)d; (void)e; return 0; }

static void on_term(int sig) { (void)sig; g_running = 0; }

static void cleanup(void) {
    if (g_lemonbar_pid > 0) kill(g_lemonbar_pid, SIGTERM);
    if (g_desktops_pid > 0) kill(g_desktops_pid, SIGTERM);
    if (g_dpy) XCloseDisplay(g_dpy);
}

/* ---------- bspwm socket ---------- */

static int bspwm_socket_path(char *buf, size_t sz) {
    const char *override = getenv("BSPWM_SOCKET");
    if (override) { snprintf(buf, sz, "%s", override); return 0; }

    const char *display = getenv("DISPLAY");
    if (!display) return -1;

    char host[64] = "";
    int dnum = 0, snum = 0;
    const char *colon = strrchr(display, ':');
    if (!colon) return -1;
    if (colon != display) {
        size_t hlen = (size_t)(colon - display);
        if (hlen >= sizeof(host)) hlen = sizeof(host) - 1;
        memcpy(host, display, hlen);
        host[hlen] = '\0';
    }
    sscanf(colon + 1, "%d.%d", &dnum, &snum);
    snprintf(buf, sz, "/tmp/bspwm%s_%d_%d-socket", host, dnum, snum);
    return 0;
}

static int bspwm_connect(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    if (bspwm_socket_path(addr.sun_path, sizeof(addr.sun_path)) < 0) {
        close(fd);
        return -1;
    }
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

/* Send a NUL-separated argv list followed by a trailing NUL terminator,
 * matching the bspwm IPC framing used by bspc. */
static int bspwm_send_args(int fd, const char *const args[]) {
    char buf[1024];
    size_t pos = 0;
    for (int i = 0; args[i]; i++) {
        size_t len = strlen(args[i]);
        if (pos + len + 1 >= sizeof(buf)) return -1;
        memcpy(buf + pos, args[i], len);
        pos += len;
        buf[pos++] = '\0';
    }
    return send(fd, buf, pos, 0) == (ssize_t)pos ? 0 : -1;
}

/* Run a one-shot bspwm command (no subscribe) and read its full reply. */
static ssize_t bspwm_query(const char *const args[], char *out, size_t outsz) {
    int fd = bspwm_connect();
    if (fd < 0) return -1;
    if (bspwm_send_args(fd, args) < 0) { close(fd); return -1; }

    size_t total = 0;
    ssize_t n;
    while (total + 1 < outsz
           && (n = recv(fd, out + total, outsz - 1 - total, 0)) > 0) {
        total += (size_t)n;
    }
    out[total] = '\0';
    close(fd);
    return (ssize_t)total;
}

/* Returns 1 if there is a fullscreen window on the primary monitor's focused
 * desktop, 0 otherwise.
 *
 * bspwm wire protocol: queries that match return their payload (e.g. a node
 * ID like "0xA00003\n"); queries that don't match return a single status byte
 * \x07 (FAILURE_MESSAGE). The bspc client strips that byte before printing,
 * but we're talking to the socket directly, so we have to skip the known
 * status bytes (\x06 EXIT, \x07 FAILURE) when scanning for real content. */
static int bspwm_is_fullscreen(const char *primary) {
    char selector[128];
    snprintf(selector, sizeof(selector), "%s:focused", primary);
    const char *args[] = { "query", "-N", "-d", selector, "-n", ".fullscreen", NULL };
    char reply[256];
    ssize_t n = bspwm_query(args, reply, sizeof(reply));
    if (n <= 0) return 0;
    for (ssize_t i = 0; i < n; i++) {
        char c = reply[i];
        if (c == '\n' || c == '\0' || c == ' ' || c == '\x06' || c == '\x07')
            continue;
        return 1;
    }
    return 0;
}

static void bspwm_set_top_padding(const char *primary, int px) {
    char val[16];
    snprintf(val, sizeof(val), "%d", px);
    const char *args[] = { "config", "-m", primary, "top_padding", val, NULL };
    char dump[64];
    bspwm_query(args, dump, sizeof(dump));
}

/* ---------- xrandr: find primary monitor name + geometry ---------- */

static int find_primary(Display *d, char *name_out, size_t name_sz,
                        int *x_out, int *y_out, int *w_out) {
    int n = 0;
    XRRMonitorInfo *mons = XRRGetMonitors(d, DefaultRootWindow(d), True, &n);
    if (!mons || n <= 0) {
        if (mons) XRRFreeMonitors(mons);
        return -1;
    }

    /* Prefer the monitor flagged as primary by RandR; fall back to first. */
    int idx = 0;
    for (int i = 0; i < n; i++) {
        if (mons[i].primary) { idx = i; break; }
    }

    char *atom_name = XGetAtomName(d, mons[idx].name);
    if (!atom_name) {
        XRRFreeMonitors(mons);
        return -1;
    }
    snprintf(name_out, name_sz, "%s", atom_name);
    XFree(atom_name);

    *x_out = mons[idx].x;
    *y_out = mons[idx].y;
    *w_out = mons[idx].width;
    XRRFreeMonitors(mons);
    return 0;
}

/* ---------- /sys/class/hwmon: locate CPU sensor at startup ---------- */

static void resolve_hwmon_temp(char *out, size_t outsz) {
    out[0] = '\0';
    for (int i = 0; i < 32; i++) {
        char dir[64], name_path[96], temp_path[96], name[64];
        snprintf(dir, sizeof(dir), "/sys/class/hwmon/hwmon%d", i);
        snprintf(name_path, sizeof(name_path), "%s/name", dir);

        FILE *f = fopen(name_path, "r");
        if (!f) continue;
        if (!fgets(name, sizeof(name), f)) { fclose(f); continue; }
        fclose(f);
        name[strcspn(name, "\n")] = '\0';

        if (strcmp(name, "k10temp") != 0
            && strcmp(name, "zenpower") != 0
            && strcmp(name, "coretemp") != 0
            && strcmp(name, "cpu_thermal") != 0)
            continue;

        snprintf(temp_path, sizeof(temp_path), "%s/temp1_input", dir);
        if (access(temp_path, R_OK) == 0) {
            snprintf(out, outsz, "%s", temp_path);
            return;
        }
    }
}

/* ---------- metric readers ---------- */

static void read_cpu(State *s) {
    FILE *f = fopen("/proc/stat", "r");
    if (!f) { snprintf(s->cpu_str, sizeof(s->cpu_str), "--"); return; }
    unsigned long u, n, sy, i, io, ir, sirq, st;
    if (fscanf(f, "cpu %lu %lu %lu %lu %lu %lu %lu %lu",
               &u, &n, &sy, &i, &io, &ir, &sirq, &st) != 8) {
        fclose(f);
        snprintf(s->cpu_str, sizeof(s->cpu_str), "--");
        return;
    }
    fclose(f);
    unsigned long total = u + n + sy + i + io + ir + sirq + st;
    unsigned long dt = total - s->prev_total;
    unsigned long di = i - s->prev_idle;
    s->prev_total = total;
    s->prev_idle = i;
    int pct = dt > 0 ? (int)((100 * (dt - di)) / dt) : 0;
    snprintf(s->cpu_str, sizeof(s->cpu_str), "%d", pct);
}

static void read_ghz(State *s) {
    unsigned long sum = 0;
    int nc = 0;
    for (int cpu = 0; cpu < 256; cpu++) {
        char path[96];
        snprintf(path, sizeof(path),
                 "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_avg_freq", cpu);
        FILE *f = fopen(path, "r");
        if (!f) {
            if (cpu == 0) break;     /* no avg_freq support: bail */
            continue;
        }
        unsigned long v;
        if (fscanf(f, "%lu", &v) == 1) { sum += v; nc++; }
        fclose(f);
    }
    if (nc == 0) { snprintf(s->ghz_str, sizeof(s->ghz_str), "-.-"); return; }
    /* avg in tenths of GHz */
    unsigned long avg10 = (sum * 10) / (unsigned long)nc / 1000000UL;
    snprintf(s->ghz_str, sizeof(s->ghz_str), "%lu.%lu", avg10 / 10, avg10 % 10);
}

static void read_ram(State *s) {
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) { snprintf(s->ram_str, sizeof(s->ram_str), "--"); return; }
    char line[256];
    long total_kb = 0, avail_kb = 0;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "MemTotal: %ld kB",     &total_kb) == 1) continue;
        if (sscanf(line, "MemAvailable: %ld kB", &avail_kb) == 1) break;
    }
    fclose(f);
    if (total_kb <= 0) { snprintf(s->ram_str, sizeof(s->ram_str), "--"); return; }
    long used_kb = total_kb - avail_kb;
    long u10 = (used_kb  * 10) / 1048576;  /* GB * 10 */
    long t10 = (total_kb * 10) / 1048576;
    snprintf(s->ram_str, sizeof(s->ram_str), "%ld.%ld/%ld.%ld",
             u10 / 10, u10 % 10, t10 / 10, t10 % 10);
}

static void read_temp(State *s) {
    if (!s->hwmon_temp[0]) { snprintf(s->temp_str, sizeof(s->temp_str), "--"); return; }
    FILE *f = fopen(s->hwmon_temp, "r");
    if (!f) { snprintf(s->temp_str, sizeof(s->temp_str), "--"); return; }
    long milli;
    if (fscanf(f, "%ld", &milli) != 1) {
        fclose(f);
        snprintf(s->temp_str, sizeof(s->temp_str), "--");
        return;
    }
    fclose(f);
    snprintf(s->temp_str, sizeof(s->temp_str), "%ld°C", milli / 1000);
}

static void read_date(State *s) {
    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);
    strftime(s->date_str, sizeof(s->date_str), "%a %d %b %I:%M %p", &tm);
}

/* ---------- rendering ---------- */

static void render(State *s, FILE *out) {
    fprintf(out,
            "%%{l} %s %%{c}%s  |  CPU %s%% %sGHz %s  |  RAM %sGB\n",
            s->desktops, s->date_str,
            s->cpu_str, s->ghz_str, s->temp_str,
            s->ram_str);
    fflush(out);
}

/* ---------- spawning helpers ---------- */

/* Fork+exec a child. If write_fd != NULL, give the child a pipe on stdin
 * and return the parent's write end via *write_fd. Same for read_fd via stdout. */
static pid_t spawn(const char *path, char *const argv[], int *write_fd, int *read_fd) {
    int in_pipe[2]  = {-1, -1};
    int out_pipe[2] = {-1, -1};
    if (write_fd && pipe(in_pipe)  < 0) return -1;
    if (read_fd  && pipe(out_pipe) < 0) {
        if (in_pipe[0] >= 0) { close(in_pipe[0]); close(in_pipe[1]); }
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0) return -1;

    if (pid == 0) {
        if (write_fd) {
            dup2(in_pipe[0], STDIN_FILENO);
            close(in_pipe[0]); close(in_pipe[1]);
        }
        if (read_fd) {
            dup2(out_pipe[1], STDOUT_FILENO);
            close(out_pipe[0]); close(out_pipe[1]);
        }
        execvp(path, argv);
        _exit(127);
    }

    if (write_fd) { close(in_pipe[0]);  *write_fd = in_pipe[1];  }
    if (read_fd)  { close(out_pipe[1]); *read_fd  = out_pipe[0]; }
    return pid;
}

/* ---------- lemonbar lifecycle ---------- */

typedef struct {
    pid_t pid;
    int   stdin_fd;
    FILE *stdin_fp;       /* writable handle to lemonbar's stdin */
    Window window;        /* X window for hide/show */
    char  primary[64];    /* monitor name in use */
    int   x, y, w;
} Lemonbar;

/* Forward decls — the start function calls helpers defined below. */
static int find_primary(Display *d, char *name_out, size_t name_sz,
                        int *x_out, int *y_out, int *w_out);
static Window wait_for_lemonbar_window(Display *d);

static int lemonbar_start(Lemonbar *lb, Display *d) {
    memset(lb, 0, sizeof(*lb));
    if (find_primary(d, lb->primary, sizeof(lb->primary),
                     &lb->x, &lb->y, &lb->w) < 0) return -1;

    char geom[64];
    snprintf(geom, sizeof(geom), "%dx%d+%d+%d",
             lb->w, BAR_HEIGHT, lb->x, lb->y);
    char *argv[] = {
        (char *)LEMONBAR_BIN, "-p", "-d", "-g", geom,
        "-B", (char *)LEMONBAR_BG, "-F", (char *)LEMONBAR_FG,
        "-f", (char *)LEMONBAR_FONT, NULL
    };
    lb->pid = spawn(LEMONBAR_BIN, argv, &lb->stdin_fd, NULL);
    if (lb->pid < 0) return -1;
    lb->stdin_fp = fdopen(lb->stdin_fd, "w");
    if (!lb->stdin_fp) { kill(lb->pid, SIGTERM); return -1; }

    lb->window = wait_for_lemonbar_window(d);
    bspwm_set_top_padding(lb->primary, BAR_HEIGHT);
    return 0;
}

static void lemonbar_stop(Lemonbar *lb) {
    if (lb->stdin_fp) { fclose(lb->stdin_fp); lb->stdin_fp = NULL; lb->stdin_fd = -1; }
    if (lb->pid > 0) {
        kill(lb->pid, SIGTERM);
        waitpid(lb->pid, NULL, 0);
        lb->pid = -1;
    }
    lb->window = None;
}

/* ---------- finding the lemonbar window after spawn ---------- */

static int wm_class_is(Display *d, Window w, const char *target) {
    XClassHint h = {0};
    if (!XGetClassHint(d, w, &h)) return 0;
    int hit = (h.res_name  && strcmp(h.res_name,  target) == 0)
           || (h.res_class && strcmp(h.res_class, target) == 0);
    if (h.res_name)  XFree(h.res_name);
    if (h.res_class) XFree(h.res_class);
    return hit;
}

static Window find_window_by_class(Display *d, Window root, const char *cls) {
    Window dummy, *children = NULL;
    unsigned int nchildren = 0;
    if (!XQueryTree(d, root, &dummy, &dummy, &children, &nchildren)) return None;
    Window hit = None;
    for (unsigned int i = 0; i < nchildren && hit == None; i++) {
        if (wm_class_is(d, children[i], cls)) hit = children[i];
    }
    if (children) XFree(children);
    return hit;
}

/* Poll for up to ~500ms until lemonbar's window appears. */
static Window wait_for_lemonbar_window(Display *d) {
    Window root = DefaultRootWindow(d);
    for (int i = 0; i < 50; i++) {
        Window w = find_window_by_class(d, root, "lemonbar");
        if (w != None) return w;
        struct timespec ts = { .tv_nsec = 10 * 1000 * 1000 };  /* 10ms */
        nanosleep(&ts, NULL);
    }
    return None;
}

/* ---------- main ---------- */

int main(void) {
    /* Single instance via flock. */
    int lock_fd = open(LOCK_PATH, O_CREAT | O_RDWR, 0600);
    if (lock_fd < 0) { perror("open lock"); return 1; }
    if (flock(lock_fd, LOCK_EX | LOCK_NB) < 0) {
        /* Another instance is running. Silent exit, matches watcher.sh. */
        return 0;
    }

    signal(SIGPIPE, SIG_IGN);
    signal(SIGTERM, on_term);
    signal(SIGINT,  on_term);
    atexit(cleanup);

    /* X + RandR */
    g_dpy = XOpenDisplay(NULL);
    if (!g_dpy) { fprintf(stderr, "bar: cannot open DISPLAY\n"); return 1; }
    XSetErrorHandler(xerror_swallow);

    State s = {0};
    snprintf(s.cpu_str,  sizeof(s.cpu_str),  "--");
    snprintf(s.ghz_str,  sizeof(s.ghz_str),  "-.-");
    snprintf(s.temp_str, sizeof(s.temp_str), "--");
    snprintf(s.ram_str,  sizeof(s.ram_str),  "--");
    s.date_str[0] = '\0';
    s.desktops[0] = '\0';
    resolve_hwmon_temp(s.hwmon_temp, sizeof(s.hwmon_temp));

    /* Prime CPU baseline so the first sample is a delta, not since-boot avg. */
    read_cpu(&s);
    snprintf(s.cpu_str, sizeof(s.cpu_str), "--");
    read_date(&s);

    time_t now = time(NULL);
    s.next_cpu  = now + INT_CPU;
    s.next_ghz  = now + INT_GHZ;
    s.next_ram  = now;             /* render RAM immediately */
    s.next_temp = now;
    s.next_date = now - (now % INT_DATE) + INT_DATE;

    /* Spawn lemonbar (detects primary monitor + sets top_padding internally). */
    Lemonbar lb;
    if (lemonbar_start(&lb, g_dpy) < 0) {
        fprintf(stderr, "bar: lemonbar_start failed\n");
        return 1;
    }
    g_lemonbar_pid = lb.pid;
    g_lemonbar_win = lb.window;

    /* Spawn bspwm-desktops; read its stdout. */
    char *bd_argv[] = { (char *)BSPWM_DESKTOPS, NULL };
    int bd_out;
    g_desktops_pid = spawn(BSPWM_DESKTOPS, bd_argv, NULL, &bd_out);
    if (g_desktops_pid < 0) { fprintf(stderr, "bar: spawn bspwm-desktops failed\n"); return 1; }

    /* Persistent bspwm event subscription (separate connection from queries). */
    int ev_fd = bspwm_connect();
    if (ev_fd < 0) { fprintf(stderr, "bar: bspwm subscribe connect failed\n"); return 1; }
    const char *sub_args[] = {
        "subscribe", "node_state", "node_focus", "node_remove",
        "node_transfer", "desktop_focus", NULL
    };
    bspwm_send_args(ev_fd, sub_args);

    /* 1Hz timer. */
    int tfd = timerfd_create(CLOCK_MONOTONIC, 0);
    if (tfd < 0) { perror("timerfd_create"); return 1; }
    struct itimerspec its = { {1, 0}, {1, 0} };  /* fire every 1s */
    timerfd_settime(tfd, 0, &its, NULL);

    /* First render so the bar appears immediately. */
    render(&s, lb.stdin_fp);

    int fullscreen = 0;
    char bd_buf[4096]; int bd_len = 0;
    char ev_buf[4096]; int ev_len = 0;

    while (g_running) {
        /* Respawn lemonbar if it died. `monitor --off` and similar tools
         * pkill lemonbar after xrandr changes; we then re-detect the new
         * monitor geometry and bring up a fresh lemonbar. bspwm-desktops and
         * the event subscription are kept alive — they don't depend on
         * monitor layout. */
        if (lb.pid > 0 && waitpid(lb.pid, NULL, WNOHANG) > 0) {
            lemonbar_stop(&lb);
            /* Brief settle so xrandr/bspwm finish their layout updates. */
            struct timespec ts = { .tv_nsec = 200 * 1000 * 1000 };
            nanosleep(&ts, NULL);
            if (lemonbar_start(&lb, g_dpy) < 0) {
                fprintf(stderr, "bar: lemonbar respawn failed\n");
                break;
            }
            g_lemonbar_pid = lb.pid;
            g_lemonbar_win = lb.window;
            fullscreen = 0;
            render(&s, lb.stdin_fp);
            continue;
        }

        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(tfd, &rfds);
        FD_SET(bd_out, &rfds);
        FD_SET(ev_fd, &rfds);
        int maxfd = tfd;
        if (bd_out > maxfd) maxfd = bd_out;
        if (ev_fd  > maxfd) maxfd = ev_fd;

        /* Poll every 500ms so we notice lemonbar dying even when no other
         * fd is active. */
        struct timeval tv = { 0, 500 * 1000 };
        int r = select(maxfd + 1, &rfds, NULL, NULL, &tv);
        if (r < 0) {
            if (errno == EINTR) continue;
            break;
        }

        /* desktops: read whatever is available, take the LAST complete line. */
        if (FD_ISSET(bd_out, &rfds)) {
            ssize_t n = read(bd_out, bd_buf + bd_len, sizeof(bd_buf) - 1 - (size_t)bd_len);
            if (n > 0) {
                bd_len += (int)n;
                bd_buf[bd_len] = '\0';
                char *last_nl = strrchr(bd_buf, '\n');
                if (last_nl) {
                    *last_nl = '\0';
                    char *prev_nl = strrchr(bd_buf, '\n');
                    const char *line = prev_nl ? prev_nl + 1 : bd_buf;
                    snprintf(s.desktops, sizeof(s.desktops), "%s", line);
                    int consumed = (int)(last_nl - bd_buf) + 1;
                    int remaining = bd_len - consumed;
                    if (remaining > 0)
                        memmove(bd_buf, bd_buf + consumed, (size_t)remaining);
                    bd_len = remaining;
                }
                render(&s, lb.stdin_fp);
            }
        }

        /* bspwm event: any data → re-check fullscreen state. */
        if (FD_ISSET(ev_fd, &rfds)) {
            ssize_t n = recv(ev_fd, ev_buf + ev_len, sizeof(ev_buf) - 1 - (size_t)ev_len, 0);
            if (n > 0) {
                ev_len += (int)n;
                ev_len = 0;
                int now_fs = bspwm_is_fullscreen(lb.primary);
                if (now_fs != fullscreen) {
                    fullscreen = now_fs;
                    if (lb.window == None)
                        lb.window = find_window_by_class(g_dpy,
                                        DefaultRootWindow(g_dpy), "lemonbar");
                    if (lb.window != None) {
                        if (fullscreen) XUnmapWindow(g_dpy, lb.window);
                        else            XMapWindow  (g_dpy, lb.window);
                        XFlush(g_dpy);
                        g_lemonbar_win = lb.window;
                    }
                    bspwm_set_top_padding(lb.primary, fullscreen ? 0 : BAR_HEIGHT);
                }
            } else if (n == 0) {
                break;  /* bspwm closed the subscription */
            }
        }

        /* 1Hz tick: drain all pending tick expirations, then refresh metrics. */
        if (FD_ISSET(tfd, &rfds)) {
            uint64_t expirations;
            (void)read(tfd, &expirations, sizeof(expirations));

            time_t t = time(NULL);
            int dirty = 0;
            if (t >= s.next_cpu)  { read_cpu(&s);  s.next_cpu  = t + INT_CPU;  dirty = 1; }
            if (t >= s.next_ghz)  { read_ghz(&s);  s.next_ghz  = t + INT_GHZ;  dirty = 1; }
            if (t >= s.next_ram)  { read_ram(&s);  s.next_ram  = t + INT_RAM;  dirty = 1; }
            if (t >= s.next_temp) { read_temp(&s); s.next_temp = t + INT_TEMP; dirty = 1; }
            if (t >= s.next_date) { read_date(&s);
                                    s.next_date = t - (t % INT_DATE) + INT_DATE; dirty = 1; }
            if (dirty) render(&s, lb.stdin_fp);
        }
    }

    return 0;
}
