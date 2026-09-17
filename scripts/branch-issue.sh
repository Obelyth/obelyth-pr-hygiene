#!/usr/bin/env bash
# The issue number a branch name carries, if any: a number at the start of the
# branch or of any path segment, optionally with a leading #, followed by a
# dash, an underscore or the end of the name. Prints it and exits 0; exits 1
# when there is none.
#
# Two shapes that carry a number but do not name an issue are refused unless
# the # is there: a number followed by another run of digits (a date such as
# 2026-09-17, a version such as 1-2-3), and a four-digit number from 1900 to
# 2099, which reads as a year. A branch named after an HTTP status - fix/404-page
# - does name issue #404 if one exists; write fix/http-404-page to avoid that.
#
#   feat/12-passkeys          -> 12
#   12-passkeys               -> 12
#   hotfix/#7-null-user       -> 7
#   feature/no-number         -> (exit 1)
#   release/v1.2              -> (exit 1)
#   chore/2026-09-17-cleanup  -> (exit 1)  a date
#   release/2026-Q3           -> (exit 1)  a year
#   feat/#2026-x              -> 2026      the # says it is an issue
set -euo pipefail

branch="${1:-}"
if [[ "$branch" =~ (^|/)(#?)([0-9]+)([-_]|$)(.*) ]]; then
  hash="${BASH_REMATCH[2]}"; digits="${BASH_REMATCH[3]}"; after="${BASH_REMATCH[5]}"
  n=$((10#$digits))
  (( n > 0 )) || exit 1
  if [[ -z "$hash" ]]; then
    # 2026-09-17-x, 1-2-3, 1_2: the next segment is digits too, so this is a
    # date or a version, not an issue.
    [[ "$after" =~ ^[0-9]+([-_./]|$) ]] && exit 1
    # 2026-Q3, 2024-roadmap: a year.
    (( ${#digits} == 4 && n >= 1900 && n <= 2099 )) && exit 1
  fi
  echo "$n"
  exit 0
fi
exit 1
