#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
checker="$repo_root/tests/check-hardcoded-colors.pl"
tmp_dir=$(mktemp -d /tmp/theme-dks-color-check.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

expect_status() {
    local expected=$1
    local description=$2
    shift 2

    set +e
    "$@" >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"
    local actual=$?
    set -e

    test "$actual" -eq "$expected" \
        || fail "$description exited $actual, expected $expected"
}

cat >"$tmp_dir/valid.css" <<'EOF'
/*
 * color: #ffffff;
 * background-image: linear-gradient(#000000, white);
 * border-color: #ffffff;
 */
button {
  color: @fg_color;
  background-color: alpha(@base_color, 0.5);
  background-image: linear-gradient(
    to bottom,
    shade(@button_bg_color, 1.05),
    @button_bg_color
  );
  border-color: rgba(0, 0, 0, 0.12);
  border-top: 1px solid rgba(255,255,255,0.4);
  border-bottom-color: transparent;
  border-image: linear-gradient(to bottom, alpha(@highlight_color, 0.4), alpha(@highlight_color, 0.4)) 1 0 1 0;
  outline: 1px solid @dim_border_color;
  text-shadow: 0 1px black;
}

shadows {
  text-shadow: 0 -1px alpha(@highlight_color, 0.04), 0 1px alpha(@shade_color, 0.3);
  box-shadow: 0 2px 5px 2px rgba(0, 0, 0, 0.4), inset 0 0 0 1px @selected_bg_color;
  -gtk-icon-shadow: 0 1px alpha(#000000, 0.2);
}

no-shadow {
  box-shadow: none;
  -gtk-icon-shadow: none;
}

image {
  color: currentColor;
  background-color: transparent;
  background-image: url("objects/red-white-#fff-rgb(1,2,3).svg");
}

label {
  background-image: none;
}

palette-reference {
  color: @white;
  background-color: @black;
}
EOF

cat >"$tmp_dir/invalid.css" <<'EOF'
label { color: #abc; }
entry { background-color: rgba(1, 2, 3, 0.4); }
button {
  background-image: linear-gradient(
    to bottom,
    #ffffff,
    rgb(4, 5, 6)
  );
}
check { color: black; }
radio { background-color: white; }
box {
  color: @fg_color;
  background-color: #112233;
}
no-semicolon-color { color: #abcdef }
no-semicolon-background { background-color: gainsboro }
no-semicolon-image { background-image: linear-gradient(white, #fedcba) }
newline-before-colon {
  color
  : #a1b2c3;
}
hsl-color { color: hsl(120, 50%, 50%); }
hsla-background { background-color: hsla(240, 50%, 50%, 0.5); }
opaque-white-border { border-color: #ffffff; }
colored-border { border: 1px solid #3a3c41; }
colored-alpha-border { border-left-color: rgba(105, 105, 105, 0.1); }
opaque-black-border { border-top-color: rgba(0, 0, 0, 1); }
named-border { border-bottom-color: white; }
border-image-literal { border-image: linear-gradient(to bottom, #dedcdf, rgba(212, 213, 219, 0.95)) 1 0 1 0; }
outline-literal { outline-color: #123456; }
white-text-shadow { text-shadow: 0 1px alpha(#ffffff, 0.35); }
colored-box-shadow { box-shadow: inset 1px 0 rgba(105, 105, 105, 0.1); }
white-icon-shadow { -gtk-icon-shadow: 0 1px rgba(255,255,255, 0.4); }
fg-text-shadow { text-shadow: 0 1px alpha(@fg_color, 0.3); }
text-color-box-shadow { box-shadow: 0 0 2px @text_color; }
EOF

expect_status 0 'valid fixture' perl "$checker" "$tmp_dir/valid.css"
expect_status 1 'invalid fixture' perl "$checker" "$tmp_dir/invalid.css"

rg --quiet --fixed-strings 'color: #abc' "$tmp_dir/stdout" \
    || fail 'hex color diagnostic is missing'
rg --quiet --fixed-strings 'background-color: rgba(1, 2, 3, 0.4)' "$tmp_dir/stdout" \
    || fail 'rgba background diagnostic is missing'
rg --quiet --fixed-strings 'background-image: linear-gradient(' "$tmp_dir/stdout" \
    || fail 'multiline gradient diagnostic is missing'
rg --quiet --fixed-strings 'color: black' "$tmp_dir/stdout" \
    || fail 'named black diagnostic is missing'
rg --quiet --fixed-strings 'background-color: white' "$tmp_dir/stdout" \
    || fail 'named white diagnostic is missing'
rg --quiet --fixed-strings 'background-color: #112233' "$tmp_dir/stdout" \
    || fail 'consecutive scoped-property diagnostic is missing'
rg --quiet --fixed-strings 'color: #abcdef' "$tmp_dir/stdout" \
    || fail 'semicolonless color diagnostic is missing'
rg --quiet --fixed-strings 'background-color: gainsboro' "$tmp_dir/stdout" \
    || fail 'named gainsboro diagnostic is missing'
rg --quiet --fixed-strings 'background-image: linear-gradient(white, #fedcba)' "$tmp_dir/stdout" \
    || fail 'semicolonless background-image diagnostic is missing'
rg --quiet --fixed-strings 'color: #a1b2c3' "$tmp_dir/stdout" \
    || fail 'newline-before-colon diagnostic is missing'
rg --quiet --fixed-strings 'color: hsl(120, 50%, 50%)' "$tmp_dir/stdout" \
    || fail 'hsl diagnostic is missing'
rg --quiet --fixed-strings 'background-color: hsla(240, 50%, 50%, 0.5)' "$tmp_dir/stdout" \
    || fail 'hsla diagnostic is missing'
rg --quiet --fixed-strings 'border-color: #ffffff' "$tmp_dir/stdout" \
    || fail 'opaque white border diagnostic is missing'
rg --quiet --fixed-strings 'border: 1px solid #3a3c41' "$tmp_dir/stdout" \
    || fail 'border shorthand diagnostic is missing'
rg --quiet --fixed-strings 'border-left-color: rgba(105, 105, 105, 0.1)' "$tmp_dir/stdout" \
    || fail 'colored alpha border diagnostic is missing'
rg --quiet --fixed-strings 'border-top-color: rgba(0, 0, 0, 1)' "$tmp_dir/stdout" \
    || fail 'opaque black border diagnostic is missing'
rg --quiet --fixed-strings 'border-bottom-color: white' "$tmp_dir/stdout" \
    || fail 'named border diagnostic is missing'
rg --quiet --fixed-strings 'border-image: linear-gradient(to bottom, #dedcdf' "$tmp_dir/stdout" \
    || fail 'border-image diagnostic is missing'
rg --quiet --fixed-strings 'outline-color: #123456' "$tmp_dir/stdout" \
    || fail 'outline diagnostic is missing'
rg --quiet --fixed-strings 'text-shadow: 0 1px alpha(#ffffff, 0.35)' "$tmp_dir/stdout" \
    || fail 'white text-shadow diagnostic is missing'
rg --quiet --fixed-strings 'box-shadow: inset 1px 0 rgba(105, 105, 105, 0.1)' "$tmp_dir/stdout" \
    || fail 'colored box-shadow diagnostic is missing'
rg --quiet --fixed-strings -- '-gtk-icon-shadow: 0 1px rgba(255,255,255, 0.4)' "$tmp_dir/stdout" \
    || fail 'white icon-shadow diagnostic is missing'
rg --quiet --fixed-strings 'text-shadow: 0 1px alpha(@fg_color, 0.3)' "$tmp_dir/stdout" \
    || fail 'foreground-token text-shadow diagnostic is missing'
rg --quiet --fixed-strings 'box-shadow: 0 0 2px @text_color' "$tmp_dir/stdout" \
    || fail 'text-color box-shadow diagnostic is missing'

set +e
printf 'label { color: #123456; }\n' \
    | perl "$checker" - >"$tmp_dir/stdin-out" 2>"$tmp_dir/stdin-err"
stdin_status=$?
set -e
test "$stdin_status" -eq 1 \
    || fail "stdin violation exited $stdin_status, expected 1"
rg --quiet --fixed-strings '<stdin>:1: color: #123456' "$tmp_dir/stdin-out" \
    || fail 'stdin diagnostic is missing'

expect_status 2 'missing arguments' perl "$checker"
rg --quiet --fixed-strings 'usage:' "$tmp_dir/stderr" \
    || fail 'missing-argument usage diagnostic is missing'

expect_status 2 'unreadable input' perl "$checker" "$tmp_dir/does-not-exist.css"
rg --quiet --fixed-strings 'cannot read' "$tmp_dir/stderr" \
    || fail 'unreadable-input diagnostic is missing'

printf 'PASS: hard-coded color scanner fixtures\n'
