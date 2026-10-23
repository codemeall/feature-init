# Usage

`feature-docs` creates a tracked record that a teammate or later session can understand without your local scratch files. Installation and modes are in the [README](./README.md); agents follow [SKILL.md](./skills/feature-docs/SKILL.md).

## Prompts

| Situation | Say this |
|---|---|
| Implemented or partially implemented feature | "Write the feature docs for csv-export; include remaining acceptance checks." |
| Existing documentation | "Convert docs/billing into feature docs." |
| Changed sources or implementation | "Sync the csv-export feature docs." |
| Check document completeness | "Check the feature docs for unfinished scaffolds and missing files." |
| Before changing a feature | "Read the csv-export overview and decisions before planning scheduled exports." |
| First feature documented | "Set up feature docs in this repo." |

## What the checks establish

| Check | Establishes | Does not establish |
|---|---|---|
| `check` | Supported document structure, filled scaffolds, and recognized citations exist | That prose is true or complete |
| `status` | Whether recorded source, document, or evidence files changed | That every dependency was covered or runtime behavior works |
| Agent reconciliation | How sources, implementation, and evidence support each claim | That an unperformed test passed |

Opening a test file is code inspection. A passing test requires an execution result. Runtime verification requires a scenario, environment, date, and result. Historical results are attributed and marked as not rerun. Unknown rationale or delivery dates remain unknown.

## Commands

Use `skills/feature-docs/scripts/feature-docs.sh` from this repository, or `scripts/feature-docs.sh` inside an installed skill. The runtime is Bash and standard Unix utilities plus `shasum` or `sha256sum`; no Node, Python, or jq is required. Git enables private source snapshots for line-level diffs.

Paths are relative to the target repository unless stated otherwise. `<feature>` is the kebab-case output folder name; it normally matches `.scratch/<feature>`.

### `new <repo> <feature>`

Create three templates in `docs/<feature>/feature-docs/`. Existing files are preserved. A new scaffold is incomplete: fill it before stamping.

### `check <repo> [<feature>] [--quiet]`

Check one feature, or every existing feature-docs folder. Reports missing/empty required documents, known unfinished scaffolds, supported structural defects, and recognized missing overview citations. Features with no decisions or tickets may say so explicitly instead of inventing rows.

This is structural validation, not a prose-quality score. Word targets are guidance, not enforced padding or truncation. Quiet mode suppresses successful checks.

### `stamp <repo> <feature> [--source <dir>] [--evidence <file> ...] [--evidence-only]`

Run after reconciling docs with sources and implementation. Stamping acknowledges that review; it does not run tests. Structural checks must pass before the baseline is replaced.

The first version-2 stamp needs a nonempty explicit evidence selection:

```bash
FD=skills/feature-docs/scripts/feature-docs.sh
bash "$FD" check . csv-export
bash "$FD" stamp . csv-export --evidence src/api/export.ts --evidence tests/export.test.ts
```

Select files supporting documented claims: implementation, relevant tests, and configuration. This inventory does not claim tests ran. Root files such as `package.json`, extensionless files, and paths with spaces can be selected; quote shell arguments containing spaces. Directory citations check existence only, so select important child files individually.

Later stamps reuse the recorded selection when `--evidence` is omitted. Supplying any `--evidence` arguments **replaces the entire selection**; include every file to retain. Files outside that set are not automatically monitored.

Normal stamping hashes recursive `*.md` files under `.scratch/<feature>`, including maps and research answers. Use `--source planning/billing` for another source folder; later stamps remember it. Git metadata, generated `docs/*/feature-docs/` folders, and `docs/FEATURES.md` are excluded so a broad source folder cannot ingest its own output or snapshots.

The version-2 `sources.json` separates source, document, and evidence hashes. Keep its generated canonical format: it is script-owned, not a file to edit or reformat. Malformed or unsupported manifests fail explicitly. Failed validation or baseline preparation preserves the previous manifest.

### Stamping without local sources

A teammate may have tracked docs and code but no `.scratch`:

```bash
bash "$FD" stamp . csv-export --evidence-only
```

This refreshes document/evidence hashes while preserving the original source hashes and source-sync date. It does not claim unavailable sources were read. Source checks resume against the preserved baseline when those files return.

For converted docs without an ongoing source folder, use `--evidence-only` on the first stamp together with evidence files. The manifest records no source folder; subsequent stamps remember that mode. Preserve original documents until the user requests their removal.

### `status <repo> [<feature>] [--quiet]`

