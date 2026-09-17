#!/usr/bin/env bash
# Gathers what the describer needs and decides whether it should run at all.
# Writes current.md (the body, LF line endings), title.txt, files.txt and
# diff.patch into OUT_DIR, and needed=true|false to GITHUB_OUTPUT.
#
#   REPO=owner/name PR_NUMBER=n OUT_DIR=.pr-hygiene GH_TOKEN=... describe-prepare.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO:?REPO is required}"; : "${PR_NUMBER:?PR_NUMBER is required}"
out="${OUT_DIR:-.pr-hygiene}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
notice() { echo "::notice::$1"; echo "- $1" >> "$GITHUB_STEP_SUMMARY"; }
max_lines="${DIFF_MAX_LINES:-3000}"

mkdir -p "$out"
pr="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json title,body)"
jq -r '.title' <<< "$pr" > "$out/title.txt"
jq -r '.body // ""' <<< "$pr" | tr -d '\r' > "$out/current.md"

if ! bash "$here/placeholder.sh" < "$out/current.md"; then
  echo "needed=false" >> "$GITHUB_OUTPUT"
  echo "describe: the body is written; nothing to fill"
  exit 0
fi

gh pr diff "$PR_NUMBER" --repo "$REPO" --name-only > "$out/files.txt"
gh pr diff "$PR_NUMBER" --repo "$REPO" > "$out/diff.full"
total="$(wc -l < "$out/diff.full")"
if (( total > max_lines )); then
  head -n "$max_lines" "$out/diff.full" > "$out/diff.patch"
  printf '\n[truncated: %s of %s lines shown; run gh pr diff %s for the rest]\n' "$max_lines" "$total" "$PR_NUMBER" >> "$out/diff.patch"
else
  mv "$out/diff.full" "$out/diff.patch"
fi
rm -f "$out/diff.full"
echo "needed=true" >> "$GITHUB_OUTPUT"
echo "describe: the body is empty or still has template placeholders"
