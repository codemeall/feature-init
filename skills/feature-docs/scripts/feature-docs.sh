#!/usr/bin/env bash
# Scaffold feature docs, detect when they fall out of step, and wire them into a repo.
#
# Feature docs live in <repo>/docs/<feature>/feature-docs/ and are tracked in git. Their sources
# (the spec and tickets, by default <repo>/.scratch/<feature>/) are local and untracked, so git
# cannot say when they change. `stamp` records a hash of every source file in sources.json and
# keeps a private copy under .git/feature-docs/; `status` and `diff` compare against them.
#
# Usage:
#   feature-docs.sh new    <repo> <feature>                    create the folder from the templates
#   feature-docs.sh stamp  <repo> <feature> [--source <dir>]   record the sources as synced today
#   feature-docs.sh status <repo> [<feature>] [--quiet]        changed sources, cited files that are gone, planned tickets
#   feature-docs.sh diff   <repo> <feature>                    line-level source changes since the last stamp
#   feature-docs.sh index  <repo>                              write docs/FEATURES.md, the list of documented features
#   feature-docs.sh setup  <repo> [--file CLAUDE.md|AGENTS.md] write the index and point the agent instructions at it
#   feature-docs.sh hook   <repo>                              install a pre-commit hook that warns when docs are out of step
#
# <dir> is relative to <repo>; the default is .scratch/<feature>. Only *.md files are tracked.
# --quiet prints only the features that are out of step, and nothing when none are.
# Exit codes: 0 done or in sync, 1 out of step (status, diff), 2 usage or other error.
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
TPL_DIR="$BASE/../assets/templates"
TODAY="$(date +%Y-%m-%d)"
INDEX="docs/FEATURES.md"

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }
die() { echo "Error: $*" >&2; exit 2; }
tmpfile() { mktemp "${TMPDIR:-/tmp}/feature-docs.XXXXXX"; }
files() { if [[ "$1" -eq 1 ]]; then echo "1 file"; else echo "$1 files"; fi; }

hash_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else die "need shasum or sha256sum on PATH"; fi
}

check_repo() {
  [[ -n "$1" ]] || { usage; exit 2; }
  [[ -d "$1" ]] || die "repo path not found: $1"
}

check_slug() {
  [[ -n "$1" ]] || { usage; exit 2; }
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "feature must be kebab-case (e.g. csv-export): $1"
}

# Prints "path<TAB>hash" for every *.md under $1, sorted by path.
current_hashes() {
  local src="$1" path
  (cd "$src" && find . -type f -name '*.md' | sed 's|^\./||' | LC_ALL=C sort) | while IFS= read -r path; do
    case "$path" in *'"'*|*'\'*|*$'\t'*) die "unsupported character in source file name: $path" ;; esac
    printf '%s\t%s\n' "$path" "$(hash_file "$src/$path")"
  done
}

# Prints "path<TAB>hash" for every file recorded in the manifest $1.
recorded_hashes() {
  sed -n 's/^    "\(.*\)": "\([0-9a-f]\{64\}\)",\{0,1\}$/\1	\2/p' "$1"
}

manifest_field() { # $1 = manifest, $2 = field name
  sed -n "s/^  \"$2\": \"\(.*\)\",\{0,1\}\$/\1/p" "$1" | head -n 1
}

# Prints "path<TAB>CHANGED|ADDED|REMOVED" for every source file that differs from the manifest.
source_changes() { # $1 = manifest, $2 = source dir
  local old new
  old="$(tmpfile)"; new="$(tmpfile)"
  recorded_hashes "$1" > "$old"
  current_hashes "$2" > "$new" || { rm -f "$old" "$new"; exit 2; }
  awk -F'\t' '
    FILENAME == ARGV[1] { old[$1] = $2; next }
    { seen[$1] = 1
      if (!($1 in old)) print $1 "\tADDED"
      else if (old[$1] != $2) print $1 "\tCHANGED" }
    END { for (p in old) if (!(p in seen)) print p "\tREMOVED" }
  ' "$old" "$new" | LC_ALL=C sort
  rm -f "$old" "$new"
}

