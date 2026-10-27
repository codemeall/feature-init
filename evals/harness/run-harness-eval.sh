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
MODEL="${HARNESS_MODEL:-}"
STOP_AFTER_TOOLS="${HARNESS_STOP_AFTER_TOOLS:-4}"
MAX_PROMPTS="${HARNESS_MAX_PROMPTS:-0}"
MIN_SCORED="${HARNESS_MIN_SCORED:-0.8}"
RUNNER=""
OUT=""

usage() {
  cat <<EOF
Usage: $0 [--runner <name-or-path>] [--out <dir>] [--model <name>] [--timeout <secs>]
          [--stop-after-tools <n>] [--max-prompts <n>] [--min-scored <fraction>]

Runs every prompt in evals/triggers.json twice:
  without the feature-docs skill
  then with that skill installed in a temporary project

Precision and recall use the CLI trace. A load is a Skill tool call named
feature-docs, or a read of that skill's installed SKILL.md. A directory
listing, a read of a different skill, and a path that only contains the
name do not count. Reply text does not count.

  --runner NAME    claude, cursor, or a path to a custom runner
  --out DIR        results.json, summary.md, and traces (default: evals/harness/out/<time>)
  --model NAME     model passed to the agent CLI (env HARNESS_MODEL; default: CLI default)
  --timeout SECS   per run limit (env EVAL_TIMEOUT, default 180). A timeout skips that prompt.
  --stop-after-tools N
                   end a run at the first skill load, or after N started tool calls
                   without one (env HARNESS_STOP_AFTER_TOOLS, default 4, 0 disables)
  --max-prompts N  run only N prompts, alternating should-trigger and near-miss
                   (env HARNESS_MAX_PROMPTS, default 0 means all). A truncation
                   is a smoke run and does not claim precision or recall.
  --min-scored F   fraction of prompts that must score, or the run is incomplete
                   and no rates are claimed (env HARNESS_MIN_SCORED, default 0.8).
                   0 still needs at least one scored row, and both classes.
  --help

Each run gets a fresh empty workspace outside the repository and, for Cursor,
an empty HOME that holds only the CLI login file. Skipped prompts (timeout,
runner failure, unreadable trace) are reported but left out of precision and recall.

If the selected runner has no CLI or credentials, this prints SKIP and exits 0.
It does not write scores.

Custom runners implement:
  probe                         exit 0 when ready, exit 3 when the CLI or credentials are missing
  agent                         print claude, cursor, codex, or antigravity
  run --cwd DIR --trace FILE --prompt TEXT
  skill-loaded --trace FILE --skill NAME --skill-dir DIR [--any-install]
                                exit 0 loaded, 1 not loaded, 2 unreadable trace
                                --any-install detects control contamination from other installs

Examples:
  ./evals/harness/run-harness-eval.sh --runner claude
  ./evals/harness/run-harness-eval.sh --runner cursor
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runner) RUNNER="${2:-}"; [[ -n "$RUNNER" ]] || { echo "Error: --runner needs a name" >&2; exit 2; }; shift 2 ;;
    --out) OUT="${2:-}"; [[ -n "$OUT" ]] || { echo "Error: --out needs a directory" >&2; exit 2; }; shift 2 ;;
    --model) MODEL="${2:-}"; [[ -n "$MODEL" ]] || { echo "Error: --model needs a name" >&2; exit 2; }; shift 2 ;;
    --timeout) EVAL_TIMEOUT="${2:-}"; shift 2 ;;
    --stop-after-tools) STOP_AFTER_TOOLS="${2:-}"; shift 2 ;;
    --max-prompts) MAX_PROMPTS="${2:-}"; shift 2 ;;
    --min-scored) MIN_SCORED="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$EVAL_TIMEOUT" =~ ^[0-9]+$ && "$EVAL_TIMEOUT" -gt 0 ]] || {
  echo "Error: EVAL_TIMEOUT must be a positive number of seconds" >&2
  exit 2
}
[[ "$STOP_AFTER_TOOLS" =~ ^[0-9]+$ ]] || { echo "Error: --stop-after-tools must be a whole number" >&2; exit 2; }
[[ "$MAX_PROMPTS" =~ ^[0-9]+$ ]] || { echo "Error: --max-prompts must be a whole number" >&2; exit 2; }
[[ "$MIN_SCORED" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]] || { echo "Error: --min-scored must be between 0 and 1" >&2; exit 2; }
export HARNESS_MODEL="$MODEL"

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

if ! command -v node >/dev/null 2>&1; then
  echo "Error: node is required to read the CLI trace. No scores were computed." >&2
  exit 2
fi
choose_runner
[[ -f "$TRIGGERS" ]] || { echo "Error: missing $TRIGGERS" >&2; exit 2; }

if [[ -z "$OUT" ]]; then
  OUT="$HARNESS_DIR/out/$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$OUT/traces"
