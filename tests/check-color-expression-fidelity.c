#include <gtk/gtk.h>
#include <lcms2.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *cursor;

static void
skip_whitespace(void)
{
    while (g_ascii_isspace(*cursor))
        cursor++;
}

static void
expect_character(char expected)
{
    skip_whitespace();
    if (*cursor != expected) {
        fprintf(stderr, "expected '%c' at: %s\n", expected, cursor);
        exit(2);
    }
    cursor++;
}

static GtkSymbolicColor *parse_expression(void);

static GtkSymbolicColor *
parse_function(void)
{
    gboolean is_shade = g_str_has_prefix(cursor, "shade(");
    gboolean is_alpha = g_str_has_prefix(cursor, "alpha(");
    GtkSymbolicColor *first;
    GtkSymbolicColor *second = NULL;
    GtkSymbolicColor *result;
    char *end;
    double factor;

    cursor += (is_shade || is_alpha) ? 6 : 4;
    first = parse_expression();
    expect_character(',');
    if (!is_shade && !is_alpha) {
        second = parse_expression();
        expect_character(',');
    }
    skip_whitespace();
    factor = g_ascii_strtod(cursor, &end);
    if (end == cursor || !isfinite(factor)) {
        fprintf(stderr, "expected finite numeric color-function factor at: %s\n", cursor);
        exit(2);
    }
    cursor = end;
    expect_character(')');

    if (is_shade)
        result = gtk_symbolic_color_new_shade(first, factor);
    else if (is_alpha)
        result = gtk_symbolic_color_new_alpha(first, factor);
    else
        result = gtk_symbolic_color_new_mix(first, second, factor);

    gtk_symbolic_color_unref(first);
    if (second != NULL)
        gtk_symbolic_color_unref(second);
    return result;
}

static GtkSymbolicColor *
parse_expression(void)
{
    const char *start;
    GtkSymbolicColor *result;

    skip_whitespace();
    if (*cursor == '@') {
        char *name;

        start = ++cursor;
        while (g_ascii_isalnum(*cursor) || *cursor == '_' || *cursor == '-')
            cursor++;
        name = g_strndup(start, cursor - start);
        result = gtk_symbolic_color_new_name(name);
        g_free(name);
        return result;
    }

    if (g_str_has_prefix(cursor, "shade(")
        || g_str_has_prefix(cursor, "alpha(")
        || g_str_has_prefix(cursor, "mix("))
        return parse_function();

    start = cursor;
    {
        int depth = 0;
        char *literal;
        GdkRGBA rgba;

        while (*cursor != '\0') {
            if (*cursor == '(')
                depth++;
            else if (*cursor == ')') {
                if (depth == 0)
                    break;
                depth--;
            } else if (*cursor == ',' && depth == 0) {
                break;
            }
            cursor++;
        }

        literal = g_strstrip(g_strndup(start, cursor - start));
        if (!gdk_rgba_parse(&rgba, literal)) {
            fprintf(stderr, "cannot parse color literal: %s\n", literal);
            exit(2);
        }
        result = gtk_symbolic_color_new_literal(&rgba);
        g_free(literal);
    }
    return result;
}

static GtkSymbolicColor *
parse_complete_expression(const char *text)
{
    GtkSymbolicColor *result;

    cursor = text;
    result = parse_expression();
    skip_whitespace();
    if (*cursor != '\0') {
        fprintf(stderr, "unexpected trailing color expression: %s\n", cursor);
        exit(2);
    }
    return result;
}

static void
load_palette(GtkStyleProperties *properties, const char *path)
{
    char *palette = NULL;
    GRegex *regex;
    GMatchInfo *match;

    if (!g_file_get_contents(path, &palette, NULL, NULL)) {
        fprintf(stderr, "cannot read palette: %s\n", path);
        exit(2);
    }

    regex = g_regex_new("@define-color\\s+([A-Za-z_][A-Za-z0-9_-]*)\\s+([^;]+);",
                        0, 0, NULL);
    g_regex_match(regex, palette, 0, &match);
    while (g_match_info_matches(match)) {
        char *name = g_match_info_fetch(match, 1);
        char *value = g_match_info_fetch(match, 2);
        GtkSymbolicColor *color = parse_complete_expression(value);

        gtk_style_properties_map_color(properties, name, color);
        gtk_symbolic_color_unref(color);
        g_free(name);
        g_free(value);
        g_match_info_next(match, NULL);
    }

    g_match_info_free(match);
    g_regex_unref(regex);
    g_free(palette);
}

static GdkRGBA
resolve_expression(GtkStyleProperties *properties, const char *text)
{
    GtkSymbolicColor *color = parse_complete_expression(text);
    GdkRGBA result;

    if (!gtk_symbolic_color_resolve(color, properties, &result)) {
        fprintf(stderr, "cannot resolve color expression: %s\n", text);
        exit(2);
    }
    gtk_symbolic_color_unref(color);
    return result;
}

