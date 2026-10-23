# Retrieval setup

Use this optional setup when feature docs exist but future sessions have no reliable route to them. Apply pieces the user has authorized; otherwise offer the relevant changes with their paths. Existing authorization does not need another confirmation.

## Index and agent pointer

```bash
bash scripts/feature-docs.sh setup <repo>
```

This creates `docs/FEATURES.md` from each overview's Summary and Updated metadata. Subsequent `new` and `stamp` commands refresh an existing index. It also adds a Feature docs pointer to `CLAUDE.md`, or `AGENTS.md` when no `CLAUDE.md` exists. With neither present, specify `--file CLAUDE.md` or `--file AGENTS.md` according to the repository's chosen agent convention; clarify only when that choice is unresolved.

The pointer should route a later session through the index to the relevant overview, then decisions before changing behavior and tickets for acceptance evidence or unfinished work. It names the condition for reading the docs rather than restating the workflow. Check the installed pointer for accuracy; an existing section is preserved when setup runs again.

## Commit notice

```bash
bash scripts/feature-docs.sh hook <repo>
```

This installs a local pre-commit notice running `status --quiet`. It always exits 0. When a pre-commit hook already exists, the command prints an integration line instead of replacing it. The installed hook records this skill's path; rerun installation after moving the skill.

Status compares recorded sources, documents and selected evidence, and checks citations. It cannot prove semantic correctness or runtime behavior. Planned/partial tickets are reminders, not drift failures.

## Claude Code session notice

When requested, merge a SessionStart hook into the repo's existing `.claude/settings.json`, or `.claude/settings.local.json` for a local-only setting. Replace the skill path:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash <skill-path>/scripts/feature-docs.sh status \"$CLAUDE_PROJECT_DIR\" --quiet || true"
          }
        ]
      }
    ]
  }
}
```

Keep existing hooks. A clean mechanical status suppresses routine output; the notice is a retrieval aid, not an instruction to rewrite unchanged documents or refresh dates.
