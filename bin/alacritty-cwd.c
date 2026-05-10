/*
 * alacritty-cwd: launch alacritty inheriting cwd from the focused Alacritty
 * window. Falls back to $HOME if the focused window is not Alacritty/split_term
 * or its cwd cannot be read.
 *
 * No forks: Xlib speaks the X protocol directly (instead of forking xdotool),
 * /proc is read with stdio (instead of forking pgrep + readlink), and execvp
 * replaces the current process with alacritty (no fork either).
 *
 * Build:  gcc -O2 -Wall -o alacritty-cwd alacritty-cwd.c -lX11
 */

#define _POSIX_C_SOURCE 200809L
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int xerror_swallow(Display *dpy, XErrorEvent *e) { (void)dpy; (void)e; return 0; }

static Window get_active_window(Display *dpy) {
    Atom net_active = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", True);
    if (net_active == None) return None;

    Atom actual_type;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;

    if (XGetWindowProperty(dpy, DefaultRootWindow(dpy), net_active, 0, 1, False,
                           XA_WINDOW, &actual_type, &actual_format, &nitems,
                           &bytes_after, &data) != Success || !data || nitems == 0) {
        if (data) XFree(data);
        return None;
    }
    Window w = *((Window *)data);
    XFree(data);
    return w;
}

static int read_pid_property(Display *dpy, Window w, pid_t *out) {
    Atom net_wm_pid = XInternAtom(dpy, "_NET_WM_PID", True);
    if (net_wm_pid == None) return 0;

    Atom actual_type;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;

    if (XGetWindowProperty(dpy, w, net_wm_pid, 0, 1, False, XA_CARDINAL,
                           &actual_type, &actual_format, &nitems, &bytes_after,
                           &data) != Success || !data || nitems == 0) {
        if (data) XFree(data);
        return 0;
    }
    /* CARDINAL values are returned as `long` regardless of the source 32-bit width. */
    *out = (pid_t) *((unsigned long *)data);
    XFree(data);
    return *out > 0;
}

static int is_target_class(const char *s) {
    return s && (strcmp(s, "Alacritty") == 0 || strcmp(s, "split_term") == 0);
}

static int read_first_child(pid_t pid, pid_t *out) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/task/%d/children", (int)pid, (int)pid);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    int got = fscanf(f, "%d", out);
    fclose(f);
    return got == 1 && *out > 0;
}

static int read_cwd(pid_t pid, char *out, size_t outsz) {
    char link[64];
    snprintf(link, sizeof(link), "/proc/%d/cwd", (int)pid);
    ssize_t n = readlink(link, out, outsz - 1);
    if (n <= 0) return 0;
    out[n] = '\0';
    return 1;
}

int main(int argc, char *argv[]) {
    char cwd[4096];
    const char *home = getenv("HOME");
    snprintf(cwd, sizeof(cwd), "%s", home ? home : "/");

    Display *dpy = XOpenDisplay(NULL);
    if (dpy) {
        XSetErrorHandler(xerror_swallow);
        Window w = get_active_window(dpy);
        if (w != None) {
            XClassHint cls = {0};
            if (XGetClassHint(dpy, w, &cls)) {
                int matched = is_target_class(cls.res_name) || is_target_class(cls.res_class);
                if (cls.res_name)  XFree(cls.res_name);
                if (cls.res_class) XFree(cls.res_class);

                if (matched) {
                    pid_t pid;
                    if (read_pid_property(dpy, w, &pid)) {
                        pid_t child;
                        pid_t target = read_first_child(pid, &child) ? child : pid;
                        char buf[4096];
                        struct stat st;
                        /* Validate: readlink returns "<path> (deleted)" when the
                         * cwd has been unlinked, and we don't want to pass a
                         * non-existent path to alacritty. */
                        if (read_cwd(target, buf, sizeof(buf))
                            && stat(buf, &st) == 0
                            && S_ISDIR(st.st_mode)) {
                            snprintf(cwd, sizeof(cwd), "%s", buf);
                        }
                    }
                }
            }
        }
        XCloseDisplay(dpy);
    }

    /* Replace ourselves with: alacritty --working-directory <cwd> <forwarded args> */
    int new_argc = argc + 2;  /* +2 for --working-directory and cwd */
    char **new_argv = malloc(sizeof(char *) * (size_t)(new_argc + 1));
    if (!new_argv) { perror("malloc"); return 1; }
    new_argv[0] = "alacritty";
    new_argv[1] = "--working-directory";
    new_argv[2] = cwd;
    for (int i = 1; i < argc; i++) new_argv[2 + i] = argv[i];
    new_argv[new_argc] = NULL;

    execvp("alacritty", new_argv);
    perror("execvp alacritty");
    return 1;
}
