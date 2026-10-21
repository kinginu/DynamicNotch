#!/usr/bin/env bash
# Prints the release notes of one version: the body of its "## [X.Y.Z]" section in
# DynamicNotchApp/CHANGELOG.md (Keep a Changelog), without the heading. Fails when the section is
# missing or empty, so a release cannot be cut without notes. Used by .github/workflows/release.yml
# and scripts/tag-release.sh.
#
#   scripts/release-notes.sh 1.0.1          # or v1.0.1
#   CHANGELOG=path/to/CHANGELOG.md scripts/release-notes.sh 1.0.1
set -euo pipefail

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
' "$CHANGELOG" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"

if [[ -z "${notes//[[:space:]]/}" ]]; then
    echo "error: no \"## [$version]\" section (or an empty one) in $CHANGELOG" >&2
    exit 1
fi
printf '%s\n' "$notes"
