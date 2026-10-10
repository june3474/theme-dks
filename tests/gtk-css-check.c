#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>

static unsigned int parse_errors = 0;

#if GTK_MAJOR_VERSION < 4
static void
ignore_non_parser_log(const gchar *domain,
                      GLogLevelFlags level,
                      const gchar *message,
                      gpointer user_data)
{
    (void) domain;
    (void) level;
    (void) message;
    (void) user_data;
}

static void
parsing_error(GtkCssProvider *provider,
              GtkCssSection *section,
              const GError *error,
              gpointer user_data)
{
    (void) provider;
    (void) section;
    (void) user_data;

    fprintf(stderr, "GTK CSS: %s\n", error->message);
    parse_errors++;
}
#else
static GLogWriterOutput
log_writer(GLogLevelFlags level,
           const GLogField *fields,
           gsize n_fields,
           gpointer user_data)
{
    const char *message = NULL;

    for (gsize i = 0; i < n_fields; i++) {
        if (strcmp(fields[i].key, "MESSAGE") == 0) {
            message = fields[i].value;
            break;
        }
    }

    if ((level & (G_LOG_LEVEL_ERROR | G_LOG_LEVEL_CRITICAL | G_LOG_LEVEL_WARNING))
        && message != NULL
        && strstr(message, "Theme parser") != NULL) {
        fprintf(stderr, "%s\n", message);
        parse_errors++;
    }

    (void) user_data;
    return G_LOG_WRITER_HANDLED;
}
#endif

int
main(int argc, char **argv)
{
    GtkCssProvider *provider;

    if (argc != 2) {
        fprintf(stderr, "usage: %s CSS_PATH\n", argv[0]);
        return 2;
    }

#if GTK_MAJOR_VERSION < 4
    g_log_set_handler("Gtk",
                      G_LOG_LEVEL_ERROR | G_LOG_LEVEL_CRITICAL | G_LOG_LEVEL_WARNING,
                      ignore_non_parser_log,
                      NULL);
#else
    g_log_set_writer_func(log_writer, NULL, NULL);
#endif

    provider = gtk_css_provider_new();

#if GTK_MAJOR_VERSION < 4
    {
        GError *error = NULL;

        g_signal_connect(provider, "parsing-error", G_CALLBACK(parsing_error), NULL);
        if (!gtk_css_provider_load_from_path(provider, argv[1], &error)) {
            if (error != NULL) {
                fprintf(stderr, "GTK CSS load: %s\n", error->message);
                g_clear_error(&error);
            }
            parse_errors++;
        }
    }
#else
    gtk_css_provider_load_from_path(provider, argv[1]);
#endif

    g_object_unref(provider);
    return parse_errors == 0 ? 0 : 1;
}
