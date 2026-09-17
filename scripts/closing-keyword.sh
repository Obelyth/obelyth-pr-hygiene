#!/usr/bin/env bash
# Does a pull request body already close an issue? Reads the body on stdin.
#
#   closing-keyword.sh        exit 0 when any GitHub closing keyword references an issue
#   closing-keyword.sh 12     exit 0 when one references issue 12 in particular
#
# GitHub's keywords - close, closes, closed, fix, fixes, fixed, resolve,
# resolves, resolved, case does not matter - followed by #n, owner/repo#n or an
# issue URL. GitHub does not link from inside code, so fenced blocks, inline
# code spans and HTML comments are stripped first: a body that says
# "use `closes #12`" or shows the syntax in a code block closes nothing.
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

# Fenced code blocks: a line opening with ``` or ~~~ (up to three spaces of
# indent) starts one, the next such line ends it, and one left open runs to
# the end of the body - the same as GitHub renders it.
prose=""
in_fence=false
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^[[:space:]]{0,3}(\`\`\`|~~~) ]]; then
    if $in_fence; then in_fence=false; else in_fence=true; fi
    continue
  fi
  $in_fence || prose+="$line"$'\n'
done

# HTML comments, which may span lines; one left open hides the rest.
while [[ "$prose" == *'<!--'* ]]; do
  before="${prose%%<!--*}"
  after="${prose#*<!--}"
  if [[ "$after" == *'-->'* ]]; then after="${after#*-->}"; else after=""; fi
  prose="$before$after"
done

# Inline code spans, double-backtick first so ``a `b` c`` goes as one.
# shellcheck disable=SC2016  # the backticks are sed's pattern, not a command
prose="$(sed -E 's/``[^`]*``//g; s/`[^`]*`//g' <<< "$prose")"

if grep -qiE "${kw}${ref}" <<< "$prose"; then
  exit 0
fi
exit 1
