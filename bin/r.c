/*
 * r - top processes by RAM (PSS when available, else RSS) and CPU%.
 *
 * Two-sample CPU like the bash original: snapshot jiffies, sleep
 * CR_INTERVAL seconds (default 0.5), snapshot again, derive %.
 * Aggregates by comm so multi-process apps (chrome, firefox) collapse.
 *
 * No forks, no temp files: walks /proc directly with readdir + open.
 *
 * Usage: r [count]            (default 10)
 * Env:   CR_INTERVAL=0.5      sampling window in seconds
 *
 * Build: gcc -O2 -Wall -o r r.c
 */

#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/sysinfo.h>

#define MAX_PROCS 8192
#define COMM_LEN  32

typedef struct {
    int pid;
    unsigned long mem_kb;
    unsigned long jiff1;
    unsigned long jiff2;
    char comm[COMM_LEN];
    int has2;
} Proc;

typedef struct {
    char comm[COMM_LEN];
    unsigned long mem_kb;
    double cpu;
    int top_pid;
    unsigned long top_mem;
} Agg;

static Proc procs[MAX_PROCS];
static int proc_count;
static Agg aggs[MAX_PROCS];
static int agg_count;

static int read_stat(int pid, unsigned long *jiff,
                     unsigned long *rss_pages, char *comm, size_t comm_sz) {
    char path[64], buf[4096];
    snprintf(path, sizeof path, "/proc/%d/stat", pid);
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    ssize_t n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n <= 0) return -1;
    buf[n] = 0;

    /* comm is wrapped in parens and may contain spaces/parens itself. */
    char *rp = strrchr(buf, ')');
    if (!rp) return -1;
    if (comm) {
        char *lp = strchr(buf, '(');
        if (lp && rp > lp) {
            size_t cl = (size_t)(rp - lp - 1);
            if (cl >= comm_sz) cl = comm_sz - 1;
            memcpy(comm, lp + 1, cl);
            comm[cl] = 0;
        } else {
            comm[0] = 0;
        }
    }

    /* After ") ": state(0) ppid(1) ... utime(11) stime(12) ... rss(21) */
    if (rp[1] == 0) return -1;
    rp += 2;
    unsigned long utime = 0, stime = 0, rss = 0;
    int idx = 0;
    char *save = NULL;
    for (char *tok = strtok_r(rp, " \t\n", &save);
         tok && idx <= 21;
         tok = strtok_r(NULL, " \t\n", &save), idx++) {
        if (idx == 11)      utime = strtoul(tok, NULL, 10);
        else if (idx == 12) stime = strtoul(tok, NULL, 10);
        else if (idx == 21) rss   = strtoul(tok, NULL, 10);
    }
    if (jiff)      *jiff = utime + stime;
    if (rss_pages) *rss_pages = rss;
    return 0;
}

static unsigned long read_pss_kb(int pid) {
    char path[64], buf[4096];
    snprintf(path, sizeof path, "/proc/%d/smaps_rollup", pid);
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    ssize_t n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n <= 0) return 0;
    buf[n] = 0;

    char *p = buf;
    if (strncmp(p, "Pss:", 4) != 0) {
        p = strstr(buf, "\nPss:");
        if (!p) return 0;
        p++;
    }
    p += 4;
    while (*p == ' ' || *p == '\t') p++;
    return strtoul(p, NULL, 10);
}

static int find_proc(int pid) {
    for (int i = 0; i < proc_count; i++)
        if (procs[i].pid == pid) return i;
    return -1;
}

static int agg_find_or_add(const char *comm) {
    for (int i = 0; i < agg_count; i++)
        if (strcmp(aggs[i].comm, comm) == 0) return i;
    if (agg_count >= MAX_PROCS) return -1;
    Agg *a = &aggs[agg_count];
    strncpy(a->comm, comm, COMM_LEN - 1);
    a->comm[COMM_LEN - 1] = 0;
    a->mem_kb = 0;
    a->cpu = 0;
    a->top_pid = 0;
    a->top_mem = 0;
    return agg_count++;
}

