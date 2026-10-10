#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
palette="$repo_root/gtk-3.0/colors.css"
dark_palette="$repo_root/theme-dks-dark/gtk-3.0/colors-dark.css"
tmp_dir=$(mktemp -d /tmp/theme-dks-color-fidelity.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

color_value() {
    local name=$1
    local value

    value=$(awk -v name="$name" '
        $1 == "@define-color" && $2 == name {
            sub(/;$/, "", $3)
            print $3
            exit
        }
    ' "$palette")
    test -n "$value" || fail "cannot read literal palette color $name"
    printf '%s\n' "$value"
}

assert_occurrences() {
    local expected=$1
    local expression=$2
    local file=$3
    local actual

    actual=$( (rg -o --fixed-strings -- "$expression" "$file" || true) | wc -l)
    test "$actual" -eq "$expected" \
        || fail "$file contains $actual calibrated expressions, expected $expected: $expression"
}

cc -std=c11 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    "$repo_root/tests/check-color-expression-fidelity.c" \
    -o "$tmp_dir/check-color-expression-fidelity" \
    $(pkg-config --cflags --libs gtk+-3.0 lcms2) -lm

set +e
"$tmp_dir/check-color-expression-fidelity" invalid-factor "$palette" \
    'shade(@fg_color, nan)' '#ffffff' '#202020' >/dev/null 2>&1
invalid_factor_status=$?
set -e
test "$invalid_factor_status" -eq 2 \
    || fail "non-finite color factor exited $invalid_factor_status, expected 2"

set +e
"$tmp_dir/check-color-expression-fidelity" invalid-tolerance "$palette" \
    '@fg_color' '#ffffff' '#202020' nan >/dev/null 2>&1
invalid_tolerance_status=$?
set -e
test "$invalid_tolerance_status" -eq 2 \
    || fail "non-finite MAX_DELTA_E exited $invalid_tolerance_status, expected 2"

suggested_hover='@suggested_hover_bg_color'
selected_disabled='mix(shade(@selected_bg_color, 1.6455), shade(@link_color, 1.4566), 0.1962)'
treeview_disabled_selected='mix(@link_color, @selected_fg_color, 0.36)'
nautilus='mix(shade(@tab_bg_color, 1.5013), shade(@selected_bg_color, 1.036), 0.1845)'
osd='mix(shade(@selected_bg_color, 0.5702), shade(@tooltip_bg_color, 1.002), 0.3893)'
magnifier='mix(shade(@base_color, 1.026), @link_color, 0.042)'
warning_infobar='@infobar_warning_bg_color'
toolbar_low='mix(shade(@toolbar_bg_color, 0.55), @bg_color, 0.25)'
osd_disabled='mix(mix(mix(@fg_color, @insensitive_fg_color, 0.583), @selected_bg_color, 0.2), @insensitive_fg_color, 0.04)'
infobar_high='@infobar_bg_color'
infobar_low='@infobar_shade_color'
toolbar_combo='alpha(@toolbar_fg_color, 0.8)'
app_disabled='alpha(@toolbar_fg_color, 0.48)'
xfdesktop_active='alpha(@desktop_icon_active_fg_color, 0.75)'
osd_pressed_border='alpha(@osd_border_color, 0.37)'
entry_border='alpha(@dim_border_color, 1.6667)'
entry_thin_border='alpha(@dim_border_color, 0.3333)'
toolbar_highlight='alpha(@highlight_color, 0.4)'
error_warning_border='mix(@error_color, @warning_color, 0.5)'
tasklist_border='shade(@button_active_bg_color, 0.58)'
notify_trough_border='shade(@button_active_bg_color, 0.14)'
destructive_disabled_bg='mix(shade(@sidebar_bg_color, 0.996), @error_color, 0.2224)'

# five hover backgrounds plus the primary-toolbar gradient end shaded from it
assert_occurrences 6 "$suggested_hover" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 3 "$suggested_hover" "$repo_root/gtk-4.0/gtk4.org"
assert_occurrences 1 '@define-color suggested_hover_bg_color #4b86e0;' "$palette"
assert_occurrences 1 "$selected_disabled" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 2 "$selected_disabled" "$repo_root/gtk-4.0/gtk4.org"
assert_occurrences 1 "$treeview_disabled_selected" "$repo_root/gtk-4.0/gtk4.org"
# trough and scrollbar border share one color
assert_occurrences 2 "alpha($nautilus, 0.85)" "$repo_root/gtk-3.0/gnome.css"
assert_occurrences 2 "alpha($nautilus, 0.85)" "$repo_root/gtk-4.0/gnome.css"
assert_occurrences 1 "alpha($osd, 0.95)" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 1 "alpha($osd, 0.95)" "$repo_root/gtk-4.0/gtk4.org"
# the osd hover surface is the osd surface shaded lighter
assert_occurrences 1 "alpha(shade($osd, 1.3), 0.95)" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 1 "alpha(shade($osd, 1.3), 0.95)" "$repo_root/gtk-4.0/gtk4.org"
assert_occurrences 2 "alpha($osd, 0.85)" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 1 "alpha($osd, 0.85)" "$repo_root/gtk-4.0/gtk4.org"
assert_occurrences 1 "alpha($magnifier, 0.85)" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 1 "alpha($magnifier, 0.85)" "$repo_root/gtk-4.0/gtk4.org"
assert_occurrences 2 "$warning_infobar" "$repo_root/gtk-4.0/gtk4.org"
# GTK 3 warning and error bars keep their own colors
assert_occurrences 2 "$warning_infobar" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 1 'linear-gradient(to bottom,@error_color,@error_color)' "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 1 '@define-color infobar_warning_bg_color #ff851a;' "$palette"
assert_occurrences 1 '@define-color infobar_warning_bg_color @warning_color;' "$dark_palette"
assert_occurrences 3 "$toolbar_low" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 3 "$toolbar_low" "$repo_root/gtk-4.0/gtk4.org"
assert_occurrences 1 "color: $osd_disabled;" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 1 "color: $osd_disabled;" "$repo_root/gtk-4.0/gtk4.org"
assert_occurrences 7 "$infobar_high" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 7 "$infobar_low" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 1 "$toolbar_combo" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 1 "$app_disabled" "$repo_root/gtk-3.0/apps.css"
assert_occurrences 1 "$app_disabled" "$repo_root/gtk-4.0/apps.css"
assert_occurrences 1 "$xfdesktop_active" "$repo_root/gtk-3.0/xfce.css"
assert_occurrences 1 '@define-color toolbar_fg_color #292121;' "$palette"
assert_occurrences 1 '@define-color desktop_icon_active_fg_color #398ee7;' "$palette"
assert_occurrences 1 '@define-color infobar_bg_color mix(@selected_bg_color, @content_bg_color, 0.8);' "$palette"
assert_occurrences 1 '@define-color infobar_shade_color shade(@selected_bg_color, 0.85);' "$palette"
assert_occurrences 1 '@define-color toolbar_fg_color @fg_color;' "$dark_palette"
assert_occurrences 1 '@define-color infobar_bg_color @selected_bg_color;' "$dark_palette"
# scale tokens alias general tokens in light; only dark has its own values
assert_occurrences 1 '@define-color scale_bg_color @selected_bg_color;' "$palette"
assert_occurrences 1 '@define-color scale_insensitive_bg_color @insensitive_fg_color;' "$palette"
assert_occurrences 1 '@define-color scale_bg_color shade(@selected_bg_color, 1.75);' "$dark_palette"
assert_occurrences 1 '@define-color scale_insensitive_bg_color shade(@selected_bg_color, 0.8);' "$dark_palette"
assert_occurrences 3 "$osd_pressed_border" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 3 "$osd_pressed_border" "$repo_root/gtk-4.0/gtk4.org"
# toolbar entry border and its focus state, plus the toolbar spinbutton frame
assert_occurrences 3 "$entry_border" "$repo_root/gtk-3.0/gtk3.org"
# two thin entry borders plus ten inset 1px separators
assert_occurrences 12 "$entry_thin_border" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 2 "$toolbar_highlight" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 2 "$error_warning_border" "$repo_root/gtk-3.0/gtk3.org"
assert_occurrences 1 "$tasklist_border" "$repo_root/gtk-3.0/xfce.css"
assert_occurrences 1 "$notify_trough_border" "$repo_root/gtk-3.0/xfce.css"
# border tokens keep the former literal border colors in the light palette
assert_occurrences 1 '@define-color selected_border_color #0277db;' "$palette"
assert_occurrences 1 '@define-color insensitive_border_color rgba(207, 214, 230, 0.55);' "$palette"
assert_occurrences 1 '@define-color drop_target_color #F08437;' "$palette"
assert_occurrences 1 '@define-color highlight_color #ffffff;' "$palette"
assert_occurrences 1 '@define-color shade_color @fg_color;' "$palette"
assert_occurrences 1 '@define-color osd_border_color rgba(35, 38, 46, 0.95);' "$palette"
assert_occurrences 1 '@define-color warning_color #F27835;' "$palette"
assert_occurrences 1 '@define-color error_color #FC4138;' "$palette"
assert_occurrences 1 '@define-color button_active_bg_color #646772;' "$palette"

"$tmp_dir/check-color-expression-fidelity" selected-disabled "$palette" \
    "$selected_disabled" '#000000' '#90b5ec'
"$tmp_dir/check-color-expression-fidelity" nautilus-trough "$palette" \
    "alpha($nautilus, 0.85)" '#ffffff' 'rgba(222, 227, 240, 0.85)'
"$tmp_dir/check-color-expression-fidelity" osd-surface "$palette" \
    "alpha($osd, 0.95)" "$(color_value base_color)" 'rgba(53, 57, 69, 0.95)'
"$tmp_dir/check-color-expression-fidelity" magnifier-surface "$palette" \
    "alpha($magnifier, 0.85)" "$(color_value base_color)" 'rgba(240, 242, 248, 0.85)'
"$tmp_dir/check-color-expression-fidelity" toolbar-low "$palette" \
    "$toolbar_low" '#ffffff' '#7e8185'
"$tmp_dir/check-color-expression-fidelity" osd-disabled "$palette" \
    "$osd_disabled" '#ffffff' '#5d626e'
"$tmp_dir/check-color-expression-fidelity" app-disabled "$palette" \
    "$app_disabled" "$(color_value toolbar_bg_color)" 'rgba(40, 32, 32, 0.48)'

# Border approximations. Surfaces are what each border is drawn over.
# The explicit MAX_DELTA_E values are approximations accepted on review.
"$tmp_dir/check-color-expression-fidelity" osd-pressed-border "$palette" \
    "$osd_pressed_border" "$(color_value selected_bg_color)" 'rgba(26, 28, 34, 0.35)' 1.25
"$tmp_dir/check-color-expression-fidelity" osd-disabled-border "$palette" \
    "$osd_pressed_border" '#d5d8dc' 'rgba(26, 28, 34, 0.35)' 1.25
"$tmp_dir/check-color-expression-fidelity" entry-disabled-border "$palette" \
    "$entry_thin_border" '#ecedef' 'rgba(82, 93, 118, 0.1)' 1.35
"$tmp_dir/check-color-expression-fidelity" entry-border "$palette" \
    "$entry_border" "$(color_value content_bg_color)" 'rgba(105, 105, 105, 0.5)'
"$tmp_dir/check-color-expression-fidelity" entry-separator "$palette" \
    "$entry_thin_border" "$(color_value content_bg_color)" 'rgba(105, 105, 105, 0.1)'
"$tmp_dir/check-color-expression-fidelity" toolbar-highlight "$palette" \
    "$toolbar_highlight" "$(color_value toolbar_bg_color)" 'rgba(212, 213, 219, 0.95)'
"$tmp_dir/check-color-expression-fidelity" error-warning-border "$palette" \
    "$error_warning_border" '#ffffff' '#f75d37'
"$tmp_dir/check-color-expression-fidelity" tasklist-border "$palette" \
    "$tasklist_border" "$(color_value panel_bg_color)" '#3a3c41'
# former border: shade(#46484f, 0.2)
"$tmp_dir/check-color-expression-fidelity" notify-trough-border "$palette" \
    "$notify_trough_border" '#000000' '#0f0f0f'
# the destructive disabled border is transparent, so its background must match the former #e3bebf border
"$tmp_dir/check-color-expression-fidelity" destructive-disabled-border "$palette" \
    "$destructive_disabled_bg" '#ffffff' '#e3bebf'

# in dark, the osd hover surface keeps the former hover color over the window
"$tmp_dir/check-color-expression-fidelity" osd-hover-dark "$dark_palette" \
    "alpha(shade($osd, 1.3), 0.95)" '#202833' '#39485c'
# reassigned token: GTK 4 disabled selected treeview text
"$tmp_dir/check-color-expression-fidelity" treeview-disabled-selected "$palette" \
    "$treeview_disabled_selected" '#ffffff' '#79a6e8' 1.95

printf 'PASS: calibrated color expressions stay within channel or perceptual tolerance\n'