OUT="$(cd "$OUT" && pwd -P)"
OBS="$OUT/observations.jsonl"
: > "$OBS"

agent="$(bash "$RUNNER_PATH" agent)"
case "$agent" in
  claude|cursor|codex|antigravity) ;;
  *) echo "Error: runner agent must be claude, cursor, codex, or antigravity (got $agent)" >&2; exit 2 ;;
esac

# Workspaces live in their own temporary root. Prompts stay in memory, so no
# eval file (triggers.json, prompt lists, harness scripts) sits near the agent.
# The directory name omits the skill name so the path does not advertise it.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/harness-eval.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

# A fresh workspace per run, so files one run writes cannot steer the next.
make_workspace() {
  local dir
  dir="$(mktemp -d "$WORK/ws.XXXXXX")"
  dir="$(cd "$dir" && pwd -P)"
  git init -q "$dir"
  printf 'Temporary workspace.\n' > "$dir/README.md"
  printf '%s\n' "$dir"
}
# The control arm has no install. Scoring it against a path that is not on
# disk keeps an exact path match from pointing at the with-skill copy.
CONTROL_SKILL_DIR="/var/empty/harness-skill-not-installed"
skill_dir_for() {
  case "$agent" in
    claude) printf '%s\n' "$1/.claude/skills/feature-docs" ;;
    cursor) printf '%s\n' "$1/.cursor/skills/feature-docs" ;;
    codex) printf '%s\n' "$1/.codex/skills/feature-docs" ;;
    antigravity) printf '%s\n' "$1/.agents/skills/feature-docs" ;;
  esac
}

fail_run() {
  local message="$1"
  node "$TRACE_JS" report \
    --observations "$OBS" \
    --status incomplete \
    --runner "$RUNNER_NAME" \
    --model "$MODEL" \
    --out "$OUT" \
    --error "$message" >/dev/null || true
  echo "Error: $message" >&2
  echo "Partial notes: $OUT/summary.md" >&2
  echo "No precision or recall was computed." >&2
  exit 1
}

PROMPTS=()
while IFS= read -r line; do
  PROMPTS+=("$line")
done < <(node -e '
const fs = require("node:fs");
const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const trigger = Array.isArray(data.should_trigger) ? data.should_trigger : [];
const miss = Array.isArray(data.should_not_trigger) ? data.should_not_trigger : [];
if (trigger.length === 0 || miss.length === 0) process.exit(2);
const max = Number(process.argv[2]);
let rows = [];
if (max > 0) {
  for (let i = 0; rows.length < max && (i < trigger.length || i < miss.length); i++) {
    if (i < trigger.length) rows.push({ expected: "trigger", prompt: trigger[i] });
    if (rows.length < max && i < miss.length) rows.push({ expected: "near_miss", prompt: miss[i] });
  }
} else {
  rows = trigger.map((prompt) => ({ expected: "trigger", prompt }))
    .concat(miss.map((prompt) => ({ expected: "near_miss", prompt })));
}
for (const row of rows) console.log(JSON.stringify(row));
' "$TRIGGERS" "$MAX_PROMPTS" || echo "__error__")
[[ "${#PROMPTS[@]}" -gt 0 && "${PROMPTS[0]}" != "__error__" && "${PROMPTS[${#PROMPTS[@]}-1]}" != "__error__" ]] \
  || fail_run "triggers.json needs should_trigger and should_not_trigger prompts"

CATALOG_SIZE="$(node -e '
const fs = require("node:fs");
const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const trigger = Array.isArray(data.should_trigger) ? data.should_trigger : [];
const miss = Array.isArray(data.should_not_trigger) ? data.should_not_trigger : [];
process.stdout.write(String(trigger.length + miss.length));
' "$TRIGGERS")"

# Runs one arm. Prints "ok" or "skip:<reason>". Never aborts the eval.
run_arm() {
  local cwd="$1" trace="$2" prompt="$3" any_install="${4:-0}" skill_dir="${5:-}" rc=0
  HARNESS_WATCH_TRACE="$trace" HARNESS_WATCH_SKILL=feature-docs \
    HARNESS_WATCH_SKILL_DIR="$skill_dir" HARNESS_WATCH_ANY_INSTALL="$any_install" \
    HARNESS_STOP_AFTER_TOOLS="$STOP_AFTER_TOOLS" \
    run_with_timeout "$EVAL_TIMEOUT" bash "$RUNNER_PATH" run --cwd "$cwd" --trace "$trace" --prompt "$prompt" >&2 || rc=$?
  if [[ "$rc" -eq 124 ]]; then printf 'skip:timeout after %ss\n' "$EVAL_TIMEOUT"; return 0; fi
  if [[ "$rc" -ne 0 ]]; then printf 'skip:runner exit %s\n' "$rc"; return 0; fi
  printf 'ok\n'
}

# Prints 1 loaded, 0 not loaded, or skip:<reason> when the trace is unreadable.
loaded_flag() {
  local rc=0
  bash "$RUNNER_PATH" skill-loaded "$@" 2>/dev/null || rc=$?
  case "$rc" in
    0) printf '1\n' ;;
    1) printf '0\n' ;;
    *) printf 'skip:unreadable trace (exit %s)\n' "$rc" ;;
  esac
}

