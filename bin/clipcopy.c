/*
 * clipcopy - copy a PNG file to clipboard with multiple targets:
 *   image/png              (for image paste in apps)
 *   text/uri-list          (for file paste in Thunar/file managers)
 *   x-special/gnome-copied-files  (GTK file managers)
 *
 * Usage: clipcopy <path.png>
 * Forks to background, stays alive until clipboard is reclaimed.
 */

#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

enum { TARGET_PNG = 0, TARGET_URI, TARGET_GNOME };

static guchar *png_data = NULL;
static gsize   png_len  = 0;
static gchar  *file_uri = NULL;
static gchar  *gnome_data = NULL;
static gsize   gnome_len  = 0;

static void get_cb(GtkClipboard *cb, GtkSelectionData *sel,
                   guint info, gpointer user_data)
{
    (void)cb; (void)user_data;
    switch (info) {
    case TARGET_PNG:
        gtk_selection_data_set(sel,
            gdk_atom_intern("image/png", FALSE), 8, png_data, png_len);
        break;
    case TARGET_URI:
        gtk_selection_data_set(sel,
            gdk_atom_intern("text/uri-list", FALSE), 8,
            (const guchar *)file_uri, strlen(file_uri));
        break;
    case TARGET_GNOME:
        gtk_selection_data_set(sel,
            gdk_atom_intern("x-special/gnome-copied-files", FALSE), 8,
            (const guchar *)gnome_data, gnome_len);
        break;
    }
}

static void clear_cb(GtkClipboard *cb, gpointer user_data)
{
    (void)cb; (void)user_data;
    gtk_main_quit();
}

int main(int argc, char *argv[])
{
    if (argc != 2) {
        fprintf(stderr, "Usage: clipcopy <file.png>\n");
        return 1;
    }

    /* Resolve to absolute path */
    char *abspath = realpath(argv[1], NULL);
    if (!abspath) {
        perror("realpath");
        return 1;
    }

    /* Read PNG data */
    GError *err = NULL;
    if (!g_file_get_contents(abspath, (gchar **)&png_data, &png_len, &err)) {
        fprintf(stderr, "read: %s\n", err->message);
        g_error_free(err);
        free(abspath);
        return 1;
    }

    /* Build URI strings */
    file_uri = g_strdup_printf("file://%s\r\n", abspath);
    gnome_data = g_strdup_printf("copy\nfile://%s", abspath);
    gnome_len = strlen(gnome_data);
    free(abspath);

    /* Fork to background */
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }
    if (pid > 0) _exit(0);   /* parent exits immediately */
    setsid();

    /* Child: init GTK (opens X connection in this process) */
    gtk_init(&argc, &argv);

    GtkTargetEntry targets[] = {
        { "image/png",                    0, TARGET_PNG   },
        { "text/uri-list",                0, TARGET_URI   },
        { "x-special/gnome-copied-files", 0, TARGET_GNOME },
    };

    GtkClipboard *cb = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    if (!gtk_clipboard_set_with_data(cb, targets, G_N_ELEMENTS(targets),
                                     get_cb, clear_cb, NULL)) {
        fprintf(stderr, "clipboard: failed to claim ownership\n");
        return 1;
    }

    gtk_main();

    g_free(png_data);
    g_free(file_uri);
    g_free(gnome_data);
    return 0;
}
