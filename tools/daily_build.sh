#!/bin/bash
# daily_build.sh: after tools/sync_upstream.sh merged something, a build of fork-patches (the workflow build.yml).
# A full fit (seed sweep) when the hardware's sources (rtl/ target/ platform/ projects/) differ from those of the newest successful run that
# fitted; else a build of the runtime and the package that reuses that run's bitstream (reuse_run: minutes, no fit).
#   DRY=1: say what would run.   Needs gh, a checkout with the history, GITHUB_REPOSITORY (or -R by gh's default).
set -euo pipefail
repo=${GITHUB_REPOSITORY:-ollisulopuisto/MIRLO64}
git fetch -q origin fork-patches
head=$(git rev-parse origin/fork-patches)
reuse=""
for id in $(gh run list -R "$repo" --workflow build.yml --status success --limit 40 --json databaseId --jq '.[].databaseId'); do
    n=$(gh api "repos/$repo/actions/runs/$id/artifacts" --jq '[.artifacts[]|select((.name|startswith("fit-")) and (.expired|not))]|length')
    [ "$n" -gt 0 ] || continue
    sha=$(gh api "repos/$repo/actions/runs/$id" --jq .head_sha)
    git cat-file -e "$sha^{commit}" 2>/dev/null || continue
    if git diff --quiet "$sha" "$head" -- rtl target platform projects ':!projects/fits.json'; then reuse=$id; break; fi
done
if [ -n "$reuse" ]; then
    echo "daily build: the hardware is as in run $reuse: runtime and package only"
    [ -n "${DRY:-}" ] || gh workflow run build.yml -R "$repo" --ref fork-patches -f reuse_run="$reuse"
else
    echo "daily build: no earlier fit has these hardware sources: a full fit"
    [ -n "${DRY:-}" ] || gh workflow run build.yml -R "$repo" --ref fork-patches
fi
