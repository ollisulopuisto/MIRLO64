#!/bin/bash
# sync_upstream.sh: this fork's branches up to date with upstream, with no build (a merge is "[skip ci]").
#
#   main           a fast-forward of upstream's main (a fork's main has no work of its own)
#   patched-v0.1   main merged in; dpad-ramp: patched-v0.1 merged in; fork-patches: dpad-ramp merged in
#
# The chain stops at the first branch whose merge conflicts (nothing of it is touched; the branches after it wait for a
# person), and says so. A merge that changes the hardware's sources (rtl/, target/, platform/, projects/) says "FIT NEEDED":
# the recorded fits (projects/fits.json) and the bitstream of the branch are stale until a seed sweep.
#   PUSH=1   push what merged (the default: only report), REMOTE=origin, UPSTREAM=upstream (a remote of tortugaveloz/MIRLO64)
# Exit status: 0 all current or merged, 1 a conflict, 2 not a clean start.
set -uo pipefail
REMOTE=${REMOTE:-origin}; UPSTREAM=${UPSTREAM:-upstream}; CHAIN=(patched-v0.1 dpad-ramp fork-patches)
git diff --quiet && git diff --cached --quiet || { echo "sync: the work tree is not clean"; exit 2; }
git fetch -q "$REMOTE" || exit 2
git fetch -q "$UPSTREAM" main || exit 2
prev_orig=$(git rev-parse --abbrev-ref HEAD)
report=(); status=0; pushes=()
# main
if git merge-base --is-ancestor "$REMOTE/main" "$UPSTREAM/main"; then
    if [ "$(git rev-parse "$REMOTE/main")" != "$(git rev-parse "$UPSTREAM/main")" ]; then
        report+=("main: fast-forwarded to $(git rev-parse --short "$UPSTREAM/main")"); pushes+=("$UPSTREAM/main:refs/heads/main")
    fi
else
    report+=("main: the fork's main has commits of its own: not fast-forwarded"); status=1
fi
prev="$UPSTREAM/main"
for b in "${CHAIN[@]}"; do
    [ $status -ne 0 ] && { report+=("$b: waiting"); continue; }
    git checkout -q -B "$b" "$REMOTE/$b" || exit 2
    if git merge-base --is-ancestor "$prev" HEAD; then
        report+=("$b: current")
    elif git merge --no-ff --no-edit -q -m "Merge ${prev#*/} into $b [skip ci]

Co-Authored-By: sync_upstream.sh <noreply@github.com>" "$prev" >/dev/null 2>&1; then
        hw=$(git diff --name-only "$REMOTE/$b" HEAD -- rtl target platform projects ':!projects/fits.json' | wc -l | tr -d ' ')
        report+=("$b: merged ${prev#*/}$([ "$hw" != 0 ] && echo " -- FIT NEEDED ($hw hardware files changed)")"); pushes+=("$b:refs/heads/$b")
    else
        report+=("$b: CONFLICT merging ${prev#*/}: $(git diff --name-only --diff-filter=U | tr '\n' ' ')"); git merge --abort; status=1
    fi
    prev=$b
done
[ "${PUSH:-0}" = 1 ] && for p in "${pushes[@]:-}"; do [ -n "$p" ] && git push -q "$REMOTE" "$p"; done
git checkout -q "$prev_orig" 2>/dev/null || true
printf 'sync: %s\n' "${report[@]}"
exit $status
