#!/usr/bin/env bash
# Requests reviews from an explicit list, and from Copilot when enabled. The
# author is skipped: GitHub does not let anyone review their own pull request.
# Logins are requested one at a time, so one that is not a collaborator does
# not take the rest down with it.
#
#   REPO=owner/name PR_NUMBER=n AUTHOR=login REVIEWERS=a,b COPILOT=false GH_TOKEN=... reviewers.sh
set -euo pipefail

: "${REPO:?REPO is required}"; : "${PR_NUMBER:?PR_NUMBER is required}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
notice() { echo "::notice::$1"; echo "- $1" >> "$GITHUB_STEP_SUMMARY"; }

# GitHub logins are case-insensitive, and the event reports the author's in
# whatever case they registered it; compare both sides lower-cased.
author="${AUTHOR:-}"; author="${author,,}"
wanted=()
IFS=',' read -ra raw <<< "${REVIEWERS:-}"
for r in "${raw[@]+"${raw[@]}"}"; do
  r="${r//[[:space:]]/}"
  [[ -n "$r" && "${r,,}" != "$author" ]] || continue
  wanted+=("$r")
done

requested=(); failed=()
for r in "${wanted[@]+"${wanted[@]}"}"; do
  if gh pr edit "$PR_NUMBER" --repo "$REPO" --add-reviewer "$r" > /dev/null 2>&1; then
    requested+=("$r")
  else
    failed+=("$r")
  fi
done
if (( ${#requested[@]} )); then
  notice "reviewers: requested ${requested[*]}"
fi
if (( ${#failed[@]} )); then
  notice "reviewers: could not request ${failed[*]} - are they collaborators on $REPO?"
fi

if [[ "${COPILOT:-false}" == "true" ]]; then
  if gh api -X POST "repos/$REPO/pulls/$PR_NUMBER/requested_reviewers" \
       -f 'reviewers[]=copilot-pull-request-reviewer[bot]' > /dev/null 2>&1; then
    notice "reviewers: requested a Copilot code review"
  else
    notice "reviewers: Copilot code review could not be requested - is it enabled for this account?"
  fi
fi
