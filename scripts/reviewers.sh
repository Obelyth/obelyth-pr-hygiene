#!/usr/bin/env bash
# Requests reviews from an explicit list, and from Copilot when enabled. The
# author is skipped: GitHub does not let anyone review their own pull request.
#
#   REPO=owner/name PR_NUMBER=n AUTHOR=login REVIEWERS=a,b COPILOT=false GH_TOKEN=... reviewers.sh
set -euo pipefail

: "${REPO:?REPO is required}"; : "${PR_NUMBER:?PR_NUMBER is required}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
notice() { echo "::notice::$1"; echo "- $1" >> "$GITHUB_STEP_SUMMARY"; }

wanted=()
IFS=',' read -ra raw <<< "${REVIEWERS:-}"
for r in "${raw[@]+"${raw[@]}"}"; do
  r="${r//[[:space:]]/}"
  [[ -n "$r" && "${r,,}" != "${AUTHOR:-}" ]] || continue
  wanted+=("$r")
done
if (( ${#wanted[@]} )); then
  list="$(IFS=,; echo "${wanted[*]}")"
  if gh pr edit "$PR_NUMBER" --repo "$REPO" --add-reviewer "$list" > /dev/null 2>&1; then
    notice "reviewers: requested $list"
  else
    notice "reviewers: could not request $list - are they collaborators on $REPO?"
  fi
fi
if [[ "${COPILOT:-false}" == "true" ]]; then
  if gh api -X POST "repos/$REPO/pulls/$PR_NUMBER/requested_reviewers" \
       -f 'reviewers[]=copilot-pull-request-reviewer[bot]' > /dev/null 2>&1; then
    notice "reviewers: requested a Copilot code review"
  else
    notice "reviewers: Copilot code review could not be requested - is it enabled for this account?"
  fi
fi
