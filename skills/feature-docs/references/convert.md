# Converting existing docs into feature docs

Where each kind of existing material lands in `docs/<feature>/feature-docs/`. Anything with no row here goes where its content fits: what exists → `overview.md`, why → `decisions.md`, units of delivered work → `tickets.md`.

## Old feature-init folders (`feature.md`, `plan.md`, `progress.md`)

These sit directly in `docs/<feature>/`. Write the new docs into `docs/<feature>/feature-docs/` beside them.

| From | To |
|---|---|
| `feature.md` Why, What, Users | `overview.md` Problem, Solution |
| `feature.md` Scope, MVP rows | `overview.md` What was built, after checking each row against the code |
| `feature.md` Fast-follow, Not doing | `overview.md` Out of scope, or Not built yet when it was committed |
| `feature.md` Decisions | `decisions.md` rows, source `converted`, keeping their original numbers so existing references still resolve. `Accepted` stays; `Proposed` or `Open` becomes a row only if the code shows which way it went |
| `feature.md` Acceptance criteria | `tickets.md` Acceptance criteria, under the milestone that delivered them |
| `plan.md` Contracts | `overview.md` How it fits together, as the code has them now |
| `plan.md` Milestones | `tickets.md` rows, one per milestone under its own id (`M1`, `M3.1`): `delivered`, `planned` or `withdrawn` |
| `plan.md` Risks | `decisions.md`, only where a risk drove a choice: the mitigation is the decision. New rows continue the numbering |
| `progress.md` Code-verified findings | `overview.md` What was built or How it fits together. A corrected assumption (❌) becomes a `decisions.md` row |
| `progress.md` Done / Left | `tickets.md` status column, set from the code. A box left unticked for work the code now shows is `delivered`; say so under the table |
| `progress.md` Verification notes | `overview.md` Testing, dated, marked as not re-run |
| `progress.md` Now, Next actions, Sign-offs | Dropped. Unfinished work goes to `overview.md` Not built yet |

## A `.scratch/<feature>/` spec and tickets, feature already built

This is WRITE. Follow those steps and `stamp` at the end.

## Loose notes, a design doc, a README section, a wiki page

| Content | To |
|---|---|
| The problem and the pitch | `overview.md` Problem, Solution |
| Behaviour the code has | `overview.md` What was built, with the file |
| Behaviour the code lacks | `overview.md` Not built yet, or Out of scope when it was dropped |
| "We chose X because Y", trade-offs, rejected options | `decisions.md`, source `converted`. Date from the doc, or from the commit that made the change |
| Task lists, phases, milestones, changelog entries | `tickets.md` rows |
| How to run or test it | `overview.md` Testing |

When a doc gives no reason for a choice, write "not recorded" in the Why column and keep the row.

## Paths

Old docs often cite paths from inside a package (`src/api/push-test.ts`). Rewrite each as a path from the repo root (`services/push/src/api/push-test.ts`) after confirming the file exists; `status` checks them in that form.

## Several documents for one feature

Read them all before writing. Where two disagree, the code decides. Record the disagreement as one `decisions.md` row whose Why names both versions.

## Finishing

- The `Source:` line of `overview.md` names every converted path and today's date: ``converted from `docs/csv-export/feature.md`, `plan.md`, `progress.md` on 2026-10-06``.
- A converted folder has no `sources.json` unless its origin is a local source folder that will keep changing. `status` then reports it as `UNTRACKED`, which is correct.
- Search the repo's agent instructions (`AGENTS.md`, `CLAUDE.md`, `docs/agents/`) for pointers to the original files, and list them for the user. They need repointing at the feature docs before the originals go.
- The originals stay until the user says to delete them.
