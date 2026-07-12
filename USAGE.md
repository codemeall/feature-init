# Usage — Scaffolding & AI Setup

> This repo is the **master**. Nothing here is copied into a target repo — the script creates only the three per-feature docs inside `<your-repo>/docs/<feature-slug>/`, with the feature name and today's date pre-filled.

Below, `<clone-path>` = wherever you cloned this repo (e.g. `~/tools/feature-init` or `~/Documents/linkzly-projects/process-templates`).

## One-time setup

```bash
git clone https://github.com/codemeall/feature-init.git
chmod +x <clone-path>/new-feature.sh

# optional — make it a global command:
echo 'alias new-feature="<clone-path>/new-feature.sh"' >> ~/.zshrc   # or ~/.bashrc
source ~/.zshrc
```

Windows: run via Git Bash or WSL, or copy the templates manually (they're plain markdown).

## Scaffolding commands

**1. Start an idea** (creates `docs/<slug>/feature.md` only — fill "Why", get the go/no-go):

```bash
new-feature /path/to/your-repo dashboard-revamp
```

**2. Idea approved → discovery** (adds `plan.md` + `progress.md` to the existing folder):

```bash
new-feature /path/to/your-repo dashboard-revamp --continue
```

**3. Skip the idea gate** (all 3 docs at once — for pre-justified work):

```bash
new-feature /path/to/your-repo attribution-v2 --all
```

Safety: refuses to overwrite existing folders/files, validates the slug (kebab-case) and repo path, and copies **only** template files — never the process docs themselves.

## AI agent setup

The skill in `skills/feature-init/` follows the cross-agent [SKILL.md standard](https://agentskills.io); Claude Code, Cursor, Codex, and Antigravity all read it natively.

**Via `npx skills` (needs Node; repo must be public, or use your local clone path):**

```bash
npx skills add codemeall/feature-init             # project install, auto-detects agents
npx skills add codemeall/feature-init -g          # global install
npx skills add <clone-path>                       # same, from a local clone (works while repo is private)
```

`npx skills` symlinks by default (updates follow the cache); add `--copy` for a standalone copy. Run `npx skills list` to see what's installed.

**Via the bundled installer (no Node needed):**

```bash
<clone-path>/install.sh all            # every harness, global (~/.claude, ~/.cursor, ~/.codex, ~/.gemini/config)
<clone-path>/install.sh claude codex   # only specific harnesses
<clone-path>/install.sh cursor --project /path/to/repo   # into the repo (.cursor/skills/) — commit it to share with the team
<clone-path>/install.sh all --force    # update an existing install after pulling a newer version
```

Project installs land in `.claude/skills/`, `.cursor/skills/`, `.codex/skills/`, and `.agents/skills/` (Antigravity — Codex reads this one too). Or copy `skills/feature-init/` there manually; the folder is self-contained.

**Claude (Cowork / claude.ai):** install the packaged `feature-init.skill` file (Settings → Capabilities → Skills), or attach/point Claude at `<clone-path>/skills/feature-init/SKILL.md`.

**Agents without skill support:** paste the block from [`adapters/AGENTS-snippet.md`](./adapters/AGENTS-snippet.md) into the target repo's `AGENTS.md`, adjusting the path to your clone — or start the session with *"Read `<clone-path>/skills/feature-init/SKILL.md` and follow it for all feature work in this repo."* Older Cursor versions: copy [`adapters/feature-init.mdc`](./adapters/feature-init.mdc) into the repo's `.cursor/rules/`.

## Everyday prompts

- Start: *"New feature: <one-line description>. Set it up per feature-init."*
- Resume: *"Continue the <slug> feature — read its progress.md and pick up from Next actions."*
- Decide: *"We're changing <X> to <Y> — record the decision and adjust the plan."*
- Hand off: *"Wrap up: update progress.md so the next agent can continue without me."*
- Review: *"Act as a fresh reviewer for docs/<slug>/ — verify citations, challenge the Proposed decisions."*

## Updating the process

Edit the templates / PROCESS.md / SKILL.md **here** (the master), then re-sync the bundled copies in `skills/feature-init/assets/` if templates changed. Already-scaffolded features keep their existing docs — don't retro-fit old folders unless a retro demands it.
