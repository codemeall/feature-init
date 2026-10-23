#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/skills/feature-docs"
FD="$SKILL/scripts/feature-docs.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/feature-docs-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
passes=0
pass() { passes=$((passes + 1)); printf 'ok %d - %s\n' "$passes" "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
contains() { [[ "$1" == *"$2"* ]] || fail "expected $2; got: $1"; }
lacks() { [[ "$1" != *"$2"* ]] || fail "unexpected $2; got: $1"; }
run() { local want="$1" got=0; shift; "$@" 2>&1 || got=$?; [[ "$got" == "$want" ]] || fail "exit $got, expected $want: $*"; }

# Minimal completed records support mechanical tests; prose is not a golden output.
make_repo() {
  local repo="$1" dest="$1/docs/csv-export/feature-docs"
  mkdir -p "$repo/.scratch/csv-export/issues" "$repo/src" "$repo/tests" "$dest"
  git init -q "$repo"
  printf '# Export format\nCSV supports the existing spreadsheet workflow.\n' > "$repo/.scratch/csv-export/spec.md"
  printf '# 01 Export endpoint\nReturn filtered report rows.\n' > "$repo/.scratch/csv-export/issues/01-export.md"
  printf 'export const exportRows = rows => rows.filter(row => row.visible);\n' > "$repo/src/export.js"
  printf '// Contract assertion for visible rows.\n' > "$repo/tests/export.test.js"
  cat > "$dest/overview.md" <<'DOC'
# Csv Export
> Summary: Export filtered reports as CSV.
> Feature docs. Updated: 2026-10-01
> Source: local planning records; evidence paths are repository-relative.

## Problem
Analysts need to reuse filtered report rows.
## Solution
The endpoint returns the report's filtered rows.
## What was built
| Capability | Where (`path/file`) | Notes |
|---|---|---|
| Export endpoint | `src/export.js` | Applies existing filters |
## How it fits together
The endpoint in `src/export.js` follows the report query contract.
## Testing
`tests/export.test.js` contains a contract check; it was not run in this documentation session.
## Out of scope
None.
## Not built yet
None.
DOC
  cat > "$dest/decisions.md" <<'DOC'
# Csv Export — Decisions
| # | Decision | Why (alternative rejected) | Source | Status | Date |
|---|---|---|---|---|---|
| D1 | Export as CSV | Existing spreadsheet workflow; binary formats deferred | spec.md, Export format | Accepted | 2026-10-01 |
DOC
  cat > "$dest/tickets.md" <<'DOC'
# Csv Export — Tickets
| # | Ticket | What it delivers | Blocked by | Status | Date |
|---|---|---|---|---|---|
| 01 | Export endpoint | Filtered report rows | None | delivered | 2026-10-01 |

## Acceptance criteria
### 01 — Export endpoint
- [x] Export applies existing filters (`src/export.js`).
DOC
}
stamp() { bash "$FD" stamp "$1" csv-export --evidence src/export.js --evidence tests/export.test.js; }
digest() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

cd "$ROOT"
bash -n install.sh "$FD" tests/test.sh
for name in SKILL.md assets/templates/overview.md assets/templates/decisions.md assets/templates/tickets.md references/convert.md references/example.md references/setup.md references/sources.md; do
  [[ -f "$SKILL/$name" ]] || fail "missing resource: $name"
done
pass "shell entrypoints parse and portable skill resources exist"
description="$(sed -n '/^---$/,/^---$/p' "$SKILL/SKILL.md" | sed -n '/^description:/,/^[a-z][a-z]*:/p' | sed '$d' | sed 's/^description:[[:space:]]*>-[[:space:]]*//' | sed 's/^[[:space:]]*//' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
description_length="${#description}"
[[ "$description_length" -le 1024 ]] || fail "SKILL.md description is $description_length chars, exceeds 1024 char limit"
[[ "$description" == "Writes, converts, syncs and looks up"* ]] || fail "SKILL.md description should start with 'Writes, converts, syncs and looks up'"
contains "$description" "Use when"
contains "$description" "write the feature docs"
contains "$description" "sync the feature docs"
pass "SKILL.md description is under 1024 chars, contains 'Use when' and trigger phrases, and starts with exact opening"
for doc in README.md USAGE.md CHANGELOG.md; do
  while IFS= read -r link; do [[ -z "$link" || -e "$ROOT/$link" ]] || fail "$doc links to $link"; done < <(grep -oE '\]\(\./[^)#]*' "$doc" | sed 's/^](//' | sort -u || true)
done
pass "published local documentation links resolve"

# Create a temporary repo for issue #2 test
EARLY_ERROR="$TMP/early-error"
make_repo "$EARLY_ERROR"
early_docs="$EARLY_ERROR/docs/csv-export/feature-docs"
# On complete docs with no v2 manifest, stamp without --evidence exits 2 and prints the evidence message
rc=0
out="$(bash "$FD" stamp "$EARLY_ERROR" csv-export 2>&1)" || rc=$?
[[ $rc -eq 2 ]] || fail "stamp without evidence on complete docs exited $rc, expected 2"
contains "$out" "first reviewed stamp needs --evidence"
# On incomplete docs, it should print both the structural findings and the evidence requirement
rm "$early_docs/decisions.md"
rc=0
out="$(bash "$FD" stamp "$EARLY_ERROR" csv-export 2>&1)" || rc=$?
[[ $rc -eq 2 ]] || fail "stamp without evidence on incomplete docs exited $rc, expected 2"
contains "$out" "first reviewed stamp needs --evidence"
contains "$out" "INCOMPLETE"
pass "first stamp without --evidence reports the error even when docs are incomplete"

REPO="$TMP/repo"
make_repo "$REPO"
DOCS="$REPO/docs/csv-export/feature-docs"
MANIFEST="$DOCS/sources.json"
cp -R "$DOCS" "$TMP/valid-docs"
rm -rf "$DOCS"
run 0 bash "$FD" new "$REPO" csv-export >/dev/null
run 1 bash "$FD" check "$REPO" csv-export >/dev/null
run 1 stamp "$REPO" >/dev/null
[[ ! -e "$MANIFEST" ]] || fail "invalid scaffold received a baseline"
echo preserved > "$DOCS/decisions.md"
run 0 bash "$FD" new "$REPO" csv-export >/dev/null
[[ "$(cat "$DOCS/decisions.md")" == preserved ]] || fail "new overwrote work"
cp "$TMP/valid-docs/"*.md "$DOCS/"
pass "new preserves work and incomplete scaffolds cannot be stamped"

run 0 bash "$FD" check "$REPO" csv-export >/dev/null
run 2 bash "$FD" stamp "$REPO" csv-export >/dev/null
[[ ! -e "$MANIFEST" ]] || fail "first stamp without explicit evidence wrote a baseline"
run 0 stamp "$REPO" >/dev/null
contains "$(cat "$MANIFEST")" '"version": 2'
run 0 bash "$FD" status "$REPO" csv-export >/dev/null
out="$(run 0 bash "$FD" status "$REPO" --quiet)"
[[ -z "$out" ]] || fail "quiet status printed for reviewed docs"
# Make the saved dates older than today: same-day repetition alone misses date churn.
sed -E 's/("(reviewed|synced)": ")[0-9]{4}-[0-9]{2}-[0-9]{2}/\12001-02-03/' "$MANIFEST" > "$TMP/older-manifest"
cp "$TMP/older-manifest" "$MANIFEST"
cp -R "$DOCS" "$TMP/docs.original"
run 0 bash "$FD" stamp "$REPO" csv-export >/dev/null
diff -r "$TMP/docs.original" "$DOCS" >/dev/null || fail "unchanged stamp changed record"
pass "reviewed baseline succeeds and unchanged stamp is byte-stable"

echo '// changed' >> "$REPO/src/export.js"
out="$(run 1 bash "$FD" status "$REPO" csv-export)"
contains "$out" 'src/export.js'
out="$(run 0 bash "$FD" diff "$REPO" csv-export)"
contains "$out" 'SOURCES UNCHANGED'
lacks "$out" 'IN SYNC'
run 0 bash "$FD" stamp "$REPO" csv-export >/dev/null
echo '// changed' >> "$REPO/tests/export.test.js"
out="$(run 1 bash "$FD" status "$REPO" csv-export)"
contains "$out" 'tests/export.test.js'
run 0 bash "$FD" stamp "$REPO" csv-export >/dev/null
mv "$REPO/src/export.js" "$REPO/src/renamed.js"
out="$(run 1 bash "$FD" status "$REPO" csv-export)"
contains "$out" 'src/export.js'
mv "$REPO/src/renamed.js" "$REPO/src/export.js"
pass "code and test content changes and moved evidence are actionable"

echo 'An editorial clarification.' >> "$DOCS/overview.md"
out="$(run 1 bash "$FD" status "$REPO" csv-export)"
contains "$out" 'overview.md'
run 0 bash "$FD" stamp "$REPO" csv-export >/dev/null
echo 'A new accepted requirement.' >> "$REPO/.scratch/csv-export/spec.md"
echo '# Retry' > "$REPO/.scratch/csv-export/issues/02-retry.md"
rm "$REPO/.scratch/csv-export/issues/01-export.md"
out="$(run 1 bash "$FD" status "$REPO" csv-export)"
for path in spec.md issues/02-retry.md issues/01-export.md; do contains "$out" "$path"; done
out="$(run 1 bash "$FD" diff "$REPO" csv-export)"
contains "$out" 'A new accepted requirement.'
contains "$out" 'Return filtered report rows.'
run 0 bash "$FD" stamp "$REPO" csv-export >/dev/null
pass "document drift and source additions, changes and removals are detected"

cp -R "$REPO/.git/feature-docs" "$TMP/snapshot.before"
cp "$MANIFEST" "$TMP/manifest.before"
cp "$DOCS/tickets.md" "$TMP/tickets.valid"
for required in overview.md decisions.md tickets.md; do
  mv "$DOCS/$required" "$TMP/missing-document"
  run 1 bash "$FD" check "$REPO" csv-export >/dev/null
  run 1 bash "$FD" stamp "$REPO" csv-export >/dev/null
  cmp "$MANIFEST" "$TMP/manifest.before" || fail "failed stamp replaced manifest"
  diff -r "$REPO/.git/feature-docs" "$TMP/snapshot.before" >/dev/null || fail "failed stamp replaced snapshot"
  mv "$TMP/missing-document" "$DOCS/$required"
done
cp "$DOCS/decisions.md" "$TMP/decisions.valid"
sed -n '/^| D1 /p' "$TMP/decisions.valid" >> "$DOCS/decisions.md"
run 1 bash "$FD" check "$REPO" csv-export >/dev/null
sed 's/| Accepted |/| Superseded by D99 |/' "$TMP/decisions.valid" > "$DOCS/decisions.md"
run 1 bash "$FD" check "$REPO" csv-export >/dev/null
cp "$TMP/decisions.valid" "$DOCS/decisions.md"
pass "missing docs, duplicate IDs and dangling supersession fail without losing baseline"

for state in partial planned; do
  sed "s/| delivered |/| $state |/" "$TMP/tickets.valid" > "$DOCS/tickets.md"
  run 0 bash "$FD" check "$REPO" csv-export >/dev/null
  run 0 bash "$FD" stamp "$REPO" csv-export >/dev/null
  out="$(run 0 bash "$FD" status "$REPO" --quiet)"
  [[ -z "$out" ]] || fail "$state work alone produced quiet warning"
done
pass "partial and planned work do not fail freshness"

CLONE="$TMP/fresh clone"
mkdir -p "$CLONE"
cp -R "$REPO/docs" "$REPO/src" "$REPO/tests" "$CLONE/"
git init -q "$CLONE"
run 0 bash "$FD" status "$CLONE" csv-export >/dev/null
run 0 bash "$FD" check "$CLONE" csv-export >/dev/null
echo '// fresh clone change' >> "$CLONE/src/export.js"
out="$(run 1 bash "$FD" status "$CLONE" csv-export)"
contains "$out" 'src/export.js'
sed '/"reviewed":/,$d' "$CLONE/docs/csv-export/feature-docs/sources.json" > "$TMP/source-baseline.before"
run 0 bash "$FD" stamp "$CLONE" csv-export --evidence-only >/dev/null
run 0 bash "$FD" status "$CLONE" csv-export >/dev/null
contains "$(cat "$CLONE/docs/csv-export/feature-docs/sources.json")" '.scratch/csv-export'
sed '/"reviewed":/,$d' "$CLONE/docs/csv-export/feature-docs/sources.json" > "$TMP/source-baseline.after"
cmp "$TMP/source-baseline.before" "$TMP/source-baseline.after" || fail "evidence-only refresh changed the unavailable source baseline"
pass "fresh clone checks evidence without scratch and retains source origin during refresh"

CONVERTED="$TMP/converted"
make_repo "$CONVERTED"
rm -rf "$CONVERTED/.scratch"
echo '{}' > "$CONVERTED/package.json"
echo contract > "$CONVERTED/src/public contract.txt"
run 0 bash "$FD" stamp "$CONVERTED" csv-export --evidence-only --evidence package.json --evidence 'src/public contract.txt' >/dev/null
run 0 bash "$FD" status "$CONVERTED" csv-export >/dev/null
echo changed >> "$CONVERTED/src/public contract.txt"
out="$(run 1 bash "$FD" status "$CONVERTED" csv-export)"
contains "$out" 'src/public contract.txt'
run 0 bash "$FD" stamp "$CONVERTED" csv-export --evidence-only --evidence package.json >/dev/null
run 0 bash "$FD" status "$CONVERTED" csv-export >/dev/null
echo changed >> "$CONVERTED/package.json"
run 1 bash "$FD" status "$CONVERTED" csv-export >/dev/null
pass "source-less conversion supports root files, spaces and evidence-set replacement"

LEGACY="$TMP/legacy"
make_repo "$LEGACY"
if command -v shasum >/dev/null 2>&1; then hash="$(shasum -a 256 "$LEGACY/.scratch/csv-export/spec.md" | cut -d' ' -f1)"; else hash="$(sha256sum "$LEGACY/.scratch/csv-export/spec.md" | cut -d' ' -f1)"; fi
cat > "$LEGACY/docs/csv-export/feature-docs/sources.json" <<JSON
{
  "source": ".scratch/csv-export",
  "synced": "2026-10-01",
  "files": {
    "spec.md": "$hash"
  }
}
JSON
out="$(run 1 bash "$FD" status "$LEGACY" csv-export)"
contains "$out" 'REVIEW REQUIRED'
run 0 stamp "$LEGACY" >/dev/null
run 0 bash "$FD" status "$LEGACY" csv-export >/dev/null
cp "$LEGACY/docs/csv-export/feature-docs/sources.json" "$TMP/legacy.upgraded"
printf '{ invalid json\n' > "$LEGACY/docs/csv-export/feature-docs/sources.json"
run 2 bash "$FD" status "$LEGACY" csv-export >/dev/null
run 2 bash "$FD" check "$LEGACY" csv-export >/dev/null
run 2 stamp "$LEGACY" >/dev/null
sed 's/"version": 2/"version": 999/' "$TMP/legacy.upgraded" > "$LEGACY/docs/csv-export/feature-docs/sources.json"
run 2 bash "$FD" status "$LEGACY" csv-export >/dev/null
pass "legacy requires review and malformed or unsupported manifests fail clearly"

# Older releases accepted these safe relative spellings. Read without rewriting,
# then normalize the source spelling when an explicit review upgrades the manifest.
legacy_case=0
for spelling in './.scratch/csv-export' '.scratch//csv-export' '.scratch/./csv-export' '././.scratch//csv-export' './.scratch//csv-export/'; do
  legacy_case=$((legacy_case + 1))
  legacy_repo="$TMP/legacy-spelling-$legacy_case"
  make_repo "$legacy_repo"
  legacy_manifest="$legacy_repo/docs/csv-export/feature-docs/sources.json"
  legacy_hash="$(digest "$legacy_repo/.scratch/csv-export/spec.md")"
  issue_hash="$(digest "$legacy_repo/.scratch/csv-export/issues/01-export.md")"
  cat > "$legacy_manifest" <<JSON
{
  "source": "$spelling",
  "synced": "2001-02-03",
  "files": {
    "issues/01-export.md": "$issue_hash",
    "spec.md": "$legacy_hash"
  }
}
JSON
  cp "$legacy_manifest" "$TMP/legacy-spelling.original"
  out="$(run 1 bash "$FD" status "$legacy_repo" csv-export)"
  contains "$out" 'REVIEW REQUIRED'
  run 0 bash "$FD" diff "$legacy_repo" csv-export >/dev/null
  echo 'A changed accepted requirement.' >> "$legacy_repo/.scratch/csv-export/spec.md"
  out="$(run 1 bash "$FD" status "$legacy_repo" csv-export)"
  contains "$out" 'spec.md'
  out="$(run 1 bash "$FD" diff "$legacy_repo" csv-export)"
  contains "$out" 'spec.md'
  cmp "$legacy_manifest" "$TMP/legacy-spelling.original" || fail "reading legacy source spelling mutated its baseline"
  run 0 stamp "$legacy_repo" >/dev/null
  contains "$(cat "$legacy_manifest")" '"source": ".scratch/csv-export"'
  run 0 bash "$FD" status "$legacy_repo" csv-export >/dev/null
done
# A fresh clone can also upgrade the legacy record without claiming a source review.
cp "$TMP/legacy-spelling.original" "$legacy_manifest"
mv "$legacy_repo/.scratch" "$legacy_repo/local-planning-away"
run 0 bash "$FD" stamp "$legacy_repo" csv-export --evidence-only --evidence src/export.js >/dev/null
contains "$(cat "$legacy_manifest")" '"source": ".scratch/csv-export"'
contains "$(cat "$legacy_manifest")" '"synced": "2001-02-03"'
contains "$(cat "$legacy_manifest")" "\"spec.md\": \"$legacy_hash\""
contains "$(cat "$legacy_manifest")" "\"issues/01-export.md\": \"$issue_hash\""
run 0 bash "$FD" status "$legacy_repo" csv-export >/dev/null
cp "$legacy_manifest" "$TMP/legacy-safe-upgrade"
for unsafe_source in '../outside' './.scratch/../outside' '/tmp' '//tmp'; do
  awk -v source="$unsafe_source" '/^  "source":/ {$0="  \"source\": \"" source "\","} {print}' "$TMP/legacy-spelling.original" > "$legacy_manifest"
  run 2 bash "$FD" status "$legacy_repo" csv-export >/dev/null
done
cp "$TMP/legacy-safe-upgrade" "$legacy_manifest"
pass "legacy dot and slash spellings preserve drift detection and safely upgrade with or without local sources"

# The same relative key in three maps must keep three separate meanings.
SCOPED="$TMP/scoped"
make_repo "$SCOPED"
echo '# Local planning choice' > "$SCOPED/.scratch/csv-export/decisions.md"
echo 'An independently reviewed repository artifact.' > "$SCOPED/decisions.md"
run 0 bash "$FD" stamp "$SCOPED" csv-export --evidence decisions.md --evidence src/export.js >/dev/null
run 0 bash "$FD" status "$SCOPED" csv-export >/dev/null
echo changed >> "$SCOPED/decisions.md"
run 1 bash "$FD" status "$SCOPED" csv-export >/dev/null
run 0 bash "$FD" stamp "$SCOPED" csv-export >/dev/null
scoped_manifest="$SCOPED/docs/csv-export/feature-docs/sources.json"
cp "$scoped_manifest" "$TMP/scoped.valid"
awk '/"files":/ {in_files=1} {print} in_files && /"decisions.md":/ {print; in_files=0}' "$TMP/scoped.valid" > "$scoped_manifest"
cp "$scoped_manifest" "$TMP/scoped.invalid"
run 2 bash "$FD" status "$SCOPED" >/dev/null
run 2 bash "$FD" check "$SCOPED" >/dev/null
run 2 bash "$FD" stamp "$SCOPED" csv-export >/dev/null
cmp "$scoped_manifest" "$TMP/scoped.invalid" || fail "malformed manifest was overwritten"
cp "$TMP/scoped.valid" "$scoped_manifest"
pass "manifest maps remain independent and duplicate keys propagate error 2 through aggregate commands"

echo outside > "$TMP/outside.txt"
ln -s "$TMP/outside.txt" "$SCOPED/src/outside.txt"
mkdir "$TMP/outside-source"
echo '# Outside planning' > "$TMP/outside-source/spec.md"
ln -s "$TMP/outside-source" "$SCOPED/outside-source"
run 2 bash "$FD" stamp "$SCOPED" csv-export --evidence src/outside.txt >/dev/null
run 2 bash "$FD" stamp "$SCOPED" csv-export --source outside-source >/dev/null
cmp "$scoped_manifest" "$TMP/scoped.valid" || fail "rejected outside paths changed the baseline"
pass "outside symlink evidence and source paths are rejected without baseline mutation"

CUSTOM="$TMP/custom"
make_repo "$CUSTOM"
mkdir -p "$CUSTOM/planning"
mv "$CUSTOM/.scratch/csv-export" "$CUSTOM/planning/billing"
run 0 bash "$FD" stamp "$CUSTOM" csv-export --source planning/billing --evidence src/export.js >/dev/null
run 0 bash "$FD" stamp "$CUSTOM" csv-export >/dev/null
contains "$(cat "$CUSTOM/docs/csv-export/feature-docs/sources.json")" 'planning/billing'
pass "custom source selection survives subsequent stamps"

# Root sources must exclude private snapshots and generated feature records, or
# each stamp can ingest its own previous output and recursively grow the cache.
ROOT_SOURCE="$TMP/root-source"
make_repo "$ROOT_SOURCE"
echo '# Repository planning' > "$ROOT_SOURCE/planning.md"
echo '# Private metadata' > "$ROOT_SOURCE/.git/private.md"
run 0 bash "$FD" index "$ROOT_SOURCE" >/dev/null
run 0 bash "$FD" stamp "$ROOT_SOURCE" csv-export --source . --evidence src/export.js >/dev/null
root_manifest="$ROOT_SOURCE/docs/csv-export/feature-docs/sources.json"
run 0 bash "$FD" status "$ROOT_SOURCE" csv-export >/dev/null
source_map="$(sed -n '/"files": {/,/^  }/p' "$root_manifest")"
contains "$source_map" 'planning.md'
lacks "$source_map" '.git/'
lacks "$source_map" 'docs/csv-export/feature-docs/'
lacks "$source_map" 'docs/FEATURES.md'
cp "$root_manifest" "$TMP/root-source.baseline"
cp -R "$ROOT_SOURCE/.git/feature-docs" "$TMP/root-source.snapshot"
for _ in 1 2; do
  run 0 bash "$FD" stamp "$ROOT_SOURCE" csv-export >/dev/null
  run 0 bash "$FD" status "$ROOT_SOURCE" csv-export >/dev/null
  cmp "$root_manifest" "$TMP/root-source.baseline" || fail "repeated root-source stamp changed the baseline"
  diff -r "$ROOT_SOURCE/.git/feature-docs" "$TMP/root-source.snapshot" >/dev/null || fail "root-source snapshot grew on repeat"
done
echo 'Generated index note.' >> "$ROOT_SOURCE/docs/FEATURES.md"
echo 'Private metadata changed.' >> "$ROOT_SOURCE/.git/private.md"
run 0 bash "$FD" status "$ROOT_SOURCE" csv-export >/dev/null
echo 'A changed accepted plan.' >> "$ROOT_SOURCE/planning.md"
out="$(run 1 bash "$FD" status "$ROOT_SOURCE" csv-export)"
contains "$out" 'planning.md'
pass "repository-root sources exclude generated artifacts and stay stable across repeated stamps"

# The portable script has always supported folders that are not git checkouts.
PLAIN="$TMP/plain"
make_repo "$PLAIN"
rm -rf "$PLAIN/.git"
run 0 stamp "$PLAIN" >/dev/null
echo 'A changed requirement.' >> "$PLAIN/.scratch/csv-export/spec.md"
out="$(run 1 bash "$FD" diff "$PLAIN" csv-export)"
contains "$out" 'spec.md'
run 0 bash "$FD" stamp "$PLAIN" csv-export >/dev/null
run 0 bash "$FD" status "$PLAIN" csv-export >/dev/null
run 2 bash "$FD" hook "$PLAIN" >/dev/null
pass "non-git folders retain stamping and diff fallback without pretending to install a hook"

run 2 bash "$FD" setup "$REPO" >/dev/null
[[ -f "$REPO/docs/FEATURES.md" ]] || fail "setup failed to write index"
printf '# Agents\n' > "$REPO/AGENTS.md"
run 0 bash "$FD" setup "$REPO" >/dev/null
cp "$REPO/AGENTS.md" "$TMP/agents.before"
run 0 bash "$FD" setup "$REPO" >/dev/null
cmp "$REPO/AGENTS.md" "$TMP/agents.before" || fail "setup duplicated pointer"
contains "$(cat "$REPO/docs/FEATURES.md")" '(csv-export/feature-docs/overview.md)'
run 0 bash "$FD" new "$REPO" another-feature >/dev/null
contains "$(cat "$REPO/docs/FEATURES.md")" '(another-feature/feature-docs/overview.md)'
pass "setup and index retain discovery without duplicate instructions"

run 0 bash "$FD" hook "$CUSTOM" >/dev/null
hook="$CUSTOM/.git/hooks/pre-commit"
[[ -x "$hook" ]] || fail "hook is not executable"
out="$(cd "$CUSTOM" && run 0 sh "$hook")"
[[ -z "$out" ]] || fail "hook warned on reviewed docs: $out"
echo '// stale' >> "$CUSTOM/src/export.js"
out="$(cd "$CUSTOM" && run 0 sh "$hook")"
contains "$out" 'src/export.js'
printf '#!/bin/sh\necho existing-hook\n' > "$hook"
run 2 bash "$FD" hook "$CUSTOM" >/dev/null
contains "$(cat "$hook")" existing-hook
pass "hook reports stale evidence without blocking or replacing another hook"

for slug in bad- -bad bad--slug Bad_slug; do run 2 bash "$FD" new "$CUSTOM" "$slug" >/dev/null; done
for source in ../outside /tmp no-such-dir; do run 2 bash "$FD" stamp "$CUSTOM" csv-export --source "$source" >/dev/null; done
for evidence in ../outside /tmp no-such-file; do run 2 bash "$FD" stamp "$CUSTOM" csv-export --evidence "$evidence" >/dev/null; done
run 2 bash "$FD" stamp "$CUSTOM" csv-export --evidence >/dev/null
run 2 bash "$FD" status "$CUSTOM" --loud >/dev/null
run 2 bash "$FD" check "$CUSTOM" --loud >/dev/null
run 2 bash "$FD" >/dev/null
run 0 bash "$FD" --help >/dev/null
pass "bad paths and arguments are usage errors"

INSTALL_PROJECT="$TMP/install-project"
mkdir -p "$INSTALL_PROJECT/.claude/skills/feature-init"
out="$(run 0 bash "$ROOT/install.sh" claude --project "$INSTALL_PROJECT")"
installed="$INSTALL_PROJECT/.claude/skills/feature-docs"
diff -r "$SKILL" "$installed" >/dev/null || fail "installed skill differs from source"
contains "$out" 'the older feature-init skill is still at'
run 0 bash "$installed/scripts/feature-docs.sh" check "$CUSTOM" csv-export >/dev/null
pass "isolated project install is complete and reports an older local skill"
printf '1..%d\n' "$passes"
