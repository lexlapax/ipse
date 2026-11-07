# Bounded fitting-note selection — 2026-11-06

Historical synthetic evidence. The [plan](../../plan.md) owns current status;
the [operator procedure](../../operator/knowledge-permissions.md#use-bounded-current-note-recall)
owns current usage. This does not qualify a populated notebook or the complete
notes journey.

The seed worker no longer stops just because the full set read so far exceeds
the allocation: a later smaller note may fit the existing greedy projection.
Discovery still stops at the existing projection, host read, dependency and
source-proof bounds and retains final root verification. The worker skips
protected value reads when the allocation is below the host-framed lower bound
for even an empty first note item. That lower bound is not a promise that a
complete note fits. Additional successful reads remain causal dependencies even
when their notes are omitted, so a larger union can increase latency or refuse
later delivery.

The first synthetic mock run reported 30 of 32 inner controls passing. Its
later-small-note fixture chose an allocation too small for the whole framing,
and the larger fixture expected 86 calls instead of the actual 87. The fixtures
were corrected to derive the allocation from the real projection and account
for the extra call. An intervening line-selected invocation excluded the only
outer test; its zero exit is not a pass. The subsequent whole-file invocation
passed its one outer wrapper, which requires exactly 32 passing inner controls,
zero skips and zero failures. These are in-memory synthetic host replies, not
an actual protected-host or installed journey. They did not access the declined
retained notebook or replace its declined acceptance check.

Source review found no concrete authority bypass in the change. A release can
still fail when an extra read's source is no longer available or the host's
separate byte limits are exceeded. Arbitrarily sparse coverage, final-use
absence revalidation, actual-host qualification and the integrated notes
workload remain open.
