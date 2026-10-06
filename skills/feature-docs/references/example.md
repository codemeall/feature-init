# A filled set of feature docs

An invented feature, `csv-export`, written from `.scratch/csv-export/spec.md` and three ticket files. It shows the level of detail to aim for. The second half shows the same docs after a sync.

## `docs/csv-export/feature-docs/overview.md`

```markdown
# Csv Export

> Summary: Any report downloads as a CSV file with the active filters applied.
> Feature docs: the tracked, as-built record of this feature. Updated: 2026-10-06
> Read order: this file → `decisions.md` → `tickets.md`. Each fact lives in one of the three.
> Source: `.scratch/csv-export` (local and untracked; `sources.json` records the last sync)

## Problem

Analysts copy rows out of the report table by hand to get them into a spreadsheet. Reports over a few hundred rows are not practical to copy.

## Solution

A Download CSV button on every report exports the rows the analyst is looking at, with the active filters applied, as a file that opens directly in a spreadsheet.

## What was built

| Capability | Where (`path/file`) | Notes |
|---|---|---|
| Export endpoint streams a report as CSV | `src/api/reports/export.ts` | Honours the same filter params as the report query |
| Rows are written in batches of 1,000 | `src/reports/csv-writer.ts` | Keeps memory flat for large reports |
| Download button on the report toolbar | `src/ui/report/Toolbar.tsx` | Disabled while a report is loading |
| Export is limited to 5 per user per minute | `src/api/middleware/rate-limit.ts` | Returns 429 with `Retry-After` |

## How it fits together

The endpoint reuses `buildReportQuery` (`src/reports/query.ts`), so a filter added to reports is exported with no change here. `csv-writer.ts` owns quoting and the header row; nothing else formats CSV.

## Testing

Tested at the HTTP seam: `tests/api/export.test.ts` requests an export and parses the response. Run with `npm test -- export`.

## Out of scope

- Excel (`.xlsx`) output: CSV opens in every spreadsheet and needs no library.
- Scheduled or emailed exports: no one asked for them in discovery.

## Not built yet

Nothing.
```

## `docs/csv-export/feature-docs/decisions.md`

```markdown
# Csv Export — Decisions

| # | Decision | Why (alternative rejected) | Source | Status | Date |
|---|---|---|---|---|---|
| D1 | Stream the response instead of building the file in memory | Largest report is 400k rows (buffering it took 1.2 GB in a prototype) | spec | Accepted | 2026-09-29 |
| D2 | Export reuses the report query builder | One definition of each filter (a separate export query would drift) | spec | Accepted | 2026-09-29 |
| D3 | Test at the HTTP seam only | Covers query, writer and headers in one test (unit-testing the writer alone missed a header bug in the prototype) | spec | Accepted | 2026-09-29 |
| D4 | Rate limit of 5 exports per user per minute | A double-click started two 400k-row exports during review (no limit) | fleet run csv-export | Accepted | 2026-10-03 |
| D5 | Dates are written as ISO 8601 UTC, not in the user's locale | The spec said "as shown on screen"; locale formats do not sort in a spreadsheet | as-built | Accepted | 2026-10-04 |
```

## `docs/csv-export/feature-docs/tickets.md`

```markdown
# Csv Export — Tickets

| # | Ticket | What it delivers | Blocked by | Status | Date |
|---|---|---|---|---|---|
| 01 | Export endpoint | A filtered report downloads as CSV from the API | None | delivered | 2026-10-02 |
| 02 | Download button | The analyst exports from the report toolbar | 01 | delivered | 2026-10-03 |
| 03 | Export rate limit | A user cannot start more than 5 exports a minute | 01 | delivered | 2026-10-04 |

## Acceptance criteria

### 01 — Export endpoint

- [x] The response has the same rows as the report with the same filters
- [x] A 400k-row report exports without the server exceeding 300 MB

### 02 — Download button

- [x] The button is on every report and disabled while the report loads

### 03 — Export rate limit

- [x] The sixth export within a minute returns 429 with `Retry-After`
```

## The same docs after a sync

A week later `to-spec` changed the delimiter decision and `to-tickets` added ticket 04. Ticket 04 is not implemented yet. `status` printed:

```text
csv-export  DRIFT  .scratch/csv-export changed since 2026-10-06
  ADDED    issues/04-semicolon-delimiter.md
  CHANGED  spec.md
```

and `diff` showed the changed lines of `spec.md`:

```text
CHANGED  .scratch/csv-export/spec.md
--- synced/spec.md
+++ current/spec.md
@@ -31,3 +31,3 @@
 ## Implementation Decisions
 
-- Fields are always separated by commas
+- The delimiter follows the workspace locale setting (comma or semicolon)
```

`decisions.md` gains a row. Had an earlier row recorded "always commas", its status would become `Superseded by D6`:

```markdown
| D6 | Delimiter follows the workspace locale setting (comma or semicolon) | German customers' Excel splits on semicolons (always-comma opened as one column) | spec | Accepted | 2026-10-13 |
```

`tickets.md` gains a `planned` row, because the code does not show it:

```markdown
| 04 | Semicolon delimiter | Exports open correctly in locales that use `;` | 01 | planned | 2026-10-13 |
```

`overview.md` "What was built" is unchanged, "Not built yet" lists ticket 04, and `Updated:` becomes 2026-10-13. Then `stamp` records the new hashes. From then on `status` prints `PLANNED  04 Semicolon delimiter` under the feature as a reminder. When ticket 04 ships, the next sync moves it to `delivered` and adds its row to "What was built".

## When the code moves

A refactor later renames `src/reports/csv-writer.ts` with no spec change. `status` catches it because `overview.md` cites the path:

```text
csv-export  STALE  .scratch/csv-export is unchanged since 2026-10-13, but the docs cite files that are gone
  MISSING  src/reports/csv-writer.ts (cited in overview.md)
```

`git log -1 -- src/reports/csv-writer.ts` names the commit that moved it. The row's path is corrected to the new file, and `status` is clean again.