static int cmp_agg(const void *a, const void *b) {
    const Agg *x = a, *y = b;
    if (y->mem_kb != x->mem_kb) return (y->mem_kb > x->mem_kb) ? 1 : -1;
    if (y->cpu > x->cpu) return 1;
    if (y->cpu < x->cpu) return -1;
    return 0;
}

int main(int argc, char **argv) {
    int limit = 10;
    if (argc >= 2) {
        char *end;
        long v = strtol(argv[1], &end, 10);
        if (*argv[1] == 0 || *end != 0 || v < 1) {
            fprintf(stderr, "Usage: %s [count]\n", argv[0]);
            return 1;
        }
        limit = (int)v;
    }

    double interval = 0.5;
    const char *env = getenv("CR_INTERVAL");
    if (env && *env) {
        double v = strtod(env, NULL);
        if (v > 0) interval = v;
    }

    long clk_tck = sysconf(_SC_CLK_TCK);
    long page_sz = sysconf(_SC_PAGESIZE);
    int  ncpu    = get_nprocs();
    if (clk_tck < 1) clk_tck = 100;
    if (page_sz < 1) page_sz = 4096;
    if (ncpu    < 1) ncpu    = 1;
    unsigned long page_kb = (unsigned long)page_sz / 1024UL;

    DIR *d = opendir("/proc");
    if (!d) { perror("/proc"); return 1; }
    struct dirent *de;
    while ((de = readdir(d)) && proc_count < MAX_PROCS) {
        if (!isdigit((unsigned char)de->d_name[0])) continue;
        int pid = atoi(de->d_name);
        if (pid <= 0) continue;
        unsigned long jiff = 0, rss_pages = 0;
        Proc *p = &procs[proc_count];
        if (read_stat(pid, &jiff, &rss_pages, p->comm, sizeof p->comm) < 0) continue;
        unsigned long pss_kb = read_pss_kb(pid);
        p->pid     = pid;
        p->mem_kb  = pss_kb ? pss_kb : rss_pages * page_kb;
        p->jiff1   = jiff;
        p->jiff2   = 0;
        p->has2    = 0;
        proc_count++;
    }
    closedir(d);

    struct timespec ts;
    ts.tv_sec  = (time_t)interval;
    ts.tv_nsec = (long)((interval - (double)ts.tv_sec) * 1e9);
    nanosleep(&ts, NULL);

    d = opendir("/proc");
    if (!d) { perror("/proc"); return 1; }
    while ((de = readdir(d))) {
        if (!isdigit((unsigned char)de->d_name[0])) continue;
        int pid = atoi(de->d_name);
        if (pid <= 0) continue;
        int i = find_proc(pid);
        if (i < 0) continue;
        unsigned long jiff = 0;
        if (read_stat(pid, &jiff, NULL, NULL, 0) < 0) continue;
        procs[i].jiff2 = jiff;
        procs[i].has2  = 1;
    }
    closedir(d);

    for (int i = 0; i < proc_count; i++) {
        if (!procs[i].has2) continue;
        long dj = (long)procs[i].jiff2 - (long)procs[i].jiff1;
        if (dj < 0) dj = 0;
        double cpu = ((double)dj / (double)clk_tck) / interval
                     / (double)ncpu * 100.0;
        int a = agg_find_or_add(procs[i].comm);
        if (a < 0) continue;
        aggs[a].mem_kb += procs[i].mem_kb;
        aggs[a].cpu    += cpu;
        if (procs[i].mem_kb > aggs[a].top_mem) {
            aggs[a].top_mem = procs[i].mem_kb;
            aggs[a].top_pid = procs[i].pid;
        }
    }

    qsort(aggs, agg_count, sizeof(Agg), cmp_agg);

    printf("%-8s %-10s %-7s %s\n", "PID", "RAM(MB)", "CPU%", "PROCESS");
    for (int i = 0; i < agg_count && i < limit; i++) {
        printf("%-8d %-10.1f %-7.1f %s\n",
               aggs[i].top_pid,
               aggs[i].mem_kb / 1024.0,
               aggs[i].cpu,
               aggs[i].comm);
    }
    return 0;
}
