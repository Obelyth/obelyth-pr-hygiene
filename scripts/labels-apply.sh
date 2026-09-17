#!/usr/bin/env bash
# Puts the type/* label from the title and the size/* label from the diff on a
# pull request. Labels a person added are never removed; see label-plan.sh.
#
#   REPO=owner/name PR_NUMBER=n GH_TOKEN=... labels-apply.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO:?REPO is required}"; : "${PR_NUMBER:?PR_NUMBER is required}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
notice() { echo "::notice::$1"; echo "- $1" >> "$GITHUB_STEP_SUMMARY"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

pr="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json title,additions,deletions,labels)"
title="$(jq -r '.title' <<< "$pr")"
additions="$(jq -r '.additions' <<< "$pr")"
deletions="$(jq -r '.deletions' <<< "$pr")"
jq -r '.labels[].name' <<< "$pr" > "$tmp/labels"
# Who put each label there. Paginated: a long-lived pull request has many events.
gh api --paginate "repos/$REPO/issues/$PR_NUMBER/events" \
  --jq '.[] | select(.event == "labeled" or .event == "unlabeled") | [.event, .label.name, .actor.login] | @tsv' \
  > "$tmp/events" 2> /dev/null || : > "$tmp/events"

want_type="$(bash "$here/type-label.sh" "$title")"
want_size="$(bash "$here/size-label.sh" "$additions" "$deletions")"

add=(); remove=()
for pair in "type $want_type" "size $want_size"; do
  ns="${pair%% *}"; want="${pair#* }"
  while IFS='=' read -r key value; do
    case "$key" in
      add) add+=("$value") ;;
      remove) remove+=("$value") ;;
      note) notice "$value" ;;
    esac
  done < <(bash "$here/label-plan.sh" "$ns" "$want" "$tmp/labels" "$tmp/events")
done

args=()
if (( ${#add[@]} )); then args+=(--add-label "$(IFS=,; echo "${add[*]}")"); fi
if (( ${#remove[@]} )); then args+=(--remove-label "$(IFS=,; echo "${remove[*]}")"); fi
if (( ${#args[@]} == 0 )); then
  echo "labels already right: $want_type $want_size"
  exit 0
fi
gh pr edit "$PR_NUMBER" --repo "$REPO" "${args[@]}" > /dev/null
notice "labels: added ${add[*]:-nothing}, removed ${remove[*]:-nothing} ($additions+ $deletions-)"
