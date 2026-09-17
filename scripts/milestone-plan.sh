#!/usr/bin/env bash
# Decides which milestone a pull request should get, without touching the
# network. Reads the repository's milestones as a JSON array of
# {title, state, number} on stdin.
#
#   POLICY=quarter|none|<title> CREATED_AT=<ISO date> CURRENT=<title or empty> \
#     milestone-plan.sh < milestones.json
#
# Prints action=skip|assign|create plus title=, due=, number= and reason=.
# A closed milestone is never reopened; a pull request that already has one is
# left alone; a literal title must already exist.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
policy="${POLICY:-quarter}"
created="${CREATED_AT:-}"
current="${CURRENT:-}"
milestones="$(cat)"
[[ -n "$milestones" ]] || milestones='[]'
jq -e 'type == "array"' <<< "$milestones" > /dev/null || { echo "milestone-plan.sh: stdin is not a JSON array" >&2; exit 2; }

skip() { echo "action=skip"; echo "reason=$1"; exit 0; }

[[ "$policy" != "none" ]] || skip "milestone policy is none"
[[ -z "$current" ]] || skip "already on milestone '$current'"

due=""
if [[ "$policy" == "quarter" ]]; then
  [[ -n "$created" ]] || { echo "milestone-plan.sh: CREATED_AT is required for the quarter policy" >&2; exit 2; }
  quarter="$(bash "$here/quarter.sh" "$created")"
  title="$(sed -n 's/^title=//p' <<< "$quarter")"
  due="$(sed -n 's/^due=//p' <<< "$quarter")"
else
  title="$policy"
fi

match="$(jq -c --arg t "$title" '[.[] | select(.title == $t)] | first // empty' <<< "$milestones")"
if [[ -n "$match" ]]; then
  state="$(jq -r '.state' <<< "$match")"
  number="$(jq -r '.number' <<< "$match")"
  [[ "$state" != "closed" ]] || skip "milestone '$title' is closed and is not reopened"
  echo "action=assign"; echo "title=$title"; echo "number=$number"
  exit 0
fi
if [[ "$policy" == "quarter" ]]; then
  echo "action=create"; echo "title=$title"; echo "due=$due"
  exit 0
fi
skip "milestone '$title' does not exist in this repository"
