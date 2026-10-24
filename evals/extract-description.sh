#!/usr/bin/env bash
# Print the SKILL.md description as one line.
# Usage: extract-description.sh [path-to-SKILL.md]
set -euo pipefail

file="${1:-}"
if [[ -z "$file" ]]; then
  root="$(cd "$(dirname "$0")/.." && pwd)"
  file="$root/skills/feature-docs/SKILL.md"
fi
[[ -f "$file" ]] || { echo "Error: skill file not found: $file" >&2; exit 2; }

sed -n '/^---$/,/^---$/p' "$file" \
  | sed -n '/^description:/,/^[a-z][a-z]*:/p' \
  | sed '$d' \
  | sed 's/^description:[[:space:]]*>-[[:space:]]*//' \
  | sed 's/^[[:space:]]*//' \
  | tr '\n' ' ' \
  | sed 's/  */ /g' \
  | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
echo
