#!/usr/bin/env bash
# Links a pull request to the issue its branch names, by appending "Closes #n"
# to the body - only when the branch carries a number, that number is an open
# issue in this repository, and the body does not already close an issue.
# The body is never replaced, only added to.
#
#   REPO=owner/name PR_NUMBER=n HEAD_REF=feat/12-thing GH_TOKEN=... link-issue.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO:?REPO is required}"; : "${PR_NUMBER:?PR_NUMBER is required}"; : "${HEAD_REF:?HEAD_REF is required}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
notice() { echo "::notice::$1"; echo "- $1" >> "$GITHUB_STEP_SUMMARY"; }

if ! n="$(bash "$here/branch-issue.sh" "$HEAD_REF")"; then
  echo "development: branch '$HEAD_REF' carries no issue number"
  exit 0
fi
body="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body --jq '.body')"
if bash "$here/closing-keyword.sh" <<< "$body"; then
  echo "development: the body already closes an issue"
  exit 0
fi
if ! issue="$(gh api "repos/$REPO/issues/$n" 2> /dev/null)"; then
  notice "development: branch names #$n but there is no such issue in $REPO"
  exit 0
fi
if jq -e '.pull_request' <<< "$issue" > /dev/null; then
  notice "development: #$n is a pull request, not an issue"
  exit 0
fi
if [[ "$(jq -r '.state' <<< "$issue")" != "open" ]]; then
  notice "development: issue #$n is closed, so it was not linked"
  exit 0
fi
if [[ -z "${body//[[:space:]]/}" ]]; then
  new="Closes #$n"
else
  new="${body}"$'\n\n'"Closes #$n"
fi
printf '%s\n' "$new" | gh pr edit "$PR_NUMBER" --repo "$REPO" --body-file - > /dev/null
notice "development: linked to #$n ($(jq -r '.title' <<< "$issue"))"
