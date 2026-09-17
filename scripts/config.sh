#!/usr/bin/env bash
# Reads a repository's .github/pr-hygiene.yml and prints every setting as a
# key=value line, defaults filled in, ready for GITHUB_OUTPUT. A missing file,
# or one that holds nothing but comments, means all defaults. Needs yq
# (mikefarah, v4), which the GitHub runners ship.
#
#   config.sh [PATH]
set -euo pipefail

path="${1:-.github/pr-hygiene.yml}"
command -v yq > /dev/null || { echo "config.sh: yq is required" >&2; exit 2; }

if [[ -f "$path" ]]; then
  yq '.' "$path" > /dev/null 2>&1 || { echo "config.sh: $path is not valid YAML" >&2; exit 2; }
  kind="$(yq 'type' "$path")"
  case "$kind" in
    '!!null') get() { yq -n "$1"; } ;;   # only comments, or a bare ---
    '!!map')  get() { yq "$1" "$path"; } ;;
    *) echo "config.sh: $path must be a mapping of settings, not $kind" >&2; exit 2 ;;
  esac
else
  get() { yq -n "$1"; }
fi

milestone="$(get '.milestone // "quarter"')"
# A single login is taken as a one-element list; the schema says array, but a
# bare string is an easy slip and an obvious meaning.
reviewers="$(get '[.reviewers // []] | flatten | map(tostring) | join(",")')"
copilot="$(get '.copilot_review // false')"
owner="$(get '.project.owner // ""')"
number="$(get '.project.number // 0')"
status_field="$(get '.project.status_field // "Status"')"
opened="$(get '.project.status.opened // "In Progress"')"
merged="$(get '.project.status.merged // "Done"')"
closed="$(get '.project.status.closed // "remove"')"

[[ -n "$milestone" ]] || { echo "config.sh: milestone must not be empty" >&2; exit 2; }
[[ "$copilot" == "true" || "$copilot" == "false" ]] || { echo "config.sh: copilot_review must be true or false" >&2; exit 2; }
[[ "$number" =~ ^[0-9]+$ ]] || { echo "config.sh: project.number must be a whole number" >&2; exit 2; }

# Each line below becomes one GITHUB_OUTPUT entry, so no value may hold a
# newline: a block scalar would smuggle in extra outputs.
for pair in "milestone=$milestone" "reviewers=$reviewers" "project.owner=$owner" \
            "project.status_field=$status_field" "project.status.opened=$opened" \
            "project.status.merged=$merged" "project.status.closed=$closed"; do
  if [[ "${pair#*=}" == *$'\n'* ]]; then
    echo "config.sh: ${pair%%=*} must be a single line" >&2; exit 2
  fi
done

echo "milestone=$milestone"
echo "reviewers=$reviewers"
echo "copilot_review=$copilot"
echo "project_owner=$owner"
echo "project_number=$number"
echo "project_status_field=$status_field"
echo "project_status_opened=$opened"
echo "project_status_merged=$merged"
echo "project_status_closed=$closed"
