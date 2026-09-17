#!/usr/bin/env bash
# Installs PR Hygiene into a repository - by pull request, never by a push to
# the default branch (the estate's rulesets require one, and a change to what
# runs on every pull request deserves a look anyway).
#
#   ./install.sh --repo owner/name           one repository
#   ./install.sh --owner Obelyth             every non-archived repository of an owner
#   ./install.sh --repo Obelyth/.github --template-only
#                                            only the pull request template, for the
#                                            organization-wide default
#   flags: --dry-run       show what would change, touch nothing
#          --only-missing  skip repositories that already have the caller
#          --force         replace an existing release.yml and pull request
#                          template; without it those are only added when absent
#
# What lands, on a branch called chore/pr-hygiene-install, as one pull request:
#   .github/workflows/pr-hygiene.yml   the caller, rendered from templates/caller.template.yml;
#                                      always brought up to date
#   .github/release.yml                release-notes categories by the type/* labels
#   .github/pull_request_template.md   the template with the placeholder comments
#   .github/pr-hygiene.yml             the settings file, only ever added, never replaced
#
# Safe to run repeatedly. A repository whose files already match is left alone.
set -euo pipefail
cd "$(dirname "$0")"

CALLER_PATH=".github/workflows/pr-hygiene.yml"
BRANCH="chore/pr-hygiene-install"

self="${GITHUB_REPOSITORY:-}"
if [[ -z "$self" ]]; then
  self="$(git config --get remote.origin.url 2> /dev/null \
    | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##' || true)"
fi
self="${self:-Obelyth/obelyth-pr-hygiene}"

DRY_RUN=false; ONLY_MISSING=false; FORCE=false; TEMPLATE_ONLY=false
REPO=""; OWNER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --only-missing) ONLY_MISSING=true ;;
    --force) FORCE=true ;;
    --template-only) TEMPLATE_ONLY=true ;;
    --repo) REPO="${2:-}"; shift ;;
    --owner) OWNER="${2:-}"; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done
if [[ -z "$REPO" && -z "$OWNER" ]]; then
  echo "give --repo owner/name or --owner name" >&2
  exit 2
fi

say() { printf '%s\n' "$*"; }

render_caller() {
  sed -e "s|__TOOLKIT_REPO__|$self|g" templates/caller.template.yml
}

list_repos() {
  if [[ -n "$REPO" ]]; then echo "$REPO"; return; fi
  gh repo list "$OWNER" --limit 200 --json nameWithOwner,isArchived \
    --jq '.[] | select(.isArchived | not) | .nameWithOwner'
}

# The content of a file on a ref, or nothing.
remote_file() {  # repo path ref
  gh api "repos/$1/contents/$2?ref=$3" --jq '.content' 2> /dev/null | base64 -d 2> /dev/null || true
}
remote_sha() {  # repo path ref
  gh api "repos/$1/contents/$2?ref=$3" --jq '.sha' 2> /dev/null || true
}

# Writes one file to the install branch, creating the branch from the default
# branch the first time. Returns 0 when something was written.
put_file() {  # repo path content message
  local repo="$1" path="$2" content="$3" message="$4" sha args
  sha="$(remote_sha "$repo" "$path" "$BRANCH")"
  args=(-f "message=$message" -f "content=$(printf '%s' "$content" | base64 -w0)" -f "branch=$BRANCH")
  [[ -n "$sha" ]] && args+=(-f "sha=$sha")
  gh api -X PUT "repos/$repo/contents/$path" "${args[@]}" > /dev/null
}

ensure_branch() {  # repo default_branch
  local repo="$1" base
  if gh api "repos/$repo/git/ref/heads/$BRANCH" > /dev/null 2>&1; then return 0; fi
  base="$(gh api "repos/$repo/git/ref/heads/$2" --jq '.object.sha')"
  gh api -X POST "repos/$repo/git/refs" -f "ref=refs/heads/$BRANCH" -f "sha=$base" > /dev/null
}

