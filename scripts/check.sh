#!/usr/bin/env bash
# Runs every check of this repository: the DynamicNotch app (Xcode build + unit tests), its
# Command Line Tools harness (build + tests), the FanControl package (build + tests), the strings
# lint (when present) and shellcheck (plus the self-test of scripts/release-notes.sh). Read-only
# with respect to the system: nothing is installed, no sudo, no SMC writes, no app is launched (the
# app's unit tests are host-less).
#
#   scripts/check.sh               all checks
#   scripts/check.sh --fast        skip the Xcode build and the app's Xcode tests
#   scripts/check.sh --list        print the step names
#   scripts/check.sh STEP…         run only these steps (names from --list)
#   scripts/check.sh --keep-going  run every step even after a failure (default: stop at the first)
#
# Environment
#   DEVELOPER_DIR    defaults to /Applications/Xcode.app/Contents/Developer when that exists
#                    (xcode-select may point at the Command Line Tools)
#   CHECK_BUILD_DIR  build products of every step (default: <repo>/.build-check, git-ignored).
#                    Kept between runs, so later runs are incremental.
#   CHECK_LOG_DIR    full logs (default: $CHECK_BUILD_DIR/logs)
#   CHECK_STRICT_WARNINGS=1  also fail on warnings in the app / harness builds (FanControl always
#                    fails on any warning)
set -uo pipefail
# The whole script is one brace group, so bash parses it before running (editing the file during
# a run cannot change what runs).
{

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/DynamicNotchApp"
FC="$ROOT/FanControl"
BUILD_DIR="${CHECK_BUILD_DIR:-$ROOT/.build-check}"
LOG_DIR="${CHECK_LOG_DIR:-$BUILD_DIR/logs}"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

ALL_STEPS=(xcodegen app-build app-test harness-build harness-test fancontrol-build fancontrol-test
           strings-lint shellcheck)
SLOW_STEPS=(xcodegen app-build app-test)

fast=0 keep_going=0 selected=()
for arg in "$@"; do
    case "$arg" in
        --fast) fast=1 ;;
        --keep-going|-k) keep_going=1 ;;
        --list) printf '%s\n' "${ALL_STEPS[@]}"; exit 0 ;;
        -h|--help) sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *)
            if [[ " ${ALL_STEPS[*]} " != *" $arg "* ]]; then echo "unknown step: $arg (see --list)" >&2; exit 2; fi
            selected+=("$arg") ;;
    esac
