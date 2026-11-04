# Focused source regression repairs — 2026-11-04

This historical record follows the failed
[combined source regression](combined-source-regression-20261104.md).
The [plan](../../plan.md) owns current acceptance and the
[testing chapter](../../developer/testing.md) owns verification procedures.
These results cover focused repairs across explicitly different source freezes.

The original frozen combined source run finished with 3,906 actual passes out of
3,932 test results, 26 failures, 52 invalid cases, 128 skips and 121 exclusions.
The installed ExUnit formatter counts invalid, skipped and excluded cases
separately. All original source, runtime, catalog/helper, link and complete file
path-set postchecks passed. This failed run remains preserved; the following
focused results do not replace it with a claim that a new full suite passed.

The first fresh repair run executed all 78 failed or invalid case IDs using Mix's
retained failure manifest: 74 passed, four failed and none remained invalid
(1,258.1 seconds). Thus all 52 previously invalid cases reached and passed their
real checks. A separate 40-test supplement passed (83.2 seconds), covering the
whole Setup and Errors files, pending-correction consistency and public refusals,
and existing native Session correction behavior. It did not qualify the committed
CLI pending-correction branch.

The repaired causes were prompt ordering based on actual sandbox availability,
service mappings outside the selected instance, unsupported `/dev` fixture
workspaces, a dense inert manifest 13 bytes above its unchanged 16 KiB bound,
and arbitrary correction-reason inspection. Fixes preserved production policy,
source guards, limits and native refusal behavior. The three remaining
declaration failures came from copying unrelated untracked scratch trees, not
from Git trust or evaluation behavior. Switching only the two fixture source
listings to Git's tracked inventory matched the existing product source capture;
all three then passed on fresh roots (59.6 seconds).

The remaining A/B fixture had attempted a generic scan of a pending proposal,
which current containment correctly refuses. Its replacement creates a fresh
native literal A, authenticates an earlier root snapshot and literal read, and
then captures independent current source B. A concurrent write makes the earlier
root prerequisite stale. The test preserves the complete dependency union and
requires current-use refusal before consumer reservation or publication, unchanged
post-winner collection witness and accounting, Saved reconstruction and idle
reopening without replay. It passed once on the new combined runtime (17.4
seconds; 201 excluded), alongside all five new management-root consistency
controls (0.1 seconds).

All three focused stages passed source, runtime, catalog/helper and symlink
postchecks; complete source/runtime path-set comparisons also passed where
recorded. The shared native operator lock was unheld at each release. Across
these explicitly different freezes, all original 26 failure cases and 52 invalid
cases now have passing fresh relevant controls. A complete regression of the
final combined source remains a separate gate. A subsequent distinct
[same-ID follow-up](chat-same-id-followup-20261104.md) also passes; it is not
counted as part of these earlier focused stages.

Frozen source/runtime manifest SHA256 pairs:

- Original combined run: `c61cdbffb09c8d424e7ec15fcf8bb48232ae25c8e5a1a2931acbb4f2512bc858` / `94c34b8a9a18d597f5458a994bedfd1ef619afb72dd388a343fe1c63ec486914`.
- Failed/invalid repair run: `55d311f86591481ed95e91947bb9fcc770fe931b2f8f58d9e1e7fd3b9587423d` / `a4e4bede6bf717ca6a8fe8a6530ae53cebd56ba7a2bd5f9e38fb0916a32f305e`.
- Declaration repair: `557b4171ccf38622342b87cd86ca2979a6c3199e33e558a442bcc4b1dcceccef` / `a4e4bede6bf717ca6a8fe8a6530ae53cebd56ba7a2bd5f9e38fb0916a32f305e`.
- A/B plus five controls: `65ccffc09acd5d9f1c34f8e026cbe683a09cb8074902a685fdca4441f94ba582` / `bc2fe560bc906465651c038ffb99b0d0e9088eb0926117657f80b47b2a90a36a`.
