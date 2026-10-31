# V4 vector progression — independent contract direction

Read-only design review, 2026-10-29, of
[proposal](shared-producer-v4-progression-design.md) SHA-256
`c61dfe44d1074e10037b01168eb0cc4a43fafc54c8c734bf2edaa9ad5ffae4d1`.
**Support domain implementation, with the narrow Host pre-put phase amendment
below required before guard2 admission is enabled.** No other concrete blocking
contract defect was found. No implementation, test, replay, effect or workload
was run here. The [plan](../../plan.md) owns overall acceptance. The accepted
public guard1/v3 first page remains exact.

## Minimum Host amendment

A positive revision/global-generation CAS proves the exact compared revision and
epoch; it does not prove the previous row was ready. Likewise a new successful
inline operation ID proves a fresh mutation, not that overwriting unknown pending
work was allowed. If Host simply accepts any positive-revision pending put as a
new live origin, an actual pending row could be overwritten with new pending
bytes and minted into fresh inference authority. This is a gap in the proposed
Host contract, not a reproduced current-v3 exploit or failure in implemented v4.

Use the existing CollectionStore/DocumentStage pre-put seam. For a v4 pending
claim, a trusted actual old-row observation must identify the exact current
Session/job/action/request, project/namespace/key, native epoch, revision and
logical hash. Expected revision zero requires actual absence. Positive revision
requires an exact closed v4 **ready** row with the matching canonical slot family
and ordinal. Actual pending, missing, malformed or mismatched state refuses.
Consume that observation only for the exact ensuing inline put; its CAS uses
the last checked epoch, without a new snapshot refreshing it after approval.
Failure/unknown cannot seed the live claim origin or reset batch poison.

This can be a caller-private pre-put check plus existing exact CAS, not a new
worker permission token, private MAC, control namespace or workflow. A shaped
worker receipt/read token is not the actual prior-phase observation. Root agreed
to implement this narrow amendment. It does not certify arbitrary out-of-protocol
operator rewrites or historical model truth.

The domain remains responsible for the stronger reuse proof: old ready work is
terminal in the advanced same Job's exact immutable group summary or the captured
selected prior Job/group, with matching page/cursor/source-set/selectors. Pin those
actual records to the same checked epoch before claiming. Pending never adopts or
overwrites; unselected/aborted ready without terminal proof waits for a separately
reviewed maintenance rule. Host need not reproduce the full group finalizer or
semantic chunker to check its fresh-origin/source boundary.

## Closed work and progress relation

Thirty-two canonical slots match at most 256 captured chunk positions, eight per
page. Reject leading-zero/alternate ordinal spellings. Guard2 keeps five fields,
permits only pending v4 and the exact `genproducer4.<partition>.<ordinal>` family,
and binds ordinal to `vector_cursor / 8`. Guard1 cannot admit v4 and guard2 cannot
admit old v3. Source-group cursor, vector cursor and complete vector count have
distinct meanings; the Host checks the exact next one-to-eight input-reference
slice and one/two batch inputs against authenticated complete source bindings,
declared chunk counts, ranges, IDs and raw/canonical hashes. This authenticates
stored byte authority, not independent semantic extraction/chunking truth.

The full closed pending shape retains current anchors, selectors, source-set and
seven-field references; new cursor/count/previous-ready fields are explicit.
Compact ready may replace repeated source bindings/references with input count,
ordered-reference digest and original pending revision/hash/actual operation,
while retaining job/root/catalog/selector/source-set/work cursors, previous page,
page descriptor and exact executed receipt flow. Validate that commitment against
the original pending/page before replacing it. A ready page is inspected without
another inference; it is progress, not an adoption or historical-model proof.
Losing original pending bytes from reused slots must not be described as lossless
receipt archival in the selected generation; original journals remain separate.

`value_put_inline_at` is a small internal client reuse of the existing request
and known/unknown receipt checks. Preserve last checked generation for both claim
and ready, exact page publication/anchors and original Session stage ownership.
A continuation follows only known page plus known ready, remains stage-free and
grants no effect by itself. Later invocation must authenticate current records,
make its own fresh claim and retain current source clocks. No TTL renewal,
unknown replay or caller-supplied committing operation ID is permitted.

## Bounds and remaining evidence

The proposal explicitly identifies two real design failures: naive full ready
8580 bytes exceeds 8192; unique per-work claims project 9410 live keys above 8192.
Compact ready and 32 reused slots address those specific failures. The recorded
6641/7357 pending and 3492/4072 compact-ready body/frame probes are static wide-field
measurements, not semantic/escaped/native maximum acceptance. Preserve refusal
when actual JSON/frame geometry exceeds existing limits.

Six native storage mutations plus four embedding effects per full page are a
proposal based on current inline/fused-part routes. The modeled 30758 permanent
IDs leaves only 2010 before facts, cleanup, imports and other new costs. Neither
that arithmetic nor 32-slot live-key conservation proves a whole-recipe fit.
Measure actual frames, 512-read/16-effect bounds, all physical/control/orphan
allocation, operation/journal/peak costs and known Session handoffs after the
recipe exists. Do not repeat an accepted aggregate merely to present estimates
as measured capacity.

Focused implementation qualification should include nonzero/tail cursors,
multiple sources/segments and page ordering, exact compact commitments, same-work
ready inspection, known terminal reuse, approval-lag epoch/CAS refusal, actual
pending overwrite refusal, unknown/no adoption, and unchanged guard1/v3 behavior.
Bounded facts, group assembly/append, final selection, full accounting/capacity,
acquisition, GC/migration and Word quality remain necessary separate sections.
