# One-time setup in a repo

Three optional pieces that keep feature docs in use after the session that wrote them. Offer them once, when the repo has feature docs and no `docs/FEATURES.md`. Each changes a file outside `docs/<feature>/feature-docs/`, so say what it will touch and wait for the user's yes.

## 1. The index and the pointer

```bash
bash scripts/feature-docs.sh setup <repo>
```

- Writes `docs/FEATURES.md`: one line per feature from its `Summary:` and `Updated:`. `new` and `stamp` rewrite it from then on.
- Appends a three-line "Feature docs" section to `CLAUDE.md`, or to `AGENTS.md` when there is no `CLAUDE.md`. That section is what makes a later agent read `decisions.md` before changing a feature, without anyone asking.
- With neither file present it stops and asks for `--file CLAUDE.md` or `--file AGENTS.md`. Ask the user which one; do not pick.

Running it again is safe: the index is regenerated and an existing section is left alone.

## 2. A warning before each commit

```bash
bash scripts/feature-docs.sh hook <repo>
```

Installs a `pre-commit` hook that runs `status --quiet` and prints the features that are out of step. It always exits 0, so it never blocks a commit. The hook is local to this checkout and records the path of this copy of the skill; rerun `hook` after moving or reinstalling the skill.

When the repo already has a `pre-commit` hook, the command refuses and prints the one line to add to it. Show that line to the user instead of editing their hook.

## 3. A notice at the start of each Claude Code session

For Claude Code, a `SessionStart` hook puts the same report into the agent's context, so drift is noticed before any work starts. Add it to the repo's `.claude/settings.json` (or `.claude/settings.local.json` to keep it out of git), with the real path of this skill's script:

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

Merge it into any hooks already in that file. `--quiet` prints nothing when every feature is in sync, so a healthy repo adds nothing to the context.
