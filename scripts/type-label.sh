#!/usr/bin/env bash
# The type/* label for a pull request title, read from its conventional-commit
# prefix. Pure: title in, one label out.
#
#   type-label.sh "feat(auth): add passkeys"   -> type/feat
#   type-label.sh "Fix: typo in the runbook"   -> type/fix    (case does not matter)
#   type-label.sh "chore!: drop node 18"       -> type/chore  (a ! marks a breaking change)
#   type-label.sh "Update README"              -> type/chore  (no known prefix)
set -euo pipefail

title="${1:-}"
# prefix, optional (scope), optional ! for a breaking change, a colon, then a
# space or the end of the title.
re='^[[:space:]]*([A-Za-z]+)(\([^)]*\))?!?:([[:space:]]|$)'
if [[ "$title" =~ $re ]]; then
  kind="${BASH_REMATCH[1],,}"
  case "$kind" in
    feat|fix|chore|docs|ci|refactor|test|perf) echo "type/$kind"; exit 0 ;;
  esac
fi
echo "type/chore"