Reports structural findings and changes to recorded inputs. Several findings can appear together; a source match does not hide code or document changes.

| Condition | Action |
|---|---|
| Incomplete documents | Fill missing content before stamping |
| Sources changed | Reconcile changed specs, comments, answers, and tickets |
| Evidence changed or disappeared | Review claims; correct moved paths and the evidence selection |
| Documents changed | Review edits and stamp the revised record |
| Legacy or absent evidence baseline | Review the feature and establish a baseline using `--evidence` |
| Recorded files match | No detected change within recorded coverage; still inspect affected behavior when the task calls for it |
| Source folder missing | Use the tracked record; available document/evidence checks continue |
| Planned or partial tickets | Informational reminder of remaining implementation or acceptance checks |

Planned/partial tickets and missing local sources alone do not fail a current baseline. Quiet mode shows actionable findings and operational errors, suppressing informational notices.

Overview citation discovery uses backticked path shapes and does not recognize every filename or Markdown link. Explicit evidence selection reliably monitors root files, unusual paths, and relevant tests/configuration. Historical paths in decisions and tickets do not automatically become current evidence.

### `diff <repo> <feature>`

Shows changes to **source Markdown**, using the private snapshot in the Git directory when available. `SOURCES UNCHANGED` says nothing about code or document freshness. Use `status` for those findings and inspect affected code with repository tools.

Without a suitable private snapshot, the command names changed files without their old lines. A source-free feature has no source diff. An unavailable recorded source is reported as an error, not treated as unchanged.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Command succeeded, or no actionable findings within its scope |
| `1` | Structural findings, missing review baseline, or detected drift |
| `2` | Invalid arguments, unsupported/malformed manifest, or operational error |

Exit `0` does not prove test execution or semantic correctness. In multi-feature checks, operational errors take precedence over findings.

### `index <repo>` and `setup <repo> [--file CLAUDE.md or AGENTS.md]`

`index` generates `docs/FEATURES.md` from each overview's `Summary:` and `Updated:` lines. `setup` adds a pointer to the repository's agent instructions. With neither instruction file present, specify which to create. Existing sections are preserved. Once the index exists, `new` and successful stamps refresh it.

Future sessions find the overview and decisions before changes; tickets provide acceptance evidence and gaps. The tracked record must stand alone even when local source links are unavailable.

### `hook <repo>`

Installs a local pre-commit hook running `status --quiet`. It reports findings/errors but always allows the commit. An unrelated existing hook is preserved; the command prints a line to add instead of replacing it. Rerun installation if the skill path changes.

The optional Claude Code session hook is in [references/setup.md](./skills/feature-docs/references/setup.md).

## Reconciliation rules

- **Partial delivery:** identify incomplete acceptance criteria. Implemented code awaiting a required runtime check remains `partial`, with that distinction stated.
- **Discovery:** resolved research, prototype, or discussion tickets contribute durable conclusions, not delivered production behavior. See [references/sources.md](./skills/feature-docs/references/sources.md).
- **Conflicts:** code establishes behavior; recorded sources establish intent and rationale. Preserve material disagreements rather than inventing approval.
- **Source cleanup:** deleting a scratch issue changes provenance. Withdraw work only with evidence that it was dropped.
- **History:** retain IDs and superseded rows; preserve hand-written corrections. An unchanged sync preserves dates and bytes.
- **Compactness:** give each fact one authoritative location. Preserve reasons and acceptance evidence, not transcripts.

The [filled example](./skills/feature-docs/references/example.md) illustrates detail level. [Conversion guidance](./skills/feature-docs/references/convert.md) covers older feature/plan/progress documents.

## Upgrading existing records

Unversioned manifests remain readable for source drift and source diffs, including safe legacy source spellings such as `./.scratch/feature`. They lack reviewed code/document baselines, so source matches alone require review. Reading does not rewrite the manifest; migration normalizes the source path.

In version 2, source-only records return `REVIEW REQUIRED` with exit 1. To upgrade one feature, reconcile its docs, run `check`, then `stamp` with explicit evidence files. Update older bare first-stamp automation to provide that one-time selection and handle review-required results. Existing decision and ticket IDs remain; no bulk history rewrite occurs.

## Scope

The skill does not run an issue tracker, replace ADRs, or copy `.scratch` into Git. It uses glossary terms and links shared decisions to their existing authority. It reports glossary/ADR candidates for the project's normal process. Installing the skill does not publish or commit generated docs.
