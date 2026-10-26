#!/usr/bin/env bash
# Claude Code runner. Prints a real `claude -p` trace. Does not invent one.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=evals/harness/lib.sh
source "$HARNESS_DIR/lib.sh"

probe() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "claude CLI is not on PATH"
    exit 3
  fi
  if [[ -n "${ANTHROPIC_API_KEY:-}" || -n "${ANTHROPIC_AUTH_TOKEN:-}" || -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    echo "ready: claude CLI with environment credentials"
    exit 0
  fi
  local cred="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
  if [[ -f "$cred" ]]; then
    echo "ready: claude CLI with a credentials file"
    exit 0
  fi
  local rc=0
  run_with_timeout 20 claude auth status >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "ready: claude auth status"
    exit 0
  fi
  echo "claude CLI is installed but no credentials are available (auth status exit $rc)"
  exit 3
}

# Keep the host skill directory out of the run when credentials can travel
# without it. Bare mode is not used: it does not advertise the skill list,
# so it cannot measure description triggering.
claude_env() {
  local work="$1"
  local home="$work/home"
  local config="$work/config"
  mkdir -p "$home" "$config"
  if [[ -n "${ANTHROPIC_API_KEY:-}" || -n "${ANTHROPIC_AUTH_TOKEN:-}" || -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    printf '%s\n' "HOME=$home" "CLAUDE_CONFIG_DIR=$config" "CLAUDE_CODE_SYNC_SKILLS=0"
    return 0
  fi
  local src="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
  if [[ -f "$src" ]]; then
    cp "$src" "$config/.credentials.json"
    chmod 600 "$config/.credentials.json"
    printf '%s\n' "HOME=$home" "CLAUDE_CONFIG_DIR=$config" "CLAUDE_CODE_SYNC_SKILLS=0"
    return 0
  fi
  printf '%s\n' "CLAUDE_CODE_SYNC_SKILLS=0"
}

run_cmd() (
  local cwd="" trace="" prompt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd) cwd="${2:-}"; shift 2 ;;
      --trace) trace="${2:-}"; shift 2 ;;
      --prompt) prompt="${2:-}"; shift 2 ;;
      *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
  done
  [[ -n "$cwd" && -d "$cwd" && -n "$trace" && -n "$prompt" ]] || {
    echo "run needs --cwd, --trace, and --prompt" >&2
    exit 2
  }
  local work env_file rc=0 cleanup_file
  work="$(mktemp -d "${TMPDIR:-/tmp}/harness-claude.XXXXXX")"
  work="$(canonical_path "$work")"
  cleanup_file="$trace.cleanup"
  # EXIT removes the work dir. The marker stays so the supervisor can remove
  # it again after a kill, once the agent can no longer recreate it.
  trap 'rm -rf "$work"' EXIT
  trap 'exit 143' TERM
  trap 'exit 130' INT
  printf '%s\n' "$work" > "$cleanup_file"
  env_file="$work/env"
  claude_env "$work" > "$env_file"
  local -a env_args=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    env_args+=("$line")
  done < "$env_file"
  # stdout is the JSONL trace. stderr is kept beside it for debugging.
  local -a model_args=()
  if [[ -n "${HARNESS_MODEL:-}" ]]; then
    model_args=(--model "$HARNESS_MODEL")
  fi
  cd "$cwd" || exit 1
  env "${env_args[@]}" claude -p "$prompt" ${model_args[@]+"${model_args[@]}"} \
    --output-format stream-json \
    --verbose \
    --permission-mode dontAsk \
    --permission-prompts none \
    --allowedTools "Skill,Read" \
    < /dev/null >"$trace" 2>"$trace.stderr" &
  # wait is interruptible, so TERM can clean up even if the CLI ignores it.
  wait "$!" || rc=$?
  rm -rf "$work"
  rm -f "$cleanup_file"
  return "$rc"
)

cmd="${1:-}"
shift || true
case "$cmd" in
  probe) probe ;;
  agent) printf '%s\n' claude ;;
  run) run_cmd "$@" ;;
  skill-loaded) exec node "$HARNESS_DIR/trace.js" skill-loaded "$@" ;;
  *) echo "Usage: $0 probe|agent|run|skill-loaded" >&2; exit 2 ;;
esac
