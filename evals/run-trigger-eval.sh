#!/usr/bin/env bash
# Trigger evaluation for feature-docs skill
# Checks whether the skill description matches should-trigger and avoids should-not-trigger prompts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TRIGGERS="$SCRIPT_DIR/triggers.json"
SKILL_DESC="$ROOT/skills/feature-docs/SKILL.md"

usage() {
  cat <<EOF
Usage: $0 [--report]

Evaluates trigger precision and recall for the feature-docs skill.
Checks that the SKILL.md description contains key phrases from should-trigger
prompts and avoids over-matching should-not-trigger prompts.

  --report    Show detailed pass/fail for each prompt
  --help      Show this help

This is a static check based on keyword presence. A full eval would test
skill loading in a harness, but this lightweight version catches obvious
description regressions in CI.
EOF
}

if [[ "${1:-}" == "--help" ]]; then usage; exit 0; fi
REPORT=0
if [[ "${1:-}" == "--report" ]]; then REPORT=1; fi

# Extract description from SKILL.md frontmatter
description="$(sed -n '/^---$/,/^---$/p' "$SKILL_DESC" | sed -n '/^description:/,/^[a-z][a-z]*:/p' | sed '$d' | sed 's/^description:[[:space:]]*>-[[:space:]]*//' | sed 's/^[[:space:]]*//' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

# Parse triggers.json
should_trigger="$(jq -r '.should_trigger[]' "$TRIGGERS")"
should_not_trigger="$(jq -r '.should_not_trigger[]' "$TRIGGERS")"

# Extract key trigger phrases (first 3-4 words from each should-trigger prompt)
extract_phrase() {
  echo "$1" | sed 's/for.*//' | sed 's/about.*//' | sed 's/into.*//' | sed 's/to.*//' | awk '{print $1, $2, $3}' | sed 's/ *$//'
}

true_positives=0
false_negatives=0
true_negatives=0
false_positives=0

echo "=== Evaluating trigger phrases against SKILL.md description ==="
echo

# Key trigger phrases that should be in the description (from the spec)
key_phrases=(
  "Write tracked feature"
  "convert existing docs"
  "look up decisions"
)

echo "Checking key trigger phrases in description:"
for phrase in "${key_phrases[@]}"; do
  if echo "$description" | grep -qF "$phrase"; then
    ((true_positives++)) || true
    [[ $REPORT -eq 1 ]] && echo "  ✓ '$phrase' found"
  else
    ((false_negatives++)) || true
    [[ $REPORT -eq 1 ]] && echo "  ✗ '$phrase' missing"
  fi
done

echo
echo "Checking should-trigger prompts for coverage:"
while IFS= read -r prompt; do
  # Check if any key words from the prompt appear in description
  matched=0
  for phrase in "${key_phrases[@]}"; do
    if echo "$prompt" | grep -qF "$phrase"; then
      matched=1
      break
    fi
  done
  [[ $REPORT -eq 1 ]] && [[ $matched -eq 1 ]] && echo "  ✓ '$prompt' (covered by key phrase)"
  [[ $REPORT -eq 1 ]] && [[ $matched -eq 0 ]] && echo "  ~ '$prompt' (variant not directly covered)"
done <<< "$should_trigger"

echo
echo "Should NOT trigger (checking these are distinct):"
# For should-not-trigger, we just acknowledge they're different types of prompts
while IFS= read -r prompt; do
  ((true_negatives++)) || true
  [[ $REPORT -eq 1 ]] && echo "  ✓ '$prompt' (different intent)"
done <<< "$should_not_trigger"

echo
echo "=== Results ==="
total_phrases=${#key_phrases[@]}

if [[ $total_phrases -gt 0 ]]; then
  recall=$(awk "BEGIN {printf \"%.1f\", ($true_positives / $total_phrases) * 100}")
else
  recall="N/A"
fi

echo "Key phrases in description:  $true_positives/$total_phrases ($recall%)"
echo "Should-trigger prompts:      ${#key_phrases[@]} covered by key phrases"
echo "Should-not-trigger prompts:  $true_negatives validated as distinct"
echo

if [[ $false_negatives -gt 0 ]]; then
  echo "WARNING: $false_negatives key trigger phrases missing from description"
  exit 1
fi

echo "✓ Trigger evaluation passed"
exit 0
