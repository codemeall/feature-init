#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/skills/feature-docs"
FD="$SKILL/scripts/feature-docs.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/feature-docs-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

passes=0

pass() {
  passes=$((passes + 1))
  printf 'ok %d - %s\n' "$passes" "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_contains() { # $1 = text, $2 = expected substring
  [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"$'\n'"got: $1"
}

assert_lacks() { # $1 = text, $2 = substring that must be absent
  [[ "$1" != *"$2"* ]] || fail "expected output not to contain: $2"$'\n'"got: $1"
}

assert_exit() { # $1 = expected code, rest = command; prints the command's output
  local want="$1" got=0
  shift
  "$@" 2>&1 || got=$?
  [[ "$got" == "$want" ]] || fail "exit $got, expected $want: $*"
}

cd "$ROOT"

bash -n install.sh "$FD" tests/test.sh
pass "shell entry points parse"

for name in SKILL.md assets/templates/overview.md assets/templates/decisions.md assets/templates/tickets.md \
  references/convert.md references/example.md references/setup.md; do
  [[ -f "$SKILL/$name" ]] || fail "missing skill file: $name"
done
grep -q '^name: feature-docs$' "$SKILL/SKILL.md" || fail "SKILL.md frontmatter lost its name"
pass "skill bundle is complete"

# Every file the skill and the docs point at exists.
checked=0
for doc in README.md USAGE.md CHANGELOG.md; do
  links="$(grep -oE '\]\(\./[^)#]*' "$doc" | sed 's/^](//' | sort -u || true)"
  for link in $links; do
    [[ -e "$link" ]] || fail "$doc links to a missing file: $link"
    checked=$((checked + 1))
  done
done
refs="$(grep -oE '`(references|scripts|assets)/[^` ]*`' "$SKILL/SKILL.md" | tr -d '`' | sort -u || true)"
for ref in $refs; do
  [[ -e "$SKILL/$ref" ]] || fail "SKILL.md points at a missing file: $ref"
  checked=$((checked + 1))
done
[[ "$checked" -ge 8 ]] || fail "expected to check at least 8 documented paths, checked $checked"
pass "documented paths exist"

REPO="$TMP/repo"
DOCS="$REPO/docs/csv-export/feature-docs"
mkdir -p "$REPO/.scratch/csv-export/issues" "$REPO/src/api"
git init -q "$REPO"
printf '## Problem Statement\n\nNo export.\n\n- Always commas\n' > "$REPO/.scratch/csv-export/spec.md"
printf '# 01: Export endpoint\n' > "$REPO/.scratch/csv-export/issues/01-export-endpoint.md"
printf '# 02: Download button\n' > "$REPO/.scratch/csv-export/issues/02-download-button.md"
printf 'not markdown\n' > "$REPO/.scratch/csv-export/notes.txt"
touch "$REPO/src/api/export.ts"

out="$(assert_exit 0 bash "$FD" new "$REPO" csv-export)"
for name in overview decisions tickets; do
  [[ -f "$DOCS/$name.md" ]] || fail "new did not create $name.md"
done
assert_contains "$(cat "$DOCS/overview.md")" '# Csv Export'
assert_contains "$(cat "$DOCS/overview.md")" "Updated: $(date +%Y-%m-%d)"
[[ ! -e "$REPO/docs/FEATURES.md" ]] || fail "new wrote an index before setup"
pass "new scaffolds the three docs with title and date"

echo 'kept' > "$DOCS/decisions.md"
out="$(assert_exit 0 bash "$FD" new "$REPO" csv-export)"
assert_contains "$out" 'skip     docs/csv-export/feature-docs/decisions.md'
[[ "$(cat "$DOCS/decisions.md")" == 'kept' ]] || fail "new overwrote an existing doc"
pass "new preserves existing docs"

out="$(assert_exit 0 bash "$FD" status "$REPO" csv-export)"
assert_contains "$out" 'csv-export  UNTRACKED'
pass "a fresh template is clean: its placeholders are not read as citations"

out="$(assert_exit 0 bash "$FD" stamp "$REPO" csv-export)"
assert_contains "$out" '(3 files from .scratch/csv-export'
manifest="$DOCS/sources.json"
assert_contains "$(cat "$manifest")" '"source": ".scratch/csv-export"'
assert_contains "$(cat "$manifest")" '"issues/01-export-endpoint.md": "'
assert_lacks "$(cat "$manifest")" 'notes.txt'
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$manifest" || fail "sources.json is not valid JSON"
fi
pass "stamp records markdown sources as valid JSON"

out="$(assert_exit 0 bash "$FD" status "$REPO" csv-export)"
assert_contains "$out" 'csv-export  IN SYNC  3 files'
out="$(assert_exit 0 bash "$FD" status "$REPO" --quiet)"
[[ -z "$out" ]] || fail "quiet status printed while in sync: $out"
out="$(assert_exit 0 bash "$FD" diff "$REPO" csv-export)"
assert_contains "$out" 'IN SYNC'
pass "status, quiet status and diff agree right after a stamp"

sed 's/Always commas/Delimiter follows the locale/' "$REPO/.scratch/csv-export/spec.md" > "$TMP/spec.new"
mv "$TMP/spec.new" "$REPO/.scratch/csv-export/spec.md"
printf '# 03: Retry\n' > "$REPO/.scratch/csv-export/issues/03-retry.md"
rm "$REPO/.scratch/csv-export/issues/02-download-button.md"
out="$(assert_exit 1 bash "$FD" status "$REPO" csv-export)"
assert_contains "$out" 'csv-export  DRIFT  .scratch/csv-export changed since'
assert_contains "$out" '  CHANGED  spec.md'
assert_contains "$out" '  ADDED    issues/03-retry.md'
assert_contains "$out" '  REMOVED  issues/02-download-button.md'
assert_lacks "$out" '01-export-endpoint'
out="$(assert_exit 1 bash "$FD" status "$REPO" --quiet)"
assert_contains "$out" 'Feature docs are out of step'
assert_contains "$out" 'csv-export  DRIFT'
pass "status lists changed, added and removed sources and exits 1"

out="$(assert_exit 1 bash "$FD" diff "$REPO" csv-export)"
assert_contains "$out" 'CHANGED  .scratch/csv-export/spec.md'
assert_contains "$out" '-- Always commas'
assert_contains "$out" '+- Delimiter follows the locale'
assert_contains "$out" 'ADDED    .scratch/csv-export/issues/03-retry.md (new file: read it in full)'
assert_contains "$out" 'REMOVED  .scratch/csv-export/issues/02-download-button.md, which said:'
assert_contains "$out" '  | # 02: Download button'
[[ -z "$(git -C "$REPO" status --porcelain -- .git 2>/dev/null)" ]] || fail "the private copy shows up in git status"
pass "diff shows the changed lines and the text of a removed file"

assert_exit 0 bash "$FD" stamp "$REPO" csv-export >/dev/null
out="$(assert_exit 0 bash "$FD" status "$REPO" csv-export)"
assert_contains "$out" 'IN SYNC'
pass "stamp clears the drift"

cat > "$DOCS/overview.md" <<'DOC'
# Csv Export

> Summary: Any report downloads as a CSV | with filters.
> Feature docs. Updated: 2026-10-06
> Source: `.scratch/csv-export` and `gone/in-the-header.md`

| Capability | Where (`path/file`) | Notes |
|---|---|---|
| Endpoint | `src/api/export.ts:12` | returns `text/csv` at `/api/export`; run `npm test -- export` |
| Writer | `src/reports/csv-writer.ts` | |
| Page | `app/(dash)/[id]/page.tsx` | |
| Folder | `src/api/` | also `src/missing-dir/` |
DOC
out="$(assert_exit 1 bash "$FD" status "$REPO" csv-export)"
assert_contains "$out" 'csv-export  STALE  .scratch/csv-export is unchanged since'
assert_contains "$out" '  MISSING  src/reports/csv-writer.ts (cited in overview.md)'
assert_contains "$out" '  MISSING  app/(dash)/[id]/page.tsx (cited in overview.md)'
assert_contains "$out" '  MISSING  src/missing-dir/ (cited in overview.md)'
for ok in 'src/api/export.ts' 'text/csv' '/api/export' 'npm test' 'in-the-header' 'path/file' 'MISSING  src/api/ '; do
  assert_lacks "$out" "$ok"
done
mkdir -p "$REPO/src/reports" "$REPO/app/(dash)/[id]" "$REPO/src/missing-dir"
touch "$REPO/src/reports/csv-writer.ts" "$REPO/app/(dash)/[id]/page.tsx"
out="$(assert_exit 0 bash "$FD" status "$REPO" csv-export)"
assert_contains "$out" 'csv-export  IN SYNC'
pass "status flags cited files that are gone, and only those"

printf '| # | Ticket | What it delivers | Blocked by | Status | Date |\n|---|---|---|---|---|---|\n| 01 | Export endpoint | x | None | delivered | 2026-10-02 |\n| 04 | Semicolon delimiter | y | 01 | planned | 2026-10-13 |\n' > "$DOCS/tickets.md"
out="$(assert_exit 0 bash "$FD" status "$REPO" csv-export)"
assert_contains "$out" '  PLANNED  04 Semicolon delimiter'
assert_lacks "$out" 'PLANNED  01'
out="$(assert_exit 0 bash "$FD" status "$REPO" --quiet)"
[[ -z "$out" ]] || fail "a planned ticket alone made quiet status speak: $out"
pass "status reminds about planned tickets without failing"

# A source outside .scratch, remembered for later stamps.
mkdir -p "$REPO/planning/billing" "$REPO/.scratch/search"
echo '# Billing spec' > "$REPO/planning/billing/spec.md"
echo '# Search spec' > "$REPO/.scratch/search/spec.md"
bash "$FD" new "$REPO" billing >/dev/null
assert_exit 0 bash "$FD" stamp "$REPO" billing --source planning/billing >/dev/null
echo 'more' >> "$REPO/planning/billing/spec.md"
out="$(assert_exit 0 bash "$FD" stamp "$REPO" billing)"
assert_contains "$out" 'from planning/billing'
pass "stamp remembers a custom source"

mkdir -p "$REPO/docs/legacy/feature-docs"
echo '# Legacy' > "$REPO/docs/legacy/feature-docs/overview.md"
echo 'changed' >> "$REPO/.scratch/csv-export/spec.md"
out="$(assert_exit 1 bash "$FD" status "$REPO")"
assert_contains "$out" 'billing  IN SYNC'
assert_contains "$out" 'csv-export  DRIFT'
assert_contains "$out" 'legacy  UNTRACKED'
assert_contains "$out" 'search  NO DOCS  .scratch/search has no feature docs'
assert_lacks "$out" 'csv-export  NO DOCS'
out="$(assert_exit 1 bash "$FD" status "$REPO" --quiet)"
assert_lacks "$out" 'billing'
assert_lacks "$out" 'NO DOCS'
pass "status without a feature covers every feature and flags undocumented sources"

mv "$REPO/.scratch" "$REPO/.scratch-elsewhere"
out="$(assert_exit 0 bash "$FD" status "$REPO" csv-export)"
assert_contains "$out" 'csv-export  SOURCE MISSING  .scratch/csv-export is not on this machine'
assert_exit 2 bash "$FD" diff "$REPO" csv-export >/dev/null
mv "$REPO/.scratch-elsewhere" "$REPO/.scratch"
pass "a missing source is reported, not treated as drift"

# No git checkout: everything works, and diff names files without their lines.
PLAIN="$TMP/plain"
mkdir -p "$PLAIN/.scratch/notes"
echo 'one' > "$PLAIN/.scratch/notes/spec.md"
bash "$FD" new "$PLAIN" notes >/dev/null
assert_exit 0 bash "$FD" stamp "$PLAIN" notes >/dev/null
echo 'two' >> "$PLAIN/.scratch/notes/spec.md"
out="$(assert_exit 1 bash "$FD" diff "$PLAIN" notes)"
assert_contains "$out" 'CHANGED  .scratch/notes/spec.md (no copy of the synced version on this machine: read it in full)'
pass "without git, diff falls back to naming the files"

out="$(assert_exit 2 bash "$FD" setup "$REPO")"
assert_contains "$out" 'no CLAUDE.md or AGENTS.md'
[[ -f "$REPO/docs/FEATURES.md" ]] || fail "setup did not write the index"
index="$(cat "$REPO/docs/FEATURES.md")"
assert_contains "$index" '| [Csv Export](csv-export/feature-docs/overview.md) | Any report downloads as a CSV \| with filters. | 2026-10-06 |'
assert_contains "$index" '| [Billing](billing/feature-docs/overview.md) |  |'
[[ -e "$REPO/docs/csv-export/feature-docs/overview.md" ]] || fail "index link target is missing"
printf '# Agents\n' > "$REPO/AGENTS.md"
out="$(assert_exit 0 bash "$FD" setup "$REPO")"
assert_contains "$out" 'added    Feature docs section to AGENTS.md'
assert_contains "$(cat "$REPO/AGENTS.md")" 'read its `decisions.md`'
out="$(assert_exit 0 bash "$FD" setup "$REPO")"
assert_contains "$out" 'skip     AGENTS.md'
[[ "$(grep -c '^## Feature docs$' "$REPO/AGENTS.md")" == 1 ]] || fail "setup added the section twice"
out="$(assert_exit 0 bash "$FD" setup "$REPO" --file CLAUDE.md)"
assert_contains "$(cat "$REPO/CLAUDE.md")" '## Feature docs'
assert_exit 2 bash "$FD" setup "$REPO" --file README.md >/dev/null
pass "setup writes the index and adds the pointer once"

bash "$FD" new "$REPO" saved-filters >/dev/null
assert_contains "$(cat "$REPO/docs/FEATURES.md")" '[Saved Filters](saved-filters/feature-docs/overview.md)'
pass "the index follows new features once it exists"

assert_exit 0 bash "$FD" stamp "$REPO" csv-export >/dev/null
out="$(assert_exit 0 bash "$FD" hook "$REPO")"
hook="$REPO/.git/hooks/pre-commit"
[[ -x "$hook" ]] || fail "hook is not executable"
out="$(assert_exit 0 sh -c "cd '$REPO' && sh .git/hooks/pre-commit")"
[[ -z "$out" ]] || fail "hook spoke while everything was in sync: $out"
echo 'drift' >> "$REPO/.scratch/csv-export/spec.md"
out="$(assert_exit 0 sh -c "cd '$REPO' && sh .git/hooks/pre-commit")"
assert_contains "$out" 'csv-export  DRIFT'
assert_exit 0 bash "$FD" hook "$REPO" >/dev/null
printf '#!/bin/sh\necho theirs\n' > "$hook"
out="$(assert_exit 2 bash "$FD" hook "$REPO")"
assert_contains "$out" 'already exists and is not ours'
assert_contains "$(cat "$hook")" 'echo theirs'
pass "the hook warns without blocking and never replaces someone else's hook"

for slug in bad- -bad bad--slug Bad_slug; do
  assert_exit 2 bash "$FD" new "$REPO" "$slug" >/dev/null
done
assert_exit 2 bash "$FD" stamp "$REPO" csv-export --source ../outside >/dev/null
assert_exit 2 bash "$FD" stamp "$REPO" csv-export --source /tmp >/dev/null
assert_exit 2 bash "$FD" stamp "$REPO" csv-export --source no-such-dir >/dev/null
assert_exit 2 bash "$FD" stamp "$REPO" csv-export --source >/dev/null
assert_exit 2 bash "$FD" stamp "$REPO" undocumented >/dev/null
assert_exit 2 bash "$FD" status "$REPO" undocumented >/dev/null
assert_exit 2 bash "$FD" status "$REPO" --loud >/dev/null
assert_exit 2 bash "$FD" diff "$REPO" legacy >/dev/null
assert_exit 2 bash "$FD" hook "$PLAIN" >/dev/null
assert_exit 2 bash "$FD" >/dev/null
assert_exit 0 bash "$FD" --help >/dev/null
pass "invalid features, sources and commands exit 2"

INSTALL_HOME="$TMP/home"
mkdir -p "$INSTALL_HOME/.claude/skills/feature-init"
out="$(HOME="$INSTALL_HOME" ./install.sh claude)"
installed="$INSTALL_HOME/.claude/skills/feature-docs"
diff -r "$SKILL" "$installed" >/dev/null || fail "installed skill differs from the source"
assert_contains "$out" 'the older feature-init skill is still at'
out="$(assert_exit 0 bash "$installed/scripts/feature-docs.sh" status "$REPO" billing)"
assert_contains "$out" 'billing  IN SYNC'
pass "the installed copy is complete, runs, and points out the old skill"

printf '1..%d\n' "$passes"
