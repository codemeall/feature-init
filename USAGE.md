# How to Use — Scaffolding Feature Docs in Any Repo

> This folder is the **master**. Nothing here (README, USAGE, script, templates) is ever copied into a target repo — the script creates only the per-feature docs (`feature.md`, `plan.md`, `progress.md`) inside `<repo>/docs/<feature-slug>/`, with the feature name and today's date pre-filled.

## One-time setup

```bash
chmod +x ~/Documents/linkzly-projects/process-templates/new-feature.sh
```

Optional — make it a global command:

```bash
echo 'alias new-feature="~/Documents/linkzly-projects/process-templates/new-feature.sh"' >> ~/.zshrc
source ~/.zshrc
```

## Commands

**1. Start an idea** (creates `docs/<slug>/feature.md` only — fill "Why", get gate 1):

```bash
new-feature ~/Documents/linkzly-projects/linkzly dashboard-revamp
```

**2. Idea approved → discovery** (adds `plan.md` + `progress.md` to the existing folder):

```bash
new-feature ~/Documents/linkzly-projects/linkzly dashboard-revamp --continue
```

**3. Skip the idea gate** (all 3 docs at once — for pre-justified work, e.g. a gap-analysis item):

```bash
new-feature ~/Documents/linkzly-projects/linkzly attribution-v2 --all
```

Works on any repo — just change the path:

```bash
new-feature ~/Documents/other-project/my-app onboarding-flow
```

## Safety behavior

- Refuses to overwrite: an existing `docs/<slug>/` errors out; existing files are skipped on `--continue`.
- Validates the slug (kebab-case) and that the repo path exists.
- Copies **only** from `templates/` — the process docs themselves never land in a repo.

## After scaffolding

1. Fill `feature.md` "Why" (about a page) → product owner gate.
2. Point an AI session at it: *"Read `~/Documents/linkzly-projects/process-templates/README.md`, then `docs/<slug>/progress.md` (if present) and `feature.md`. Continue from Next actions."*
3. Everything else — stages, gates, decisions, handoffs — is in [`README.md`](./README.md).

## Updating the process

Edit templates/README here (the master). Already-scaffolded features keep their copies as-is — the process is versioned by when a feature started, which is fine; don't retro-fit old folders unless a retro demands it.
