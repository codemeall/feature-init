#!/usr/bin/env bash
# Scaffold feature docs in any target repo from the master templates.
# Master stays here — only the per-feature docs are created in the target repo.
#
# Usage:
#   ./new-feature.sh <repo-path> <feature-slug>          # Idea stage: feature.md only
#   ./new-feature.sh <repo-path> <feature-slug> --all    # Discovery: feature.md + plan.md + progress.md
#   ./new-feature.sh <repo-path> <feature-slug> --continue  # add plan.md + progress.md to an existing feature folder
set -euo pipefail

# Templates live at ./templates (repo layout) or ../assets/templates (bundled-skill layout)
BASE="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "$BASE/templates" ]]; then TPL_DIR="$BASE/templates"
elif [[ -d "$BASE/../assets/templates" ]]; then TPL_DIR="$(cd "$BASE/../assets/templates" && pwd)"
else echo "Error: templates directory not found near $BASE"; exit 1; fi
REPO="${1:-}"; SLUG="${2:-}"; MODE="${3:-}"
TODAY="$(date +%Y-%m-%d)"

if [[ -z "$REPO" || -z "$SLUG" ]]; then
  echo "Usage: $0 <repo-path> <feature-slug> [--all|--continue]"; exit 1
fi
[[ -d "$REPO" ]] || { echo "Error: repo path not found: $REPO"; exit 1; }
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "Error: slug must be kebab-case (e.g. dashboard-revamp)"; exit 1; }

DEST="$REPO/docs/$SLUG"
TITLE="$(echo "$SLUG" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')"

copy_tpl() { # $1 = template filename
  [[ -f "$DEST/$1" ]] && { echo "skip  $1 (already exists)"; return; }
  sed -e "s/<Feature>/$TITLE/g" -e "s/<YYYY-MM-DD>/$TODAY/g" "$TPL_DIR/$1" > "$DEST/$1"
  echo "created  docs/$SLUG/$1"
}

case "$MODE" in
  "")
    [[ -e "$DEST" ]] && { echo "Error: $DEST already exists (use --continue to add plan/progress)"; exit 1; }
    mkdir -p "$DEST"; copy_tpl feature.md
    echo; echo "Next: fill the 'Why' section of docs/$SLUG/feature.md (Stage: Idea) -> gate 1."
    echo "When discovery starts: $0 $REPO $SLUG --continue"
    ;;
  --all)
    [[ -e "$DEST" ]] && { echo "Error: $DEST already exists"; exit 1; }
    mkdir -p "$DEST"; copy_tpl feature.md; copy_tpl plan.md; copy_tpl progress.md
    echo; echo "Next: fill feature.md Why/What/Scope, then plan.md, keep progress.md live."
    ;;
  --continue)
    [[ -d "$DEST" ]] || { echo "Error: $DEST does not exist (run without flags first)"; exit 1; }
    copy_tpl plan.md; copy_tpl progress.md
    echo; echo "Next: discovery findings -> progress.md, milestones -> plan.md."
    ;;
  *) echo "Unknown option: $MODE (use --all or --continue)"; exit 1 ;;
esac
