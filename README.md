# feature-docs

**Tracked feature docs for work that was specced and ticketed in local, untracked files.**

When a feature is built from a spec and tickets that live in `.scratch/`, the code reaches git and the reasoning does not. `feature-docs` is an agent skill that writes the reasoning down next to the code: one folder per feature, `docs/<feature>/feature-docs/`, describing what was built and why. It converts docs you already have into that shape, keeps the folder in step when the spec, the tickets or the code change, and makes later agents read it before they change the feature.

The skill was called `feature-init` until 2026-10-06, and this repository still carries that name. See [Upgrading](./CHANGELOG.md#upgrading).

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
| Specs, tickets and code keep changing | Docs written once drift from all three | Detect a changed spec or ticket by hash, and a moved or deleted file by checking every cited path |
| Nobody remembers the docs are there | The next session starts from the code alone | An index, a pointer in the agent instructions, and optional hooks that surface drift on their own |

## What you get

```text
docs/
├── FEATURES.md                 one line per documented feature (generated)
└── csv-export/feature-docs/
    ├── overview.md             summary, problem, solution, what was built (with file citations), testing, out of scope
    ├── decisions.md            every significant choice: why, alternative rejected, source, status, date
    ├── tickets.md              the slices delivered and their acceptance criteria
    └── sources.json            hashes of the spec and ticket files at the last sync (written by the script)
```

A filled example of all three docs: [`skills/feature-docs/references/example.md`](./skills/feature-docs/references/example.md).

## The four use cases

Each one is a mode of the skill. You say the sentence; the agent does the rest.

### 1. Write: a feature has just been implemented

**When:** the tickets are done and verified, and you are about to commit.

> "The csv-export feature is done. Write its feature docs."

The agent reads `.scratch/csv-export/spec.md`, every ticket and any decisions recorded during the build, opens the code behind each ticket, and writes `docs/csv-export/feature-docs/`. Anything specced but missing from the code is listed under "Not built yet" instead of being described as done. You review and commit the folder with the code.

### 2. Convert: you already have docs somewhere

**When:** a feature is documented in an older format or a loose file: a `docs/<feature>/feature.md` + `plan.md` + `progress.md` folder from the earlier version of this skill, a design doc, a README section, notes.

> "Convert `docs/billing/` into feature docs."
> "Turn `notes/search-redesign.md` and the Search section of the README into feature docs."

The agent reads what you pointed at, checks each claim against the code, and writes the feature docs. A claim the code contradicts is recorded as the code has it; a claim nothing can confirm is marked `unverified`. Decisions keep their original numbers. The originals stay where they are until you say to delete them.

### 3. Sync: the spec, the tickets or the code changed

**When:** you ran `to-spec` or `to-tickets` again on a documented feature, edited `.scratch/` by hand, or refactored code the docs cite.

> "Sync the feature docs."

The agent runs the status check, which names exactly what is out of step:

```text
csv-export  DRIFT  .scratch/csv-export changed since 2026-10-06
  ADDED    issues/04-semicolon-delimiter.md
  CHANGED  spec.md
  MISSING  src/reports/csv-writer.ts (cited in overview.md)
  PLANNED  03 Export rate limit
```

It then reads the changed lines and updates the matching rows:

- A changed decision becomes a new row and the old one is marked superseded, so the history stays readable.
- A new ticket that is not in the code yet is recorded as `planned`, not as built.
- A cited file that moved gets its path corrected.
- A `planned` ticket the code now shows becomes `delivered`.

### 4. Look up: before changing a documented feature

**When:** you are about to grill, spec or ticket a change to a feature that has feature docs.

> "We're adding scheduled exports. Check the csv-export feature docs first."

The agent reads `decisions.md` and `overview.md` and carries the relevant decisions into the new spec by ID ("builds on D1", "supersedes D5"). A decision it wants to overturn is raised with you first. After the [one-time setup](#one-time-setup-per-repo), agents do this without being asked.

### When not to use it

- **Before the feature is built.** The spec is the document for that stage. Feature docs describe code that exists.
- **For a fix that changes no decision and no capability.** The commit message is enough.
- **As a progress tracker.** Ticket status during a build belongs to the tickets and to the run that implements them.
- **As a replacement for ADRs or the glossary.** A decision that binds other features belongs in an ADR; the feature docs cite it. The skill names such decisions as candidates and leaves recording them to you.

## Install

The skill follows the [SKILL.md standard](https://agentskills.io) that Claude Code, Cursor, Codex and Antigravity read natively.

```bash
npx skills add codemeall/feature-init --skill feature-docs -g   # all projects
npx skills add codemeall/feature-init --skill feature-docs      # the current project only
npx skills add codemeall/feature-init --skill feature-docs -g -a claude-code -a codex -a cursor
```

Or from a clone, with no Node:

```bash
git clone https://github.com/codemeall/feature-init.git && cd feature-init
./install.sh all                                  # every supported agent, globally
./install.sh claude codex                         # only the ones you use
./install.sh cursor --project /path/to/your-repo  # into one repo, to commit with it
./install.sh all --force                          # replace an existing install
```

For an agent without skill support, paste [`adapters/AGENTS-snippet.md`](./adapters/AGENTS-snippet.md) into the repo's `AGENTS.md`. Older Cursor versions can use the rule file [`adapters/feature-docs.mdc`](./adapters/feature-docs.mdc).

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
bash $FD stamp  /path/to/repo csv-export   # record the sources as synced today
bash $FD status /path/to/repo              # every feature: in sync, drifted, stale, or undocumented
bash $FD diff   /path/to/repo csv-export   # the changed lines since the last stamp
```

Commands, output and exit codes are in [USAGE.md](./USAGE.md), with a walk-through of each use case and the questions that come up.

## For AI agents

The instructions are in [`skills/feature-docs/SKILL.md`](./skills/feature-docs/SKILL.md). The short version:

- Feature docs are **as-built**. "What was built" and a `delivered` ticket come from code you opened; decisions come from the sources and the conversation.
- Pick the mode from the situation: implemented and undocumented → write; pointed at existing docs → convert; sources or cited code changed → sync; about to change a documented feature → look up.
- `status` tells you what is out of step and `diff` shows the lines; you never edit `sources.json` yourself.
- Cite files as paths from the repo root, in backticks. `status` checks every one.
- Rows in `decisions.md` and `tickets.md` are superseded or withdrawn, never deleted.
- Use the repo's glossary terms, cite an ADR instead of restating it, and name glossary and ADR candidates in your report.

## Repo layout

```text
skills/feature-docs/           the portable skill
  SKILL.md                     agent instructions: the four modes and the rules
  scripts/feature-docs.sh      new | stamp | status | diff | index | setup | hook
  assets/templates/            overview.md, decisions.md, tickets.md
  references/convert.md        where each kind of existing doc lands
  references/example.md        a filled set of feature docs, before and after a sync
  references/setup.md          the index, the pointer and the hooks
adapters/                      AGENTS.md snippet and Cursor rule, for agents without skill support
install.sh                     installs the skill into Claude Code, Cursor, Codex or Antigravity
tests/test.sh                  checks the script, the bundle and the installer
USAGE.md                       commands, walk-throughs and questions
```

The skill adds `docs/<feature>/feature-docs/` to your project, and `docs/FEATURES.md` plus one section in `CLAUDE.md` or `AGENTS.md` if you run the setup.

## License

MIT. See [LICENSE](./LICENSE).
