# feature-docs

**Tracked feature docs for work that was specced and ticketed in local, untracked files.**

When a feature is built from a spec and tickets that live in `.scratch/`, the code reaches git and the reasoning does not. `feature-docs` is an agent skill that writes the reasoning down next to the code: one folder per feature, `docs/<feature>/feature-docs/`, describing what exists, why, what remains, and what was verified. It converts existing docs, reconciles changes, and points later agents at the record before they change the feature.

The npm package is named `feature-docs`. The GitHub repository is named `feature-init`. Neither name is being changed. The skill was called `feature-init` until 2026-10-06. See [Upgrading](./CHANGELOG.md#upgrading).

Version 2.0.0 was published to npm without npm provenance. The registry record for `feature-docs@2.0.0` has no provenance attestation.

## Why this exists

The skill is built for the workflow around [mattpocock/skills](https://github.com/mattpocock/skills) with the local-markdown tracker: `grill-with-docs`, then `to-spec`, then `to-tickets`, then implementation by hand or with [agent-fleet](https://github.com/codemeall/agent-fleet).

```text
grill-with-docs → to-spec → to-tickets → implement → feature-docs
                     │           │                        │
        .scratch/<feature>/   .scratch/<feature>/    docs/<feature>/feature-docs/
        spec.md               issues/NN-*.md         overview.md  decisions.md  tickets.md
        └──────── local, untracked ────────┘         └──────── tracked in git ────────┘
```

That workflow leaves five gaps, and each one is a reason the skill exists:

| Gap | What goes wrong | What feature docs do |
|---|---|---|
| `.scratch/` never leaves your machine | A teammate, a fresh clone or a new laptop has the code and no record of why it looks that way | Put the record in `docs/`, committed with the code |
| A spec is written before the code | It names no files (on purpose, they would go stale) and it does not know what changed during the build | Record the feature **as built**: every capability cites the file that proves it |
| Decisions live in the spec and the chat | The next agent re-argues a choice that was already settled, or quietly reverses it | Keep a decisions table with the reason and the rejected alternative, cited by ID in later specs |
| Specs, tickets and code keep changing | Docs written once drift from all three | Compare source, document, and explicitly selected code/test hashes; check supported overview citations for missing paths |
| Nobody remembers the docs are there | The next session starts from the code alone | An index, a pointer in the agent instructions, and optional hooks that surface drift on their own |

## What you get

```text
docs/
├── FEATURES.md                 one line per documented feature (generated)
└── csv-export/feature-docs/
    ├── overview.md             summary, problem, solution, what was built (with file citations), testing, out of scope
    ├── decisions.md            every significant choice: why, alternative rejected, source, status, date
    ├── tickets.md              delivery states, acceptance criteria, and evidence
    └── sources.json            source, document, and selected evidence hashes (written by the script)
```

A filled example of all three docs: [`skills/feature-docs/references/example.md`](./skills/feature-docs/references/example.md).

## The four use cases

Each one is a mode of the skill. You say the sentence; the agent does the rest.

### 1. Write: a feature has just been implemented

**When:** implementation exists and needs a durable record, including any unfinished acceptance checks.

> "The csv-export feature is done. Write its feature docs."

The agent reads the spec, tickets, relevant comments and discovery conclusions, opens the implementation and tests, and writes the three docs. A resolved research or prototype ticket contributes its conclusion; it does not become shipped functionality. Partial implementation and outstanding acceptance checks stay visible. Code inspection, passing tests, and runtime verification are recorded separately. You review and commit the folder with the code.

### 2. Convert: you already have docs somewhere

**When:** a feature is documented in an older format or a loose file: a `docs/<feature>/feature.md` + `plan.md` + `progress.md` folder from the earlier version of this skill, a design doc, a README section, notes.

> "Convert `docs/billing/` into feature docs."
> "Turn `notes/search-redesign.md` and the Search section of the README into feature docs."

The agent reads what you pointed at, checks each claim, and writes the feature docs. Code establishes current behavior; recorded decisions establish accepted intent. A disagreement remains visible, and missing rationale is marked as not recorded. Decisions keep their original numbers. The originals stay where they are until you say to delete them.

### 3. Sync: the spec, the tickets or the code changed

**When:** you ran `to-spec` or `to-tickets` again on a documented feature, edited `.scratch/` by hand, or refactored code the docs cite.

> "Sync the feature docs."

The agent runs structural and freshness checks, then reconciles the affected sources and evidence. For example:

```text
Source change: .scratch/csv-export/spec.md
Evidence change: src/reports/csv-writer.ts
Remaining work: ticket 03, Export rate limit
```

It then reads the changed lines and updates the matching rows:

- A changed decision becomes a new row and the old one is marked superseded, so the history stays readable.
- A new ticket that is not in the code yet is recorded as `planned`, not as built.
- A cited file that moved gets its path corrected.
- A ticket becomes `delivered` when every acceptance criterion has appropriate evidence.

Delivery requires evidence appropriate to every acceptance criterion. A ticket with implemented code but an outstanding required load or device check remains `partial`. Deleting a scratch file alone does not withdraw the work. An unchanged sync leaves dates and history alone.

The script checks recorded files, not every dependency or runtime environment. Matching hashes do not prove semantic correctness or test success. The agent still reviews affected behavior when asked to sync after an implementation change.

### 4. Look up: before changing a documented feature

**When:** you are about to grill, spec or ticket a change to a feature that has feature docs.

> "We're adding scheduled exports. Check the csv-export feature docs first."

The agent reads `overview.md` for context, then `decisions.md` before proposing changes, and consults `tickets.md` for acceptance evidence and gaps. It carries the relevant decisions into the new spec by ID ("builds on D1", "proposes to supersede D5"). An accepted replacement is reconciled through SYNC. After the [one-time setup](#one-time-setup-per-repo), agents do this without being asked.

### When not to use it

- **Before implementation starts.** The spec is the document for that stage. Partially built features can have feature docs, with their gaps recorded.
- **For new prose after a fix that changes no documented claim.** Existing evidence baselines may still need review and refresh.
- **As a progress tracker.** Ticket status during a build belongs to the tickets and to the run that implements them.
- **As a replacement for ADRs or the glossary.** A decision that binds other features belongs in an ADR; the feature docs cite it. The skill names such decisions as candidates and leaves recording them to you.

## Install

The skill follows the [SKILL.md standard](https://agentskills.io) that Claude Code, Cursor, Codex and Antigravity read natively.

Node 20 is the minimum for the `npx` commands below. `package.json` engines is `>=20`. Use the same commands on macOS and Linux. The clone path uses `bash` and does not need Node.

From npm. This runs the bundled `install.sh`:

```bash
npx feature-docs@latest all                              # every supported agent, globally
npx feature-docs@latest claude --project .               # into the current repo
npx feature-docs@latest all --force                      # update an existing install
```

A global install writes only these directories:

- `~/.claude/skills/feature-docs`
- `~/.cursor/skills/feature-docs`
- `~/.codex/skills/feature-docs`
- `~/.gemini/config/skills/feature-docs`

A `--project` install writes `<repo>/.claude/skills/feature-docs`, `<repo>/.cursor/skills/feature-docs`, `<repo>/.codex/skills/feature-docs`, and `<repo>/.agents/skills/feature-docs`.

The package published as `feature-docs@2.0.0` accepts those install commands. It rejects `--uninstall` and `--remove-legacy`.

From a clone of this repository, with no Node:

```bash
git clone https://github.com/codemeall/feature-init.git && cd feature-init
./install.sh all                                  # every supported agent, globally
./install.sh claude codex                         # only the ones you use
./install.sh cursor --project /path/to/your-repo  # into one repo, to commit with it
./install.sh all --force                          # replace an existing install
./install.sh --uninstall all                      # remove feature-docs
./install.sh --uninstall all --remove-legacy      # also remove old feature-init
```

`install.sh` in this repository accepts `--uninstall` and `--remove-legacy`. `--remove-legacy` also deletes a legacy `feature-init` skill directory next to `feature-docs`.

The third-party `skills` CLI is a different installer:

```bash
npx skills add codemeall/feature-init --skill feature-docs -g
npx skills add codemeall/feature-init --skill feature-docs
npx skills add codemeall/feature-init --skill feature-docs -g -a claude-code -a codex -a cursor
```

That CLI writes `~/.agents/skills/feature-docs` for a global install, or `./.agents/skills/feature-docs` for a project install. With `-a claude-code` it also symlinks `~/.claude/skills/feature-docs` to the global copy. It does not create `~/.cursor/skills/feature-docs`, `~/.codex/skills/feature-docs`, or `~/.gemini/config/skills/feature-docs`. Use `npx feature-docs@latest` or `./install.sh` when you want those directories. Checked with the `skills` CLI on Linux, Node 20.20.2 and Node 22.23.4, in a clean home.

For an agent without skill support, paste [`adapters/AGENTS-snippet.md`](./adapters/AGENTS-snippet.md) into the repo's `AGENTS.md`. Older Cursor versions can use the rule file [`adapters/feature-docs.mdc`](./adapters/feature-docs.mdc).

Version 2 requires explicit evidence files on the first stamp and a completed document structure. Existing source-only manifests require review before upgrading. Follow [Upgrading existing records](./USAGE.md#upgrading-existing-records) when updating an installation or automation from version 1.

## One-time setup per repo

Three optional steps make the docs work without anyone remembering them. The agent offers them after the first feature is documented; you can also run them yourself.

| Step | Command | What it changes |
|---|---|---|
| Index and pointer | `feature-docs.sh setup <repo>` | Writes `docs/FEATURES.md` and adds a three-line "Feature docs" section to `CLAUDE.md` or `AGENTS.md`, so later agents read a feature's decisions before changing it |
| Warning before commits | `feature-docs.sh hook <repo>` | Installs a `pre-commit` hook that prints what is out of step. It never blocks a commit and never replaces a hook you already have |
| Notice at session start | a `SessionStart` hook for Claude Code | Puts the same report into the agent's context when a session opens. The snippet is in [`references/setup.md`](./skills/feature-docs/references/setup.md) |

## Using it without an agent

The script is plain bash and needs only `shasum` or `sha256sum`. In a git checkout it can also show changed lines:

```bash
FD=skills/feature-docs/scripts/feature-docs.sh
bash $FD new    /path/to/repo csv-export   # create the three docs from the templates
                                         # fill the docs and review their evidence
bash $FD check  /path/to/repo csv-export   # check structure and supported citations
bash $FD stamp  /path/to/repo csv-export --evidence src/export.ts --evidence tests/export.test.ts
bash $FD status /path/to/repo              # document, source, and recorded evidence changes
bash $FD diff   /path/to/repo csv-export   # the changed lines since the last stamp
```

Commands, compatibility notes and exit codes are in [USAGE.md](./USAGE.md).

## For AI agents

The instructions are in [`skills/feature-docs/SKILL.md`](./skills/feature-docs/SKILL.md). The short version:

- Feature docs are **as-built**. Claims need appropriate evidence: opening a test file is not running it, and observed code is not proof of an accepted decision.
- Pick the mode from the situation: implemented and undocumented → write; pointed at existing docs → convert; sources or cited code changed → sync; about to change a documented feature → look up.
- `check` catches structural defects, `status` compares recorded inputs, and `diff` shows source changes. You never edit `sources.json` yourself.
- Cite implementation paths from the repo root and explicitly select reviewed files with `--evidence`. Later stamps reuse that selection; a supplied list replaces it.
- Rows in `decisions.md` and `tickets.md` are superseded or withdrawn, never deleted.
- Use the repo's glossary terms, cite an ADR instead of restating it, and name glossary and ADR candidates in your report.

## Repo layout

```text
skills/feature-docs/           the portable skill
  SKILL.md                     agent instructions: the four modes and the rules
  scripts/feature-docs.sh      new | check | stamp | status | diff | index | setup | hook
  assets/templates/            overview.md, decisions.md, tickets.md
  references/convert.md        where each kind of existing doc lands
  references/sources.md        scratch comments, discovery answers, conflicts, and Fleet evidence
  references/example.md        a filled set of feature docs, before and after a sync
  references/setup.md          the index, the pointer and the hooks
adapters/                      AGENTS.md snippet and Cursor rule, for agents without skill support
evals/                         trigger prompts, an advisory overlap check, and a harness eval
  triggers.json                should-trigger and should-not-trigger prompts
  extract-description.sh       shared SKILL.md description extraction
  check-trigger-phrases.sh     blocking quoted-phrase check used by CI and tests/test.sh
  run-trigger-eval.sh          advisory IDF overlap smoke signal; cannot separate feature docs from ticket creation
  harness/                     real CLI trigger eval; skips when no CLI or credentials are present
install.sh                     installs the skill into Claude Code, Cursor, Codex or Antigravity
tests/test.sh                  checks the script, the bundle and the installer
USAGE.md                       commands, walk-throughs and questions
```

The skill adds `docs/<feature>/feature-docs/` to your project, and `docs/FEATURES.md` plus one section in `CLAUDE.md` or `AGENTS.md` if you run the setup.

## Testing

Run the test suite:
```bash
./tests/test.sh
```

The trigger overlap script is an advisory smoke signal. It prints coverage and max overlap, warns when its reference thresholds are missed, and exits 0. It cannot separate feature docs from ticket creation. CI blocks on the quoted trigger phrases instead. That phrase check also runs inside `./tests/test.sh`.
```bash
./evals/run-trigger-eval.sh --report
```

The harness eval runs each prompt in `evals/triggers.json` through a real agent CLI, once with the skill installed and once without. It records a skill load only from the CLI tool trace, then writes precision, recall, and a per-prompt summary when it actually runs. It is not part of CI. If the CLI or credentials are missing it prints `SKIP` and exits 0, and it does not invent scores. No scored harness run is part of this release.
```bash
./evals/harness/run-harness-eval.sh --runner claude
./evals/harness/run-harness-eval.sh --runner cursor
```
See [evals/harness/README.md](./evals/harness/README.md).

## What is measured

Measured:

- The test suite, `./tests/test.sh` (this includes the quoted trigger phrase check).
- The CI matrix in `.github/workflows/test.yml`: ubuntu-latest and macos-latest, each with Node 20, 22, and 24.
- The advisory overlap scorer, `./evals/run-trigger-eval.sh`. It is a smoke signal. It does not decide whether the skill should trigger.

Not measured:

- Real-agent trigger precision and recall. See [issue #5](https://github.com/codemeall/feature-init/issues/5). A harness eval exists under `evals/harness/`, but it is unscored.

## System requirements

Requires bash, git, awk, and `shasum` or `sha256sum`. Windows requires WSL or Git Bash.

Node 18 support was dropped because Node 18 is end of life. Node 20 is the minimum for the npx entry point (`package.json` engines is `>=20`). CI runs the test suite on Node 20, 22, and 24 for both Ubuntu and macOS.

## Security

Report a vulnerability privately. See [SECURITY.md](./SECURITY.md).

## License

MIT. See [LICENSE](./LICENSE).
