# Report export

## Problem
Analysts manually copy filtered report rows into spreadsheets.

## Accepted requirements — 2026-10-18
- Export the visible rows as CSV, retaining their order.
- Use commas for the first version.
- Format dates the same way they appear in the analyst's workspace.
- A 400,000-row export must remain below 300 MB peak process memory.

## Implementation decisions
D1: Reuse the filtered report rows. A separate filtering implementation could disagree with the screen. Accepted by product and engineering on 2026-10-18.
D2: Start with CSV rather than XLSX because analysts already import CSV. Accepted on 2026-10-18.

## Testing decisions
Check output quoting and visible-row order at the formatter seam. Keep the large-report memory acceptance as a separate runtime check.

The speculative delimiter discussion in research.md was resolved in comments.md. Read both before describing locale support.
