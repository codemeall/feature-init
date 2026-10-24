#!/usr/bin/env bash
# Run every prompt in evals/triggers.json through a real agent CLI, once with
# feature-docs installed and once without. Skill loads come from the CLI trace.
# If no CLI or credentials are available, print SKIP and exit 0. Never invents scores.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"
TRIGGERS="$ROOT/evals/triggers.json"
TRACE_JS="$HARNESS_DIR/trace.js"
INSTALL="$ROOT/install.sh"
# shellcheck source=evals/harness/lib.sh
source "$HARNESS_DIR/lib.sh"

EVAL_TIMEOUT="${EVAL_TIMEOUT:-180}"
RUNNER=""
OUT=""

usage() {
  cat <<EOF
Usage: $0 [--runner <name-or-path>] [--out <dir>]

Runs every prompt in evals/triggers.json twice:
  with the feature-docs skill installed in a temporary project
  without that skill

Precision and recall use the CLI trace. A load is a Skill tool call, or a
read of the installed SKILL.md. Reply text does not count.

  --runner NAME    claude, cursor, or a path to a custom runner
  --out DIR        results.json, summary.md, and traces (default: evals/harness/out/<time>)
  --help

If the selected runner has no CLI or credentials, this prints SKIP and exits 0.
It does not write scores.

Custom runners implement:
  probe                         exit 0 when ready, exit 3 when the CLI or credentials are missing
  agent                         print claude, cursor, codex, or antigravity
  run --cwd DIR --trace FILE --prompt TEXT
  skill-loaded --trace FILE --skill NAME --skill-dir DIR
                                exit 0 loaded, 1 not loaded, 2 unreadable trace

Examples:
  ./evals/harness/run-harness-eval.sh --runner claude
  ./evals/harness/run-harness-eval.sh --runner cursor
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runner) RUNNER="${2:-}"; [[ -n "$RUNNER" ]] || { echo "Error: --runner needs a name" >&2; exit 2; }; shift 2 ;;
    --out) OUT="${2:-}"; [[ -n "$OUT" ]] || { echo "Error: --out needs a directory" >&2; exit 2; }; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$EVAL_TIMEOUT" =~ ^[0-9]+$ && "$EVAL_TIMEOUT" -gt 0 ]] || {
  echo "Error: EVAL_TIMEOUT must be a positive number of seconds" >&2
  exit 2
}

