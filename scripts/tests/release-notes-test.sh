#!/usr/bin/env bash
# Self-test of scripts/release-notes.sh: section extraction and the unwrapping of hard-wrapped
# Markdown (GitHub renders a single newline in release notes as a line break). scripts/check.sh
# runs it after shellcheck.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/CHANGELOG.md" <<'MD'
# Changelog

Intro that is
wrapped.

## [1.2.0] — 2026-01-02

A paragraph that is
hard-wrapped over
three lines.

### Added

- An item that
  continues here
  and here.
- Second item.
  - Nested item
    continued.
1. Numbered item
   continued.

```sh
keep  these
lines
```

Line with a hard break  
next line.

| a | b |
|---|---|
| 1 | 2 |

## [1.1.0] — 2026-01-01

Older.

[1.2.0]: https://example.com/v1.2.0
MD

cat > "$tmp/expected.md" <<'MD'
A paragraph that is hard-wrapped over three lines.

### Added

- An item that continues here and here.
- Second item.
  - Nested item continued.
1. Numbered item continued.

```sh
keep  these
lines
```

Line with a hard break  
next line.

| a | b |
|---|---|
| 1 | 2 |
MD

fail=0
CHANGELOG="$tmp/CHANGELOG.md" "$ROOT/scripts/release-notes.sh" v1.2.0 > "$tmp/actual.md"
if ! diff -u "$tmp/expected.md" "$tmp/actual.md"; then echo "FAIL: section 1.2.0" >&2; fail=1; fi

[[ "$(CHANGELOG="$tmp/CHANGELOG.md" "$ROOT/scripts/release-notes.sh" 1.1.0)" == "Older." ]] \
    || { echo "FAIL: section 1.1.0" >&2; fail=1; }

if CHANGELOG="$tmp/CHANGELOG.md" "$ROOT/scripts/release-notes.sh" 9.9.9 2>/dev/null; then
    echo "FAIL: a missing section must fail" >&2; fail=1
fi

[[ "$("$ROOT/scripts/release-notes.sh" --reflow "$tmp/CHANGELOG.md" | sed -n 3p)" == "Intro that is wrapped." ]] \
    || { echo "FAIL: --reflow" >&2; fail=1; }

# The CHANGELOGs of this repository must already be unwrapped (reflowing them changes nothing).
# A submodule's file (FanControl in the public repository) is checked in its own repository.
for f in DynamicNotchApp/CHANGELOG.md FanControl/CHANGELOG.md; do
    git -C "$ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1 || continue
    f="$ROOT/$f"
    if ! "$ROOT/scripts/release-notes.sh" --reflow "$f" | diff -q "$f" - >/dev/null; then
        echo "FAIL: $f is hard-wrapped (fix: scripts/release-notes.sh --reflow)" >&2; fail=1
    fi
done

((fail == 0)) && echo "release-notes-test: ok"
exit "$fail"
