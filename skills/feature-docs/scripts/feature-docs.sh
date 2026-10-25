#!/usr/bin/env bash
# Scaffold feature docs, detect when they fall out of step, and wire them into a repo.
#
# Feature docs live in <repo>/docs/<feature>/feature-docs/ and are tracked in git. Their sources
# (the spec and tickets, by default <repo>/.scratch/<feature>/) are local and untracked, so git
# cannot say when they change. `stamp` acknowledges review and records source, document and
# selected code/test hashes in sources.json. Hash matches are not proof of semantic correctness.
#
# Usage:
#   feature-docs.sh new    <repo> <feature>                    create the folder from the templates
#   feature-docs.sh check  <repo> [<feature>] [--quiet]        check the three documents
#   feature-docs.sh stamp  <repo> <feature> [--source <dir>] [--evidence <file> ...] [--evidence-only]
#   feature-docs.sh status <repo> [<feature>] [--quiet]        source/document/evidence drift and remaining work
#   feature-docs.sh diff   <repo> <feature>                    line-level source changes since the last stamp
#   feature-docs.sh index  <repo>                              write docs/FEATURES.md, the list of documented features
#   feature-docs.sh setup  <repo> [--file CLAUDE.md|AGENTS.md] write the index and point the agent instructions at it
#   feature-docs.sh hook   <repo>                              install a pre-commit hook that warns when docs are out of step
#
# <dir> is relative to <repo>; the default is .scratch/<feature>. Sources include *.md files,
# excluding Git metadata, generated feature-docs folders and docs/FEATURES.md.
# First stamp needs --evidence files; later stamps reuse the list unless a new list is supplied.
# --evidence-only preserves old source hashes/date, or creates a source-free review baseline.
# stamp acknowledges that the docs were reconciled with the selected files; it never runs tests.
# Manifests use a strict script-owned JSON layout; externally reformatted JSON is unsupported.
# --quiet prints only the features that are out of step, and nothing when none are.
# Exit codes: 0 success, 1 structural findings/review required/drift, 2 usage or operational error.
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
TPL_DIR="$BASE/../assets/templates"
MANIFEST_AWK="$BASE/manifest.awk"
WORK=""
trap '[[ -z "$WORK" ]] || rm -rf "$WORK"' EXIT
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

# The manifest is generated, not hand-authored. Fail closed on unfamiliar layouts.
validate_manifest() { awk -v mode=validate -f "$MANIFEST_AWK" "$1"; }
manifest_field() { awk -v mode=field -v field="$2" -f "$MANIFEST_AWK" "$1"; }
recorded_hashes() { awk -v mode=hashes -v field="${2:-files}" -f "$MANIFEST_AWK" "$1" | LC_ALL=C sort; }

safe_relative() {
  local path="$1"
  case "$path" in
    ''|/*|..|../*|*/..|*/../*|./*|*/./*|*/.|*//*|*'"'*|*'\'*|*$'\n'*|*$'\r'*|*$'\t'*)
      die "unsupported repo-relative path: $path" ;;
  esac
  if printf '%s' "$path" | LC_ALL=C grep -q '[[:cntrl:]]'; then die "control character in path"; fi
}

