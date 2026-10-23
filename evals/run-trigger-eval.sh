#!/usr/bin/env bash
# Static description check for feature-docs skill trigger coverage
# Scores each prompt by IDF-weighted coverage against the description and reports coverage and max overlap.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TRIGGERS="$SCRIPT_DIR/triggers.json"
# SKILL_MD overrides the skill file so regression descriptions can be scored.
SKILL_DESC="${SKILL_MD:-$ROOT/skills/feature-docs/SKILL.md}"

usage() {
  cat <<EOF
Usage: $0 [--report]

Static description check for the feature-docs skill. Scores each prompt in
triggers.json by IDF-weighted overlap with the SKILL.md description. Inverse
document frequency is computed over the 24 prompts in triggers.json, so a word
that appears in many prompts counts less than a word that appears in few.

The gate requires:
- every should-trigger prompt scores at least 60
- every near miss scores at most 55
- the margin (worst should-trigger minus best near miss) is at least 12

Reported metrics:
- coverage: average should-trigger score
- max overlap: the highest near-miss score

  --report    Show the score for each prompt
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

{
  jq -r '.should_trigger[] | "T\t" + .' "$TRIGGERS"
  jq -r '.should_not_trigger[] | "N\t" + .' "$TRIGGERS"
} | awk -v description="$description" -v report="$REPORT" '
BEGIN {
  stop["the"] = 1
  stop["a"] = 1
  stop["an"] = 1
  stop["for"] = 1
  stop["to"] = 1
  stop["of"] = 1
  stop["in"] = 1
  stop["on"] = 1
  stop["at"] = 1
  stop["by"] = 1
  stop["with"] = 1
  stop["from"] = 1
  stop["this"] = 1
  stop["that"] = 1
  stop["is"] = 1
  stop["are"] = 1
  stop["these"] = 1
  stop["those"] = 1

  nparts = split(tolower(description), parts, /[^a-z0-9]+/)
  for (i = 1; i <= nparts; i++) {
    if (parts[i] != "") desc[parts[i]] = 1
  }
}

function tokenize(text, out,    i, n, parts, w) {
  delete out
  n = split(tolower(text), parts, /[^a-z0-9]+/)
  for (i = 1; i <= n; i++) {
    w = parts[i]
    if (w != "" && !(w in stop)) out[w] = 1
  }
}

{
  count++
  kinds[count] = substr($0, 1, 1)
  texts[count] = substr($0, 3)
  tokenize(texts[count], words)
  tok = ""
  for (w in words) {
    df[w]++
    tok = tok w " "
  }
  tokens[count] = tok
}

END {
  if (count == 0) {
    print "FAIL: no prompts in triggers.json"
    exit 1
  }

  print "=== Scoring prompts against SKILL.md description ==="
  print ""

  min_t = 101
  max_n = -1
  sum_t = 0
  sum_n = 0
  n_t = 0
  n_n = 0

  if (report == 1) print "Should-trigger prompts:"
  for (i = 1; i <= count; i++) {
    if (kinds[i] != "T") continue
    score = prompt_score(i)
    scores[i] = score
    sum_t += score
    n_t++
    if (score < min_t) min_t = score
    if (report == 1) printf "  %5.1f%% - %s\n", score, texts[i]
  }

  if (report == 1) {
    print ""
    print "Should-not-trigger prompts:"
  }
  for (i = 1; i <= count; i++) {
    if (kinds[i] != "N") continue
    score = prompt_score(i)
    scores[i] = score
    sum_n += score
    n_n++
    if (score > max_n) max_n = score
    if (report == 1) printf "  %5.1f%% - %s\n", score, texts[i]
  }

  if (n_t == 0 || n_n == 0) {
    print "FAIL: triggers.json needs both should-trigger and should-not-trigger prompts"
    exit 1
  }

  avg_t = sum_t / n_t
  avg_n = sum_n / n_n
  margin = min_t - max_n

  print ""
  print "=== Results ==="
  printf "Should-trigger:     min=%.1f%%, avg=%.1f%% (%d prompts)\n", min_t, avg_t, n_t
  printf "Should-not-trigger: max=%.1f%%, avg=%.1f%% (%d prompts)\n", max_n, avg_n, n_n
  print ""
  printf "Coverage:     %.1f%% (avg should-trigger)\n", avg_t
  printf "Max overlap:  %.1f%% (best near-miss)\n", max_n
  print ""

  failed = 0
  if (min_t < 60) {
    printf "FAIL: worst should-trigger prompt scored %.1f%%, below 60%% threshold\n", min_t
    failed = 1
  }
  if (max_n > 55) {
    printf "FAIL: best near-miss prompt scored %.1f%%, above 55%% threshold\n", max_n
    failed = 1
  }
  if (margin < 12) {
    printf "FAIL: margin between worst should-trigger (%.1f%%) and best near-miss (%.1f%%) is %.1f%%, below 12 point minimum\n", min_t, max_n, margin
    failed = 1
  }
  if (failed) exit 1

  print "Static description check passed"
  exit 0
}

function prompt_score(i,    j, nws, ws, w, idf, sum_all, sum_hit) {
  nws = split(tokens[i], ws, " ")
  sum_all = 0
  sum_hit = 0
  for (j = 1; j <= nws; j++) {
    w = ws[j]
    if (w == "") continue
    idf = log(count / df[w])
    sum_all += idf
    if (w in desc) sum_hit += idf
  }
  if (sum_all == 0) return 0
  return (sum_hit / sum_all) * 100
}
'
