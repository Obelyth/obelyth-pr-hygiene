#!/usr/bin/env bash
# Checks that a rewritten pull request body changed nothing but the template's
# placeholder comments.
#
#   body-guard.sh CURRENT NEW
#
# CURRENT is the body as it is; NEW is the proposed one. Exit 0 when NEW is
# CURRENT with each <!-- pr-hygiene: ... --> comment replaced by something and
# every other byte in place (CR/LF and trailing newlines aside), exit 3 when
# nothing changed, exit 1 with the reason for anything else. A body that was
# empty may become anything.
#
# "Something" is not quite anything: what goes into a slot may not open an
# HTML comment (which would hide every section after it), leave a code fence
# open (same effect), close an issue with a GitHub keyword, mention anyone
# with @, or look like a credential. The model reads the diff, and the diff
# is where a stranger's text comes from.
set -euo pipefail

if [[ $# -ne 2 || ! -f "$1" || ! -f "$2" ]]; then
  echo "usage: body-guard.sh CURRENT NEW" >&2
  exit 2
fi
old="$(tr -d '\r' < "$1")"
new="$(tr -d '\r' < "$2")"
fail() { echo "REJECTED: $1"; exit 1; }

# The marker, the same definition as placeholder.sh: case does not matter, and
# it is <!-- followed by optional whitespace and pr-hygiene:. The comment runs
# to the first --> after it, or to the end of the body when there is none.
# nocasematch is switched on only for these matches; every comparison of
# what a person wrote stays byte-exact.
start='<!--[[:space:]]*pr-hygiene:'
find_marker() {  # text -> MATCH is the marker's opening text, or return 1
  local rc=1
  shopt -s nocasematch
  [[ "$1" =~ $start ]] && rc=0
  shopt -u nocasematch
  (( rc == 0 )) && MATCH="${BASH_REMATCH[0]}"
  return $rc
}

kw_re='(^|[^[:alnum:]_])(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+(([[:alnum:]._-]+/[[:alnum:]._-]+)?#[0-9]+|https://github\.com/[[:alnum:]._-]+/[[:alnum:]._-]+/issues/[0-9]+)'
mention_re='(^|[^[:alnum:]_])@[[:alnum:]][[:alnum:]-]*'
secret_re='(^|[^[:alnum:]_])(sk-ant-|gh[pousr]_|github_pat_)'
check_slot() {  # text where
  local s="$1" where="$2" stripped
  [[ "$s" != *'<!--'* ]] || fail "$where holds an HTML comment, which would hide what follows"
  stripped="${s//\`\`\`/}"
  (( (${#s} - ${#stripped}) / 3 % 2 == 0 )) || fail "$where opens a \`\`\` code fence it does not close"
  stripped="${s//\~\~\~/}"
  (( (${#s} - ${#stripped}) / 3 % 2 == 0 )) || fail "$where opens a ~~~ code fence it does not close"
  local bad=""
  shopt -s nocasematch
  if [[ "$s" =~ $kw_re ]]; then bad="closes an issue with a GitHub keyword; linking is the development job's"
  elif [[ "$s" =~ $mention_re ]]; then bad="mentions someone with @"
  elif [[ "$s" =~ $secret_re ]]; then bad="looks like it holds a credential"
  fi
  shopt -u nocasematch
  [[ -z "$bad" ]] || fail "$where $bad"
}

if [[ -z "${old//[[:space:]]/}" ]]; then
  [[ -n "${new//[[:space:]]/}" ]] || fail "the new body is empty"
  check_slot "$new" "the body"
  echo "ok: the body was empty, so any description is an improvement"
  exit 0
fi
if [[ "$new" == "$old" ]]; then
  echo "unchanged: nothing was filled in"
  exit 3
fi

# Split the current body into the literal text between placeholders. Only a
# comment that opens a line is a placeholder; one quoted inside a sentence is
# text a person wrote and stays part of the literal segment.
nl=$'\n'
line_start="(^|$nl)[[:blank:]]*$"
segments=()   # segments[k] is the literal text before markers[k]
markers=()    # markers[k] is the placeholder comment after segments[k]
acc=""
rest="$old"
MATCH=""
while find_marker "$rest"; do
  pre="${rest%%"$MATCH"*}"
  tail="${rest:${#pre}}"
  if [[ "$tail" == *'-->'* ]]; then m="${tail%%-->*}-->"; else m="$tail"; fi
  if [[ "$pre" =~ $line_start ]]; then
    segments+=("$acc$pre")
    markers+=("$m")
    acc=""
  else
    acc+="$pre$m"
  fi
  rest="${rest:$(( ${#pre} + ${#m} ))}"
done
segments+=("$acc$rest")
(( ${#segments[@]} > 1 )) || fail "the current body has no placeholder to fill"

# The new body must be those segments, in order, with anything between them -
# anything that passes check_slot, or the placeholder itself left in place.
cur="$new"
first="${segments[0]}"
[[ "$cur" == "$first"* ]] || fail "the text before the first placeholder changed"
cur="${cur:${#first}}"
last=$(( ${#segments[@]} - 1 ))
orig=""   # what the slot being matched held before: its marker, or several when nothing separated them
for (( i = 1; i <= last; i++ )); do
  orig+="${markers[$(( i - 1 ))]}"
  seg="${segments[$i]}"
  [[ -n "$seg" ]] || continue
  [[ "$cur" == *"$seg"* ]] || fail "the text after placeholder $i was changed or removed"
  repl="${cur%%"$seg"*}"
  [[ "$repl" == "$orig" ]] || check_slot "$repl" "placeholder $i"
  orig=""
  cur="${cur:$(( ${#repl} + ${#seg} ))}"
done
if [[ -n "${segments[$last]}" ]]; then
  [[ -z "$cur" ]] || fail "text was added after the end of the body"
elif [[ "$cur" != "$orig" ]]; then
  check_slot "$cur" "the last placeholder"
fi
echo "ok: only placeholders changed"