index=0
for row in "${PROMPTS[@]}"; do
  index=$((index + 1))
  expected="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).expected)' "$row")"
  prompt="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).prompt)' "$row")"
  with_trace="$OUT/traces/$(printf '%02d' "$index")-with.jsonl"
  without_trace="$OUT/traces/$(printf '%02d' "$index")-without.jsonl"
  echo "prompt $index of ${#PROMPTS[@]} ($expected)" >&2
  # Control runs before the skill exists on disk. Creating both workspaces
  # first let the control agent list the shared parent and read the other
  # arm's SKILL.md, which scored as a load.
  reason=""
  without_dir="$(make_workspace)"
  status_without="$(run_arm "$without_dir" "$without_trace" "$prompt" 1 "$CONTROL_SKILL_DIR")"
  [[ "$status_without" == ok ]] || reason="without-skill ${status_without#skip:}"
  rm -rf "$without_dir"

  skill_dir="$CONTROL_SKILL_DIR"
  if [[ -z "$reason" ]]; then
    with_dir="$(make_workspace)"
    bash "$INSTALL" "$agent" --project "$with_dir" >/dev/null
    skill_dir="$(skill_dir_for "$with_dir")"
    [[ -f "$skill_dir/SKILL.md" ]] || fail_run "install did not create $skill_dir/SKILL.md"
    status_with="$(run_arm "$with_dir" "$with_trace" "$prompt" 0 "$skill_dir")"
    [[ "$status_with" == ok ]] || reason="with-skill ${status_with#skip:}"
    rm -rf "$with_dir"
  fi
  loaded_with=0
  loaded_without=0
  if [[ -z "$reason" ]]; then
    loaded_with="$(loaded_flag --trace "$with_trace" --skill feature-docs --skill-dir "$skill_dir")"
    [[ "$loaded_with" != skip:* ]] || reason="with-skill ${loaded_with#skip:}"
  fi
  if [[ -z "$reason" ]]; then
    loaded_without="$(loaded_flag --trace "$without_trace" --skill feature-docs --skill-dir "$CONTROL_SKILL_DIR" --any-install)"
    [[ "$loaded_without" != skip:* ]] || reason="without-skill ${loaded_without#skip:}"
  fi
  [[ -z "$reason" ]] || echo "  skipped: $reason" >&2
  meta_with="$( [[ -f "$with_trace" ]] && node "$TRACE_JS" meta --trace "$with_trace" 2>/dev/null || echo '{}')"
  meta_without="$( [[ -f "$without_trace" ]] && node "$TRACE_JS" meta --trace "$without_trace" 2>/dev/null || echo '{}')"
  node -e '
const fs = require("node:fs");
const [prompt, expected, lw, lwo, tw, two, reason, mw, mwo, file] = process.argv.slice(1);
const metaWith = JSON.parse(mw || "{}");
const metaWithout = JSON.parse(mwo || "{}");
const row = { prompt, expected };
if (reason) {
  row.skipped = true;
  row.skip_reason = reason;
} else {
  row.loaded_with_skill = lw === "1";
  row.loaded_without_skill = lwo === "1";
}
row.early_stop_with = metaWith.early_stop || null;
row.early_stop_without = metaWithout.early_stop || null;
row.usage_with = metaWith.usage || null;
row.usage_without = metaWithout.usage || null;
row.trace_with = tw;
row.trace_without = two;
fs.appendFileSync(file, JSON.stringify(row) + "\n");
' "$prompt" "$expected" "$loaded_with" "$loaded_without" "$with_trace" "$without_trace" "$reason" "$meta_with" "$meta_without" "$OBS"
done

rc=0
node "$TRACE_JS" report --observations "$OBS" --status complete --runner "$RUNNER_NAME" \
  --model "$MODEL" --min-scored "$MIN_SCORED" --max-prompts "$MAX_PROMPTS" \
  --catalog-size "$CATALOG_SIZE" --stop-after-tools "$STOP_AFTER_TOOLS" --out "$OUT" || rc=$?
if [[ "$rc" -eq 2 ]]; then
  echo "The without-skill run loaded feature-docs. Precision and recall were not computed." >&2
  echo "Wrote $OUT/results.json" >&2
  echo "Wrote $OUT/summary.md" >&2
  exit 2
fi
if [[ "$rc" -eq 3 ]]; then
  echo "The run is incomplete and no rates are claimed." >&2
  echo "Wrote $OUT/results.json" >&2
  echo "Wrote $OUT/summary.md" >&2
  exit 1
fi
[[ "$rc" -eq 0 ]] || exit "$rc"
echo "Wrote $OUT/results.json"
echo "Wrote $OUT/summary.md"
