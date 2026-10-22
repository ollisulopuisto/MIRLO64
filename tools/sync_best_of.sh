#!/bin/bash
# sync_best_of.sh: the sync branch for best-of (the build that goes on the Pocket), for a pull request to review.
#
# sync/best-of-upstream = best-of with these merged in, each on its own, those that bring something:
#   fork-patches (the fork's daily chain), upstream's main, and upstream's branches in TRACK (work not yet on main).
# A merge that conflicts is left out (nothing of it is touched) and named in the report: the fork's own work is never
# reset to upstream's. A merge that changes the hardware's sources says "FIT NEEDED": the seeds of best-of are stale.
#   PUSH=1  push the branch (default: only report), REMOTE=origin, UPSTREAM=upstream, BASE=best-of
#   TRACK="perf-cpu undo-ldc1-cache"  the upstream branches followed until they are on main
# Writes report.md (the pull request's body). GITHUB_OUTPUT: changed=1 when the branch has something over BASE.
# Exit status: 0 done, 2 not a clean start.
set -uo pipefail
REMOTE=${REMOTE:-origin}; UPSTREAM=${UPSTREAM:-upstream}; BASE=${BASE:-best-of}
TRACK=${TRACK:-perf-cpu undo-ldc1-cache}; SYNC=sync/best-of-upstream
git diff --quiet && git diff --cached --quiet || { echo "sync: the work tree is not clean"; exit 2; }
git fetch -q "$REMOTE" || exit 2
git fetch -q "$UPSTREAM" || exit 2
prev_orig=$(git rev-parse --abbrev-ref HEAD)
git checkout -q -B "$SYNC" "$REMOTE/$BASE" || exit 2
merged=(); skipped=(); fit=0
for src in "$REMOTE/fork-patches" "$UPSTREAM/main" $(for t in $TRACK; do echo "$UPSTREAM/$t"; done); do
    git rev-parse -q --verify "$src" >/dev/null || { skipped+=("$src: no such branch (merged upstream and deleted?)"); continue; }
    git merge-base --is-ancestor "$src" HEAD && continue
    before=$(git rev-parse HEAD)
    if git merge --no-ff --no-edit -q -m "Merge ${src#*/} into $BASE [skip ci]" "$src" >/dev/null 2>&1; then
        hw=$(git diff --name-only "$before" HEAD -- rtl target platform projects ':!projects/fits.json' ':!projects/fits-winbox.json' | wc -l | tr -d ' ')
        merged+=("${src#*/}: $(git rev-list --count "$before..$src") new commits$([ "$hw" != 0 ] && echo " -- FIT NEEDED ($hw hardware files)")")
        [ "$hw" != 0 ] && fit=1
    elif [ "$(git diff --name-only --diff-filter=U)" = projects/fits.json ] && git checkout -q --ours projects/fits.json &&
         git add projects/fits.json && git commit -q --no-edit; then
        # (projects/fits.json: the fits of upstream's sources are not best-of's; ours is kept as ever, FIT NEEDED says the rest)
        hw=$(git diff --name-only "$before" HEAD -- rtl target platform projects ':!projects/fits.json' ':!projects/fits-winbox.json' | wc -l | tr -d ' ')
        merged+=("${src#*/}: $(git rev-list --count "$before..$src") new commits, fits.json kept as ours$([ "$hw" != 0 ] && echo " -- FIT NEEDED ($hw hardware files)")")
        [ "$hw" != 0 ] && fit=1
    else
        skipped+=("${src#*/}: CONFLICT in $(git diff --name-only --diff-filter=U | tr '\n' ' ')-- left out, merge by hand"); git merge --abort
    fi
done
{
    echo "Automated sync of \`$BASE\` with the fork's chain and upstream (tools/sync_best_of.sh)."; echo
    echo "Merged:"; [ ${#merged[@]} -gt 0 ] && printf -- '- %s\n' "${merged[@]}" || echo "- nothing"; echo
    [ ${#skipped[@]} -gt 0 ] && { echo "Left out:"; printf -- '- %s\n' "${skipped[@]}"; echo; }
    [ $fit = 1 ] && echo "**FIT NEEDED**: the hardware's sources changed; run a seed sweep (tools/winfit/fit.py) before this goes on a card."
} > report.md
cat report.md
changed=0; [ "$(git rev-parse HEAD)" != "$(git rev-parse "$REMOTE/$BASE")" ] && changed=1
[ "${PUSH:-0}" = 1 ] && [ $changed = 1 ] && git push -q "$REMOTE" "$SYNC" --force
[ -n "${GITHUB_OUTPUT:-}" ] && { echo "changed=$changed"; echo "fit_needed=$fit"; } >> "$GITHUB_OUTPUT"
git checkout -q "$prev_orig" 2>/dev/null || true
exit 0
