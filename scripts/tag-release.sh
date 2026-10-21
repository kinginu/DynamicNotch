#!/usr/bin/env bash
# Cuts a DynamicNotch release in two steps, because `main` only accepts pull requests:
#
#   1. scripts/tag-release.sh 1.2.3   (project.yml is not at 1.2.3 yet)
#      Checks that DynamicNotchApp/CHANGELOG.md has a "## [1.2.3]" section, sets MARKETING_VERSION
#      = 1.2.3 and CURRENT_PROJECT_VERSION = 10203 (major*10000 + minor*100 + patch) in
#      DynamicNotchApp/project.yml and commits that on the current branch (on main it creates
#      release/1.2.3 first). Push the branch and merge its pull request.
#   2. scripts/tag-release.sh 1.2.3   (again, on an up-to-date main that has the bump)
#      Checks the CHANGELOG section and the version again and creates the annotated tag v1.2.3.
#
# It never pushes: each step prints the command to run. Pushing the tag starts
# .github/workflows/release.yml, which builds, signs, zips and publishes the GitHub Release.
#
#   scripts/tag-release.sh [--remote origin] <version>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/DynamicNotchApp/project.yml"
FOOTER="Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
REMOTE=origin

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

version=""
while (( $# > 0 )); do
    case "$1" in
        --remote) REMOTE="${2:?--remote needs a name}"; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) printf 'unknown option: %s\n' "$1" >&2; exit 64 ;;
        *) [[ -z "$version" ]] || { usage >&2; exit 64; }; version="${1#v}" ;;
    esac
    shift
done
[[ -n "$version" ]] || { usage >&2; exit 64; }
[[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "not a version: $version (expected X.Y.Z)"
major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
(( minor < 100 && patch < 100 )) || die "minor and patch must be below 100 (build number = major*10000 + minor*100 + patch)"
build=$(( 10#$major * 10000 + 10#$minor * 100 + 10#$patch ))
tag="v$version"

cd "$ROOT"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "the working tree has uncommitted changes"
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "tag $tag already exists"
"$ROOT/scripts/release-notes.sh" "$version" >/dev/null   # fails without a CHANGELOG section

current_version="$(sed -n 's/^    MARKETING_VERSION: "\(.*\)"$/\1/p' "$PROJECT")"
current_build="$(sed -n 's/^    CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' "$PROJECT")"
[[ -n "$current_version" && -n "$current_build" ]] || die "MARKETING_VERSION / CURRENT_PROJECT_VERSION not found in $PROJECT"
branch="$(git symbolic-ref --quiet --short HEAD || true)"

if [[ "$current_version" != "$version" || "$current_build" != "$build" ]]; then
    # --- Step 1: bump and commit ---------------------------------------------------------
    (( current_build < build )) || die "build number $build is not above the current $current_build"
    if [[ "$branch" == main || -z "$branch" ]]; then
        branch="release/$version"
        git switch -c "$branch"
    fi
    sed -i '' \
        -e "s/^    MARKETING_VERSION: \".*\"$/    MARKETING_VERSION: \"$version\"/" \
        -e "s/^    CURRENT_PROJECT_VERSION: \".*\"$/    CURRENT_PROJECT_VERSION: \"$build\"/" \
        "$PROJECT"
    git add "$PROJECT"
    git commit -q -m "Release $version" -m "$FOOTER"
    echo "Committed \"Release $version\" (version $version, build $build) on $branch."
    echo "Next: push it, merge the pull request, then run this script again on main:"
    echo "  git push -u $REMOTE $branch && gh pr create --fill --base main"
    echo "  # after the merge:"
    echo "  git switch main && git pull --ff-only && scripts/tag-release.sh $version"
    exit 0
fi

# --- Step 2: tag -------------------------------------------------------------------------
[[ "$branch" == main ]] || die "project.yml is already at $version; tag from main (git switch main && git pull --ff-only)"
git fetch -q "$REMOTE" main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "$REMOTE/main")" ]] \
    || die "main is not at $REMOTE/main; pull (or push) first so the tag points at a published commit"
git tag -a "$tag" -m "DynamicNotch $version"
echo "Tagged $tag at $(git rev-parse --short HEAD) (version $version, build $build)."
echo "Publish the release (starts .github/workflows/release.yml):"
echo "  git push $REMOTE $tag"
