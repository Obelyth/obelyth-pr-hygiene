#!/usr/bin/env bash
# Puts a pull request on its milestone. Policy quarter: "Qn YYYY" for the
# quarter it was opened in, created with the quarter's last day as the due
# date if missing. Policy none: nothing. Anything else: that title, which must
# exist. A pull request that already has a milestone is left alone, and a
# closed milestone is never reopened.
#
#   REPO=owner/name PR_NUMBER=n POLICY=quarter CREATED_AT=<ISO> GH_TOKEN=... milestone.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO:?REPO is required}"; : "${PR_NUMBER:?PR_NUMBER is required}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
notice() { echo "::notice::$1"; echo "- $1" >> "$GITHUB_STEP_SUMMARY"; }

current="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json milestone --jq '.milestone.title // empty')"
milestones="$(gh api --paginate "repos/$REPO/milestones?state=all&per_page=100" --jq '.[] | {title, state, number}' | jq -s '.')"

plan="$(CURRENT="$current" POLICY="${POLICY:-quarter}" CREATED_AT="${CREATED_AT:-}" bash "$here/milestone-plan.sh" <<< "$milestones")"
field() { sed -n "s/^$1=//p" <<< "$plan"; }
action="$(field action)"; title="$(field title)"

case "$action" in
  skip)
    notice "milestone: $(field reason)" ;;
  assign)
    gh pr edit "$PR_NUMBER" --repo "$REPO" --milestone "$title" > /dev/null
    notice "milestone: $title" ;;
  create)
    due="$(field due)"
    # GitHub's own UI stores due dates at 07:00 UTC (midnight Pacific); match it
    # so the date reads the same everywhere. A concurrent run may have created
    # it first, in which case the POST fails and the assign still works.
    if gh api -X POST "repos/$REPO/milestones" -f "title=$title" -f "due_on=${due}T07:00:00Z" > /dev/null 2>&1; then
      notice "milestone: created $title, due $due"
    fi
    gh pr edit "$PR_NUMBER" --repo "$REPO" --milestone "$title" > /dev/null
    notice "milestone: $title" ;;
  *)
    echo "milestone.sh: unexpected plan: $plan" >&2; exit 1 ;;
esac
