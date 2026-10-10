#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
mode=${1:-all}
tmp_dir=$(mktemp -d /tmp/theme-dks-test.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

compile_checkers() {
    # Several modes need the checkers; `all` builds them once.
    if test -x "$tmp_dir/gtk4-css-check"; then
        return
    fi

    cc -std=c11 -Wall -Wextra -Werror \
        "$repo_root/tests/gtk-css-check.c" \
        $(pkg-config --cflags --libs gtk+-3.0) \
        -o "$tmp_dir/gtk3-css-check"

    cc -std=c11 -Wall -Wextra -Werror \
        "$repo_root/tests/gtk-css-check.c" \
        $(pkg-config --cflags --libs gtk4) \
        -o "$tmp_dir/gtk4-css-check"

    printf '* { not-a-property: value; }\n' > "$tmp_dir/invalid.css"
    if "$tmp_dir/gtk3-css-check" "$tmp_dir/invalid.css" >/dev/null 2>&1; then
        fail 'GTK 3 checker accepted deliberately invalid CSS'
    fi
    if "$tmp_dir/gtk4-css-check" "$tmp_dir/invalid.css" >/dev/null 2>&1; then
        fail 'GTK 4 checker accepted deliberately invalid CSS'
    fi
}

check_entry_point() {
    local gtk_dir=$1
    printf '@import url("colors.css");\n@import url("gtk-common.css");\n' \
        > "$tmp_dir/expected-entry.css"
    cmp "$tmp_dir/expected-entry.css" "$repo_root/$gtk_dir/gtk.css" \
        || fail "$gtk_dir/gtk.css is not the generated two-import entry point"
}

check_tangle() {
    local gtk_dir=$1
    local org_file=$2
    local tangle_dir="$tmp_dir/tangle/$gtk_dir"

    # The light and dark modes both need the tangle; `all` compares it once.
    if test -f "$tangle_dir/gtk-common.css"; then
        return
    fi

    mkdir -p "$tangle_dir" \
        "$tmp_dir/tangle/theme-dks-dark/gtk-3.0" \
        "$tmp_dir/tangle/theme-dks-dark/gtk-4.0"
    cp "$repo_root/$gtk_dir/$org_file" "$tangle_dir/$org_file"
    (
        cd "$tangle_dir"
        emacs --batch --quick "$org_file" --funcall org-babel-tangle >/dev/null 2>&1
    )

    cmp "$tangle_dir/gtk.css" "$repo_root/$gtk_dir/gtk.css" \
        || fail "$gtk_dir/gtk.css differs from its Org tangle"
    cmp "$tangle_dir/gtk-common.css" "$repo_root/$gtk_dir/gtk-common.css" \
        || fail "$gtk_dir/gtk-common.css differs from its Org tangle"
}

assert_define() {
    local file=$1
    local name=$2
    local expected=$3
    local actual

    actual=$(awk -v name="$name" '$1 == "@define-color" && $2 == name { sub(/;$/, "", $3); print $3 }' "$file")
    test "$actual" = "$expected" \
        || fail "$file defines $name as '$actual', expected '$expected'"
}

assert_relative_link() {
    local path=$1
    local target

    test -L "$path" || fail "$path is not a symbolic link"
    target=$(readlink "$path")
    case "$target" in
        /*) fail "$path uses an absolute link target" ;;
    esac
    test -e "$path" || fail "$path is a broken symbolic link"
}

assert_multiline_pattern() {
    local file=$1
    local pattern=$2
    local description=$3

    rg --quiet --multiline "$pattern" "$file" \
        || fail "$file does not implement $description"
}

assert_gtk3_title_button_refs() {
    local stylesheet=$1
    local directory=$2
    local variant_suffix=$3
    local label=$4
    local asset
    local control
    local state
    local stem

    test -f "$stylesheet" || fail "$label stylesheet is missing: $stylesheet"

    for control in close maximize minimize; do
        for state in '' '-active' '-backdrop' '-hover'; do
            stem="titlebutton-${control}${state}${variant_suffix}"
            for asset in "$stem.svg" "$stem@2.svg"; do
                test -f "$repo_root/gtk-3.0/objects/$directory/$asset" \
                    || fail "missing $label title-button asset $asset"
                rg --quiet --fixed-strings "$asset" "$stylesheet" \
                    || fail "$label stylesheet does not reference $asset"
            done
        done
    done
}

assert_gtk4_title_button_refs() {
    local stylesheet=$1
    local directory=$2
    local variant_suffix=$3
    local label=$4
    local asset
    local control
    local state
    local stem

    test -f "$stylesheet" || fail "$label stylesheet is missing: $stylesheet"

    for control in close maximize minimize; do
        for state in '' '-active' '-backdrop' '-hover'; do
            stem="titlebutton-${control}${state}${variant_suffix}"
            asset="$stem.svg"
            test -f "$repo_root/gtk-4.0/objects/$directory/$asset" \
                || fail "missing $label title-button asset $asset"
            rg --quiet --fixed-strings "$asset" "$stylesheet" \
                || fail "$label stylesheet does not reference $asset"
            if rg --quiet --fixed-strings "$stem@2.svg" "$stylesheet"; then
                fail "$label stylesheet must not reference $stem@2.svg"
            fi
        done
    done
}

check_light() {
    compile_checkers
    check_entry_point gtk-3.0
    check_entry_point gtk-4.0
    check_tangle gtk-3.0 gtk3.org
    check_tangle gtk-4.0 gtk4.org
    assert_gtk3_title_button_refs \
        "$repo_root/gtk-3.0/gtk-common.css" title-buttons '' 'GTK 3 light'
    assert_gtk4_title_button_refs \
        "$repo_root/gtk-4.0/gtk-common.css" title-buttons '' 'GTK 4 light'
    bash "$repo_root/tests/verify-color-fidelity.sh"
    "$tmp_dir/gtk3-css-check" "$repo_root/gtk-3.0/gtk.css"
    "$tmp_dir/gtk4-css-check" "$repo_root/gtk-4.0/gtk.css"
    printf 'PASS: GTK 3 light parse; GTK 4 light parse; Org tangles match\n'
}

palette_tokens() {
    awk '$1 == "@define-color" { print $2 }' "$1"
}

# Prints the @tokens used by the given CSS files that the palette does not
# define. GTK parses such references without an error.
undefined_tokens() {
    local palette=$1
    shift
    LC_ALL=C comm -13 \
        <(palette_tokens "$palette" | LC_ALL=C sort -u) \
        <(perl -0777 -ne 's{/\*.*?\*/}{}gs; print "$1\n" while /\@([A-Za-z_][A-Za-z0-9_]*)/g' "$@" \
            | grep -vxE 'import|keyframes' | LC_ALL=C sort -u)
}

