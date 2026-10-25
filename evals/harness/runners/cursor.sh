#!/usr/bin/env bash
# Cursor agent runner. Prints a real `agent -p` trace. Does not invent one.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=evals/harness/lib.sh
source "$HARNESS_DIR/lib.sh"

cursor_bin() {
  if command -v cursor-agent >/dev/null 2>&1; then
    command -v cursor-agent
    return 0
  fi
  if command -v agent >/dev/null 2>&1; then
    local help
    help="$(run_with_timeout 5 agent --help 2>/dev/null)" || return 1
    if [[ "$help" == *"Start the Cursor Agent"* ]]; then
      command -v agent
      return 0
    fi
  fi
  return 1
}

probe() {
  local bin=""
  bin="$(cursor_bin)" || {
    echo "cursor agent CLI is not on PATH (cursor-agent or a verified Cursor agent)"
    exit 3
  }
  if [[ -n "${CURSOR_API_KEY:-}" ]]; then
    echo "ready: cursor agent CLI with CURSOR_API_KEY"
    exit 0
  fi
  local rc=0
  run_with_timeout 20 "$bin" status >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "ready: cursor agent status"
    exit 0
  fi
  echo "cursor agent CLI is installed but no credentials are available (status exit $rc)"
  exit 3
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
  local bin rc=0
  bin="$(cursor_bin)" || { echo "cursor agent CLI is not on PATH" >&2; exit 3; }
  local -a args=(-p --output-format stream-json --trust --force --workspace "$cwd" "$prompt")
  if [[ -n "${CURSOR_API_KEY:-}" ]]; then
    local home
    home="$(mktemp -d "${TMPDIR:-/tmp}/feature-docs-cursor-home.XXXXXX")"
    trap 'rm -rf "$home"' EXIT
    trap 'exit 143' TERM
    trap 'exit 130' INT
    # A separate HOME hides skills already installed for the user.
    # CURSOR_API_KEY stays in the environment and is not printed.
    env HOME="$home" "$bin" "${args[@]}" < /dev/null >"$trace" 2>"$trace.stderr" &
    wait "$!" || rc=$?
    return "$rc"
  fi
  "$bin" "${args[@]}" < /dev/null >"$trace" 2>"$trace.stderr"
)

cmd="${1:-}"
shift || true
case "$cmd" in
  probe) probe ;;
  agent) printf '%s\n' cursor ;;
  run) run_cmd "$@" ;;
  skill-loaded) exec node "$HARNESS_DIR/trace.js" skill-loaded "$@" ;;
  *) echo "Usage: $0 probe|agent|run|skill-loaded" >&2; exit 2 ;;
esac
