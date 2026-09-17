#!/usr/bin/env bash
# Does a pull request body already close an issue? Reads the body on stdin.
#
#   closing-keyword.sh        exit 0 when any GitHub closing keyword references an issue
#   closing-keyword.sh 12     exit 0 when one references issue 12 in particular
#
# GitHub's keywords - close, closes, closed, fix, fixes, fixed, resolve,
# resolves, resolved, case does not matter - followed by #n, owner/repo#n or an
# issue URL.
set -euo pipefail

n="${1:-}"
kw='(^|[^[:alnum:]_])(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+'
name='[[:alnum:]._-]+'
if [[ -n "$n" ]]; then
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "closing-keyword.sh: '$n' is not an issue number" >&2; exit 2; }
  ref="(($name/$name)?#$n|https://github\\.com/$name/$name/issues/$n)([^0-9]|$)"
else
  ref="(($name/$name)?#[0-9]+|https://github\\.com/$name/$name/issues/[0-9]+)"
fi
if grep -qiE "${kw}${ref}"; then
  exit 0
fi
exit 1