# Resolve existing paths without realpath/Python, including symlinks, then enforce containment.
contained_path() {
  local repo="$1" path="$2" root resolved parent target hops=0
  safe_relative "$path"
  root="$(cd "$repo" && pwd -P)" || return 2
  resolved="$root/$path"
  while :; do
    if [[ -d "$resolved" ]]; then resolved="$(cd "$resolved" && pwd -P)" || return 2; break; fi
    parent="$(cd "$(dirname "$resolved")" 2>/dev/null && pwd -P)" || return 1
    resolved="$parent/$(basename "$resolved")"
    if [[ ! -L "$resolved" ]]; then break; fi
    hops=$((hops + 1)); [[ "$hops" -le 40 ]] || die "symlink loop: $path"
    target="$(readlink "$resolved")" || return 2
    case "$target" in /*) resolved="$target" ;; *) resolved="$parent/$target" ;; esac
  done
  case "$resolved" in "$root"|"$root"/*) ;; *) die "path resolves outside the repo: $path" ;; esac
  [[ -e "$resolved" ]]
}

# Source names with spaces work. Reject unsupported names before producing canonical JSON.
current_hashes() { # source directory, repo
  local src="$1" path digest source_root repo_root
  source_root="$(cd "$src" && pwd -P)" || return 2
  repo_root="$(cd "$2" && pwd -P)" || return 2
  (cd "$src" && find . -type d -name .git -prune -o -type f -name '*.md' -print0) | while IFS= read -r -d '' path; do
    path="${path#./}"
    # A broad source folder must not ingest its own output or private snapshots.
    case "$source_root/$path" in
      "$repo_root"/.git/*|"$repo_root"/docs/FEATURES.md|"$repo_root"/docs/*/feature-docs/*) continue ;;
    esac
    safe_relative "$path"
    digest="$(hash_file "$src/$path")" || return 2
    printf '%s\t%s\n' "$path" "$digest" || return 2
  done | LC_ALL=C sort
}

compare_hashes() {
  awk -F'\t' '
    FILENAME == ARGV[1] { old[$1] = $2; next }
    { seen[$1] = 1
      if (!($1 in old)) print $1 "\tADDED"
      else if (old[$1] != $2) print $1 "\tCHANGED" }
    END { for (p in old) if (!(p in seen)) print p "\tREMOVED" }
  ' "$1" "$2" | LC_ALL=C sort
}

source_changes() { # manifest, source directory, repo
  local old new rc=0
  old="$(tmpfile)"; new="$(tmpfile)"
  recorded_hashes "$1" > "$old" && current_hashes "$2" "$3" > "$new" && compare_hashes "$old" "$new" || rc=2
  rm -f "$old" "$new"
  return "$rc"
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
      local rc=0
      contained_path "$1" "${path%/}" || rc=$?
      [[ "$rc" -ne 2 ]] || return 2
      [[ "$rc" -eq 0 ]] || echo "$path"
    done
}

# Parse the actual Status column, not arbitrary cells containing the word planned.
ticket_reminders() {
  [[ -f "$1" ]] || return 0
  awk -F'|' '
    function trim(s) { gsub(/^[ \t`*]+|[ \t`*]+$/, "", s); return s }
    /^\|/ {
      for (i = 2; i <= NF; i++) if (tolower(trim($i)) == "status") { col = i; next }
      if (col && (tolower(trim($col)) == "planned" || tolower(trim($col)) == "partial"))
        print toupper(trim($col)) "  " trim($2) " " trim($3)
    }
  ' "$1"
}

# Deterministic shape/scaffold checks only. No semantic claims, invented dates, or mandatory rows.
structure_findings() {
  local repo="$1" slug="$2" dest name path heading missing
  dest="$repo/docs/$slug/feature-docs"
  for name in overview.md decisions.md tickets.md; do
    path="$dest/$name"
    if [[ -e "$path" || -L "$path" ]]; then contained_path "$repo" "docs/$slug/feature-docs/$name" || return 2; fi
    if [[ ! -s "$path" ]] || ! grep -q '[^[:space:]]' "$path"; then
      echo "  INCOMPLETE  $name is missing or empty"; continue
    fi
    contained_path "$repo" "docs/$slug/feature-docs/$name" || return 2
    grep -q '^# .[^[:space:]]*' "$path" || echo "  INCOMPLETE  $name needs a title"
    # Only known template markers, not arbitrary angle-bracket syntax in real documentation.
    if grep -Eq '<(Feature|YYYY-MM-DD|title|NN|one sentence|\.scratch/feature|source path|problem|solution|capability|path/file|notes|contracts|verification summary|scope exclusions|ticket links|decision|recorded reason|source>|Accepted,|criterion|ticket|what|blocked|status|date|material conflict)' "$path" ||
       grep -Eq '^(Who had the problem and what it was, from their side\.|What the feature does for that person, in one paragraph\.|What is tested, at which seam, and the command that runs it\.|Expand here only the decisions that took real debate:|- \[ \] …)' "$path"; then
      echo "  INCOMPLETE  $name contains unfinished template text"
    fi
  done
  if [[ -s "$dest/overview.md" ]]; then
    grep -Eq '^> Summary: [^[:space:]]' "$dest/overview.md" || echo '  INCOMPLETE  overview.md needs Summary:'
    grep -Eq 'Updated: ([0-9]{4}-[0-9]{2}-[0-9]{2}|Unknown)' "$dest/overview.md" || echo '  INCOMPLETE  overview.md needs Updated:'
    for heading in 'Problem' 'Solution' 'What was built' 'How it fits together' 'Testing' 'Out of scope' 'Not built yet'; do
      grep -Fxq "## $heading" "$dest/overview.md" || echo "  INCOMPLETE  overview.md needs section: $heading"
    done
  fi
  for name in decisions tickets; do
    [[ -s "$dest/$name.md" ]] || continue
    if ! awk -F'|' -v kind="$name" '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      /^\|/ {
        if (trim($2) == "#" && trim($3) == (kind == "decisions" ? "Decision" : "Ticket") &&
            trim($6) == "Status" && trim($7) == "Date") found = 1
      }
      END { exit !found }
    ' "$dest/$name.md"; then echo "  INCOMPLETE  $name.md needs its record table"; fi
    awk -F'|' -v kind="$name" '
      function trim(s) { gsub(/^[ \t`*]+|[ \t`*]+$/, "", s); return s }
      /^\|/ {
        if (trim($2) == "#" && trim($3) == (kind == "decisions" ? "Decision" : "Ticket")) { records = 1; next }
        if (!records || trim($2) ~ /^[-:]+$/) next
        id = trim($2)
        if (id == "" || tolower(id) == "none") next
        if (id in ids) print "  INCOMPLETE  " kind ".md duplicate ID: " id
        ids[id] = 1
        status = trim($6)
        if (kind == "decisions" && status ~ /^Superseded by D[0-9]+$/) {
          sub(/^Superseded by /, "", status); targets[status] = 1
        }
        next
      }
      { records = 0 }
      END {
        for (target in targets) if (!(target in ids))
          print "  INCOMPLETE  decisions.md supersession target is missing: " target
      }
    ' "$dest/$name.md" || return 2
  done
  if [[ -s "$dest/tickets.md" ]]; then
    grep -Fxq '## Acceptance criteria' "$dest/tickets.md" || echo '  INCOMPLETE  tickets.md needs Acceptance criteria'
  fi
  missing="$(missing_citations "$repo" "$dest/overview.md")" || return 2
  if [[ -n "$missing" ]]; then printf '%s\n' "$missing" | sed 's/^/  MISSING CITATION  /'; fi
}

# Rewrites docs/FEATURES.md from every feature's overview.md.
write_index() { # $1 = repo
  local repo="$1" dir name title summary updated
  mkdir -p "$repo/docs"
  {
    echo "# Features"
    echo
    echo "> Generated by \`feature-docs.sh index\`. Edit the feature docs, not this file."
    echo "> Read the overview for context, then decisions before changing behavior; tickets hold acceptance evidence and gaps."
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

write_map() { # section, TSV input, trailing comma
  local count
  count="$(wc -l < "$2" | tr -d ' ')"
  if [[ "$count" -eq 0 ]]; then printf '  "%s": {}%s\n' "$1" "$3"; return; fi
  printf '  "%s": {\n' "$1"
  awk -F'\t' -v n="$count" '{ printf "    \"%s\": \"%s\"%s\n", $1, $2, (NR < n ? "," : "") }' "$2"
  printf '  }%s\n' "$3"
}

cmd_stamp() {
  local repo="${1:-}" slug="${2:-}" source="" source_set=0 evidence_only=0 selected=0
  local dest manifest old_source="" synced="" reviewed="$TODAY" version="" findings path digest
  local same=0 snap="" staged="" backup="" count
  local evidence=()
  check_repo "$repo"; check_slug "$slug"
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "--source needs a directory"
        [[ "$source_set" -eq 0 ]] || die "--source may be supplied only once"
        source="${2%/}"; safe_relative "$source"; source_set=1; shift 2 ;;
      --evidence)
        [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "--evidence needs a file"
        safe_relative "$2"; evidence+=("$2"); selected=1; shift 2 ;;
      --evidence-only) evidence_only=1; shift ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  [[ "$source_set" -eq 0 || "$evidence_only" -eq 0 ]] || die "--source and --evidence-only cannot be combined"
  dest="$repo/docs/$slug/feature-docs"; manifest="$dest/sources.json"
  [[ -d "$dest" ]] || die "no feature docs at docs/$slug/feature-docs (run: new $repo $slug)"
  contained_path "$repo" "docs/$slug/feature-docs" || die "feature docs directory is unavailable"
  if [[ -e "$manifest" || -L "$manifest" ]]; then
    contained_path "$repo" "docs/$slug/feature-docs/sources.json" || die "manifest is unavailable"
    validate_manifest "$manifest" || exit 2
    version="$(manifest_field "$manifest" version)"
    old_source="$(manifest_field "$manifest" source)"
    synced="$(manifest_field "$manifest" synced)"
  fi
  findings="$(structure_findings "$repo" "$slug")" || exit 2
  evidence_error=""
  if [[ "$selected" -eq 0 && "$version" != 2 ]]; then
    evidence_error="first reviewed stamp needs --evidence <repo-relative file> (repeat for code and tests)"
  fi
  if [[ -n "$findings" && -n "$evidence_error" ]]; then
    printf '%s  CHECK FAILED\n%s\n' "$slug" "$findings"
    die "$evidence_error"
  elif [[ -n "$findings" ]]; then
    printf '%s  CHECK FAILED\n%s\n' "$slug" "$findings"
    exit 1
  elif [[ -n "$evidence_error" ]]; then
    die "$evidence_error"
  fi
  WORK="$(mktemp -d "$dest/.stamp.XXXXXX")" || die "cannot stage manifest"
  if [[ "$selected" -eq 1 ]]; then
    printf '%s\n' "${evidence[@]}" | LC_ALL=C sort -u > "$WORK/paths"
  else
    recorded_hashes "$manifest" evidence | cut -f1 > "$WORK/paths" || die "cannot read evidence inventory"
  fi
  : > "$WORK/evidence"
  while IFS= read -r path; do
    safe_relative "$path"
    contained_path "$repo" "$path" || die "evidence file is missing: $path"
    [[ -f "$repo/$path" ]] || die "evidence must be a regular file, not a directory: $path"
    [[ ! "$repo/$path" -ef "$manifest" ]] || die "sources.json cannot be its own evidence"
    digest="$(hash_file "$repo/$path")" || die "cannot hash evidence: $path"
    printf '%s\t%s\n' "$path" "$digest" >> "$WORK/evidence"
  done < "$WORK/paths"
  [[ -s "$WORK/evidence" ]] || die "reviewed evidence inventory must not be empty"
  : > "$WORK/documents"
  for path in decisions.md overview.md tickets.md; do
    digest="$(hash_file "$dest/$path")" || die "cannot hash document: $path"
    printf '%s\t%s\n' "$path" "$digest" >> "$WORK/documents"
  done
  : > "$WORK/files"
  if [[ "$evidence_only" -eq 1 ]]; then
    source="$old_source"
    if [[ -n "$version" ]]; then recorded_hashes "$manifest" > "$WORK/files" || exit 2; fi
  else
    if [[ "$source_set" -eq 0 ]]; then
      if [[ -n "$version" ]]; then source="$old_source"; else source=".scratch/$slug"; fi
    fi
    if [[ -n "$source" ]]; then
      safe_relative "$source"
      contained_path "$repo" "$source" || die "source directory unavailable: $source; use --evidence-only to preserve the previous source baseline"
      [[ -d "$repo/$source" ]] || die "source is not a directory: $source"
      current_hashes "$repo/$source" "$repo" > "$WORK/files" || die "cannot hash sources"
      [[ -s "$WORK/files" ]] || die "no *.md files under $source"
      synced="$TODAY"
      if [[ -n "$version" && "$source" == "$old_source" ]]; then
        recorded_hashes "$manifest" > "$WORK/old-files" || exit 2
        if cmp -s "$WORK/files" "$WORK/old-files"; then synced="$(manifest_field "$manifest" synced)"; fi
      fi
    else synced=""; fi
  fi
  if [[ "$version" == 2 && "$source" == "$old_source" ]]; then
    recorded_hashes "$manifest" > "$WORK/old-files" || exit 2
    recorded_hashes "$manifest" documents > "$WORK/old-documents" || exit 2
    recorded_hashes "$manifest" evidence > "$WORK/old-evidence" || exit 2
    if cmp -s "$WORK/files" "$WORK/old-files" && cmp -s "$WORK/documents" "$WORK/old-documents" && cmp -s "$WORK/evidence" "$WORK/old-evidence"; then
      same=1; reviewed="$(manifest_field "$manifest" reviewed)"
    fi
  fi
  {
    printf '{\n  "version": 2,\n'
    if [[ -n "$source" ]]; then printf '  "source": "%s",\n  "synced": "%s",\n' "$source" "$synced"
    else printf '  "source": null,\n  "synced": null,\n'; fi
    write_map files "$WORK/files" ','
    printf '  "reviewed": "%s",\n' "$reviewed"
    write_map documents "$WORK/documents" ','
    write_map evidence "$WORK/evidence" ''
    printf '}\n'
  } > "$WORK/manifest" || die "cannot write staged manifest"
  validate_manifest "$WORK/manifest" || exit 2
  if [[ "$same" -eq 1 ]]; then
    echo "unchanged  docs/$slug/feature-docs/sources.json (recorded inputs match; no dates changed)"
    return
  fi
  # Prepare every private source copy before touching the last good baseline.
  if [[ "$evidence_only" -eq 0 && -n "$source" ]] && snap="$(snapshot_dir "$repo" "$slug")"; then
    mkdir -p "$(dirname "$snap")" || die "cannot create snapshot directory"
    staged="$(mktemp -d "$(dirname "$snap")/.$slug.XXXXXX")" || die "cannot stage sources"
    while IFS=$'\t' read -r path digest; do
      if ! mkdir -p "$staged/$(dirname "$path")" || ! cp "$repo/$source/$path" "$staged/$path" ||
          [[ "$(hash_file "$staged/$path")" != "$digest" ]]; then
        rm -rf "$staged"; die "source changed or could not be copied: $path"
      fi
    done < "$WORK/files"
    if [[ -e "$snap" ]]; then
      backup="$staged.previous"
      mv "$snap" "$backup" || { rm -rf "$staged"; die "cannot preserve previous source snapshot"; }
    fi
    if ! mv "$staged" "$snap"; then
      [[ -z "$backup" ]] || mv "$backup" "$snap"
      rm -rf "$staged"; die "cannot install source snapshot"
    fi
  fi
  if ! mv "$WORK/manifest" "$manifest"; then
    if [[ -n "$staged" ]]; then rm -rf "$snap"; [[ -z "$backup" ]] || mv "$backup" "$snap"; fi
    die "cannot replace sources.json"
  fi
  [[ -z "$backup" ]] || rm -rf "$backup"
  refresh_index "$repo" || die "stamp saved, but index refresh failed"
  count="$(wc -l < "$WORK/evidence" | tr -d ' ')"
  echo "stamped  docs/$slug/feature-docs/sources.json ($(files "$count") reviewed; hashes do not prove tests passed)"
  if [[ "$evidence_only" -eq 1 && -n "$source" ]]; then echo "  source baseline preserved from $synced: $source"; fi
  sed 's/^/  EVIDENCE  /' "$WORK/paths"
}

report() { # repo, slug, quiet, check|status
  local repo="$1" slug="$2" quiet="$3" mode="$4" dest manifest findings rc=0 version="" source="" changes=""
  local path old digest kind prefix exists missing_source=0 reminders
  dest="$repo/docs/$slug/feature-docs"; manifest="$dest/sources.json"
  contained_path "$repo" "docs/$slug/feature-docs" || return 2
  if [[ -e "$manifest" || -L "$manifest" ]]; then
    contained_path "$repo" "docs/$slug/feature-docs/sources.json" || return 2
    validate_manifest "$manifest" || return 2
    version="$(manifest_field "$manifest" version)" || return 2
  fi
  findings="$(structure_findings "$repo" "$slug")" || return 2
  if [[ -n "$findings" ]]; then printf '%s  CHECK FAILED\n%s\n' "$slug" "$findings"; rc=1; fi
  if [[ "$mode" == check ]]; then
    if [[ "$rc" -eq 0 && "$quiet" -eq 0 ]]; then echo "$slug  CHECK OK  structure and current citations only"; fi
    return "$rc"
  fi
  if [[ -z "$version" ]]; then
    echo "$slug  REVIEW REQUIRED  no sources.json; no reviewed evidence baseline"; rc=1
  else
    source="$(manifest_field "$manifest" source)" || return 2
    if [[ -n "$source" ]]; then
      exists=0; contained_path "$repo" "$source" || exists=$?
      [[ "$exists" -ne 2 ]] || return 2
      if [[ "$exists" -ne 0 || ! -d "$repo/$source" ]]; then
        missing_source=1
        if [[ "$quiet" -eq 0 ]]; then echo "$slug  SOURCE MISSING  $source is not on this machine; available docs and evidence are still checked"; fi
      else
        changes="$(source_changes "$manifest" "$repo/$source" "$repo")" || return 2
        if [[ -n "$changes" ]]; then
          echo "$slug  SOURCE DRIFT  $source changed since $(manifest_field "$manifest" synced)"
          printf '%s\n' "$changes" | awk -F'\t' '{ printf "  %-8s %s\n", $2, $1 }'; rc=1
        fi
      fi
    fi
    if [[ "$version" == 1 ]]; then
      echo "$slug  REVIEW REQUIRED  legacy source hashes contain no document or code/test review baseline"; rc=1
    else
      for kind in documents evidence; do
        prefix=""; [[ "$kind" != documents ]] || prefix="docs/$slug/feature-docs/"
        changes="$(recorded_hashes "$manifest" "$kind")" || return 2
        while IFS=$'\t' read -r path old; do
          exists=0; contained_path "$repo" "$prefix$path" || exists=$?
          [[ "$exists" -ne 2 ]] || return 2
          if [[ "$exists" -ne 0 || ! -f "$repo/$prefix$path" ]]; then
            if [[ "$kind" == documents ]]; then echo "$slug  DOCS MISSING  $path"; else echo "$slug  EVIDENCE MISSING  $path"; fi
            rc=1
          else
            digest="$(hash_file "$repo/$prefix$path")" || return 2
            if [[ "$digest" != "$old" ]]; then
              if [[ "$kind" == documents ]]; then echo "$slug  DOCS CHANGED  $path"; else echo "$slug  EVIDENCE CHANGED  $path"; fi
              rc=1
            fi
          fi
        done <<< "$changes"
      done
      if [[ "$rc" -eq 0 && "$quiet" -eq 0 ]]; then
        if [[ "$missing_source" -eq 1 ]]; then echo "$slug  REVIEWED FILES MATCH  local source availability is separate"
        else echo "$slug  IN SYNC  recorded documents and reviewed files match (not semantic or runtime verification)"; fi
      fi
    fi
  fi
  if [[ "$quiet" -eq 0 ]]; then
    reminders="$(ticket_reminders "$dest/tickets.md")" || return 2
    [[ -z "$reminders" ]] || printf '%s\n' "$reminders" | sed 's/^/  /'
  fi
  return "$rc"
}

scan() { # check|status, then CLI args
  local mode="$1" repo="${2:-}" slug="" quiet=0 result=0 found=0 dir name out rc sources="" src
  shift
  check_repo "$repo"; shift
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
    report "$repo" "$slug" "$quiet" "$mode" || result=$?
  else
    for dir in "$repo"/docs/*/feature-docs; do
      [[ -d "$dir" ]] || continue
      found=1; name="$(basename "$(dirname "$dir")")"; check_slug "$name"
      rc=0; report "$repo" "$name" "$quiet" "$mode" || rc=$?
      if [[ "$rc" -gt "$result" ]]; then result="$rc"; fi
      if [[ "$rc" -ne 2 && -f "$dir/sources.json" ]]; then
        src="$(manifest_field "$dir/sources.json" source)" || return 2
        sources="$sources$src"$'\n'
      fi
    done
    if [[ "$quiet" -eq 0 ]]; then
      [[ "$found" -ne 0 ]] || echo 'no feature docs under docs/*/feature-docs'
      if [[ "$mode" == status ]]; then
        for dir in "$repo"/.scratch/*/; do
          [[ -d "$dir" ]] || continue
          src=".scratch/$(basename "$dir")"
          if ! printf '%s' "$sources" | grep -Fxq -- "$src"; then echo "$(basename "$dir")  NO DOCS  $src has no recorded source baseline"; fi
        done
      fi
    fi
  fi
  return "$result"
}

cmd_status() { scan status "$@"; }
cmd_check() { scan check "$@"; }

cmd_diff() {
  local repo="${1:-}" slug="${2:-}" manifest source changes snap="" path kind expected
  check_repo "$repo"
  check_slug "$slug"
  manifest="$repo/docs/$slug/feature-docs/sources.json"
  [[ -f "$manifest" ]] || die "docs/$slug/feature-docs has no sources.json, so there is no synced state to compare with"
  contained_path "$repo" "docs/$slug/feature-docs/sources.json" || die "manifest is unavailable"
  validate_manifest "$manifest" || exit 2
  source="$(manifest_field "$manifest" source)"
  if [[ -z "$source" ]]; then echo "$slug  NO SOURCE TRACKED  use status for reviewed document and evidence checks"; return; fi
  contained_path "$repo" "$source" || die "source $source is unavailable on this machine"
  [[ -d "$repo/$source" ]] || die "source ${source:-<unrecorded>} is not on this machine"
  changes="$(source_changes "$manifest" "$repo/$source" "$repo")"
  if [[ -z "$changes" ]]; then echo "$slug  SOURCES UNCHANGED  nothing changed in $source; use status for document and evidence checks"; exit 0; fi
  snap="$(snapshot_dir "$repo" "$slug")" || snap=""
  while IFS=$'\t' read -r path kind; do
    expected="$(recorded_hashes "$manifest" | awk -F'\t' -v path="$path" '$1 == path { print $2 }')"
    case "$kind" in
      ADDED) echo "ADDED    $source/$path (new file: read it in full)" ;;
      CHANGED)
        if [[ -n "$snap" && -f "$snap/$path" && ! -L "$snap/$path" && "$(hash_file "$snap/$path")" == "$expected" ]]; then
          echo "CHANGED  $source/$path"
          diff -u -L "synced/$path" -L "current/$path" "$snap/$path" "$repo/$source/$path" || true
        else
          echo "CHANGED  $source/$path (no copy of the synced version on this machine: read it in full)"
        fi ;;
      REMOVED)
        if [[ -n "$snap" && -f "$snap/$path" && ! -L "$snap/$path" && "$(hash_file "$snap/$path")" == "$expected" ]]; then
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

Features are recorded in `docs/<feature>/feature-docs/`; `docs/FEATURES.md` lists them. Read the overview for context, then decisions before speccing, ticketing or changing behavior. Cite the decision IDs the change builds on or overturns. Read tickets for acceptance evidence and remaining gaps. Write, convert and sync these docs with the `feature-docs` skill.
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
  check) shift; cmd_check "$@" ;;
  status) shift; cmd_status "$@" ;;
  diff) shift; cmd_diff "$@" ;;
  index) shift; cmd_index "$@" ;;
  setup) shift; cmd_setup "$@" ;;
  hook) shift; cmd_hook "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
