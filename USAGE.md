# Usage

How to use `feature-docs` day to day: what to say to an agent, what the script prints, and what to do by hand when no agent is involved. Why the skill exists and how to install it are in the [README](./README.md).

`<feature>` is always the folder name under `.scratch/`, so `.scratch/csv-export/` pairs with `docs/csv-export/feature-docs/`.

## Prompts

| Situation | Say this |
|---|---|
| A feature is implemented | "The csv-export feature is done. Write its feature docs." |
| A Fleet run just finished | "Run is verified. Write the feature docs for csv-export before I commit." |
| Old docs exist | "Convert `docs/billing/` into feature docs." |
| Loose notes exist | "Turn `notes/search-redesign.md` into feature docs for the search feature." |
| The spec or tickets changed | "Sync the feature docs." or "Sync the csv-export feature docs." |
| Code was refactored | "Sync the feature docs." (a moved file shows as `MISSING`) |
| You are not sure what is stale | "Which feature docs are out of date?" |
| You are about to change a feature | "Check the csv-export feature docs before we spec scheduled exports." |
| You want a past decision | "What did we decide about the export rate limit, and why?" |
| First feature documented in a repo | "Set up feature docs in this repo." |

## The script

`skills/feature-docs/scripts/feature-docs.sh`, or `scripts/feature-docs.sh` inside an installed copy of the skill. Plain bash; it needs `shasum` or `sha256sum`. In a git checkout it also keeps a private copy of the synced sources under `.git/feature-docs/`, which is what lets `diff` show changed lines.

### `new <repo> <feature>`

Creates `docs/<feature>/feature-docs/` with the three templates. Files that already exist are left alone.

```text
$ bash feature-docs.sh new . csv-export
created  docs/csv-export/feature-docs/overview.md
created  docs/csv-export/feature-docs/decisions.md
created  docs/csv-export/feature-docs/tickets.md
```

### `stamp <repo> <feature> [--source <dir>]`

Records a hash of every `*.md` file in the source folder into `sources.json`. Run it after the docs are written or synced: it means "the docs now reflect these files". The source defaults to `.scratch/<feature>`. Pass `--source` once for a source kept elsewhere in the repo; later stamps remember it.

```text
$ bash feature-docs.sh stamp . csv-export
stamped  docs/csv-export/feature-docs/sources.json (3 files from .scratch/csv-export, synced 2026-10-06)
```

### `status <repo> [<feature>] [--quiet]`

Reports what is out of step. Without a feature it covers every feature in the repo.

```text
$ bash feature-docs.sh status .
billing  IN SYNC  1 file in planning/billing, last synced 2026-10-06
csv-export  DRIFT  .scratch/csv-export changed since 2026-10-06
  REMOVED  issues/02-download-button.md
  ADDED    issues/03-retry-failed-exports.md
  CHANGED  spec.md
  MISSING  src/reports/csv-writer.ts (cited in overview.md)
  PLANNED  04 Semicolon delimiter
legacy  UNTRACKED  no sources.json (converted or hand-written; nothing to sync from)
saved-filters  NO DOCS  .scratch/saved-filters has no feature docs
```

| State | Meaning | What to do |
|---|---|---|
| `IN SYNC` | The sources match the last stamp and every cited file exists | Nothing |
| `DRIFT` | The listed source files changed, appeared or disappeared | Sync |
| `STALE` | The sources are unchanged, but `overview.md` cites files that are gone | Sync |
| `UNTRACKED` | The feature docs have no recorded source (converted or written by hand) | Nothing; cited files are still checked |
| `SOURCE MISSING` | The recorded source folder is not on this machine | Nothing; the feature docs are the record here |
| `NO DOCS` | A `.scratch/` folder has no feature docs | Write them once the feature is implemented |

| Line under a feature | Meaning |
|---|---|
| `CHANGED`, `ADDED`, `REMOVED` | A source file differs from the last stamp |
| `MISSING` | A file or folder cited in `overview.md` no longer exists: the code moved or was deleted |
| `PLANNED` | A ticket recorded as not built yet. A reminder; it does not fail the check |