resolve_runner() {
  local name="$1" path
  if [[ "$name" == */* ]]; then
    [[ -f "$name" ]] || { echo "Error: runner not found: $name" >&2; exit 2; }
    printf '%s\n' "$name"
    return 0
  fi
  path="$HARNESS_DIR/runners/$name"
  if [[ ! -f "$path" && -f "$path.sh" ]]; then
    path="$path.sh"
  fi
  [[ -f "$path" ]] || { echo "Error: unknown runner: $name" >&2; exit 2; }
  printf '%s\n' "$path"
}

skip() {
  printf 'SKIP: %s\n' "$1"
  cat <<EOF

This run did not score any prompts.
Command:
  ./evals/harness/run-harness-eval.sh --runner claude
  ./evals/harness/run-harness-eval.sh --runner cursor
EOF
  exit 0
}

choose_runner() {
  local candidate path reason rc
  if [[ -n "$RUNNER" ]]; then
    RUNNER_PATH="$(resolve_runner "$RUNNER")"
    RUNNER_NAME="$(basename "$RUNNER_PATH")"
    RUNNER_NAME="${RUNNER_NAME%.sh}"
    reason="$(bash "$RUNNER_PATH" probe)" && rc=0 || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi
    if [[ "$rc" -eq 3 ]]; then
      skip "$reason"
    fi
    echo "Error: runner probe failed: $reason" >&2
    exit "$rc"
  fi
  local reasons=""
  for candidate in claude cursor; do
    path="$(resolve_runner "$candidate")"
    reason="$(bash "$path" probe)" && rc=0 || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      RUNNER_PATH="$path"
      RUNNER_NAME="$candidate"
      return 0
    fi
    if [[ "$rc" -eq 3 ]]; then
      reasons="${reasons}${candidate}: ${reason}"$'\n'
      continue
    fi
    echo "Error: $candidate probe failed: $reason" >&2
    exit "$rc"
  done
  skip "no agent CLI with credentials is available.
${reasons}"
}

choose_runner

if ! command -v node >/dev/null 2>&1; then
  echo "Error: node is required to read the CLI trace. No scores were computed." >&2
  exit 2
fi
[[ -f "$TRIGGERS" ]] || { echo "Error: missing $TRIGGERS" >&2; exit 2; }

if [[ -z "$OUT" ]]; then
  OUT="$HARNESS_DIR/out/$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$OUT/traces"
OBS="$OUT/observations.jsonl"
: > "$OBS"

agent="$(bash "$RUNNER_PATH" agent)"
case "$agent" in
  claude|cursor|codex|antigravity) ;;
  *) echo "Error: runner agent must be claude, cursor, codex, or antigravity (got $agent)" >&2; exit 2 ;;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/feature-docs-harness.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
WITH_DIR="$WORK/with-skill"
WITHOUT_DIR="$WORK/without-skill"
make_workspace() {
  local dir="$1"
  mkdir -p "$dir"
  git init -q "$dir"
  printf 'A temporary workspace for a trigger eval. It is not the feature-docs repository.\n' > "$dir/README.md"
}
make_workspace "$WITH_DIR"
make_workspace "$WITHOUT_DIR"
bash "$INSTALL" "$agent" --project "$WITH_DIR" >/dev/null
case "$agent" in
  claude) SKILL_DIR="$WITH_DIR/.claude/skills/feature-docs" ;;
  cursor) SKILL_DIR="$WITH_DIR/.cursor/skills/feature-docs" ;;
  codex) SKILL_DIR="$WITH_DIR/.codex/skills/feature-docs" ;;
  antigravity) SKILL_DIR="$WITH_DIR/.agents/skills/feature-docs" ;;
esac
[[ -f "$SKILL_DIR/SKILL.md" ]] || { echo "Error: install did not create $SKILL_DIR/SKILL.md" >&2; exit 2; }

fail_run() {
  local message="$1"
  node "$TRACE_JS" report \
    --observations "$OBS" \
    --status incomplete \
    --runner "$RUNNER_NAME" \
    --out "$OUT" \
    --error "$message" >/dev/null || true
  echo "Error: $message" >&2
  echo "Partial notes: $OUT/summary.md" >&2
  echo "No precision or recall was computed." >&2
  exit 1
}

node -e '
const fs = require("node:fs");
const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const trigger = Array.isArray(data.should_trigger) ? data.should_trigger : [];
const miss = Array.isArray(data.should_not_trigger) ? data.should_not_trigger : [];
if (trigger.length === 0 || miss.length === 0) process.exit(2);
for (const prompt of trigger) console.log(JSON.stringify({ expected: "trigger", prompt }));
for (const prompt of miss) console.log(JSON.stringify({ expected: "near_miss", prompt }));
' "$TRIGGERS" > "$WORK/prompts.jsonl" || fail_run "triggers.json needs should_trigger and should_not_trigger prompts"

index=0
while IFS= read -r row; do
  index=$((index + 1))
  expected="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).expected)' "$row")"
  prompt="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).prompt)' "$row")"
  with_trace="$OUT/traces/$(printf '%02d' "$index")-with.jsonl"
  without_trace="$OUT/traces/$(printf '%02d' "$index")-without.jsonl"
  echo "prompt $index ($expected)" >&2
  if ! run_with_timeout "$EVAL_TIMEOUT" bash "$RUNNER_PATH" run --cwd "$WITH_DIR" --trace "$with_trace" --prompt "$prompt"; then
    fail_run "runner failed for the with-skill run of prompt $index"
  fi
  if ! run_with_timeout "$EVAL_TIMEOUT" bash "$RUNNER_PATH" run --cwd "$WITHOUT_DIR" --trace "$without_trace" --prompt "$prompt"; then
    fail_run "runner failed for the without-skill run of prompt $index"
  fi
  loaded_with=0
  if bash "$RUNNER_PATH" skill-loaded --trace "$with_trace" --skill feature-docs --skill-dir "$SKILL_DIR"; then
    loaded_with=1
  else
    rc=$?
    [[ "$rc" -eq 1 ]] || fail_run "with-skill trace for prompt $index could not be read (exit $rc)"
  fi
  loaded_without=0
  if bash "$RUNNER_PATH" skill-loaded --trace "$without_trace" --skill feature-docs --skill-dir "$SKILL_DIR"; then
    loaded_without=1
  else
    rc=$?
    [[ "$rc" -eq 1 ]] || fail_run "without-skill trace for prompt $index could not be read (exit $rc)"
  fi
  node -e '
const fs = require("node:fs");
const row = {
  prompt: process.argv[1],
  expected: process.argv[2],
  loaded_with_skill: process.argv[3] === "1",
  loaded_without_skill: process.argv[4] === "1",
  trace_with: process.argv[5],
  trace_without: process.argv[6]
};
fs.appendFileSync(process.argv[7], JSON.stringify(row) + "\n");
' "$prompt" "$expected" "$loaded_with" "$loaded_without" "$with_trace" "$without_trace" "$OBS"
done < "$WORK/prompts.jsonl"

rc=0
node "$TRACE_JS" report --observations "$OBS" --status complete --runner "$RUNNER_NAME" --out "$OUT" || rc=$?
if [[ "$rc" -eq 2 ]]; then
  echo "The without-skill run loaded feature-docs. Precision and recall were not computed." >&2
  echo "Wrote $OUT/results.json" >&2
  echo "Wrote $OUT/summary.md" >&2
  exit 2
fi
[[ "$rc" -eq 0 ]] || exit "$rc"
echo "Wrote $OUT/results.json"
echo "Wrote $OUT/summary.md"
