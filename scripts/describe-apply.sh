#!/usr/bin/env bash
# Puts the describer's body on the pull request - but only after body-guard.sh
# has confirmed it changed nothing except the template's placeholder comments.
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
if verdict="$(bash "$here/body-guard.sh" "$out/current.md" "$out/body.lf.md")"; then
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
