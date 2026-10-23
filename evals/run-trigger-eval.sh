#!/usr/bin/env bash
# Static description check for feature-docs skill trigger coverage
# Scores prompts by word overlap with description, measures precision and recall
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TRIGGERS="$SCRIPT_DIR/triggers.json"
SKILL_DESC="$ROOT/skills/feature-docs/SKILL.md"

usage() {
  cat <<EOF
Usage: $0 [--report]

Static description check for the feature-docs skill. Scores each prompt in
triggers.json by word overlap with the SKILL.md description, then validates:
- All should-trigger prompts score above a threshold
- No should-not-trigger prompt scores as high as the worst should-trigger

  --report    Show detailed scores for each prompt
  --help      Show this help

This is a lightweight static check. For full evaluation, manually test skill
loading in a harness: run 'claude -p <repo>' with and without the skill
installed, comparing which prompts load feature-docs.
EOF
}

if [[ "${1:-}" == "--help" ]]; then usage; exit 0; fi
REPORT=0
if [[ "${1:-}" == "--report" ]]; then REPORT=1; fi

# Require jq for JSON parsing
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required for parsing triggers.json" >&2
  exit 2
fi

# Extract description from SKILL.md frontmatter
description="$(sed -n '/^---$/,/^---$/p' "$SKILL_DESC" | sed -n '/^description:/,/^[a-z][a-z]*:/p' | sed '$d' | sed 's/^description:[[:space:]]*>-[[:space:]]*//' | sed 's/^[[:space:]]*//' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

# Normalize to lowercase for matching
description_lower="$(echo "$description" | tr '[:upper:]' '[:lower:]')"

# Score a prompt by counting how many of its significant words appear in description
score_prompt() {
  local prompt="$1"
  local prompt_lower words
  prompt_lower="$(echo "$prompt" | tr '[:upper:]' '[:lower:]')"
  # Extract words, skip common stop words
  words="$(echo "$prompt_lower" | tr -cs '[:alnum:]' '\n' | grep -Ev '^(the|a|an|for|to|of|in|on|at|by|with|from|this|that|is|are|these|those)$' | grep -v '^$')"
  local total=0
  local matched=0
  while IFS= read -r word; do
    [[ -n "$word" ]] || continue
    ((total++)) || true
    if echo "$description_lower" | grep -qw "$word"; then
      ((matched++)) || true
    fi
  done <<< "$words"
  if [[ $total -eq 0 ]]; then echo "0"; return; fi
  awk "BEGIN {printf \"%.2f\", ($matched / $total) * 100}"
}

# Parse triggers
mapfile -t should_trigger < <(jq -r '.should_trigger[]' "$TRIGGERS")
mapfile -t should_not_trigger < <(jq -r '.should_not_trigger[]' "$TRIGGERS")

echo "=== Scoring prompts against SKILL.md description ==="
echo

# Score should-trigger prompts
min_trigger_score=100
total_trigger_score=0
if [[ $REPORT -eq 1 ]]; then echo "Should-trigger prompts:"; fi
for prompt in "${should_trigger[@]}"; do
  score="$(score_prompt "$prompt")"
  total_trigger_score="$(awk "BEGIN {print $total_trigger_score + $score}")"
  score_int="$(awk "BEGIN {print int($score)}")"
  if [[ $score_int -lt $min_trigger_score ]]; then
    min_trigger_score=$score_int
  fi
  [[ $REPORT -eq 1 ]] && printf "  %5.1f%% - %s\n" "$score" "$prompt"
done

if [[ $REPORT -eq 1 ]]; then echo; echo "Should-not-trigger prompts:"; fi
# Score should-not-trigger prompts
max_non_trigger_score=0
total_non_trigger_score=0
for prompt in "${should_not_trigger[@]}"; do
  score="$(score_prompt "$prompt")"
  total_non_trigger_score="$(awk "BEGIN {print $total_non_trigger_score + $score}")"
  score_int="$(awk "BEGIN {print int($score)}")"
  if [[ $score_int -gt $max_non_trigger_score ]]; then
    max_non_trigger_score=$score_int
  fi
  [[ $REPORT -eq 1 ]] && printf "  %5.1f%% - %s\n" "$score" "$prompt"
done

echo
echo "=== Results ==="
avg_trigger="$(awk "BEGIN {printf \"%.1f\", $total_trigger_score / ${#should_trigger[@]}}")"
avg_non_trigger="$(awk "BEGIN {printf \"%.1f\", $total_non_trigger_score / ${#should_not_trigger[@]}}")"

echo "Should-trigger:     min=${min_trigger_score}%, avg=${avg_trigger}% (${#should_trigger[@]} prompts)"
echo "Should-not-trigger: max=${max_non_trigger_score}%, avg=${avg_non_trigger}% (${#should_not_trigger[@]} prompts)"
echo

# Validation: every should-trigger prompt must score at least 60%
threshold_trigger=60
if [[ $min_trigger_score -lt $threshold_trigger ]]; then
  echo "FAIL: worst should-trigger prompt scored ${min_trigger_score}%, below ${threshold_trigger}% threshold"
  exit 1
fi

# Validation: every should-not-trigger prompt must score at most 67%
threshold_near_miss=67
if [[ $max_non_trigger_score -gt $threshold_near_miss ]]; then
  echo "FAIL: best near-miss prompt scored ${max_non_trigger_score}%, above ${threshold_near_miss}% threshold"
  exit 1
fi

# Validation: worst should-trigger must beat best should-not-trigger by at least 14 points
margin=$((min_trigger_score - max_non_trigger_score))
if [[ $margin -lt 14 ]]; then
  echo "FAIL: margin between worst should-trigger (${min_trigger_score}%) and best near-miss (${max_non_trigger_score}%) is ${margin}%, below 14% minimum"
  exit 1
fi

coverage="$avg_trigger"
max_overlap="$max_non_trigger_score"

echo "Coverage:     ${coverage}% (avg should-trigger)"
echo "Max overlap:  ${max_overlap}% (best near-miss)"
echo
echo "✓ Static description check passed"
exit 0
