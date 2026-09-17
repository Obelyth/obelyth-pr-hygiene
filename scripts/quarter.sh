#!/usr/bin/env bash
# The quarter milestone for a date: its title and its due date, the last day of
# that quarter. Dates are read as UTC, which is how GitHub reports created_at.
#
#   quarter.sh 2026-09-17T10:11:12Z
#   title=Q3 2026
#   due=2026-09-30
set -euo pipefail

d="${1:-}"
if ! [[ "$d" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
  echo "quarter.sh: expected an ISO 8601 date, got '$d'" >&2
  exit 2
fi
year="${BASH_REMATCH[1]}"
month=$((10#${BASH_REMATCH[2]}))
day=$((10#${BASH_REMATCH[3]}))
if (( month < 1 || month > 12 || day < 1 || day > 31 )); then
  echo "quarter.sh: '$d' is not a calendar date" >&2
  exit 2
fi
q=$(( (month - 1) / 3 + 1 ))
case "$q" in
  1) due="$year-03-31" ;;
  2) due="$year-06-30" ;;
  3) due="$year-09-30" ;;
  *) due="$year-12-31" ;;
esac
echo "title=Q$q $year"
echo "due=$due"
