#!/usr/bin/env bash
# The issue number a branch name carries, if any: a number at the start of the
# branch or of any path segment, optionally with a leading #, followed by a
# dash, an underscore or the end of the name. Prints it and exits 0; exits 1
# when there is none.
#
#   feat/12-passkeys      -> 12
#   12-passkeys           -> 12
#   hotfix/#7-null-user   -> 7
#   feature/no-number     -> (exit 1)
#   release/v1.2          -> (exit 1)
set -euo pipefail

branch="${1:-}"
if [[ "$branch" =~ (^|/)#?([0-9]+)([-_]|$) ]]; then
  n=$((10#${BASH_REMATCH[2]}))
  if (( n > 0 )); then
    echo "$n"
    exit 0
  fi
fi
exit 1
