---
name: feature-docs
description: >-
  Use when a feature has just been implemented from a local spec and tickets and needs a tracked
  record, when the user points at existing docs to turn into feature docs, when a spec or ticket
  under .scratch/ changed after its feature docs were written, when feature docs cite code that
  moved, or before speccing, ticketing or changing a feature that already has
  docs/<feature>/feature-docs/. Phrases: "write the feature docs", "document this feature",
  "convert these docs", "sync the feature docs", "what did we decide about X".
---

# feature-docs

`to-spec` and `to-tickets` write the spec and tickets to `.scratch/<feature>/`, which is local and untracked. **Feature docs** are the tracked counterpart: `docs/<feature>/feature-docs/`, written once the feature is built. They are an **as-built** record. The spec says what was intended; feature docs say what the code shows and why, for the agent or teammate who will never see `.scratch/`.

| File | Holds |
|---|---|
| `overview.md` | Summary, problem, solution, what was built (each capability cites a file), testing, out of scope, not built yet |
| `decisions.md` | Every significant choice: why, alternative rejected, source, status, date |
| `tickets.md` | The slices delivered, with their acceptance criteria |
| `sources.json` | Hashes of the source files at the last sync. The script writes it; you never do |

`<feature>` is the `.scratch/<feature>/` slug. The script is `bash scripts/feature-docs.sh`; `--help` lists its commands. A filled set of the three docs is in `references/example.md`; read it when you are unsure what a finished row looks like.

## Pick the mode

- The feature's tickets are implemented and verified, and it has no feature docs → **WRITE**
- The user points at existing docs, in any folder or format → **CONVERT**
- The spec or tickets changed, cited code moved, the user says "sync", or a run is finishing on a feature that already has feature docs → **SYNC**
- You are about to spec, ticket or change a feature that has feature docs → **LOOKUP**

A change to a documented feature goes into its existing folder as new rows. A fix that changes no decision and no capability needs no doc change.

When the repo has no `docs/FEATURES.md`, finish the first WRITE or CONVERT by offering the one-time setup in `references/setup.md`. It makes later sessions find these docs unprompted.

## WRITE — after implementation

1. Find the sources: `.scratch/<feature>/spec.md`, every file in `.scratch/<feature>/issues/`, and the decisions made while building. For a Fleet run, `.fleet/runs/<run>/` holds `notes.md` and the plan's `decisions`, plus the worker reports and the lead's evidence files, which feed the Testing section and the delivery dates. Those are inputs for writing, not tracked sources: `stamp` hashes only `.scratch/<feature>`.
2. Run `bash scripts/feature-docs.sh new <repo> <feature>`.
3. Read every source end to end, then open the code behind each ticket. This step is done when every ticket has a file that proves it or is headed for "Not built yet".
4. Fill `overview.md`, starting with the one-sentence `Summary:`. Condense the spec's user stories into the "What was built" rows, one per capability, each citing a file you opened. Write paths from the repo root, including the package or submodule folder (`apps/web/src/export.ts`). The spec leaves paths out because they go stale before the code exists; here they are the evidence, and `status` checks them.
5. Fill `decisions.md`: one row for every item in the spec's Implementation Decisions and Testing Decisions, every decision made during the build, and every place the code departs from the spec (source `as-built`).
6. Fill `tickets.md`: one row and one criteria block per issue file. `delivered` only where the code shows it. The date is when it was delivered: from the ticket, the decision record or the commit, or for a Fleet run the day the lead accepted it (`verified_at` in `fleet resume <run> --json`; the evidence file's date on older runs).
7. Run `bash scripts/feature-docs.sh stamp <repo> <feature>`, then report the files written, everything under "Not built yet", and any glossary or ADR candidates. The user commits the folder with the code.

## SYNC — the docs are out of step

1. Run `bash scripts/feature-docs.sh status <repo> [<feature>]`. `IN SYNC` with no lines beneath it means stop and say so. `SOURCE MISSING` means the spec is on another machine and the feature docs are the record; only `MISSING` and `PLANNED` lines need work then.
2. On `DRIFT`, run `bash scripts/feature-docs.sh diff <repo> <feature>` for the changed lines, and reconcile each file:
   - `spec.md` → `overview.md` and `decisions.md`. A changed decision is a new row, and the old row's status becomes `Superseded by D<n>`.
   - `issues/NN-*.md` → that ticket's row and criteria in `tickets.md`. `ADDED` is a new row. `REMOVED` becomes `withdrawn` with its reason; ask the user when the sources give none.
3. For each `MISSING` path, the code moved or was removed without a spec change. `git log -1 -- <path>` names the commit. Moved: correct the path. Removed: take the row out of "What was built" and add an `as-built` decision row saying what was removed and why.
4. For each `PLANNED` ticket, and for every change from step 2, check the code. Work the code shows is `delivered` and joins "What was built"; work it does not show stays `planned` under "Not built yet".
5. Set `Updated:` to today, run `stamp` when the feature has a `sources.json`, and report what changed in each file. Sync is done when `status` prints no `DRIFT`, `STALE` or `MISSING`.

Sync runs one way, from the sources and the code into the feature docs. Corrections made directly in the feature docs stay.

## CONVERT — existing docs become feature docs

1. Read everything the user pointed at, end to end.
2. Name the features. One folder per feature; when the material covers several, propose the split and confirm it with the user before writing.
3. Run `new` for each feature and map the material into the three files. `references/convert.md` has the mapping for the common inputs (the old `feature.md` / `plan.md` / `progress.md` folders, loose notes, a bare `.scratch` spec).
4. Check each claim against the code: cite the file when it holds, record what the code shows when it differs, and mark the claim `unverified` when nothing in the repo can settle it.
5. Write the origin on the `Source:` line of `overview.md`. Run `stamp` only when the origin is a local source folder that will keep changing, with `--source <dir>` when it is somewhere other than `.scratch/<feature>`.
6. Run `status` to confirm every cited path exists. Leave the originals where they are: list them and ask the user whether to delete them now that the feature docs supersede them.

## LOOKUP — before changing a documented feature

1. Read `docs/FEATURES.md`, or list `docs/*/feature-docs/` when there is no index, and pick the features the work touches.
2. Read `decisions.md`, then `overview.md`.
3. Carry the decisions forward by ID in the new spec or ticket: "builds on D3", "supersedes D5". Raise a decision you want to overturn with the user; it changes in the feature docs through SYNC, after the new spec says so.

## Glossary and ADRs

Find the repo's glossary and ADR folder from `docs/agents/domain.md` when it exists; otherwise look for `CONTEXT.md` or `GLOSSARY.md` at the root and for `docs/adr/`.

- Name things with the glossary's terms. A term the feature introduced that the glossary lacks is a **glossary candidate**.
- A decision already recorded elsewhere, in an ADR or in another feature's decision table, is one row that cites it (`ADR-0007`, source `ADR`). The reasoning stays where it is, and that record is the authority when the two differ.
- A decision that binds other features (a shared contract, a convention, a technology choice) is an **ADR candidate**. Keep its row.

Name the candidates in your report. The user records them through their own glossary and ADR process.

## Rules

1. **As-built.** "What was built" and `delivered` come from the code. Decisions come from the sources and the conversation.
2. **One fact, one file.** Cross-reference between the three docs, and cite an ADR instead of restating it.
3. **Rows stay.** Superseded decisions and withdrawn tickets keep their rows, so a later reader sees what was tried.
4. **Absolute dates.** The docs outlive the session.
5. **Tables over prose.** One line of rationale per decision; expand only the contested ones.