done
if ((${#selected[@]} == 0)); then
    for s in "${ALL_STEPS[@]}"; do
        if ((fast)) && [[ " ${SLOW_STEPS[*]} " == *" $s "* ]]; then continue; fi
        selected+=("$s")
    done
fi

mkdir -p "$LOG_DIR"

# Swift / Xcode output → the lines worth showing: file-anchored errors first, then test and build
# summaries (warnings stay in the log).
summarize() {
    local out
    out=$({
        grep -E '^/[^ ]+:[0-9]+:([0-9]+:)? error: |^error: ' "$1" | sort -u | head -25
        grep -E '^\*\* (BUILD|TEST) |Test run with|✘ Test|Executed [0-9]+ tests|SC[0-9]{4}|^In /.* line [0-9]+:' "$1" | head -15
    } | cut -c1-240)
    # Nothing recognisable (e.g. a lint report): show the start of the log instead.
    if [[ -n "$out" ]]; then echo "$out"; else head -20 "$1" | cut -c1-240; fi
}

# Compiler warnings from our own sources (dependency checkouts are ignored), one per line.
own_warnings() {
    grep -E '^/[^ ]+\.swift:[0-9]+:[0-9]+: warning: ' "$1" \
        | grep -v -E '/(\.build|SourcePackages|checkouts)/' | sort -u
}

# Fails (and lists them) when our sources have any compiler warning.
no_own_warnings() {
    local hits
    hits=$(own_warnings "$1")
    if [[ -n "$hits" ]]; then
        echo "$hits" | head -20
        echo "→ $(echo "$hits" | wc -l | tr -d ' ') warning(s) in our sources"
        return 1
    fi
}

run_step() {
    local step="$1" log="$LOG_DIR/$1.log"
    case "$step" in
        xcodegen)
            (cd "$APP" && xcodegen generate --quiet) ;;
        app-build)
            xcodebuild -project "$APP/DynamicNotch.xcodeproj" -scheme DynamicNotch -configuration Debug \
                -derivedDataPath "$BUILD_DIR/xcode" build CODE_SIGN_IDENTITY=- ;;
        app-test)
            xcodebuild -project "$APP/DynamicNotch.xcodeproj" -scheme DynamicNotch -configuration Debug \
                -derivedDataPath "$BUILD_DIR/xcode" test -only-testing:DynamicNotchAppTests CODE_SIGN_IDENTITY=- ;;
        harness-build)
            (cd "$APP" && swift build --scratch-path "$BUILD_DIR/harness") ;;
        harness-test)
            (cd "$APP" && swift test --scratch-path "$BUILD_DIR/harness") ;;
        fancontrol-build)
            (cd "$FC" && swift build --scratch-path "$BUILD_DIR/fancontrol") ;;
        fancontrol-test)
            (cd "$FC" && swift test --scratch-path "$BUILD_DIR/fancontrol") ;;
        strings-lint)
            # Optional lint script (DynamicNotchApp/Support/lint-strings.*); skipped when absent.
            local lint
            for lint in "$APP/Support/lint-strings.py" "$APP/Support/lint-strings.sh" "$ROOT/scripts/lint-strings.sh"; do
                if [[ -f "$lint" ]]; then
                    case "$lint" in
                        *.py) (cd "$APP" && PYTHONDONTWRITEBYTECODE=1 python3 -I "$lint") ;;
                        *) bash "$lint" ;;
                    esac
                    return
                fi
            done
            # Fallback: the generated strings file must be a valid plist and merge-strings.py must compile.
            plutil -lint "$APP/Localization/en.lproj/Localizable.strings" &&
                python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$APP/Support/merge-strings.py" ;;
        shellcheck)
            if ! command -v shellcheck >/dev/null; then echo "shellcheck not installed (brew install shellcheck)"; return 1; fi
            local files=()
            while IFS= read -r f; do files+=("$ROOT/$f"); done < <(cd "$ROOT" && git ls-files '*.sh'; \
                cd "$ROOT" && git ls-files --others --exclude-standard '*.sh')
            ((${#files[@]})) || return 0
            shellcheck -x "${files[@]}" &&
                "$ROOT/scripts/tests/release-notes-test.sh" ;;
    esac > "$log" 2>&1
    local status=$?
    # Warnings: FanControl must have none (it is kept at 0). The app
    # and the harness still carry a few known warnings, so they are only counted there unless
    # CHECK_STRICT_WARNINGS=1.
    if ((status == 0)); then
        case "$step" in
            fancontrol-build)
                no_own_warnings "$log" || status=1 ;;
            app-build|harness-build)
                if [[ "${CHECK_STRICT_WARNINGS:-0}" == 1 ]]; then
                    no_own_warnings "$log" || status=1
                else
                    WARNINGS=$(own_warnings "$log" | wc -l | tr -d ' ')
                fi ;;
        esac
    fi
    return $status
}

failed=() start_all=$SECONDS
for step in "${selected[@]}"; do
    start=$SECONDS
    printf '▸ %-18s ' "$step"
    WARNINGS=0
    if run_step "$step"; then
        if ((WARNINGS > 0)); then
            printf 'ok   (%ss, %s known warning(s), see log)\n' $((SECONDS - start)) "$WARNINGS"
        else
            printf 'ok   (%ss)\n' $((SECONDS - start))
        fi
    else
        printf 'FAIL (%ss) — log: %s\n' $((SECONDS - start)) "$LOG_DIR/$step.log"
        summarize "$LOG_DIR/$step.log" | sed 's/^/    /'
        failed+=("$step")
        ((keep_going)) || break
    fi
done

echo
if ((${#failed[@]})); then
    echo "FAILED: ${failed[*]}  ($((SECONDS - start_all))s)"
    exit 1
fi
echo "All ${#selected[@]} checks passed ($((SECONDS - start_all))s)."
exit 0
}
