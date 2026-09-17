#!/usr/bin/env bash
# Puts the describer's body on the pull request - but only after body-guard.sh
# has confirmed it changed nothing except the template's placeholder comments,
# and only if nobody edited the body while the model was writing.
#
#   REPO=owner/name PR_NUMBER=n OUT_DIR=.pr-hygiene GH_TOKEN=... describe-apply.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO:?REPO is required}"; : "${PR_NUMBER:?PR_NUMBER is required}"
out="${OUT_DIR:-.pr-hygiene}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
notice() { echo "::notice::$1"; echo "- $1" >> "$GITHUB_STEP_SUMMARY"; }

if [[ ! -s "$out/body.md" ]]; then
  notice "describe: no description was produced, so the body was left as it is"
  exit 0
fi
tr -d '\r' < "$out/body.md" > "$out/body.lf.md"

# current.md was taken before the model ran, minutes ago. A person may have
# typed their own summary since, and gh pr edit replaces the whole body - so
# read it again now and give up if it moved. The edited event that edit
# raised is queued behind this run and looks at the body afresh.
gh pr view "$PR_NUMBER" --repo "$REPO" --json body --jq '.body // ""' | tr -d '\r' > "$out/live.md"
if ! cmp -s "$out/current.md" "$out/live.md"; then
  notice "describe: the body was edited while the description was being written, so the proposal was discarded"
  exit 0
fi

if verdict="$(bash "$here/body-guard.sh" "$out/live.md" "$out/body.lf.md")"; then
  gh pr edit "$PR_NUMBER" --repo "$REPO" --body-file "$out/body.lf.md" > /dev/null
  notice "describe: filled in the empty sections of the description ($verdict)"
else
  rc=$?
  if (( rc == 3 )); then
    notice "describe: the describer changed nothing"
  else
    echo "::warning::describe: the proposed body was discarded - $verdict"
    echo "- describe: the proposed body was discarded - $verdict" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