A citation is a backticked path with a slash that names a file (`src/api/export.ts`, with or without `:12`) or a folder (`src/api/`), written from the repo root. Only `overview.md` is checked, because it claims what exists now; `decisions.md` and `tickets.md` are history and may name files that are gone.

Exit codes: `0` in step, `1` for `DRIFT`, `STALE` or `MISSING`, `2` for bad arguments or another error. `--quiet` prints only the features that exit 1 and nothing at all when there are none, which is what the hooks use.

### `diff <repo> <feature>`

Shows what changed in the sources since the last stamp, line by line.

```text
$ bash feature-docs.sh diff . csv-export
REMOVED  .scratch/csv-export/issues/02-download-button.md, which said:
  | # 02: Download button

ADDED    .scratch/csv-export/issues/03-retry.md (new file: read it in full)

CHANGED  .scratch/csv-export/spec.md
--- synced/spec.md
+++ current/spec.md
@@ -4,4 +4,4 @@
 
 ## Implementation Decisions
 
-- Always comma delimiter
+- Delimiter follows the workspace locale
```

Outside a git checkout, or on a machine that never stamped the feature, there is no copy to compare with and `diff` names the changed files without their lines.

### `index <repo>` and `setup <repo> [--file CLAUDE.md|AGENTS.md]`

`index` writes `docs/FEATURES.md` from each feature's `Summary:` and `Updated:` lines. `setup` does that and also appends a "Feature docs" section to `CLAUDE.md`, or to `AGENTS.md` when there is no `CLAUDE.md`. With neither file present it asks you to choose with `--file`. Once the index exists, `new` and `stamp` keep it current.

```text
$ bash feature-docs.sh setup .
wrote    docs/FEATURES.md (1 feature)
added    Feature docs section to CLAUDE.md
```

The section it adds:

```markdown
## Feature docs

Built features are recorded in `docs/<feature>/feature-docs/`; `docs/FEATURES.md` lists them. Before speccing, ticketing or changing a listed feature, read its `decisions.md` and cite the decision IDs the change builds on or overturns. Write, convert and sync these docs with the `feature-docs` skill.
```

### `hook <repo>`

Installs a `pre-commit` hook that runs `status --quiet`. It prints what is out of step and always lets the commit through.

```text
$ git commit -m "refactor report writer"
Feature docs are out of step with their sources or the code. Sync them with the feature-docs skill ("sync the feature docs"):
csv-export  STALE  .scratch/csv-export is unchanged since 2026-10-06, but the docs cite files that are gone
  MISSING  src/reports/csv-writer.ts (cited in overview.md)
[main 3f2a9c1] refactor report writer
```

If the repo already has a `pre-commit` hook, the command leaves it alone and prints the one line to add to it. The Claude Code `SessionStart` variant is in [`references/setup.md`](./skills/feature-docs/references/setup.md).

## Walk-throughs

### Write, after an implementation

1. Finish and verify the tickets in `.scratch/csv-export/issues/`.
2. Ask: "Write the feature docs for csv-export."
3. The agent runs `new`, reads the spec, the tickets and the code, fills the three docs and runs `stamp`.
4. Read `overview.md`. Check "Not built yet": anything there was specced or ticketed and is absent from the code.
5. Read the end of the agent's report for glossary and ADR candidates, and record the ones you agree with.
6. Commit `docs/csv-export/feature-docs/` together with the code.

By hand: run `new`, fill the three files using [`references/example.md`](./skills/feature-docs/references/example.md) as the model, then run `stamp` and `status`.

### Convert an old 3-doc folder

1. Ask: "Convert `docs/billing/` into feature docs."
2. The agent reads `feature.md`, `plan.md` and `progress.md`, checks their claims against the code and writes `docs/billing/feature-docs/`. The mapping it follows is in [`references/convert.md`](./skills/feature-docs/references/convert.md).
3. Decisions keep their numbers. Milestones become ticket rows. A box the old docs left unticked for work the code now shows is recorded as `delivered`, with a note.
4. The agent lists the original files, and any agent instructions that still point at them, and asks whether to delete the originals. Keep them until you have read the new docs.