static double
srgb_to_linear(double value)
{
    if (value <= 0.04045)
        return value / 12.92;
    return pow((value + 0.055) / 1.055, 2.4);
}

static double
lab_component(double value)
{
    const double boundary = 216.0 / 24389.0;

    if (value > boundary)
        return cbrt(value);
    return (24389.0 / 27.0 * value + 16.0) / 116.0;
}

static cmsCIELab
rgb_to_lab(const double rgb[3])
{
    double red = srgb_to_linear(rgb[0]);
    double green = srgb_to_linear(rgb[1]);
    double blue = srgb_to_linear(rgb[2]);
    double x = (0.4124564 * red + 0.3575761 * green + 0.1804375 * blue) / 0.95047;
    double y = 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue;
    double z = (0.0193339 * red + 0.1191920 * green + 0.9503041 * blue) / 1.08883;
    double fx = lab_component(x);
    double fy = lab_component(y);
    double fz = lab_component(z);
    cmsCIELab result = { 116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz) };

    return result;
}

static gboolean
rgba_is_finite(const GdkRGBA *color)
{
    return isfinite(color->red)
        && isfinite(color->green)
        && isfinite(color->blue)
        && isfinite(color->alpha);
}

int
main(int argc, char **argv)
{
    GtkStyleProperties *properties;
    GdkRGBA actual;
    GdkRGBA surface;
    GdkRGBA target;
    double actual_composite[3];
    double target_composite[3];
    double difference[3];
    double maximum;
    cmsCIELab actual_lab;
    cmsCIELab target_lab;
    double delta_e;
    double max_delta_e = 1.0;

    if (argc != 6 && argc != 7) {
        fprintf(stderr, "usage: %s LABEL PALETTE EXPRESSION SURFACE TARGET [MAX_DELTA_E]\n",
                argv[0]);
        return 2;
    }
    if (argc == 7) {
        char *end;

        /* An explicit, reviewed tolerance for an accepted approximation. */
        max_delta_e = g_ascii_strtod(argv[6], &end);
        if (end == argv[6] || *end != '\0' || !isfinite(max_delta_e) || max_delta_e <= 0.0) {
            fprintf(stderr, "invalid MAX_DELTA_E for %s: %s\n", argv[1], argv[6]);
            return 2;
        }
    }

    properties = gtk_style_properties_new();
    load_palette(properties, argv[2]);
    actual = resolve_expression(properties, argv[3]);
    if (!gdk_rgba_parse(&surface, argv[4]) || !gdk_rgba_parse(&target, argv[5])) {
        fprintf(stderr, "cannot parse surface or target for %s\n", argv[1]);
        return 2;
    }
    if (!rgba_is_finite(&actual) || !rgba_is_finite(&surface) || !rgba_is_finite(&target)) {
        fprintf(stderr, "non-finite resolved color for %s\n", argv[1]);
        return 2;
    }

    actual_composite[0] = actual.red * actual.alpha + surface.red * (1.0 - actual.alpha);
    actual_composite[1] = actual.green * actual.alpha + surface.green * (1.0 - actual.alpha);
    actual_composite[2] = actual.blue * actual.alpha + surface.blue * (1.0 - actual.alpha);
    target_composite[0] = target.red * target.alpha + surface.red * (1.0 - target.alpha);
    target_composite[1] = target.green * target.alpha + surface.green * (1.0 - target.alpha);
    target_composite[2] = target.blue * target.alpha + surface.blue * (1.0 - target.alpha);
    difference[0] = fabs(actual_composite[0] - target_composite[0]) * 255.0;
    difference[1] = fabs(actual_composite[1] - target_composite[1]) * 255.0;
    difference[2] = fabs(actual_composite[2] - target_composite[2]) * 255.0;
    maximum = fmax(difference[0], fmax(difference[1], difference[2]));
    actual_lab = rgb_to_lab(actual_composite);
    target_lab = rgb_to_lab(target_composite);
    delta_e = cmsCIE2000DeltaE(&actual_lab, &target_lab, 1.0, 1.0, 1.0);

    g_object_unref(properties);
    if (!isfinite(maximum) || !isfinite(delta_e)) {
        fprintf(stderr, "non-finite fidelity result for %s\n", argv[1]);
        return 2;
    }
    if (maximum > 2.0 + 1e-6 && delta_e > max_delta_e + 1e-6) {
        fprintf(stderr,
                "FAIL: %s maximum composited channel difference %.6f exceeds 2"
                " and CIEDE2000 %.6f exceeds %g\n",
                argv[1], maximum, delta_e, max_delta_e);
        return 1;
    }

    printf("PASS: %s maximum composited channel difference %.6f; CIEDE2000 %.6f\n",
           argv[1], maximum, delta_e);
    return 0;
}
