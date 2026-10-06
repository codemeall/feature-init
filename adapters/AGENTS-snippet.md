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

If you read nothing else:
- Before speccing or changing a feature, read its `decisions.md` and cite the decision IDs the
  change builds on or overturns.
- After a feature is implemented, write its feature docs from the spec, the tickets and the
  code. "What was built" rows cite a real file; work the code does not show is "Not built yet".
- When `.scratch/<feature>/` changes, run
  `bash <clone-path>/skills/feature-docs/scripts/feature-docs.sh status .` and update the
  rows for the files it names.
- Superseded decisions and withdrawn tickets keep their rows.
```
