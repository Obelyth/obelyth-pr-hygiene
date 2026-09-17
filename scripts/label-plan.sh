#!/usr/bin/env bash
# Decides what to do about one managed label namespace (type/* or size/*) on a
# pull request, without touching the network.
#
#   label-plan.sh NAMESPACE WANTED LABELS_FILE EVENTS_FILE OWN_FILE
#
#   NAMESPACE    type or size
#   WANTED       the label this tool computed, e.g. type/feat
#   LABELS_FILE  the pull request's current labels, one per line
#   EVENTS_FILE  its labeled/unlabeled events in order, tab-separated:
#                event <TAB> label <TAB> actor login
#   OWN_FILE     the labels this tool may claim as its own, one per line: the
#                scheme's names, minus any the repository's labeler.yml hands
#                to actions/labeler
#
# Prints add=<label> and remove=<label> lines for the caller to apply, and
# note= lines for the job summary. The rule: a label in the namespace that this
# tool put there - it is one of its own names and the last thing to add it was
# github-actions[bot] - and that no longer matches is replaced. One a person put
# there, or one that belongs to another automation running under the same bot,
# is never removed, and when such a label sits in the namespace the computed
# one is not added over it.
set -euo pipefail

ns="${1:-}"; want="${2:-}"; labels_file="${3:-}"; events_file="${4:-}"; own_file="${5:-}"
bot="${LABEL_BOT:-github-actions[bot]}"
if [[ -z "$ns" || -z "$want" || ! -f "$labels_file" || ! -f "$events_file" || ! -f "$own_file" ]]; then
  echo "usage: label-plan.sh NAMESPACE WANTED LABELS_FILE EVENTS_FILE OWN_FILE" >&2
  exit 2
fi

have=false
other=""
stale=()
while IFS= read -r label; do
  [[ "$label" == "$ns/"* ]] || continue
  if [[ "$label" == "$want" ]]; then have=true; continue; fi
  actor="$(awk -F'\t' -v L="$label" '$1 == "labeled" && $2 == L { a = $3 } END { print a }' "$events_file")"
  if [[ "$actor" == "$bot" ]] && grep -qxF -- "$label" "$own_file"; then
    stale+=("$label")
  else
    other="$label"
  fi
done < "$labels_file"

for s in "${stale[@]+"${stale[@]}"}"; do
  echo "remove=$s"
done
if [[ -n "$other" ]]; then
  echo "note=$other was set by a person or another tool, so $want was not added over it"
elif ! $have; then
  echo "add=$want"
fi