# Where the private copy of a feature's synced sources is kept. Fails when <repo> is not the
# top of a git checkout; there is then no copy, and `diff` names the files without their lines.
snapshot_dir() { # $1 = repo, $2 = slug
  local top gitdir
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ "$top" -ef "$1" ]] || return 1
  gitdir="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  echo "$gitdir/feature-docs/$2"
}

# Repo files that overview.md cites and that no longer exist. A citation is a backticked token
# with a slash that names a file (its last part has a dot) or a folder (it ends in a slash).
# Only overview.md is checked: it claims what exists now, while decisions and tickets are history.
missing_citations() { # $1 = repo, $2 = overview.md
  local path
  [[ -f "$2" ]] || return 0
  { grep -v '^>' "$2" | grep -oE '`[][A-Za-z0-9_.@+/()~-]+(:[0-9]+(-[0-9]+)?)?`' || true; } \
    | tr -d '`' | sed -E 's/:[0-9]+(-[0-9]+)?$//' | LC_ALL=C sort -u | while IFS= read -r path; do
      case "$path" in
        /*|'~'*|.scratch/*|.fleet/*|path/file*|*//*) continue ;;
        */) ;;
        */*) case "${path##*/}" in *.*) ;; *) continue ;; esac ;;
        *) continue ;;
      esac
      [[ -e "$1/$path" ]] || echo "$path"
    done
}

# Tickets whose status is `planned`, as "<number> <title>".
planned_tickets() { # $1 = tickets.md
  [[ -f "$1" ]] || return 0
  awk -F'|' '
    function trim(s) { gsub(/^[ \t`*]+|[ \t`*]+$/, "", s); return s }
    /^\|/ { for (i = 2; i <= NF; i++) if (tolower(trim($i)) == "planned") { print trim($2) " " trim($3); next } }
  ' "$1"
}

# Rewrites docs/FEATURES.md from every feature's overview.md.
write_index() { # $1 = repo
  local repo="$1" dir name title summary updated
  mkdir -p "$repo/docs"
  {
    echo "# Features"
    echo
    echo "> Generated by \`feature-docs.sh index\`. Edit the feature docs, not this file."
    echo "> Each feature below has an as-built record in \`docs/<feature>/feature-docs/\`. Before changing one, read its \`decisions.md\`."
    echo
    echo "| Feature | Summary | Updated |"
    echo "|---|---|---|"
    for dir in "$repo"/docs/*/feature-docs; do
      [[ -f "$dir/overview.md" ]] || continue
      name="$(basename "$(dirname "$dir")")"
      title="$(sed -n 's/^# //p' "$dir/overview.md" | head -n 1)"
      summary="$(sed -n 's/^> Summary: *//p' "$dir/overview.md" | head -n 1)"
      case "$summary" in '<'*) summary="" ;; esac
      updated="$({ grep -oE 'Updated: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$dir/overview.md" || true; } | head -n 1 | cut -d' ' -f2)"
      echo "| [${title:-$name}]($name/feature-docs/overview.md) | ${summary//|/\\|} | $updated |"
    done
  } > "$repo/$INDEX"
}

refresh_index() { if [[ -f "$1/$INDEX" ]]; then write_index "$1"; fi; }

cmd_new() {
  local repo="${1:-}" slug="${2:-}" dest title name
  check_repo "$repo"
  check_slug "$slug"
  [[ -d "$TPL_DIR" ]] || die "templates not found: $TPL_DIR"
  dest="$repo/docs/$slug/feature-docs"
  title="$(echo "$slug" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')"
  mkdir -p "$dest"
  for name in overview.md decisions.md tickets.md; do
    if [[ -f "$dest/$name" ]]; then echo "skip     docs/$slug/feature-docs/$name (already exists)"; continue; fi
    sed -e "s/<Feature>/$title/g" -e "s/<YYYY-MM-DD>/$TODAY/g" "$TPL_DIR/$name" > "$dest/$name"
    echo "created  docs/$slug/feature-docs/$name"
  done
  refresh_index "$repo"
}

