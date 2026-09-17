#!/usr/bin/env bash
# Makes sure the label scheme exists in a repository. Idempotent: an existing
# label gets its colour and description refreshed, nothing is ever deleted.
#
#   REPO=owner/name GH_TOKEN=... labels-ensure.sh labels/labels.json
set -euo pipefail

file="${1:-}"
[[ -f "$file" ]] || { echo "usage: labels-ensure.sh LABELS_JSON" >&2; exit 2; }
: "${REPO:?REPO is required}"

n=0
while IFS=$'\t' read -r name color description; do
  gh label create "$name" --repo "$REPO" --color "$color" --description "$description" --force > /dev/null
  n=$((n + 1))
done < <(jq -r '.[] | [.name, .color, .description] | @tsv' "$file")
echo "$n labels present in $REPO"
