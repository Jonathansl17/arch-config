/*
 * bspwm-desktops: conecta directo al socket Unix de bspwm, subscribe report,
 * parsea la línea y escribe el string formateado para lemonbar a stdout.
 * Sin intermediarios (bspc), sin buffering extra.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>

static int get_socket_path(char *buf, size_t len)
{
    const char *path = getenv("BSPWM_SOCKET");
    if (path) {
        snprintf(buf, len, "%s", path);
        return 0;
    }

    const char *display = getenv("DISPLAY");
    if (!display) return -1;

    char host[256] = "";
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
    snprintf(buf, len, "/tmp/bspwm%s_%d_%d-socket", host, dnum, snum);
    return 0;
}

static int connect_bspwm(void)
{
    char path[256];
    if (get_socket_path(path, sizeof(path)) < 0) return -1;

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    if (snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path)
        >= (int)sizeof(addr.sun_path)) {
        close(fd);
        return -1;
    }

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static int send_subscribe(int fd)
{
    /* bspwm IPC: palabras separadas por \0 */
    const char msg[] = "subscribe\0report";
    return send(fd, msg, sizeof(msg), 0) > 0 ? 0 : -1;
}

static void parse_report(const char *line)
{
    if (line[0] != 'W') return;

    const char *p = line + 1;
    char out[4096];
    int pos = 0;

    while (*p) {
        const char *start = p;
        while (*p && *p != ':' && *p != '\n') p++;

        size_t tlen = (size_t)(p - start);
        if (tlen == 0) { if (*p) p++; continue; }

        char flag = start[0];
        const char *name = start + 1;
        int nlen = (int)(tlen - 1);

        switch (flag) {
        case 'M': case 'm':
        case 'L': case 'T': case 'G':
            break;
        case 'O': case 'F': case 'U':
            pos += snprintf(out + pos, sizeof(out) - (size_t)pos,
                "%%{F#FF000000}%%{B#FFFFFFFF} %.*s %%{B-}%%{F-}", nlen, name);
            break;
        case 'o': case 'f': case 'u':
            pos += snprintf(out + pos, sizeof(out) - (size_t)pos,
                "%%{F#88FFFFFF} %.*s %%{F-}", nlen, name);
            break;
        }

        if (*p == ':') p++;
    }

    out[pos] = '\0';
    printf("%s\n", out);
    fflush(stdout);
}

int main(void)
{
    signal(SIGPIPE, SIG_IGN);

    int fd = connect_bspwm();
    if (fd < 0) {
        fprintf(stderr, "bspwm-desktops: cannot connect to bspwm socket\n");
        return 1;
    }

    if (send_subscribe(fd) < 0) {
        fprintf(stderr, "bspwm-desktops: subscribe failed\n");
        close(fd);
        return 1;
    }

    char buf[4096];
    int blen = 0;
    ssize_t n;

    while ((n = recv(fd, buf + blen, sizeof(buf) - (size_t)blen - 1, 0)) > 0) {
        blen += (int)n;
        buf[blen] = '\0';

        char *line = buf;
        char *nl;
        while ((nl = strchr(line, '\n')) != NULL) {
            *nl = '\0';
            parse_report(line);
            line = nl + 1;
        }

        int remaining = blen - (int)(line - buf);
        if (remaining > 0) memmove(buf, line, (size_t)remaining);
        blen = remaining;
    }

    close(fd);
    return 0;
}
