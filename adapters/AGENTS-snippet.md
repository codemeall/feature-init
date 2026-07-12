# Adapter: AGENTS.md snippet (any AGENTS.md-reading agent)

**Prefer a native skill install if your agent supports the SKILL.md standard** — Codex,
Cursor, Claude Code, and Antigravity all do (see `../install.sh`). Use this snippet for agents
without skill support, or as a repo-level nudge so every agent working in the repo follows the
process even without the skill installed.

Paste the block below into the target repo's `AGENTS.md` (create the file at repo root if it
doesn't exist). **Replace `<clone-path>` with where you cloned feature-init** (e.g.
`~/tools/feature-init`).

```markdown
## Feature development process (feature-init)

This repo uses the feature-init 3-doc process. Before starting, resuming, planning, or handing
off ANY feature work, read and follow:

    <clone-path>/skills/feature-init/SKILL.md

(clone from https://github.com/codemeall/feature-init if missing)

Non-negotiables even if you read nothing else:
- Per-feature docs live in docs/<feature-slug>/ — feature.md (what/why + decisions),
  plan.md (milestones + gates), progress.md (live state; read this FIRST when resuming).
- No code from a non-Accepted decision row.
- Every codebase claim cites a real file path.
- Before ending a session, update progress.md (now / done-left / half-done detail / next
  actions) and commit it with the code.
```