check_hardcoded_colors() {
    local light="$repo_root/gtk-3.0/colors.css"
    local dark="$repo_root/theme-dks-dark/gtk-3.0/colors-dark.css"
    local -a theme_css=(
        "$repo_root/gtk-3.0/gtk-common.css"
        "$repo_root/gtk-4.0/gtk-common.css"
        "$repo_root/gtk-3.0/apps.css"
        "$repo_root/gtk-4.0/apps.css"
        "$repo_root/gtk-3.0/gnome.css"
        "$repo_root/gtk-4.0/gnome.css"
        "$repo_root/gtk-3.0/xfce.css"
        "$repo_root/theme-dks-dark/gtk-3.0/dark-overrides.css"
        "$repo_root/theme-dks-dark/gtk-4.0/dark-overrides.css"
    )
    local missing

    bash "$repo_root/tests/verify-hardcoded-colors.sh"
    perl "$repo_root/tests/check-hardcoded-colors.pl" "${theme_css[@]}"

    cmp -s <(palette_tokens "$light") <(palette_tokens "$dark") \
        || fail 'colors.css and colors-dark.css must define the same tokens in the same order'

    printf 'a { color: @fg_color; border-color: @no_such_color; }\n/* @commented_color */\n' \
        > "$tmp_dir/undefined-token.css"
    test "$(undefined_tokens "$light" "$tmp_dir/undefined-token.css")" = no_such_color \
        || fail 'undefined-token check does not report @no_such_color'

    missing=$(undefined_tokens "$light" "${theme_css[@]}")
    test -z "$missing" || fail "theme CSS uses undefined colors: ${missing//$'\n'/ }"

    # Tokens are used for their meaning, not only for a matching value.
    local common
    for common in "$repo_root/gtk-3.0/gtk-common.css" "$repo_root/gtk-4.0/gtk-common.css"; do
        test "$(rg -o --fixed-strings '@rubberband_border_color' "$common" | wc -l)" -eq 1 \
            || fail "$common uses @rubberband_border_color outside the rubberband"
        assert_multiline_pattern "$common" \
            'rubberband,\s*\.rubberband \{[^}]*border: 1px solid @rubberband_border_color;' \
            'the rubberband border token'
        assert_multiline_pattern "$common" \
            'switch slider \{[^}]*background-color: @raised_bg_color;' \
            'a raised switch slider'
        assert_multiline_pattern "$common" \
            'scale slider \{[^}]*background-color: @raised_bg_color;' \
            'a raised scale slider'
        assert_multiline_pattern "$common" \
            'scale highlight \{[^}]*background-color: @scale_bg_color;' \
            'the scale highlight token'
        assert_multiline_pattern "$common" \
            'scale highlight:disabled \{[^}]*background-color: @scale_insensitive_bg_color;' \
            'the disabled scale highlight token'
        assert_multiline_pattern "$common" \
            'button\.osd \{[^}]*background-image: none;' \
            'an osd button without the button gradient'
        assert_multiline_pattern "$common" \
            'button\.osd:hover \{[^}]*color: shade\(@selected_bg_color, 2\.0\);' \
            'a light osd hover text'
    done

    printf 'PASS: active GTK color declarations use palette expressions; both palettes define every used token\n'
}

