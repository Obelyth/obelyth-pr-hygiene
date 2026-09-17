#!/usr/bin/env bash
# Does this pull request body still need a description? Reads the body on
# stdin. Exit 0 when it is empty (whitespace only) or still carries a
# placeholder comment from the template - one that opens with
# <!-- pr-hygiene: - and exit 1 when a person has written it.
set -euo pipefail

body="$(cat)"
if [[ -z "${body//[[:space:]]/}" ]]; then
  exit 0
fi
if grep -qiE '<!--[[:space:]]*pr-hygiene:' <<< "$body"; then
  exit 0
fi
exit 1
