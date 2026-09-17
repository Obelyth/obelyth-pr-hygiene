#!/usr/bin/env bash
# Keeps a pull request's Status on a Projects v2 board in step with its state:
# opened -> the opened status (only when it has none yet, so a person's move
# is kept), merged -> the merged status, closed without merging -> removed
# from the board, or set to the closed status when that option exists.
#
# Field and option ids are resolved by name on every run, case-insensitively,
# so renaming a column in the board's UI needs nothing here. A status the
# board does not have is a notice, not a failure. Needs a token that can
# write projects: GITHUB_TOKEN cannot, see README.
#
#   GH_TOKEN=<PROJECTS_TOKEN> PROJECT_OWNER=Obelyth PROJECT_NUMBER=3 STATUS_FIELD=Status \
#   STATUS_OPENED="In Progress" STATUS_MERGED=Done STATUS_CLOSED=remove \
#   PR_NODE_ID=PR_kwDO... ITEM_ID=<from actions/add-to-project, may be empty> \
#   EVENT_ACTION=opened|closed|... MERGED=true|false project-sync.sh
#
# The $name tokens inside the single-quoted queries are GraphQL variables,
# bound with -F, not shell expansions.
# shellcheck disable=SC2016
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PROJECT_OWNER:?}"; : "${PROJECT_NUMBER:?}"; : "${PR_NODE_ID:?}"
field="${STATUS_FIELD:-Status}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
notice() { echo "::notice::$1"; echo "- $1" >> "$GITHUB_STEP_SUMMARY"; }

owner_type="$(gh api "users/$PROJECT_OWNER" --jq '.type')"
root="user"; [[ "$owner_type" == "Organization" ]] && root="organization"
project="$(gh api graphql -F login="$PROJECT_OWNER" -F number="$PROJECT_NUMBER" -f query="
  query(\$login: String!, \$number: Int!) {
    $root(login: \$login) {
      projectV2(number: \$number) {
        id
        fields(first: 100) {
          nodes { ... on ProjectV2SingleSelectField { id name options { id name } } }
        }
      }
    }
  }")"
project_id="$(jq -r ".data.$root.projectV2.id // empty" <<< "$project")"
[[ -n "$project_id" ]] || { echo "project-sync.sh: no project $PROJECT_NUMBER under $PROJECT_OWNER, or the token cannot see it" >&2; exit 1; }
fields="$(jq ".data.$root.projectV2.fields.nodes | map(select(.id != null))" <<< "$project")"

# Which item on the board is this pull request?
item="${ITEM_ID:-}"
if [[ -z "$item" ]]; then
  item="$(gh api graphql -F id="$PR_NODE_ID" -f query='
    query($id: ID!) {
      node(id: $id) { ... on PullRequest { projectItems(first: 100) { nodes { id project { id } } } } }
    }' | jq -r --arg p "$project_id" '.data.node.projectItems.nodes[] | select(.project.id == $p) | .id' | head -n1)"
fi

mode="set"; target=""
if [[ "${MERGED:-false}" == "true" ]]; then
  target="${STATUS_MERGED:-Done}"
elif [[ "${EVENT_ACTION:-}" == "closed" ]]; then
  if [[ "${STATUS_CLOSED:-remove}" == "remove" ]]; then
    mode="remove"
  else
    target="${STATUS_CLOSED}"
    # "Cancelled" only if the board has such a column; otherwise off the board.
    if ! bash "$here/project-fields.sh" "$field" "$target" <<< "$fields" > /dev/null 2>&1; then
      mode="remove"
    fi
  fi
else
  mode="set-if-empty"; target="${STATUS_OPENED:-In Progress}"
fi

if [[ -z "$item" ]]; then
  if [[ "$mode" == "remove" ]]; then
    echo "projects: not on the board, nothing to remove"
    exit 0
  fi
  echo "project-sync.sh: the pull request is not on the board and no item id was given" >&2
  exit 1
fi

if [[ "$mode" == "remove" ]]; then
  gh api graphql -F project="$project_id" -F item="$item" -f query='
    mutation($project: ID!, $item: ID!) {
      deleteProjectV2Item(input: { projectId: $project, itemId: $item }) { deletedItemId }
    }' > /dev/null
  notice "projects: removed from $PROJECT_OWNER's board #$PROJECT_NUMBER (closed without merging)"
  exit 0
fi

if [[ "$mode" == "set-if-empty" ]]; then
  current="$(gh api graphql -F id="$item" -F field="$field" -f query='
    query($id: ID!, $field: String!) {
      node(id: $id) { ... on ProjectV2Item { fieldValueByName(name: $field) { ... on ProjectV2ItemFieldSingleSelectValue { name } } } }
    }' | jq -r '.data.node.fieldValueByName.name // empty')"
  if [[ -n "$current" ]]; then
    echo "projects: already '$current' on the board; left where it is"
    exit 0
  fi
fi

# A board whose columns are not the settings' - GitHub's own template says
# "Todo / In Progress / Done", a renamed column, a merged status that never
# existed - is a notice in the summary, not a red check on every event.
rc=0
ids="$(bash "$here/project-fields.sh" "$field" "$target" <<< "$fields" 2> /dev/null)" || rc=$?
if (( rc == 4 )); then
  notice "projects: the board's '$field' field has no option named '$target', so the status was left as it is - set project.status in .github/pr-hygiene.yml to one of its options"
  exit 0
elif (( rc != 0 )); then
  echo "project-sync.sh: the board has no field named '$field'; set project.status_field in .github/pr-hygiene.yml" >&2
  exit 1
fi
field_id="$(sed -n 's/^field_id=//p' <<< "$ids")"
option_id="$(sed -n 's/^option_id=//p' <<< "$ids")"
gh api graphql -F project="$project_id" -F item="$item" -F field="$field_id" -F option="$option_id" -f query='
  mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
    updateProjectV2ItemFieldValue(input: { projectId: $project, itemId: $item, fieldId: $field, value: { singleSelectOptionId: $option } }) {
      projectV2Item { id }
    }
  }' > /dev/null
notice "projects: $field set to '$target' on $PROJECT_OWNER's board #$PROJECT_NUMBER"
