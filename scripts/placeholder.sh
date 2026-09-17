#!/usr/bin/env bash
# Does this pull request body still need a description? Reads the body on
# stdin. Exit 0 when it is empty (whitespace only) or still carries a
# placeholder comment from the template - a line that opens with
# <!-- pr-hygiene: - and exit 1 when a person has written it. A mention of
# the marker inside a sentence is not a placeholder.
set -euo pipefail

body="$(cat)"
if [[ -z "${body//[[:space:]]/}" ]]; then
  exit 0
fi
if grep -qiE '^[[:space:]]*<!--[[:space:]]*pr-hygiene:' <<< "$body"; then
  exit 0
fi
exit 1
