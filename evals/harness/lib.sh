#!/usr/bin/env bash
# Shared helpers for the trigger harness. Sourced, not executed.
# macOS TMPDIR often ends in a slash, so mktemp can return a doubled slash.
# The supervisor deletes a recorded path only when the text already matches
# a lexical resolve, which collapses those slashes. tr is required here:
# bash 3.2, the macOS /bin/bash, keeps the backslash in ${value//\/\//\/}
# and the supervisor then refuses the marker.
canonical_path() {
  tr -s '/' <<<"$1"
}
run_with_timeout() {
  local secs="$1"
  shift
  local helper_dir
  helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  node "$helper_dir/timeout.js" "$secs" "$@"
}
