# Discovery answers

Question: Must the separator follow the workspace locale?
Finding on 2026-10-17: Some spreadsheet imports default to semicolons in German locales. Proposed option: make the separator locale dependent. This was a research option, not a product decision. The later accepted review comment is authoritative.

Question: Is browser download plumbing part of this feature?
Finding on 2026-10-18: The existing report menu already handles file download. A separate toolbar button is unnecessary for the initial release; product acceptance is recorded in comments.md.

Question: Has large-report memory use been established?
Answer on 2026-10-20: No. No load-test result is available.
