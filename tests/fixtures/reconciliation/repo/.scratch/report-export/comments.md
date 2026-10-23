# Review comments

2026-10-19, product, accepted: Keep commas in v1 even for German workspaces. Existing downstream imports require commas. The proposed locale-dependent delimiter is deferred, not accepted for this release.

2026-10-19, engineering: The formatter currently emits ISO UTC dates. This does not satisfy the accepted workspace-date requirement. We have not agreed to drop that requirement.

2026-10-19, product, accepted: Withdraw ticket 03, the toolbar button, from this release; the existing report menu will invoke the formatter. Keep the ticket as history.

2026-10-20, engineering: There is no recorded rationale for the current buffering strategy. Do not infer a memory or speed advantage from it.