A converted folder has no `sources.json` and shows as `UNTRACKED`. That is correct: nothing local feeds it. Its cited files are still checked.

### Sync after the spec changed

1. Change the feature the usual way: `to-spec` updates `.scratch/csv-export/spec.md`, `to-tickets` adds `issues/04-semicolon-delimiter.md`.
2. Ask: "Sync the feature docs."
3. The agent runs `status` and `diff`, and updates the matching rows:
   - the changed decision becomes a new row in `decisions.md`, and the row it replaces is marked `Superseded by D6`;
   - ticket 04 is added to `tickets.md` as `planned`, because the code does not show it yet.
4. From then on `status` lists `PLANNED  04 Semicolon delimiter`. After ticket 04 is implemented, sync again: it moves to `delivered` and its capability joins "What was built".

### Sync after a refactor

1. Rename or delete a file that `overview.md` cites. No spec changes.
2. The pre-commit hook, the session hook or a manual `status` prints `STALE` with a `MISSING` line.
3. Ask: "Sync the feature docs." The agent finds where the capability lives now and corrects the path. If the capability was removed, its row comes out of "What was built" and a decision row records the removal.

### Look up, before a change

1. Ask: "Check the csv-export feature docs before we spec scheduled exports."
2. The agent reads `decisions.md` and `overview.md` and tells you which decisions the change touches.
3. The new spec cites them: "builds on D1 (streaming)", "supersedes D5 (date format)".

## With agent-fleet

Fleet implements approved tickets and leaves commits to you. Feature docs fit between verification and your commit:

1. `grill-with-docs` → `to-spec` → `to-tickets` write `.scratch/<feature>/`.
2. Fleet plans, launches and verifies the tickets.
3. Ask the lead to write the feature docs, or to sync them when the feature already has some. The run's `notes.md` and plan decisions are sources for `decisions.md`.
4. Review and commit the code and the feature docs together.

## With a glossary and ADRs

The skill reads `docs/agents/domain.md` when the repo has one (written by `setup-matt-pocock-skills`), and otherwise looks for `CONTEXT.md` or `GLOSSARY.md` and `docs/adr/`.

- Feature docs use the glossary's terms.
- A decision that an ADR, or another feature's decision table, already records gets one row that cites it. The reasoning is not copied.
- A decision that binds other features is named in the agent's report as an ADR candidate, and a new term as a glossary candidate. You record them with your usual process; the skill does not write ADRs or edit the glossary.

## Questions

**Why not just commit `.scratch/`?** A spec is written before the code and is meant to go stale: it names no files and it does not record what changed during the build. Feature docs are written after, from the code. Committing the spec would track the intention, not the result.

**The feature folder is named differently from the `.scratch/` folder.** Use the name you want under `docs/` as `<feature>` and pass the real source once: `stamp . billing --source .scratch/billing-v2`.

**The repo is a monorepo, or uses submodules.** Run the script on the repo root and cite files from there, including the package folder: `apps/console/src/export.ts`. A file inside a checked-out submodule is found like any other.

**I edited the feature docs by hand. Will a sync undo it?** No. Sync only applies what changed in the sources and the code, and it never writes back to `.scratch/`.

**A teammate cloned the repo and `status` says `SOURCE MISSING`.** Expected. `.scratch/` is on your machine, not theirs. The feature docs are their record, and `MISSING` and `PLANNED` lines still work for them.

**`status` flags something that is not a file.** Citations are recognised by shape: a backticked token with a slash whose last part has a dot, or that ends in a slash. Write a route as `/api/export` (a leading slash is ignored), or drop the backticks.

**What does sync do when a ticket file is deleted?** The row stays and its status becomes `withdrawn`, with the reason. The agent asks for the reason when the sources do not give one.

**Can one spec produce several feature folders?** Yes, when it covers several features. The agent proposes the split and asks before writing.

**Does it track files other than Markdown?** No. Specs and tickets are Markdown, and tracking only `*.md` keeps editor and OS files out of the drift report.

**Where is the private copy of the sources, and is it safe?** In `.git/feature-docs/<feature>/`. Git never tracks or pushes anything inside `.git/`, and each `stamp` replaces it.
