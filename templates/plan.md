# <Feature> — Plan

> Owner: <name> · Updated: <YYYY-MM-DD>
> How & in what order. Progress ticks live in `progress.md`; this file changes only when the plan itself changes.
> Rule: M(n+1) never starts before M(n)'s exit gate.

## Contracts (freeze before parallel work)

Only what parallel workstreams build against. Unresolved items marked **Proposed** — confirming them is part of M0's gate.

**Data model**

| Table | Columns / semantics | Open |
|---|---|---|

**API**

| Endpoint | Method | Req/Res shape |
|---|---|---|

**Shared artifacts** (schemas/types both sides import or duplicate + CI-sync): what, where it lives, which milestones it gates.

## Milestones

### M0 — Design closure & spikes
- Spikes to de-risk unknowns (each ends in written findings, logged in `progress.md`)
- Confirm all Proposed contract items
- **Gate:** findings written + contracts frozen

### M1 — <workstream>
- Work items…
- **Gate:** …

### Mn — Release
- Feature flag: <name, location> · Rollout: internal → beta orgs → % → GA
- Checklist: acceptance criteria pass in staging ☐ · migrations reversible ☐ · monitoring/alerts ☐ · rollback path ☐ · user docs + changelog ☐ · support briefed ☐ · plan gating verified ☐
- **Gate:** checklist done → retro note in `progress.md` after 2–4 weeks → Stage: Released

## Sequencing

Which milestones run in parallel, and which contract artifact gates each pairing.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
