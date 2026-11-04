# A compact evidence-aware record

This invented `csv-export` example has two delivery tickets and one resolved prototype. A QA engineer reported an earlier passing test in a ticket comment; the current writer inspected code but did not rerun it. A memory benchmark and an accepted rate-limit change remain incomplete. The planning notes were in `.scratch/csv-export/`, which is not in git, so the record states their conclusions and never points at them.

## `docs/csv-export/feature-docs/overview.md`

```markdown
# CSV Export

> Summary: Analysts download filtered reports as CSV from the report toolbar.
> Feature docs: the tracked record of this feature. Updated: 2026-10-06
> Source: the spec, two tickets and a buffering prototype from local planning notes (not in git); their conclusions are recorded here.

## Problem

Analysts copy report rows into spreadsheets to share results with colleagues who do not use the application. Manual copying is slow and can lose the active filters, making the spreadsheet disagree with the report the analyst reviewed.

## Solution

The toolbar offers a CSV download for the current report and its selected filters. This preserves the familiar report workflow while producing a file recipients can open in their spreadsheet application. Delivery of the complete agreed slice remains partial; the outstanding acceptance checks are recorded in ticket 01.

## What was built

| Capability | Where (`path/file`) | Notes |
|---|---|---|
| Export endpoint uses the report's filter query | `src/api/reports/export.ts` | Code inspected; acceptance evidence in ticket 01 |
| CSV writer streams rows | `src/reports/csv-writer.ts` | Code inspected; decision D1 |
| Toolbar exposes the download action | `src/ui/report/Toolbar.tsx` | Code inspected; ticket 02 |
| Middleware enforces an export rate limit | `src/api/middleware/rate-limit.ts` | Observed setting differs from accepted intent; D2–D3 |

## How it fits together

The endpoint delegates filter construction to the existing report query builder and row formatting to the CSV writer. The toolbar submits the current filter values to that endpoint. Changes to report filters therefore need review at the shared query boundary as well as the export acceptance criteria. The rate-limit middleware is a separate constraint; its current value is recorded in D3.

## Testing

Ticket 01 records a historical passing API check, attributed to its source and not rerun in this review. Code inspection establishes the present call paths and toolbar state handling. It does not establish large-report memory use or current runtime success. Ticket 01 retains the required benchmark and rate-limit gap; ticket 02's static criterion is supported by inspection.

## Out of scope

Excel-format files and scheduled exports were explicitly excluded; see D4 for the recorded scope rationale.

## Not built yet

Ticket 01 remains partial. Read its unchecked criteria for the exact implementation and verification gaps before treating the export slice as complete.

## Glossary

Terms this feature introduces. Project-wide terms live in the repo glossary and are not repeated here.

**Export**:
One CSV file of a report's rows, produced with the filters active when the analyst asked for it.
_Avoid_: Download (that is the browser action), dump, extract

**Export limit**:
The number of exports one user may start per minute; set by the rate-limit middleware (D2, D3).
_Avoid_: Throttle, quota
```

## `docs/csv-export/feature-docs/decisions.md`

```markdown
# CSV Export — Decisions

> Status: Accepted (recorded agreement), Proposed (unaccepted option), Observed (implementation without recorded agreement), or Superseded by Dn.
> The table is the index; each decision has a section below. Superseded decisions stay.

| # | Decision | Status | Date |
|---|---|---|---|
| D1 | Stream rows rather than build the whole CSV in memory | Accepted | 2026-09-29 |
| D2 | Allow ten exports per user per minute | Accepted | 2026-10-02 |
| D3 | The middleware currently allows five exports per minute | Observed | Unknown |
| D4 | No Excel files and no scheduled exports | Accepted | 2026-09-29 |

## D1 — Stream rows

**Decision:** The CSV writer streams rows to the response instead of building the file in memory.
**Why:** A prototype that built the whole file used 1.2 GB for a 400k-row report. That is design evidence, not a production memory result (ticket 01).
**Rejected:** Building the file in memory, for the reason above.
**Agreed by:** Tech lead, in the spec's implementation decisions, 2026-09-29.

## D2 — Ten exports per minute

**Decision:** Each user may start ten exports per minute.
**Why:** Not recorded.
**Rejected:** None recorded.
**Agreed by:** Product owner, in a comment on the export endpoint ticket, 2026-10-02.

## D3 — Five exports per minute in code

**Decision:** `src/api/middleware/rate-limit.ts` allows five exports per minute.
**Why:** Not recorded.
**Rejected:** None recorded.
**Agreed by:** No one; observed in the code. See Contested decisions.

## D4 — Manual CSV only

**Decision:** Excel-format files and scheduled exports are out of scope.
**Why:** Discovery limited the request to sharing the report an analyst is looking at.
**Rejected:** Excel output and schedules, deferred until someone asks for them.
**Agreed by:** Product owner, in the spec's scope section, 2026-09-29.

## Contested decisions

D2 and D3 conflict. The code allows five; the product owner agreed ten. No later agreement resolves this. Ticket 01 keeps the missing behavior open; D3 does not supersede D2.
```

## `docs/csv-export/feature-docs/tickets.md`

```markdown
# CSV Export — Tickets

| # | Ticket | What it delivers | Blocked by | Status | Date |
|---|---|---|---|---|---|
| 01 | Export endpoint | Download a filtered report within the agreed limits | None | partial | Unknown |
| 02 | Download button | Start an export from the report toolbar | 01 | delivered | Unknown |

## Acceptance criteria

### 01 — Export endpoint

- [x] Export uses the selected report filters — code inspected: `src/api/reports/export.ts`; historical test passed: `npm test -- export`, API filter cases, 2026-10-03, reported by the QA engineer; not rerun.
- [ ] A 400k-row export stays below 300 MB — runtime unverified; production-equivalent benchmark remains pending.
- [ ] Rate limit matches the accepted policy D2 — code inspected; implementation differs as recorded in D3.

### 02 — Download button

- [x] The toolbar contains a download action disabled while the report loads — code inspected: `src/ui/report/Toolbar.tsx`, handler and loading guard. This static criterion does not claim a browser interaction check.

## Discovery outcomes

| Question | Type | Outcome |
|---|---|---|
| Can the export build the file in memory? | prototype | No: 1.2 GB for 400k rows; led to D1 |
```

Ticket 02's dependency records the original implementation order, not a claim that ticket 01's remaining acceptance checks passed. The discovery row names the question instead of its local ticket number, which a teammate's clone does not have.

## Baseline and later reconciliation

After structural checking and semantic review, record the inspected implementation and test files explicitly:

```bash
bash scripts/feature-docs.sh check . csv-export
bash scripts/feature-docs.sh stamp . csv-export \
  --evidence src/api/reports/export.ts \
  --evidence src/reports/csv-writer.ts \
  --evidence src/ui/report/Toolbar.tsx \
  --evidence src/api/middleware/rate-limit.ts \
  --evidence tests/api/export.test.ts
```

The test file is tracked evidence of test coverage, not evidence that it passed in this session. Source comments preserve the attributed historical result. Future comments, map changes and answers are covered by source Markdown hashes; edits to the selected implementation/test files are covered by evidence hashes.

If the rate limit later changes and the benchmark passes, reconcile ticket 01 using the actual result and update D3's historical status only when the replacement decision is established. If scratch is missing, preserve its last source baseline with `stamp . csv-export --evidence-only`. If nothing changed, leave Updated and the manifest untouched.

An `IN SYNC` result means recorded baselines match. Ticket 01's `PARTIAL` reminder can remain: source equality does not complete its acceptance criteria.
