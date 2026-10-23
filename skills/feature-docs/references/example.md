# A compact evidence-aware record

This invented `csv-export` example has two delivery tickets and one resolved prototype. Source comments report an earlier passing test; the current writer inspected code but did not rerun it. A memory benchmark and an accepted rate-limit change remain incomplete.

## `docs/csv-export/feature-docs/overview.md`

```markdown
# CSV Export

> Summary: Analysts download filtered reports as CSV from the report toolbar.
> Feature docs: the tracked record of this feature. Updated: 2026-10-06
> Source: `.scratch/csv-export` (local source; conclusions are preserved here)

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
```

## `docs/csv-export/feature-docs/decisions.md`

```markdown
# CSV Export — Decisions

| # | Decision | Why (alternative rejected) | Source | Status | Date |
|---|---|---|---|---|---|
| D1 | Stream rows rather than buffer the whole CSV | Prototype reported 1.2 GB for a buffered 400k-row export; this is design evidence, not a production memory result | spec Implementation Decisions; prototype 03 Answer, linked from map.md | Accepted | 2026-09-29 |
| D2 | Allow ten exports per user per minute | Not recorded | ticket 01 Comments: user acceptance | Accepted | 2026-10-02 |
| D3 | Current middleware allows five exports per minute | Not recorded | inspected src/api/middleware/rate-limit.ts | Observed | Unknown |
| D4 | Exclude Excel-format files and scheduled exports | Discovery limited the request to manually sharing current report results | spec Out of Scope | Accepted | 2026-09-29 |

## Contested decisions

D2 and D3 conflict. The inspected implementation establishes five; the accepted comment establishes intent for ten. No later agreement resolves this. Ticket 01 retains the missing accepted behavior; D3 does not supersede D2.
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

- [x] Export uses the selected report filters — code inspected: `src/api/reports/export.ts`; historical test passed: `npm test -- export`, API filter cases, 2026-10-03, reported in ticket 01 Comments; not rerun.
- [ ] A 400k-row export stays below 300 MB — runtime unverified; production-equivalent benchmark remains pending.
- [ ] Rate limit matches the accepted policy D2 — code inspected; implementation differs as recorded in D3.

### 02 — Download button

- [x] The toolbar contains a download action disabled while the report loads — code inspected: `src/ui/report/Toolbar.tsx`, handler and loading guard. This static criterion does not claim a browser interaction check.

## Discovery outcomes

| Source | Type | Outcome |
|---|---|---|
| 03 — Buffering experiment | prototype | Resolved design question; conclusion preserved in D1 |
```

Ticket 02's dependency records the original implementation order, not a claim that ticket 01's remaining acceptance checks passed. The discovery row preserves navigation without duplicating D1's rationale.

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
