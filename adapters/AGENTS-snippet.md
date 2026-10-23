# Adapter: AGENTS.md snippet (any AGENTS.md-reading agent)

**Prefer a native skill install if your agent supports the SKILL.md standard.** Codex, Cursor,
Claude Code and Antigravity all do (see `../install.sh`). Use this snippet for agents without
skill support, or as a repo-level nudge so every agent in the repo keeps the feature docs
current even without the skill installed.

Paste the block below into the target repo's `AGENTS.md` (create the file at the repo root if
it does not exist). **Replace `<clone-path>` with where you cloned feature-init** (for example
`~/tools/feature-init`).

```markdown
## Feature docs

Specs and tickets for this repo live in `.scratch/<feature>/`, which is local and untracked.
The tracked record of each built feature is `docs/<feature>/feature-docs/` (overview.md,
decisions.md, tickets.md, sources.json). To write, convert or sync feature docs, read and follow:

    <clone-path>/skills/feature-docs/SKILL.md

(clone from https://github.com/codemeall/feature-init if missing)

Before speccing or changing a documented feature, use `docs/FEATURES.md` to find its overview
and decisions; cite the decision IDs the change builds on or overturns. Consult tickets for
acceptance evidence and remaining work. After implementation or a change to sources, code, or
docs, follow the skill's WRITE or SYNC workflow. Structural checks and matching hashes do not
prove test execution or runtime correctness. Preserve decision IDs and delivery history.
```
