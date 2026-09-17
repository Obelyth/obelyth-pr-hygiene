#!/usr/bin/env bash
# Does this pull request body still need a description? Reads the body on
# stdin. Exit 0 when it is empty (whitespace only) or still carries a
# placeholder comment from the template - a line that opens with
# <!-- pr-hygiene: - and exit 1 when a person has written it. A mention of
# the marker inside a sentence is not a placeholder.
#
# The marker here and the one body-guard.sh splits on are the same
# definition: case does not matter, blanks may precede it on the line, and
# it is <!-- followed by optional whitespace and pr-hygiene:. Keep them in
# step, or the describer runs and the guard then rejects its output.
set -euo pipefail

body="$(cat)"
if [[ -z "${body//[[:space:]]/}" ]]; then
  exit 0
fi
if grep -qiE '^[[:blank:]]*<!--[[:space:]]*pr-hygiene:' <<< "$body"; then
  exit 0
fi
exit 1
