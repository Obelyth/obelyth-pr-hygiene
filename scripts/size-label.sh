#!/usr/bin/env bash
# The size/* label for a diff: additions plus deletions, bucketed.
#
#   size-label.sh ADDITIONS DELETIONS
#   XS < 10 lines, S < 50, M < 200, L < 500, XL from 500 up.
set -euo pipefail

add="${1:-}"; del="${2:-}"
if ! [[ "$add" =~ ^[0-9]+$ && "$del" =~ ^[0-9]+$ ]]; then
  echo "usage: size-label.sh ADDITIONS DELETIONS (whole numbers)" >&2
  exit 2
fi
n=$((10#$add + 10#$del))
if   (( n < 10 ));  then echo size/XS
elif (( n < 50 ));  then echo size/S
elif (( n < 200 )); then echo size/M
elif (( n < 500 )); then echo size/L
else                     echo size/XL
fi
