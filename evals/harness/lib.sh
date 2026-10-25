#!/usr/bin/env bash
# Shared helpers for the trigger harness. Sourced, not executed.
run_with_timeout() {
  local secs="$1"
  shift
  local helper_dir
  helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  node "$helper_dir/timeout.js" "$secs" "$@"
}