install_into() {
  local repo="$1" default_branch existing desired
  local -a plan=()   # "path<TAB>message"
  local -A want=()

  default_branch="$(gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name' 2> /dev/null || true)"
  if [[ -z "$default_branch" ]]; then say "  skip - empty repository or unreadable"; return; fi

  if ! $TEMPLATE_ONLY; then
    desired="$(render_caller)"
    existing="$(remote_file "$repo" "$CALLER_PATH" "$default_branch")"
    if [[ -n "$existing" ]] && $ONLY_MISSING; then say "  already installed"; return; fi
    if [[ "$existing" != "$desired" ]]; then
      want[$CALLER_PATH]="$desired"
      if [[ -n "$existing" ]]; then plan+=("$CALLER_PATH	ci: refresh the PR Hygiene caller")
      else plan+=("$CALLER_PATH	ci: add PR Hygiene"); fi
    fi

    desired="$(cat templates/release.yml)"
    existing="$(remote_file "$repo" ".github/release.yml" "$default_branch")"
    if [[ -z "$existing" ]]; then
      want[.github/release.yml]="$desired"; plan+=(".github/release.yml	chore: release notes grouped by type/* labels")
    elif [[ "$existing" != "$desired" ]]; then
      if $FORCE; then want[.github/release.yml]="$desired"; plan+=(".github/release.yml	chore: replace release notes config with the PR Hygiene one")
      else say "  keeping the repository's own .github/release.yml (--force replaces it)"; fi
    fi

    existing="$(remote_file "$repo" ".github/pr-hygiene.yml" "$default_branch")"
    if [[ -z "$existing" ]]; then
      want[.github/pr-hygiene.yml]="$(cat templates/pr-hygiene.yml)"
      plan+=(".github/pr-hygiene.yml	chore: PR Hygiene settings")
    fi
  fi

  desired="$(cat templates/pull_request_template.md)"
  existing="$(remote_file "$repo" ".github/pull_request_template.md" "$default_branch")"
  if [[ -z "$existing" ]]; then
    # A template at the repository root or in docs/ counts too; do not shadow it.
    if [[ -z "$(remote_file "$repo" "pull_request_template.md" "$default_branch")$(remote_file "$repo" "docs/pull_request_template.md" "$default_branch")" ]] || $FORCE; then
      want[.github/pull_request_template.md]="$desired"; plan+=(".github/pull_request_template.md	chore: pull request template with sections PR Hygiene can fill")
    else
      say "  keeping the repository's own pull request template (--force replaces it)"
    fi
  elif [[ "$existing" != "$desired" ]]; then
    if $FORCE; then want[.github/pull_request_template.md]="$desired"; plan+=(".github/pull_request_template.md	chore: replace the pull request template with the PR Hygiene one")
    else say "  keeping the repository's own .github/pull_request_template.md (--force replaces it)"; fi
  fi

  if (( ${#plan[@]} == 0 )); then say "  up to date"; return; fi
  local line
  for line in "${plan[@]}"; do say "  ${line%%	*} - ${line#*	}"; done
  $DRY_RUN && return

  ensure_branch "$repo" "$default_branch"
  for line in "${plan[@]}"; do
    local path="${line%%	*}" msg="${line#*	}"
    if [[ "$(remote_file "$repo" "$path" "$BRANCH")" == "${want[$path]}" ]]; then continue; fi
    put_file "$repo" "$path" "${want[$path]}" "$msg"
  done

  local existing_pr
  existing_pr="$(gh pr list -R "$repo" --head "$BRANCH" --state open --json number --jq '.[0].number // empty' 2> /dev/null || true)"
  if [[ -n "$existing_pr" ]]; then
    say "    updated pull request #$existing_pr"
  else
    gh pr create -R "$repo" --base "$default_branch" --head "$BRANCH" \
      --title "ci: add PR Hygiene" \
      --body "$(printf 'Installs PR Hygiene: labels, milestone, linked issue, description, release notes and board, filled in on every pull request.\n\nSettings: .github/pr-hygiene.yml. Full description: https://github.com/%s' "$self")" > /dev/null
    say "    opened a pull request"
  fi
}

report_secrets() {
  local repo="$1" owner="${1%%/*}" names
  names="$(gh secret list -R "$repo" --json name --jq '[.[].name] | join(",")' 2> /dev/null || true)"
  names="${names},$(gh secret list --org "$owner" --json name --jq '[.[].name] | join(",")' 2> /dev/null || true)"
  [[ "$names" == *CLAUDE_CODE_OAUTH_TOKEN* || "$names" == *ANTHROPIC_API_KEY* ]] \
    || say "  note: no CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY - descriptions will not be written"
  [[ "$names" == *PROJECTS_TOKEN* ]] \
    || say "  note: no PROJECTS_TOKEN - the project board will not be touched"
}

$DRY_RUN && { say "DRY RUN - nothing will be changed."; say ""; }
while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue
  if [[ "$repo" == "$self" ]]; then say "$repo"; say "  skip - the toolkit runs its own copy"; continue; fi
  if [[ -z "$REPO" && "${repo#*/}" == ".github" ]]; then say "$repo"; say "  skip - the org repo gets --template-only, on its own"; continue; fi
  say "$repo"
  install_into "$repo"
  $TEMPLATE_ONLY || report_secrets "$repo"
done < <(list_repos)
