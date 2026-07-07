# Feature Process — 3 Docs, Idea to Release

> Master home of the development process and templates, kept outside the repos so it can serve any project in `linkzly-projects/`. Every feature = one folder `docs/<feature-slug>/` inside the target repo, holding exactly **3 docs** copied from [`templates/`](./templates/). Built for fast AI/human pickup and efficient context use.

## The 3 docs

| Doc | Holds | Changes when |
|---|---|---|
| `feature.md` | What & why: problem, concept, scope, decisions table, acceptance criteria | Scope or a decision changes |
| `plan.md` | How: contracts to freeze, milestones with exit gates, release checklist, risks | The plan itself changes |
| `progress.md` | Live state: now / done-left / verified findings / open questions / next / sign-offs | Every state change |

**Read order (human or AI): `progress.md` → `feature.md` → `plan.md`.**

## Lifecycle = the Stage field in `feature.md`

`Idea → Discovery → Design → Build → Released`, three gates, recorded in `progress.md` Sign-offs:

1. **Idea → Discovery** — only `feature.md` exists, only "Why" filled (about a page). Product owner: worth investigating?
2. **Design approved** — all 3 docs filled; every decision row Accepted; contracts frozen. Reviewers get `progress.md` + the decisions table, 3–5 days async, one 30-min sync max.
3. **Released** — release checklist in `plan.md` done; retro note in `progress.md` after 2–4 weeks.

## Starting a feature (in any repo)

```bash
mkdir <repo>/docs/<feature-slug>
cp ~/Documents/linkzly-projects/process-templates/templates/feature.md <repo>/docs/<feature-slug>/
# fill "Why" only → gate 1; copy plan.md + progress.md when discovery starts
```

**Existing-feature improvements:** no new folder. Big change → new decision row + milestone in that feature's docs. Small fix → ticket + PR, no docs.

## Working with AI agents

- Start any session with: *"Read `~/Documents/linkzly-projects/process-templates/README.md`, then `docs/<feature>/progress.md`, and continue from Next actions."*
- **Handoff on session/token limits:** before a session ends, have the agent update `progress.md` — exactly what's done, what's half-done and in which file, what's next. The next agent (or developer) resumes from that file alone; the doc is the memory, not the chat.
- **Review with a fresh agent:** a second AI with no attachment to the draft verifies code citations and challenges decisions before approval.
- Commit code + the matching `progress.md` update in the same commit.

## Rules (these keep it working)

1. **Each fact lives in exactly one doc.** Cross-reference, never copy — duplication drifts and wastes context.
2. **Code-verify every claim** — cite `path/file.ts` in scope tables and findings. Corrected wrong assumptions (❌) are the most valuable rows; keep them.
3. **No implementation from a non-Accepted decision.** Exit gates, not dates; M(n+1) waits for M(n)'s gate.
4. **Complete beats short.** Write everything the work needs — cut filler and repetition, never substance. If a doc grows past a few hundred lines, that's a signal to split the feature, not to trim the doc.
5. **Tables over prose** where structure fits; one-line decision rationale, expand only contested decisions.
6. **`progress.md` holds current state only** — superseded detail lives in git history. Tickets are cut only from design-approved docs.
7. Process friction found after release → improve this folder (it's the single master; repos don't carry copies).
