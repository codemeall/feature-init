# Converting existing docs

Read all supplied material before mapping it into the three feature documents. Verify implementation and acceptance claims using the evidence rules in the skill. Existing records may preserve accepted intent even where current code differs.

## Old feature-init folders

Write into `docs/<feature>/feature-docs/` beside existing `feature.md`, `plan.md` and `progress.md` files.

| From | To |
|---|---|
| `feature.md` Why, What, Users | Overview Problem and Solution |
| Scope/MVP rows | Overview capabilities supported by inspected code; ticket criteria for remaining work |
| Fast-follow/Not doing | Tickets when still committed; decisions when explicitly excluded, with overview links |
| Decisions | Decisions table, retaining IDs, recorded rationale and Accepted/Proposed state |
| Acceptance criteria | Tickets, assessed independently of old checkbox state |
| `plan.md` Contracts | Overview contracts, distinguishing current implementation from accepted intent |
| Milestones | Ticket rows retaining IDs such as M1 or M3.1 |
| Risks | Decisions only when a risk informed a significant choice |
| `progress.md` Findings | Their owning file, with the appropriate evidence and provenance |
| Done/Left, sign-offs | Ticket evidence or gaps; status follows the criteria, not the old heading |
| Verification notes | Dated ticket evidence, attributed and marked not rerun unless repeated now |

Preserve a relevant Proposed/Open choice or unresolved disagreement. Use Observed for a choice evident only in implementation. A missing rationale is Not recorded; a missing historical date is Unknown.

## Other inputs

A `.scratch` spec and tickets after full or partial implementation use WRITE. For maps, typed discovery tickets, answers and comments, read `sources.md`.

For loose notes, a design doc, README section or wiki page, map user needs and current behavior into overview, choices and trade-offs into decisions, and work units/acceptance into tickets. Copy only material conclusions. If no delivery slices exist, say None in tickets rather than inventing historical work.

When sources disagree, distinguish the implementation claim from the intent or verification claim. Record unresolved material conflicts with both origins. A source's removal is not cancellation.

## Finishing

- Convert code citations to verified repository-relative paths, including package prefixes.
- Name the original paths and conversion date on the overview's Source line. These references identify provenance; keep the actual material conclusion in the tracked record.
- Run `check`. Stamp with explicit evidence files and `--source <dir>` for a continuing local source folder, or `--evidence-only` without one. On a first stamp, the latter creates a source-null manifest; an existing source baseline is preserved instead.
- Report agent instructions pointing at originals so they can be repointed. Leave originals intact unless removal is authorized.
