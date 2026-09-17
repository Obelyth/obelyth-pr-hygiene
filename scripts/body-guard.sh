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
set -euo pipefail

if [[ $# -ne 2 || ! -f "$1" || ! -f "$2" ]]; then
  echo "usage: body-guard.sh CURRENT NEW" >&2
  exit 2
fi
old="$(tr -d '\r' < "$1")"
new="$(tr -d '\r' < "$2")"
fail() { echo "REJECTED: $1"; exit 1; }

if [[ -z "${old//[[:space:]]/}" ]]; then
  [[ -n "${new//[[:space:]]/}" ]] || fail "the new body is empty"
  echo "ok: the body was empty, so any description is an improvement"
  exit 0
fi
if [[ "$new" == "$old" ]]; then
  echo "unchanged: nothing was filled in"
  exit 3
fi

# Split the current body into the literal text between placeholders.
ph='<!--[[:space:]]*pr-hygiene:[^>]*-->'
segments=()
rest="$old"
while [[ "$rest" =~ $ph ]]; do
  m="${BASH_REMATCH[0]}"
  pre="${rest%%"$m"*}"
  segments+=("$pre")
  rest="${rest:$(( ${#pre} + ${#m} ))}"
done
segments+=("$rest")
(( ${#segments[@]} > 1 )) || fail "the current body has no placeholder to fill"

# The new body must be those segments, in order, with anything between them.
cur="$new"
first="${segments[0]}"
[[ "$cur" == "$first"* ]] || fail "the text before the first placeholder changed"
cur="${cur:${#first}}"
last=$(( ${#segments[@]} - 1 ))
for (( i = 1; i <= last; i++ )); do
  seg="${segments[$i]}"
  [[ -n "$seg" ]] || continue
  [[ "$cur" == *"$seg"* ]] || fail "the text after placeholder $i was changed or removed"
  repl="${cur%%"$seg"*}"
  cur="${cur:$(( ${#repl} + ${#seg} ))}"
done
if [[ -n "${segments[$last]}" && -n "$cur" ]]; then
  fail "text was added after the end of the body"
fi
echo "ok: only placeholders changed"
