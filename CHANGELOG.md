# Changelog

## 2026-10-07 — 1.0.1: sources from a Fleet run

- WRITE names a Fleet run's worker reports and evidence files as inputs for the Testing section and the delivery dates, and dates a Fleet-delivered ticket from `verified_at` in `fleet resume <run> --json`. They are writing inputs, not tracked sources: `stamp` still hashes only `.scratch/<feature>`.
- USAGE notes that a Fleet lead runs `status` on a documented feature before its closing report.

## 2026-10-06 — published to npm as `feature-docs`

- `npx feature-docs@latest <agent...> [--project <repo>] [--force]` runs the bundled `install.sh`; `--force` updates an existing install.
- `npx skills add codemeall/feature-init --skill feature-docs` keeps working from GitHub.

## 2026-10-06 — feature docs replace the 3-doc lifecycle

The skill is renamed from `feature-init` to `feature-docs`, and it now records a feature after it is built instead of driving it from idea to release. Planning is left to the tools that already do it (`grill-with-docs`, `to-spec`, `to-tickets`, agent-fleet); this skill writes the tracked record those tools do not produce, because their specs and tickets stay in the untracked `.scratch/` folder.

**Output and modes**

- New output: `docs/<feature>/feature-docs/` with `overview.md` (as built, with file citations), `decisions.md`, `tickets.md` and `sources.json`.
- Four modes: write after implementation, convert existing docs, sync when the docs are out of step, and look up decisions before changing a documented feature.
- The skill uses the repo's glossary terms, cites an existing ADR or decision record instead of restating it, and names glossary and ADR candidates in its report.

**Script: `skills/feature-docs/scripts/feature-docs.sh`**

- `new` scaffolds the folder and `stamp` records a hash of every source file.
- `status` reports three kinds of problem: source files that changed (`DRIFT`), files cited in `overview.md` that no longer exist (`STALE`, `MISSING`), and tickets still recorded as `PLANNED`. It exits 1 on the first two. `--quiet` prints only what is out of step.
- `diff` shows the changed lines since the last stamp, from a private copy kept under `.git/feature-docs/`.
- `index` writes `docs/FEATURES.md`; `setup` also adds a "Feature docs" section to `CLAUDE.md` or `AGENTS.md`.
- `hook` installs a `pre-commit` hook that warns and never blocks. A Claude Code `SessionStart` snippet is in `references/setup.md`.

**Removed**

- `feature.md`, `plan.md` and `progress.md` templates, the Idea → Released stages, gates and sign-offs, `new-feature.sh`, `PROCESS.md` and the root `templates/` folder. The skill folder is now the only copy of the templates and script.

**Docs and checks**

- README and USAGE rewritten around why the skill exists, its four use cases, prompts, command output and common questions.
- Added a filled example, a conversion mapping and a setup guide under `skills/feature-docs/references/`.
- Added `tests/test.sh`, a CI workflow that runs it, and an MIT `LICENSE`.
- The skill was tried on two real features, one written from a `.scratch` spec and one converted from a 3-doc folder; what that showed is folded into the skill text and the conversion mapping.

### Upgrading

1. Install the new skill: `npx skills add codemeall/feature-init --skill feature-docs -g`, or `./install.sh all` from a clone.
2. Remove the old one so the two do not both trigger: `npx skills remove feature-init`, or delete the `feature-init` folder from your skills directory. `install.sh` points out an old copy when it finds one.
3. Existing `docs/<feature>/` folders with `feature.md`, `plan.md` and `progress.md` are left untouched. Ask the agent to "convert `docs/<feature>/` into feature docs" to bring one over. The new folder is written beside the old files, which stay until you delete them.

The repository is still named `feature-init`. Renaming it on GitHub is optional: old URLs redirect.

## Earlier — 3-doc lifecycle

The first version, `feature-init`, scaffolded `feature.md`, `plan.md` and `progress.md` per feature and tracked it through Idea, Discovery, Design, Build and Released, with Accepted-decision gates and progress-first handoffs between sessions.
