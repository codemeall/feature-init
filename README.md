# feature-init

**A 3-doc feature lifecycle any human or AI agent can pick up mid-stride.**

Every feature gets one folder in your repo — `docs/<feature-slug>/` — with exactly three documents. They carry a feature from idea to release, and they let you hand work between team members, AI sessions, and different AI tools (Claude, Codex, Cursor, …) without losing state. The docs are the memory, not the chat.

| Doc | Holds |
|---|---|
| `feature.md` | What & why — problem, concept, scope, decisions table, acceptance criteria |
| `plan.md` | How — contracts, milestones with exit gates, release checklist, risks |
| `progress.md` | Live state — now / done-left / findings / next actions. **Read this first when resuming.** |

Why it works: AI sessions die at context limits, teammates rotate, and chat history doesn't transfer between tools. With feature-init, any agent resumes from one small file (`progress.md`), decisions are recorded once instead of re-litigated, and every claim about your codebase carries a file citation so designs don't rest on wrong assumptions.

## Quick start (60 seconds)

```bash
git clone https://github.com/codemeall/feature-init.git
cd feature-init && chmod +x new-feature.sh

# scaffold your first feature in any repo:
./new-feature.sh /path/to/your-repo my-feature
```

That creates `your-repo/docs/my-feature/feature.md`. Fill the "Why" section (one page), decide it's worth pursuing, then:

```bash
./new-feature.sh /path/to/your-repo my-feature --continue   # adds plan.md + progress.md
```

Full scaffolding options: [USAGE.md](./USAGE.md).

## Use it with AI agents

The skill follows the [SKILL.md standard](https://agentskills.io) that Claude Code, Cursor, Codex, and Antigravity all support natively — same file, different install directory.

**Install from GitHub — `npx skills` (easiest, no clone needed):**

```bash
npx skills add codemeall/feature-init             # install into agents detected in the current project
npx skills add codemeall/feature-init -g          # global (all projects)
npx skills add codemeall/feature-init -a claude-code -a cursor -a codex   # pick agents
npx skills add https://github.com/codemeall/feature-init   # full URL works too
```

(Works for any public GitHub repo — while this repo is private, use `npx skills add <local-clone-path>` instead.)

**Install from a git clone — `install.sh` (no Node needed):**

```bash
git clone https://github.com/codemeall/feature-init.git && cd feature-init
./install.sh all                 # every harness, globally (all your projects)
./install.sh claude cursor       # just the ones you use
./install.sh codex --project /path/to/your-repo   # per-repo, committed with the repo
```

| Agent | Global install | Project install |
|---|---|---|
| **Claude Code** | `~/.claude/skills/` | `.claude/skills/` |
| **Cursor** | `~/.cursor/skills/` | `.cursor/skills/` |
| **Codex** | `~/.codex/skills/` | `.codex/skills/` |
| **Antigravity** | `~/.gemini/config/skills/` | `.agents/skills/` |
| **Claude (Cowork / claude.ai)** | package [`skills/feature-init/`](./skills/feature-init/) as a `.skill` and upload it | — |
| **Anything else** | paste [`adapters/AGENTS-snippet.md`](./adapters/AGENTS-snippet.md) into the repo's `AGENTS.md`, or point the agent at [`skills/feature-init/SKILL.md`](./skills/feature-init/SKILL.md) — it's plain markdown | — |

Older Cursor versions without skills support: use the rule file [`adapters/feature-init.mdc`](./adapters/feature-init.mdc) instead.

All routes lead to the same instruction file, so every tool follows the same process. Typical prompts once set up:

> *"Start a new feature: users need CSV export of the analytics report."* → agent scaffolds docs, drafts the Why, stops for your gate decision.
> *"Continue the csv-export feature, pick up where the last session left off."* → agent reads `progress.md`, does the next item, updates state.
> *"We need to switch to a server-side approach — record this properly."* → agent adds a decision row, adjusts the plan, keeps history.
> *"Wrap up this session with a clean handoff."* → agent writes exact done/half-done/next state into `progress.md`.

## The process in one paragraph

Stages: `Idea → Discovery → Design → Build → Released`, tracked in `feature.md`'s header. An idea costs one page (just the "Why"). Discovery verifies claims against your actual code before anything is designed. Design closes when every decision row is Accepted — no code from an undecided choice. Build goes milestone by milestone, each with an exit gate, ticking `progress.md` as it goes. Release runs a checklist and ends with a retro. The full spec, gates, and team workflow: **[PROCESS.md](./PROCESS.md)**.

## Repo layout

```
templates/             the 3 doc templates (master copies)
new-feature.sh         scaffolds docs into any target repo
install.sh             installs the skill into Claude Code / Cursor / Codex / Antigravity
PROCESS.md             the full process specification
USAGE.md               scaffolding commands + AI setup details
skills/feature-init/   the portable skill (SKILL.md + bundled templates/script)
adapters/              AGENTS.md snippet and Cursor rule, for agents without skill support
```

Nothing from this repo gets copied into your project except the three per-feature docs.

## License & contributions

Use it anywhere. If a retro shows the process itself can improve, PRs welcome — the templates and SKILL.md here are the single source of truth.
