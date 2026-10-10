#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_close() {
    local actual=$1
    local expected=$2
    local tolerance=$3
    local label=$4

    awk -v actual="$actual" -v expected="$expected" -v tolerance="$tolerance" '
        BEGIN {
            difference = actual - expected
            if (difference < 0) difference = -difference
            exit difference <= tolerance ? 0 : 1
        }
    ' || fail "$label is $actual, expected $expected ± $tolerance"
}

query_bbox() {
    local file=$1
    local id=$2
    inkscape "$file" --query-id="$id" --query-x --query-y --query-width \
        --query-height 2>/dev/null
}

final_leaf_id() {
    local file=$1
    xmllint --xpath \
        'string((//*[local-name()="path" or local-name()="rect" or local-name()="circle" or local-name()="polygon" or local-name()="line" or local-name()="ellipse" or local-name()="use"])[last()]/@id)' \
        "$file"
}

check_file() {
    local file=$1
    local relative=${file#"$repo_root/"}
    local id
    local target
    local doc_width
    local doc_height
    local x
    local y
    local width
    local height
    local max_dimension

    xmllint --noout "$file" \
        || fail "$relative is not valid XML"

    id=$(final_leaf_id "$file")
    test -n "$id" || fail "$relative has no central graphical object"

    if [[ "$file" = *@2.svg ]]; then
        target=19
    else
        target=9.5
    fi

    doc_width=$(xmllint --xpath 'string(/*[local-name()="svg"]/@width)' "$file")
    doc_height=$(xmllint --xpath 'string(/*[local-name()="svg"]/@height)' "$file")

    read -r x y width height _ <<< "$(query_bbox "$file" "$id" | tr '\n' ' ')"
    max_dimension=$(awk -v width="$width" -v height="$height" \
        'BEGIN { print (width > height ? width : height) }')
    assert_close "$max_dimension" "$target" 0.01 "$relative central glyph size"
    assert_close "$(awk -v x="$x" -v width="$width" 'BEGIN { print x + width / 2 }')" \
        "$(awk -v width="$doc_width" 'BEGIN { print width / 2 }')" \
        0.01 "$relative central glyph horizontal center"
    assert_close "$(awk -v y="$y" -v height="$height" 'BEGIN { print y + height / 2 }')" \
        "$(awk -v height="$doc_height" 'BEGIN { print height / 2 }')" \
        0.01 "$relative central glyph vertical center"
}

count=0
for directory in \
    "$repo_root/gtk-3.0/objects/title-buttons" \
    "$repo_root/gtk-3.0/objects/title-buttons-dark"; do
    test -d "$directory" || fail "missing title-button directory: $directory"
    # The restore SVGs are kept, but no stylesheet references them.
    while IFS= read -r -d '' file; do
        check_file "$file"
        count=$((count + 1))
    done < <(find "$directory" -maxdepth 1 -type f -name '*.svg' \
        ! -name 'titlebutton-restore*' -print0 | sort -z)
done

test "$count" -eq 48 || fail "checked $count SVG files, expected 48"
printf 'PASS: %s title-button SVG glyphs sized and centered\n' "$count"
