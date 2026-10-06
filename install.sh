#!/usr/bin/env bash
# Install the feature-docs skill into any AI harness that supports the SKILL.md
# standard (agentskills.io): Claude Code, Cursor, Codex, Antigravity.
# The skill folder is self-contained (templates, script and references), so a copy works offline.
#
# Usage:
#   ./install.sh <agent...>                    # global install (all projects)
#   ./install.sh <agent...> --project <repo>   # project install (checked into that repo)
#   ./install.sh all [--project <repo>] [--force]
#
# Agents: claude | cursor | codex | antigravity | all
#   --force  replace an existing install (e.g. to update to a newer version)
set -euo pipefail

SRC="$(cd "$(dirname "$0")/skills/feature-docs" && pwd)"
SKILL_NAME="feature-docs"
OLD_NAME="feature-init"   # the skill's name before 2026-10-06

AGENTS=(); PROJECT=""; FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    claude|cursor|codex|antigravity) AGENTS+=("$1"); shift ;;
    all) AGENTS=(claude cursor codex antigravity); shift ;;
    --project) PROJECT="${2:-}"; [[ -d "$PROJECT" ]] || { echo "Error: project path not found: $PROJECT"; exit 1; }; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) echo "Unknown argument: $1"; echo "Usage: $0 <claude|cursor|codex|antigravity|all>... [--project <repo>] [--force]"; exit 1 ;;
  esac
done
[[ ${#AGENTS[@]} -gt 0 ]] || { echo "Usage: $0 <claude|cursor|codex|antigravity|all>... [--project <repo>] [--force]"; exit 1; }

dest_for() { # $1 = agent; echoes the skills parent dir
  if [[ -n "$PROJECT" ]]; then
    case "$1" in
      claude)      echo "$PROJECT/.claude/skills" ;;
      cursor)      echo "$PROJECT/.cursor/skills" ;;
      codex)       echo "$PROJECT/.codex/skills" ;;
      antigravity) echo "$PROJECT/.agents/skills" ;;
    esac
  else
    case "$1" in
      claude)      echo "$HOME/.claude/skills" ;;
      cursor)      echo "$HOME/.cursor/skills" ;;
      codex)       echo "$HOME/.codex/skills" ;;
      antigravity) echo "$HOME/.gemini/config/skills" ;;
    esac
  fi
}

for agent in "${AGENTS[@]}"; do
  DEST="$(dest_for "$agent")/$SKILL_NAME"
  if [[ -e "$DEST" ]]; then
    if [[ $FORCE -eq 1 ]]; then rm -rf "$DEST"
    else echo "skip     $agent: $DEST already exists (use --force to replace)"; continue; fi
  fi
  mkdir -p "$(dirname "$DEST")"
  cp -R "$SRC" "$DEST"
  chmod +x "$DEST/scripts/feature-docs.sh" 2>/dev/null || true
  echo "installed $agent -> $DEST"
  OLD="$(dest_for "$agent")/$OLD_NAME"
  if [[ -e "$OLD" ]]; then echo "note     $agent: the older $OLD_NAME skill is still at $OLD; remove it so the two do not both trigger"; fi
done

echo
echo "Done. The agent picks the skill up when you ask it to write, convert or sync feature docs."
if [[ -n "$PROJECT" ]]; then
  echo "Project installs are meant to be committed to $PROJECT so teammates get them too."
fi