# GTK 4 links to the same dark palette, so `all` checks its anchors once.
assert_dark_palette() {
    local palette="$repo_root/theme-dks-dark/gtk-3.0/colors-dark.css"

    if test -e "$tmp_dir/dark-palette-checked"; then
        return
    fi

    test -f "$palette" || fail 'theme-dks-dark/gtk-3.0/colors-dark.css is missing'
    assert_define "$palette" fg_color '#f7f8fa'
    assert_define "$palette" text_color '#f7f8fa'
    assert_define "$palette" unfocused_fg_color '#d7dde6'
    assert_define "$palette" insensitive_fg_color '#8ea0b7'
    assert_define "$palette" selected_bg_color '#4b5f7a'
    assert_define "$palette" bg_color '#202833'
    assert_define "$palette" base_color '#202833'
    assert_define "$palette" error_color '#b35a5e'
    assert_define "$palette" destructive_color '#b35a5e'
    assert_define "$palette" window_border_color '#5a6c82'
    assert_define "$palette" window_unfocused_border_color '#405168'
    assert_define "$palette" raised_bg_color '@sidebar_bg_color'
    assert_define "$palette" infobar_bg_color '@selected_bg_color'
    touch "$tmp_dir/dark-palette-checked"
}

check_gtk3_dark() {
    local dark_root="$repo_root/theme-dks-dark/gtk-3.0"
    local palette="$dark_root/colors-dark.css"
    local override="$dark_root/dark-overrides.css"
    local link
    local asset

    test -f "$dark_root/gtk.css" || fail 'theme-dks-dark/gtk-3.0/gtk.css is missing'
    assert_dark_palette

    printf '@import url("colors-dark.css");\n@import url("gtk-common.css");\n@import url("dark-overrides.css");\n' \
        > "$tmp_dir/expected-dark-entry.css"
    cmp "$tmp_dir/expected-dark-entry.css" "$dark_root/gtk.css" \
        || fail 'GTK 3 dark entry point is not the expected Org-generated import list'

    # The dark palette and overrides belong to the dark theme; everything else is shared.
    for link in gtk-common.css xfce.css apps.css gnome.css objects; do
        assert_relative_link "$dark_root/$link"
    done
    test -f "$palette" && test ! -L "$palette" \
        || fail 'theme-dks-dark/gtk-3.0/colors-dark.css must be a regular file'
    test -f "$override" && test ! -L "$override" \
        || fail 'theme-dks-dark/gtk-3.0/dark-overrides.css must be a regular file'

    check_tangle gtk-3.0 gtk3.org
    cmp "$tmp_dir/tangle/theme-dks-dark/gtk-3.0/gtk.css" "$dark_root/gtk.css" \
        || fail 'GTK 3 dark gtk.css differs from its Org tangle'

    for asset in "$repo_root"/gtk-3.0/objects/checkbox-objects/*-dark*.svg \
                 "$repo_root"/gtk-3.0/objects/radio-objects/*-dark*.svg; do
        rg --quiet --fixed-strings "$(basename "$asset")" "$override" \
            || fail "dark override does not reference $(basename "$asset")"
    done

    assert_gtk3_title_button_refs \
        "$override" title-buttons-dark '-dark' 'GTK 3 dark'

    find "$repo_root/gtk-3.0/objects/title-buttons-dark" -maxdepth 1 -type f -name '*.svg' -print0 \
        | xargs -0 identify >/dev/null 2>&1

    assert_multiline_pattern "$repo_root/gtk-3.0/xfce.css" \
        '\.thunar notebook treeview \{[^}]*background-color: @bg_color;' \
        'the Thunar main background token'
    assert_multiline_pattern "$repo_root/gtk-3.0/xfce.css" \
        '\.thunar \.shortcuts-pane\.sidebar \{[^}]*background-color: @sidebar_bg_color;' \
        'the Thunar elevated sidebar token'
    assert_multiline_pattern "$repo_root/gtk-3.0/xfce.css" \
        '\.thunar notebook treeview \*:selected \{[^}]*background-color: @selected_bg_color;[^}]*color: @selected_fg_color;' \
        'the Thunar focused selection tokens'
    assert_multiline_pattern "$repo_root/gtk-3.0/xfce.css" \
        '\.thunar notebook treeview:not\(:focus\) \*:selected \{[^}]*background-color: @unfocused_selected_bg_color;[^}]*color: @unfocused_fg_color;' \
        'the Thunar unfocused selection tokens'
    assert_multiline_pattern "$repo_root/gtk-3.0/xfce.css" \
        '\.thunar toolbar button:disabled \{[^}]*color: @insensitive_fg_color;' \
        'the Thunar muted disabled token'
    assert_multiline_pattern "$repo_root/gtk-3.0/gtk-common.css" \
        'window > decoration \{[^}]*border: 1px solid @window_border_color;' \
        'the active CSD window border token'
    assert_multiline_pattern "$repo_root/gtk-3.0/gtk-common.css" \
        'window:backdrop > decoration \{[^}]*border-color: @window_unfocused_border_color;' \
        'the backdrop CSD window border token'
    rg --quiet --fixed-strings '@destructive_color' "$repo_root/gtk-3.0/gtk-common.css" \
        || fail 'GTK 3 shared rules do not consume destructive_color'
    assert_multiline_pattern "$override" \
        'button:disabled,[^{]*\{[^}]*background-image: none;' \
        'dark disabled controls without a light gradient'
    assert_multiline_pattern "$override" \
        'notebook > header > tabs > tab:disabled \{[^}]*background-image: none;' \
        'dark disabled notebook tabs without a light gradient'
    assert_multiline_pattern "$repo_root/gtk-3.0/apps.css" \
        'window\.background:not\(\.solid-csd\) > notebook:not\(\.frame\) \{[^}]*background-color: @content_bg_color;' \
        'a palette-aware LibreOffice document surface'
    assert_multiline_pattern "$repo_root/gtk-3.0/gnome.css" \
        '\.nautilus-window notebook \{[^}]*background-color: @content_bg_color;' \
        'a palette-aware Nautilus notebook surface'
    assert_multiline_pattern "$repo_root/gtk-3.0/gnome.css" \
        '\.gedit-bottom-panel-paned \{[^}]*background-color: @content_bg_color;' \
        'a palette-aware Gedit bottom panel'

    compile_checkers
    "$tmp_dir/gtk3-css-check" "$dark_root/gtk.css"

    mkdir -p "$tmp_dir/gtk3-gnome"
    cp "$palette" "$tmp_dir/gtk3-gnome/colors.css"
    cp "$repo_root/gtk-3.0/gnome.css" "$tmp_dir/gtk3-gnome/gnome.css"
    printf '@import url("colors.css");\n@import url("gnome.css");\n' \
        > "$tmp_dir/gtk3-gnome/check.css"
    "$tmp_dir/gtk3-css-check" "$tmp_dir/gtk3-gnome/check.css"

    printf 'PASS: GTK 3 dark palette, Thunar states, assets, links, parser, and Org tangle\n'
}

check_gtk4_dark() {
    local dark_root="$repo_root/theme-dks-dark/gtk-4.0"
    local palette="$dark_root/colors-dark.css"
    local override="$dark_root/dark-overrides.css"
    local link
    local asset

    test -f "$dark_root/gtk.css" || fail 'theme-dks-dark/gtk-4.0/gtk.css is missing'
    test ! -L "$override" \
        || fail 'theme-dks-dark/gtk-4.0/dark-overrides.css must be GTK 4-specific, not a symbolic link'

    assert_relative_link "$palette"
    test "$(readlink "$palette")" = ../gtk-3.0/colors-dark.css \
        || fail 'theme-dks-dark/gtk-4.0/colors-dark.css must link to ../gtk-3.0/colors-dark.css'
    assert_dark_palette

    printf '@import url("colors-dark.css");\n@import url("gtk-common.css");\n@import url("dark-overrides.css");\n' \
        > "$tmp_dir/expected-dark-entry.css"
    cmp "$tmp_dir/expected-dark-entry.css" "$dark_root/gtk.css" \
        || fail 'GTK 4 dark entry point is not the expected Org-generated import list'

    for link in gtk-common.css apps.css gnome.css objects; do
        assert_relative_link "$dark_root/$link"
    done

    check_tangle gtk-4.0 gtk4.org
    cmp "$tmp_dir/tangle/theme-dks-dark/gtk-4.0/gtk.css" "$dark_root/gtk.css" \
        || fail 'GTK 4 dark gtk.css differs from its Org tangle'

    for asset in "$repo_root"/gtk-4.0/objects/checkbox-objects/*-dark*.svg \
                 "$repo_root"/gtk-4.0/objects/radio-objects/*-dark*.svg; do
        rg --quiet --fixed-strings "$(basename "$asset")" "$override" \
            || fail "GTK 4 dark override does not reference $(basename "$asset")"
    done

    assert_gtk4_title_button_refs \
        "$override" title-buttons-dark '-dark' 'GTK 4 dark'

    find "$repo_root/gtk-4.0/objects/title-buttons-dark" -maxdepth 1 -type f -name '*.svg' -print0 \
        | xargs -0 identify >/dev/null 2>&1
    if find "$repo_root/gtk-4.0/objects/title-buttons-dark" -maxdepth 1 -type f -perm /111 -print -quit \
        | grep -q .; then
        fail 'GTK 4 dark SVG assets must not be executable'
    fi

    assert_multiline_pattern "$repo_root/gtk-4.0/gtk-common.css" \
        'window \{[^}]*border: 1px solid @window_border_color;' \
        'the active GTK 4 CSD border token'
    assert_multiline_pattern "$repo_root/gtk-4.0/gtk-common.css" \
        'window:backdrop \{[^}]*border-color: @window_unfocused_border_color;' \
        'the backdrop GTK 4 CSD border token'
    assert_multiline_pattern "$override" \
        'listview > row:selected,[^{]*gridview > child:selected \{[^}]*background-color: @selected_bg_color;[^}]*color: @selected_fg_color;' \
        'GTK 4 list and grid selection tokens'
    assert_multiline_pattern "$override" \
        'button:disabled,[^{]*\{[^}]*background-image: none;' \
        'GTK 4 dark disabled controls without a light gradient'
    assert_multiline_pattern "$override" \
        'popover\.menu > contents,[^{]*popover\.menu > arrow \{[^}]*background-color: @sidebar_bg_color;' \
        'GTK 4 dark menu surfaces'
    assert_multiline_pattern "$override" \
        'dialog,[^{]*window\.dialog \{[^}]*background-color: @bg_color;' \
        'GTK 4 dark dialog surfaces'
    assert_multiline_pattern "$override" \
        'tooltip,[^{]*tooltip\.background \{[^}]*background-color: @tooltip_bg_color;' \
        'GTK 4 dark tooltip surfaces'
    assert_multiline_pattern "$repo_root/gtk-4.0/apps.css" \
        'window\.background:not\(\.solid-csd\) > notebook:not\(\.frame\) \{[^}]*background-color: @content_bg_color;' \
        'a palette-aware LibreOffice document surface'
    assert_multiline_pattern "$repo_root/gtk-4.0/gnome.css" \
        '\.nautilus-window notebook \{[^}]*background-color: @content_bg_color;' \
        'a palette-aware Nautilus notebook surface'
    assert_multiline_pattern "$repo_root/gtk-4.0/gnome.css" \
        '\.gedit-bottom-panel-paned \{[^}]*background-color: @content_bg_color;' \
        'a palette-aware Gedit bottom panel'
    rg --quiet --fixed-strings '@destructive_color' "$repo_root/gtk-4.0/gtk-common.css" \
        || fail 'GTK 4 shared rules do not consume destructive_color'

    compile_checkers
    "$tmp_dir/gtk4-css-check" "$dark_root/gtk.css"

    mkdir -p "$tmp_dir/gtk4-gnome"
    cp "$palette" "$tmp_dir/gtk4-gnome/colors.css"
    cp "$repo_root/gtk-4.0/gnome.css" "$tmp_dir/gtk4-gnome/gnome.css"
    printf '@import url("colors.css");\n@import url("gnome.css");\n' \
        > "$tmp_dir/gtk4-gnome/check.css"
    "$tmp_dir/gtk4-css-check" "$tmp_dir/gtk4-gnome/check.css"

    printf 'PASS: GTK 4 dark palette, states, assets, links, parser, and Org tangle\n'
}

assert_themerc_value() {
    local file=$1
    local key=$2
    local expected=$3
    local actual

    actual=$(awk -F= -v key="$key" '$1 == key { print $2 }' "$file")
    test "$actual" = "$expected" \
        || fail "$file sets $key to '$actual', expected '$expected'"
}

assert_image_size() {
    local file=$1
    local expected=$2
    local actual

    test -f "$file" || fail "$file is missing"
    actual=$(identify -format '%wx%h' "$file")
    test "$actual" = "$expected" \
        || fail "$file is ${actual}px, expected ${expected}px"
}

assert_alpha_levels() {
    local file=$1
    local expected=$2
    local actual

    actual=$(magick "$file" -alpha extract -format '%k' info:)
    test "$actual" = "$expected" \
        || fail "$file has $actual alpha levels, expected $expected"
}

assert_transparent_top_rows() {
    local file=$1
    local rows=$2
    local width
    local maximum

    width=$(identify -format '%w' "$file")
    maximum=$(magick "$file" -crop "${width}x${rows}+0+0" +repage \
        -alpha extract -format '%[fx:maxima]' info:)
    test "$maximum" = 0 \
        || fail "$file does not have $rows fully transparent rows at the top"
}

assert_row_has_alpha() {
    local file=$1
    local row=$2
    local width
    local maximum

    width=$(identify -format '%w' "$file")
    maximum=$(magick "$file" -crop "${width}x1+0+${row}" +repage \
        -alpha extract -format '%[fx:maxima]' info:)
    test "$maximum" != 0 \
        || fail "$file row $row is fully transparent"
}

assert_alpha_bounds() {
    local file=$1
    local expected=$2
    local actual

    actual=$(magick "$file" -alpha extract -threshold 0 -trim \
        -format '%wx%h%O' info:)
    test "$actual" = "$expected" \
        || fail "$file has nontransparent bounds $actual, expected $expected"
}

assert_solid_rgb() {
    local file=$1
    local expected=$2
    local colors
    local actual

    colors=$(magick "$file" -background "#$expected" -alpha background \
        -alpha off -format '%k' info:)
    test "$colors" = 1 || fail "$file contains $colors RGB colors, expected one"
    actual=$(magick "$file" -background "#$expected" -alpha background \
        -alpha off -format '%[hex:p{0,0}]' info:)
    test "$actual" = "$expected" \
        || fail "$file uses RGB #$actual, expected #$expected"
}

assert_pixel_hex() {
    local file=$1
    local point=$2
    local expected=$3
    local actual

    actual=$(magick "$file" -format "%[hex:p{$point}]" info:)
    actual=${actual:0:6}
    test "$actual" = "$expected" \
        || fail "$file pixel $point is #$actual, expected #$expected"
}

assert_pixel_alpha_byte() {
    local file=$1
    local point=$2
    local expected=$3
    local actual

    actual=$(magick "$file" -format "%[fx:round(255*p{$point}.a)]" info:)
    test "$actual" = "$expected" \
        || fail "$file pixel $point has alpha $actual, expected $expected"
}

assert_mirrored_pair() {
    local left=$1
    local right=$2
    local flipped="$tmp_dir/$(basename "$right").flipped.png"

    magick "$right" -flop "$flipped"
    compare -metric AE "$left" "$flipped" null: 2> "$tmp_dir/compare.txt" \
        || fail "$left and $right are not mirrored pairs"
    test "$(cat "$tmp_dir/compare.txt")" = '0 (0)' \
        || fail "$left and $right differ after mirroring"
}

check_xfwm_dark() {
    local light_root="$repo_root/xfwm4"
    local dark_root="$repo_root/theme-dks-dark/xfwm4"
    local asset
    local corner
    local name
    local state

    test -f "$dark_root/themerc" || fail 'theme-dks-dark/xfwm4/themerc is missing'

    assert_themerc_value "$dark_root/themerc" active_border_color '#5a6c82'
    assert_themerc_value "$dark_root/themerc" inactive_border_color '#405168'
    assert_themerc_value "$dark_root/themerc" active_color_2 '#202833'
    assert_themerc_value "$dark_root/themerc" active_text_color '#dee3ed'
    assert_themerc_value "$dark_root/themerc" inactive_text_color '#777777'
    assert_themerc_value "$light_root/themerc" title_vertical_offset_active '2'
    assert_themerc_value "$light_root/themerc" title_vertical_offset_inactive '1'
    assert_themerc_value "$dark_root/themerc" title_vertical_offset_active '2'
    assert_themerc_value "$dark_root/themerc" title_vertical_offset_inactive '1'
    assert_themerc_value "$dark_root/themerc" shadow_delta_height '4'
    assert_themerc_value "$dark_root/themerc" shadow_delta_y '-6'

    for asset in "$light_root"/*; do
        name=$(basename "$asset")
        test "$name" = themerc && continue
        test -f "$dark_root/$name" || fail "$dark_root/$name is missing"
    done

    if find "$dark_root" -maxdepth 1 \( -iname '*glow*' -o -iname '*frame*' \) -print -quit \
        | grep -q .; then
        fail 'dark Xfwm4 variant contains a second frame or glow asset'
    fi

    find -L "$dark_root" -maxdepth 1 -type f \( -name '*.xpm' -o -name '*.png' \) -print0 \
        | xargs -0 identify >/dev/null 2>&1
    test "$(rg -l 's active_border_color' "$dark_root"/*.xpm | wc -l)" -eq 10 \
        || fail 'active XPM frame edges do not all map to active_border_color'
    test "$(rg -l 's inactive_border_color' "$dark_root"/*.xpm | wc -l)" -eq 10 \
        || fail 'inactive XPM frame edges do not all map to inactive_border_color'

    for state in active inactive; do
        for corner in top-left top-right; do
            assert_image_size "$light_root/$corner-$state.xpm" 8x30
            assert_image_size "$light_root/$corner-$state.png" 8x30
            assert_image_size "$dark_root/$corner-$state.png" 8x30
            assert_row_has_alpha "$light_root/$corner-$state.xpm" 0
            assert_row_has_alpha "$light_root/$corner-$state.png" 0
            assert_row_has_alpha "$dark_root/$corner-$state.png" 0
            assert_row_has_alpha "$light_root/$corner-$state.png" 29
            assert_row_has_alpha "$dark_root/$corner-$state.png" 29
            assert_alpha_levels "$light_root/$corner-$state.png" 24
            assert_alpha_levels "$dark_root/$corner-$state.png" 24
        done

        # An 8px outer radius fills the 8px corner canvas exactly. These
        # hand-checked edge samples distinguish it from the former 6px curve.
        assert_pixel_alpha_byte "$light_root/top-left-$state.xpm" 4,0 0
        assert_pixel_alpha_byte "$light_root/top-left-$state.xpm" 5,0 255
        assert_pixel_alpha_byte "$light_root/top-left-$state.xpm" 2,1 0
        assert_pixel_alpha_byte "$light_root/top-left-$state.xpm" 3,1 255
        assert_pixel_alpha_byte "$light_root/top-left-$state.xpm" 1,2 0
        assert_pixel_alpha_byte "$light_root/top-left-$state.xpm" 2,2 255
        assert_pixel_alpha_byte "$light_root/top-left-$state.xpm" 0,4 0
        assert_pixel_alpha_byte "$light_root/top-left-$state.xpm" 1,4 255
        assert_pixel_alpha_byte "$light_root/top-left-$state.xpm" 0,5 255
        assert_pixel_alpha_byte "$light_root/top-right-$state.xpm" 2,0 255
        assert_pixel_alpha_byte "$light_root/top-right-$state.xpm" 3,0 0
    done

    for corner_root in "$light_root" "$dark_root"; do
        assert_pixel_alpha_byte "$corner_root/top-left-active.png" 4,0 49
        assert_pixel_alpha_byte "$corner_root/top-left-active.png" 3,1 141
        assert_pixel_alpha_byte "$corner_root/top-left-active.png" 2,2 183
        assert_pixel_alpha_byte "$corner_root/top-left-active.png" 0,5 152
        assert_pixel_alpha_byte "$corner_root/top-left-inactive.png" 4,0 59
        assert_pixel_alpha_byte "$corner_root/top-left-inactive.png" 3,1 158
        assert_pixel_alpha_byte "$corner_root/top-left-inactive.png" 2,2 200
        assert_pixel_alpha_byte "$corner_root/top-left-inactive.png" 0,5 173
    done

    assert_image_size "$light_root/button.xpm" 18x22
    assert_image_size "$light_root/button-active.xpm" 18x22
    for state in active inactive prelight pressed; do
        assert_image_size "$light_root/close-$state.xpm" 18x22
        assert_image_size "$light_root/hide-$state.xpm" 18x22
        assert_image_size "$light_root/maximize-$state.xpm" 18x22
        assert_image_size "$light_root/shade-$state.xpm" 18x22
        assert_image_size "$light_root/close-$state.png" 18x22
        assert_alpha_bounds "$light_root/close-$state.png" 18x18+0+4
        case "$state" in
            active|inactive)
                assert_image_size "$light_root/hide-$state.png" 16x20
                assert_image_size "$light_root/maximize-$state.png" 16x20
                assert_image_size "$light_root/shade-$state.png" 16x20
                assert_alpha_bounds "$light_root/hide-$state.png" 10x4+3+10
                assert_alpha_bounds "$light_root/maximize-$state.png" 10x10+3+7
                assert_alpha_bounds "$light_root/shade-$state.png" 10x10+3+7
                if test "$state" = active; then
                    assert_transparent_top_rows "$light_root/close-$state.png" 4
                    assert_transparent_top_rows "$light_root/hide-$state.png" 10
                    assert_transparent_top_rows "$light_root/maximize-$state.png" 7
                    assert_transparent_top_rows "$light_root/shade-$state.png" 7
                fi
                ;;
            prelight|pressed)
                assert_image_size "$light_root/hide-$state.png" 18x22
                assert_image_size "$light_root/maximize-$state.png" 18x22
                assert_image_size "$light_root/shade-$state.png" 18x22
                assert_alpha_bounds "$light_root/hide-$state.png" 18x18+0+4
                assert_alpha_bounds "$light_root/maximize-$state.png" 18x18+0+4
                assert_alpha_bounds "$light_root/shade-$state.png" 18x18+0+4
                assert_transparent_top_rows "$light_root/close-$state.png" 4
                assert_transparent_top_rows "$light_root/hide-$state.png" 4
                assert_transparent_top_rows "$light_root/maximize-$state.png" 4
                assert_transparent_top_rows "$light_root/shade-$state.png" 4
                ;;
        esac
    done
    for state in active inactive pressed; do
        assert_image_size "$light_root/menu-$state.xpm" 18x22
    done

    assert_solid_rgb "$light_root/top-left-active.png" 808080
    assert_solid_rgb "$light_root/top-left-inactive.png" 808080
    assert_solid_rgb "$dark_root/top-left-active.png" 5A6C82
    assert_solid_rgb "$dark_root/top-left-inactive.png" 405168
    assert_mirrored_pair "$light_root/top-left-active.png" "$light_root/top-right-active.png"
    assert_mirrored_pair "$light_root/top-left-inactive.png" "$light_root/top-right-inactive.png"
    assert_mirrored_pair "$dark_root/top-left-active.png" "$dark_root/top-right-active.png"
    assert_mirrored_pair "$dark_root/top-left-inactive.png" "$dark_root/top-right-inactive.png"

    for state in active inactive; do
        assert_pixel_hex "$light_root/left-$state.xpm" 0,0 808080
        assert_pixel_hex "$light_root/right-$state.xpm" 0,0 B5B8C0
        assert_pixel_hex "$light_root/right-$state.xpm" 2,0 808080
        assert_pixel_hex "$light_root/bottom-$state.xpm" 0,0 B5B8C0
        assert_pixel_hex "$light_root/bottom-$state.xpm" 0,2 808080
        assert_pixel_hex "$light_root/bottom-left-$state.xpm" 0,0 808080
        assert_pixel_hex "$light_root/bottom-left-$state.xpm" 2,0 B5B8C0
        assert_pixel_hex "$light_root/bottom-right-$state.xpm" 2,0 B5B8C0
        assert_pixel_hex "$light_root/bottom-right-$state.xpm" 4,0 808080

        if test "$state" = active; then
            assert_pixel_hex "$light_root/left-$state.xpm" 1,0 808080
            assert_pixel_hex "$light_root/right-$state.xpm" 1,0 808080
            assert_pixel_hex "$light_root/bottom-$state.xpm" 0,1 808080
            assert_pixel_hex "$light_root/bottom-left-$state.xpm" 1,0 808080
            assert_pixel_hex "$light_root/bottom-right-$state.xpm" 3,0 808080
        else
            assert_pixel_hex "$light_root/left-$state.xpm" 1,0 B5B8C0
            assert_pixel_hex "$light_root/right-$state.xpm" 1,0 B5B8C0
            assert_pixel_hex "$light_root/bottom-$state.xpm" 0,1 B5B8C0
            assert_pixel_hex "$light_root/bottom-left-$state.xpm" 1,0 B5B8C0
            assert_pixel_hex "$light_root/bottom-right-$state.xpm" 3,0 B5B8C0
        fi

        for title in 1 2 3 4 5; do
            assert_image_size "$light_root/title-$title-$state.xpm" 5x30
            assert_pixel_hex "$light_root/title-$title-$state.xpm" 0,0 808080
            if test "$state" = active; then
                assert_pixel_hex "$light_root/title-$title-$state.xpm" 0,1 808080
            else
                assert_pixel_hex "$light_root/title-$title-$state.xpm" 0,1 B5B8C0
            fi
            assert_pixel_hex "$light_root/title-$title-$state.xpm" 0,2 B5B8C0
            assert_pixel_hex "$light_root/title-$title-$state.xpm" 0,29 B5B8C0
        done
    done

    printf 'PASS: light/dark Xfwm4 30px titlebars, 8px antialiased corners, and unclipped state-aligned buttons\n'
}

assert_theme_metadata() {
    local file=$1
    local expected=$2

    test -f "$file" || fail "$file is missing"
    test "$(awk -F= '$1 == "Name" { print $2 }' "$file")" = "$expected" \
        || fail "$file has the wrong Name"
    test "$(awk -F= '$1 == "GtkTheme" { print $2 }' "$file")" = "$expected" \
        || fail "$file has the wrong GtkTheme"
}

assert_no_executable_code() {
    local root=$1
    local file

    if find "$root" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.pl' -o -name '*.desktop' \) \
        -print -quit | grep -q .; then
        fail "$root contains executable or autostart payload files"
    fi

    while IFS= read -r -d '' file; do
        if head -c 2 "$file" 2>/dev/null | grep -q '^#!'; then
            fail "$root contains a shebang executable: $file"
        fi
        if test "$(head -c 4 "$file" 2>/dev/null || true)" = $'\x7fELF'; then
            fail "$root contains an ELF binary: $file"
        fi
    done < <(find "$root" -type f -print0)
}

check_layout() {
    local moved="$tmp_dir/moved"
    local installed="$tmp_dir/installed"

    assert_theme_metadata "$repo_root/index.theme" theme-dks
    assert_theme_metadata "$repo_root/theme-dks-dark/index.theme" theme-dks-dark
    test -d "$repo_root/theme-dks-dark/gtk-3.0" || fail 'dark GTK 3 root is missing'
    test -d "$repo_root/theme-dks-dark/gtk-4.0" || fail 'dark GTK 4 root is missing'
    test -d "$repo_root/theme-dks-dark/xfwm4" || fail 'dark Xfwm4 root is missing'
    test ! -e "$repo_root/theme-dks-dark/gtk-2.0" || fail 'dark root must not include GTK 2'
    assert_no_executable_code "$repo_root/theme-dks-dark"

    mkdir -p "$moved"
    cp -a "$repo_root/gtk-3.0" "$repo_root/gtk-4.0" "$repo_root/xfwm4" \
        "$repo_root/theme-dks-dark" "$moved/"
    if find -L "$moved/theme-dks-dark" -type l -print -quit | grep -q .; then
        fail 'relative links break after moving the source checkout'
    fi

    mkdir -p "$installed"
    cp -aL "$repo_root/theme-dks-dark" "$installed/theme-dks-dark"
    if find "$installed/theme-dks-dark" -type l -print -quit | grep -q .; then
        fail 'dereferenced installation still contains symbolic links'
    fi
    test ! -e "$installed/theme-dks-dark/gtk-2.0" \
        || fail 'dereferenced dark installation unexpectedly includes GTK 2'
    assert_no_executable_code "$installed/theme-dks-dark"

    compile_checkers
    "$tmp_dir/gtk3-css-check" "$installed/theme-dks-dark/gtk-3.0/gtk.css"
    "$tmp_dir/gtk4-css-check" "$installed/theme-dks-dark/gtk-4.0/gtk.css"
    find "$installed/theme-dks-dark/xfwm4" -maxdepth 1 -type f \
        \( -name '*.xpm' -o -name '*.png' \) -print0 | xargs -0 identify >/dev/null 2>&1

    printf 'PASS: source-move and dereferenced-copy layouts are self-contained; no GTK 2 or executable code\n'
}

check_title_buttons() {
    bash "$repo_root/tests/verify-title-buttons.sh"
}

check_all() {
    check_light
    check_hardcoded_colors
    check_gtk3_dark
    check_gtk4_dark
    check_xfwm_dark
    check_layout
    check_title_buttons
    printf 'PASS: all theme verification modes\n'
}

case "$mode" in
    light)
        check_light
        ;;
    hardcoded-colors)
        check_hardcoded_colors
        ;;
    gtk3-dark)
        check_gtk3_dark
        ;;
    gtk4-dark)
        check_gtk4_dark
        ;;
    xfwm-dark)
        check_xfwm_dark
        ;;
    layout)
        check_layout
        ;;
    title-buttons)
        check_title_buttons
        ;;
    all)
        check_all
        ;;
    *)
        fail "unknown verification mode: $mode"
        ;;
esac
