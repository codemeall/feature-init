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
    # Other tools also install a command named agent. Cursor's help prints
    # "Start the Cursor Agent", so a name match alone is not enough.
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
  local -a args=(-p --output-format stream-json --trust --force --workspace "$cwd")
  if [[ -n "${HARNESS_MODEL:-}" ]]; then
    args+=(--model "$HARNESS_MODEL")
  fi
  args+=("$prompt")
  # Every run gets an empty HOME so skills, plugins, rules, and chats the user
  # installed globally (~/.cursor/plugins, ~/.cursor/skills-cursor) are not
  # visible. The only file carried over is the CLI login, auth.json, copied
  # with mode 0600 and removed with the HOME when the run ends.
  local home cleanup_file
  home="$(mktemp -d "${TMPDIR:-/tmp}/harness-cursor-home.XXXXXX")"
  home="$(canonical_path "$home")"
  cleanup_file="$trace.cleanup"
  # EXIT removes the HOME. The marker stays so the supervisor can remove the
  # directory again after a kill, once the agent can no longer recreate it.
  trap 'rm -rf "$home"' EXIT
  trap 'exit 143' TERM
  trap 'exit 130' INT
  printf '%s\n' "$home" > "$cleanup_file"
  mkdir -p "$home/.config/cursor"
  if [[ -z "${CURSOR_API_KEY:-}" ]]; then
    local auth="${XDG_CONFIG_HOME:-$HOME/.config}/cursor/auth.json"
    [[ -f "$auth" ]] || { echo "cursor login not found at $auth; set CURSOR_API_KEY or run cursor-agent login" >&2; exit 3; }
    (umask 077 && cp "$auth" "$home/.config/cursor/auth.json")
    chmod 600 "$home/.config/cursor/auth.json"
  fi
  # A foreground CLI would defer TERM and INT until it returned. wait is
  # interruptible, so these traps run even when the CLI ignores the signal.
  # CURSOR_API_KEY, when set, stays in the environment and is not printed.
  (cd "$cwd" && exec env -u XDG_CONFIG_HOME HOME="$home" TMPDIR="$home" "$bin" "${args[@]}") < /dev/null >"$trace" 2>"$trace.stderr" &
  wait "$!" || rc=$?
  rm -rf "$home"
  rm -f "$cleanup_file"
  return "$rc"
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
