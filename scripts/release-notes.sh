#!/usr/bin/env bash
# Prints the release notes of one version: the body of its "## [X.Y.Z]" section in
# DynamicNotchApp/CHANGELOG.md (Keep a Changelog), without the heading. Fails when the section is
# missing or empty, so a release cannot be cut without notes. Used by .github/workflows/release.yml
# and scripts/tag-release.sh.
#
# GitHub renders a single newline in release notes as a line break, so hard-wrapped Markdown is
# unwrapped: a non-blank line joins the line before it (with one space) unless it starts a list
# item, a heading, a code fence, a table row, a block quote or a link definition, or the line before
# ends a paragraph-breaking construct (heading, table row, hard break). Fenced code is kept as is.
# `--reflow FILE` prints FILE unwrapped the same way (used to keep the CHANGELOGs single-line).
#
#   scripts/release-notes.sh 1.0.1          # or v1.0.1
#   CHANGELOG=path/to/CHANGELOG.md scripts/release-notes.sh 1.0.1
#   scripts/release-notes.sh --reflow path/to/file.md
set -euo pipefail

# Joins hard-wrapped Markdown lines (stdin or files → stdout).
reflow() {
    awk '
        function flush() { if (buf != "") print buf; buf = "" }
        /^[ \t]*(```|~~~)/ { flush(); print; fence = !fence; next }
        fence { print; next }
        /^[ \t]*$/ { flush(); print; next }
        /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/ || /^#/ || /^[ \t]*[|>]/ || /^\[[^]]+\]: / {
            flush(); buf = $0
            if ($0 ~ /^#/ || $0 ~ /^[ \t]*\|/) flush()
            next
        }
        buf == "" { buf = $0; next }
        buf ~ /(  |\\)$/ { flush(); buf = $0; next }   # explicit hard break
        { line = $0; sub(/^[ \t]+/, "", line); buf = buf " " line }
        END { flush() }
    ' "$@"
}

if [[ "${1:-}" == --reflow ]]; then
    shift
    (( $# >= 1 )) || { echo "usage: $(basename "$0") --reflow FILE…" >&2; exit 64; }
    reflow "$@"
    exit
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="${CHANGELOG:-$ROOT/DynamicNotchApp/CHANGELOG.md}"

if (( $# != 1 )) || [[ "$1" == -h || "$1" == --help ]]; then
    echo "usage: $(basename "$0") <version>   (X.Y.Z or vX.Y.Z)" >&2
    exit 64
fi
version="${1#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: not a version: $1 (expected X.Y.Z)" >&2; exit 64; }
[[ -f "$CHANGELOG" ]] || { echo "error: $CHANGELOG not found" >&2; exit 1; }

# The section starts at "## [X.Y.Z]" (optionally followed by " — date") and ends before the next
# "## " heading. Leading and trailing blank lines and the "[X.Y.Z]: <url>" link definitions are dropped.
notes="$(awk -v v="$version" '
    BEGIN { heading = "## [" v "]" }
    /^## / {
        if (found) exit
        if (substr($0, 1, length(heading)) == heading) { found = 1; next }
    }
    found && /^\[[0-9]+\.[0-9]+\.[0-9]+\]: / { next }   # version link definitions at the end of the file
    found { print }
' "$CHANGELOG" | reflow | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"

if [[ -z "${notes//[[:space:]]/}" ]]; then
    echo "error: no \"## [$version]\" section (or an empty one) in $CHANGELOG" >&2
    exit 1
fi
printf '%s\n' "$notes"