cmd_stamp() {
  local repo="${1:-}" slug="${2:-}" source="" dest manifest tmp count snap path
  check_repo "$repo"
  check_slug "$slug"
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source) [[ $# -ge 2 && -n "$2" ]] || die "--source needs a directory"; source="$2"; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  dest="$repo/docs/$slug/feature-docs"
  manifest="$dest/sources.json"
  [[ -d "$dest" ]] || die "no feature docs at docs/$slug/feature-docs (run: new $repo $slug)"
  if [[ -z "$source" && -f "$manifest" ]]; then source="$(manifest_field "$manifest" source)"; fi
  [[ -n "$source" ]] || source=".scratch/$slug"
  source="${source%/}"
  case "$source" in /*|..|../*|*/..|*/../*) die "--source must be a path inside the repo, relative to it: $source" ;; esac
  case "$source" in *'"'*|*'\'*) die "unsupported character in source path: $source" ;; esac
  [[ -d "$repo/$source" ]] || die "source directory not found: $repo/$source"

  tmp="$(tmpfile)"
  current_hashes "$repo/$source" > "$tmp" || { rm -f "$tmp"; exit 2; }
  count="$(wc -l < "$tmp" | tr -d ' ')"
  [[ "$count" -gt 0 ]] || { rm -f "$tmp"; die "no *.md files under $source"; }
  {
    printf '{\n  "source": "%s",\n  "synced": "%s",\n  "files": {\n' "$source" "$TODAY"
    awk -F'\t' -v n="$count" '{ printf "    \"%s\": \"%s\"%s\n", $1, $2, (NR < n ? "," : "") }' "$tmp"
    printf '  }\n}\n'
  } > "$manifest"
  if snap="$(snapshot_dir "$repo" "$slug")"; then
    rm -rf "$snap"
    while IFS=$'\t' read -r path _; do
      mkdir -p "$snap/$(dirname "$path")"
      cp "$repo/$source/$path" "$snap/$path"
    done < "$tmp"
  fi
  rm -f "$tmp"
  refresh_index "$repo"
  echo "stamped  docs/$slug/feature-docs/sources.json ($(files "$count") from $source, synced $TODAY)"
}

# Prints one feature's state. Returns 1 when the docs are out of step, 0 otherwise.
report() { # $1 = repo, $2 = slug
  local repo="$1" slug="$2" dest manifest source="" synced="" changes="" count=0 state missing planned rc=0
  dest="$repo/docs/$slug/feature-docs"
  manifest="$dest/sources.json"
  if [[ ! -f "$manifest" ]]; then
    state=untracked
  else
    source="$(manifest_field "$manifest" source)"
    synced="$(manifest_field "$manifest" synced)"
    if [[ -z "$source" || ! -d "$repo/$source" ]]; then
      state=nosource
    else
      changes="$(source_changes "$manifest" "$repo/$source")"
      count="$(recorded_hashes "$manifest" | wc -l | tr -d ' ')"
      if [[ -n "$changes" ]]; then state=drift; else state=sync; fi
    fi
  fi
  missing="$(missing_citations "$repo" "$dest/overview.md")"
  planned="$(planned_tickets "$dest/tickets.md")"

  case "$state" in
    untracked) echo "$slug  UNTRACKED  no sources.json (converted or hand-written; nothing to sync from)" ;;
    nosource) echo "$slug  SOURCE MISSING  ${source:-<unrecorded>} is not on this machine; the feature docs are the record (last synced $synced)" ;;
    drift) echo "$slug  DRIFT  $source changed since $synced"; rc=1 ;;
    sync)
      if [[ -n "$missing" ]]; then echo "$slug  STALE  $source is unchanged since $synced, but the docs cite files that are gone"
      else echo "$slug  IN SYNC  $(files "$count") in $source, last synced $synced"; fi ;;
  esac
  if [[ -n "$changes" ]]; then echo "$changes" | awk -F'\t' '{ printf "  %-8s %s\n", $2, $1 }'; fi
  if [[ -n "$missing" ]]; then rc=1; echo "$missing" | sed 's/^/  MISSING  /; s/$/ (cited in overview.md)/'; fi
  if [[ -n "$planned" ]]; then echo "$planned" | sed 's/^/  PLANNED  /'; fi
  return "$rc"
}

cmd_status() {
  local repo="${1:-}" slug="" quiet=0 out_of_step=0 found=0 dir name sources src out rc lines=""
  check_repo "$repo"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet) quiet=1 ;;
      -*) die "unknown argument: $1" ;;
      *) [[ -z "$slug" ]] || die "unexpected argument: $1"; slug="$1" ;;
    esac
    shift
  done
  if [[ -n "$slug" ]]; then
    check_slug "$slug"
    [[ -d "$repo/docs/$slug/feature-docs" ]] || die "no feature docs at docs/$slug/feature-docs"
    rc=0; out="$(report "$repo" "$slug")" || rc=$?
    if [[ "$rc" -ne 0 ]]; then out_of_step=1; fi
    if [[ "$quiet" -eq 0 || "$rc" -ne 0 ]]; then lines="$out"$'\n'; fi
  else
    sources=""
    for dir in "$repo"/docs/*/feature-docs; do
      [[ -d "$dir" ]] || continue
      found=1
      name="$(basename "$(dirname "$dir")")"
      rc=0; out="$(report "$repo" "$name")" || rc=$?
      if [[ "$rc" -ne 0 ]]; then out_of_step=1; fi
      if [[ "$quiet" -eq 0 || "$rc" -ne 0 ]]; then lines="$lines$out"$'\n'; fi
      if [[ -f "$dir/sources.json" ]]; then sources="$sources$(manifest_field "$dir/sources.json" source)"$'\n'; fi
    done
    if [[ "$quiet" -eq 0 ]]; then
      if [[ "$found" -eq 0 ]]; then lines="no feature docs under docs/*/feature-docs"$'\n'; fi
      # Source folders nothing was written from yet: a hint, since they may not be implemented.
      for dir in "$repo"/.scratch/*/; do
        [[ -d "$dir" ]] || continue
        src=".scratch/$(basename "$dir")"
        printf '%s' "$sources" | grep -Fxq -- "$src" || lines="$lines$(basename "$dir")  NO DOCS  $src has no feature docs"$'\n'
      done
    fi
  fi
  if [[ "$quiet" -eq 1 && "$out_of_step" -eq 1 ]]; then
    echo 'Feature docs are out of step with their sources or the code. Sync them with the feature-docs skill ("sync the feature docs"):'
  fi
  printf '%s' "$lines"
  exit "$out_of_step"
}

cmd_diff() {
  local repo="${1:-}" slug="${2:-}" manifest source changes snap="" path kind
  check_repo "$repo"
  check_slug "$slug"
  manifest="$repo/docs/$slug/feature-docs/sources.json"
  [[ -f "$manifest" ]] || die "docs/$slug/feature-docs has no sources.json, so there is no synced state to compare with"
  source="$(manifest_field "$manifest" source)"
  [[ -n "$source" && -d "$repo/$source" ]] || die "source ${source:-<unrecorded>} is not on this machine"
  changes="$(source_changes "$manifest" "$repo/$source")"
  if [[ -z "$changes" ]]; then echo "$slug  IN SYNC  nothing changed in $source"; exit 0; fi
  snap="$(snapshot_dir "$repo" "$slug")" || snap=""
  while IFS=$'\t' read -r path kind; do
    case "$kind" in
      ADDED) echo "ADDED    $source/$path (new file: read it in full)" ;;
      CHANGED)
        if [[ -n "$snap" && -f "$snap/$path" ]]; then
          echo "CHANGED  $source/$path"
          diff -u -L "synced/$path" -L "current/$path" "$snap/$path" "$repo/$source/$path" || true
        else
          echo "CHANGED  $source/$path (no copy of the synced version on this machine: read it in full)"
        fi ;;
      REMOVED)
        if [[ -n "$snap" && -f "$snap/$path" ]]; then
          echo "REMOVED  $source/$path, which said:"
          sed 's/^/  | /' "$snap/$path"
        else
          echo "REMOVED  $source/$path"
        fi ;;
    esac
    echo
  done <<< "$changes"
  exit 1
}

cmd_index() {
  local repo="${1:-}" count
  check_repo "$repo"
  write_index "$repo"
  count="$(grep -c '^| \[' "$repo/$INDEX" || true)"
  if [[ "$count" -eq 1 ]]; then echo "wrote    $INDEX (1 feature)"; else echo "wrote    $INDEX ($count features)"; fi
}

cmd_setup() {
  local repo="${1:-}" file="" target
  check_repo "$repo"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) [[ $# -ge 2 ]] || die "--file needs CLAUDE.md or AGENTS.md"; file="$2"; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  case "$file" in ""|CLAUDE.md|AGENTS.md) ;; *) die "--file must be CLAUDE.md or AGENTS.md" ;; esac
  cmd_index "$repo"
  if [[ -z "$file" ]]; then
    if [[ -f "$repo/CLAUDE.md" ]]; then file=CLAUDE.md
    elif [[ -f "$repo/AGENTS.md" ]]; then file=AGENTS.md
    else die "no CLAUDE.md or AGENTS.md in $repo: rerun with --file CLAUDE.md or --file AGENTS.md to create one"; fi
  fi
  target="$repo/$file"
  if [[ -f "$target" ]] && grep -q '^## Feature docs$' "$target"; then
    echo "skip     $file (already has a Feature docs section)"
    return 0
  fi
  {
    if [[ -s "$target" ]]; then echo; fi
    cat <<'EOF'
## Feature docs

Built features are recorded in `docs/<feature>/feature-docs/`; `docs/FEATURES.md` lists them. Before speccing, ticketing or changing a listed feature, read its `decisions.md` and cite the decision IDs the change builds on or overturns. Write, convert and sync these docs with the `feature-docs` skill.
EOF
  } >> "$target"
  echo "added    Feature docs section to $file"
}

cmd_hook() {
  local repo="${1:-}" hooks file marker="# feature-docs pre-commit"
  check_repo "$repo"
  hooks="$(cd "$repo" && git rev-parse --git-path hooks 2>/dev/null)" || die "not a git checkout: $repo"
  case "$hooks" in /*) ;; *) hooks="$(cd "$repo" && pwd)/$hooks" ;; esac
  file="$hooks/pre-commit"
  case "$BASE" in *"'"*) die "the skill path contains a quote: $BASE" ;; esac
  if [[ -f "$file" ]] && ! grep -Fq "$marker" "$file"; then
    echo "Error: $file already exists and is not ours. Add this line to it instead:" >&2
    echo "  bash '$BASE/feature-docs.sh' status \"\$(git rev-parse --show-toplevel)\" --quiet >&2 || true" >&2
    exit 2
  fi
  mkdir -p "$hooks"
  cat > "$file" <<EOF
#!/bin/sh
$marker: warns when feature docs are out of step. It never blocks a commit.
FD='$BASE/feature-docs.sh'
[ -f "\$FD" ] || exit 0
bash "\$FD" status "\$(git rev-parse --show-toplevel)" --quiet >&2 || true
exit 0
EOF
  chmod +x "$file"
  echo "installed  $file (warns when docs are out of step, never blocks)"
}

case "${1:-}" in
  new) shift; cmd_new "$@" ;;
  stamp) shift; cmd_stamp "$@" ;;
  status) shift; cmd_status "$@" ;;
  diff) shift; cmd_diff "$@" ;;
  index) shift; cmd_index "$@" ;;
  setup) shift; cmd_setup "$@" ;;
  hook) shift; cmd_hook "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
