#!/usr/bin/env bash
# Blocking check: the description must open with the required sentence and
# contain every quoted trigger phrase. Shared by CI and tests/test.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
file="${1:-}"
if [[ -n "$file" ]]; then
  description="$(bash "$SCRIPT_DIR/extract-description.sh" "$file")"
else
  description="$(bash "$SCRIPT_DIR/extract-description.sh")"
fi

echo "Description: $description"
failed=0
if [[ "$description" != "Writes, converts, syncs and looks up"* ]]; then
  echo "ERROR: description must open with 'Writes, converts, syncs and looks up'" >&2
  failed=1
fi

phrases=(
  "write the feature docs"
  "document this feature"
  "convert these docs"
  "sync the feature docs"
  "reconcile the feature docs"
  "update the feature documentation"
  "what did we decide about X"
)
for phrase in "${phrases[@]}"; do
  if ! printf '%s\n' "$description" | grep -qF -- "$phrase"; then
    echo "ERROR: Missing trigger phrase: $phrase" >&2
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
echo "All quoted trigger phrases present"
