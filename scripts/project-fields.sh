#!/usr/bin/env bash
# Resolves a Projects v2 single-select field and one of its options by name,
# from the field list a GraphQL query returned. Reads the fields' nodes array
# on stdin.
#
#   project-fields.sh FIELD_NAME OPTION_NAME < fields.json
#
# Prints field_id= and option_id=. Exit 1 when the field does not exist, 4
# when the field exists but has no option of that name.
set -euo pipefail

field="${1:-}"; option="${2:-}"
[[ -n "$field" && -n "$option" ]] || { echo "usage: project-fields.sh FIELD_NAME OPTION_NAME < fields.json" >&2; exit 2; }
nodes="$(cat)"
node="$(jq -c --arg f "$field" '[.[] | select(.name == $f)] | first // empty' <<< "$nodes")"
[[ -n "$node" ]] || { echo "no field named '$field' on this project" >&2; exit 1; }
field_id="$(jq -r '.id' <<< "$node")"
option_id="$(jq -r --arg o "$option" '(.options // [])[] | select(.name == $o) | .id' <<< "$node" | head -n1)"
echo "field_id=$field_id"
[[ -n "$option_id" ]] || { echo "field '$field' has no option named '$option'" >&2; exit 4; }
echo "option_id=$option_id"
