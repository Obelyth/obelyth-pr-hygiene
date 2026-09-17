#!/usr/bin/env bash
# Decides what to do about one managed label namespace (type/* or size/*) on a
# pull request, without touching the network.
#
#   label-plan.sh NAMESPACE WANTED LABELS_FILE EVENTS_FILE
#
#   NAMESPACE    type or size
#   WANTED       the label this tool computed, e.g. type/feat
#   LABELS_FILE  the pull request's current labels, one per line
#   EVENTS_FILE  its labeled/unlabeled events in order, tab-separated:
#                event <TAB> label <TAB> actor login
#
# Prints add=<label> and remove=<label> lines for the caller to apply, and
# note= lines for the job summary. The rule: a label in the namespace that this
# tool put there (actor github-actions[bot]) and that no longer matches is
# replaced; one a person put there is never removed, and when a person chose a
# label in the namespace the computed one is not added over it.
set -euo pipefail

ns="${1:-}"; want="${2:-}"; labels_file="${3:-}"; events_file="${4:-}"
bot="${LABEL_BOT:-github-actions[bot]}"
if [[ -z "$ns" || -z "$want" || ! -f "$labels_file" || ! -f "$events_file" ]]; then
  echo "usage: label-plan.sh NAMESPACE WANTED LABELS_FILE EVENTS_FILE" >&2
  exit 2
fi

have=false
human=""
stale=()
while IFS= read -r label; do
  [[ "$label" == "$ns/"* ]] || continue
  if [[ "$label" == "$want" ]]; then have=true; continue; fi
  actor="$(awk -F'\t' -v L="$label" '$1 == "labeled" && $2 == L { a = $3 } END { print a }' "$events_file")"
  if [[ "$actor" == "$bot" ]]; then
    stale+=("$label")
  else
    human="$label"
  fi
done < "$labels_file"

for s in "${stale[@]+"${stale[@]}"}"; do
  echo "remove=$s"
done
if [[ -n "$human" ]]; then
  echo "note=$human was set by a person, so $want was not added over it"
elif ! $have; then
  echo "add=$want"
fi
