# Bounded shared-producer progression proposal — 2026-10-29

**Proposal for review, not an enabled contract.** The accepted
[public v3 first page](shared-producer-public-adoption-independent-review.md)
stays unchanged. This design adds no Core/native primitive, quota, provider or
source permission. Worker implementation waits for Root/Shared agreement; Root
owns any Host guard extension. Complete producer, capacity and recovery acceptance
remain in the plan.

## Work item and bounded claims

One work item produces the next one-to-eight vectors in one captured group of
one-to-eight complete Source bundles. Existing `cursor` keeps its Job meaning:
source-group offset, a multiple of eight in 0..992. New `vector_cursor` is the
offset in the ordered flattened `(source_index, chunk_index)` sequence, a multiple
of eight in 0..248. `vector_count` is the sum of captured source-head chunk counts,
at most 256. A page covers exactly `min(8, vector_count-vector_cursor)` consecutive
positions, and ordinal is `div(vector_cursor,8)`. No chunk/segment is skipped,
split, trimmed or renumbered. Source eligibility and original clocks are checked
before claim and each batch; Host makes the existing final source admission.

Use **32 reusable claim slots**, not a permanent new key for every work item:
`genproducer4.<partition>.<ordinal>`, ordinal 0..31. Body job ID, source cursor and
vector cursor identify the exact work item; actual row revision/hash distinguish
slot epochs. A separate work-id field is unnecessary. Root's original v3 key
`genproducer.<partition>` and guard version 1 remain unchanged.

A pending v4 record has all existing v3 claim fields, with version 4 and recipe
`ipse.evidence.shared_producer.pages.v4`, plus exactly:

| Field | Relation |
| --- | --- |
| `vector_cursor` | Eight-aligned offset below `vector_count` |
| `vector_count` | Complete captured group chunk count, not a caller budget |
| `previous_ready` | Null at zero; otherwise exact preceding ready key/revision/sha256/byte_count |

`inputs` retain the seven existing fields `[source_index, chunk_index, chunk_id,
canonical_input_sha256, raw_sha256, start_byte, end_byte]`. They must match the
exact ordered slice starting at `vector_cursor`, and original authenticated
Source.text bytes. All captured source bindings, selection, catalog/floor,
Job/root and source-set digest keep their current meanings. Pending status has
no page or receipts and never supplies an inference retry/adoption token.

The **ready v4 closed shape differs explicitly from pending** at the same key.
Keep every common job/catalog/root/selector/cursor/source-set/previous-ready field,
status, page descriptor and actual per-call receipts. Replace repeated
`source_bindings` and `inputs` with:

| Field | Value |
| --- | --- |
| `claim` | Original confirmed pending `revision`, `sha256`, actual committing `operation_id` |
| `input_count` | 1..8, exactly this cursor's expected span |
| `input_refs_sha256` | Raw SHA-256 of complete ordered seven-field input-reference JSON |

Before writing ready, verify page rows against those exact source chunks and all
receipt canonical/raw input hashes. This compact ready is a durable progress
record, not independently authenticated historical model provenance. Original
pending bytes, inference requests and receipts remain in their original Session
journals; reusing a slot does not preserve every old receipt in the selected
generation. Any future stronger historical provenance needs its own versioned
commitment and complete cost accounting.

## Slot reuse and known continuation

An absent slot may be claimed. A ready slot for this exact work item is inspected
without another inference. A ready slot from a completed earlier group is reusable
only after authenticating a current terminal reference: for the same Job, the
advanced Job cursor and its exact immutable group summary; for a later Job, the
captured selected root's manifest/group header. The terminal group must include
the exact old page under matching cursor/source-set/selectors. Reuse then uses
that slot's exact old revision in the new claim CAS. An unselected/aborted ready
slot without such proof refuses until an explicit maintenance rule is reviewed.

Pending slots are never overwritten, adopted or resumed. A failed or
unknown inference/storage result stops with no continuation. Active native stage
slots remain original-Session owned. A complete next-work token is emitted only
after known page publication and known ready replacement, with exact Job,
source/vector cursor and previous-ready descriptor. It authorizes no effect by
itself: the next invocation reauthenticates current records and commits its own
new pending claim before inference. No implicit replay or Source TTL renewal.
Explicit inspection/recovery after unknown remains separate from continuing a
known ready work item.

## Existing transport and final generation

Use the existing `value.put_inline` once for the pending claim, existing
`value.write_parts` with `publish: true` for the inactive immutable vector page,
and a separate `value.put_inline` for compact ready. The existing Collection
client already uses these routes for `:value_write`. One narrow internal client
entry is needed for claim/ready: `:value_put_inline_at` sends the existing request
at the **last checked native generation**, without obtaining a fresh snapshot
between proof and CAS. It validates the same body/frame limits and reuses the
known/unknown inline receipt checks. This is no new Host API or atomic primitive.
Ready checks all captured anchors and exact published page before that pinned CAS.

At 1,024 dimensions, eight rows occupy approximately 45 KiB. Two 6,144-byte parts
per complete bounded SDK frame require four mutations; final fused publication
releases the one occupied stage. Thus a full work item uses six native mutations
(claim 1, page 4, ready 1), four embedding calls and at most ten effects. All
actual frames, read budgets and result pages must be counted in the implemented
fixture; this arithmetic is not a measured producer run. Bounds remain 512 reads,
16 effects, 16 transport slots, 8,192 live keys and 32,768 permanent native IDs.
Escaped-envelope/body refusal is preserved, never repaired by truncation.

`Generation.vector_page/6` must accept aligned nonzero starts and canonical page
ordinals while producing identical bytes for existing start zero. A bounded
vector-page decoder/assembler must reconstruct every canonical chunk/vector and
reject gaps, duplicates, reordered pages, bad finite floats, input mismatch and
wrong source/model/recipe. Existing `Generation.pack_group` then determines the
canonical header/pages; every previously produced page must equal that result.
The private `Job.append_plan`/controller can reuse exact existing vector values,
validate all immutable prerequisites and atomically advance Job/captured-catalog
metadata. Selection still waits for the existing finalizer's final root CAS.

Group packing currently requires 1..32 valid facts for **each** source. The vector
progression does not invent empty facts or claim group completion. Bounded facts
production, its source/inference admission, durable inputs and receipts, internal
group assembly/append wiring and public progression remain necessary sections.
No oversized group is sent through one SDK invocation argument.

## Concrete measurements and full-profile reservations

The retained schema/frame probes use fabricated wide fields, not semantic source
authentication or storage effects. Eight bindings, safe-integer widths, a
128-byte ASCII model and 64-byte profile produce:

| Candidate | Logical JSON | Complete SDK frame | Existing transport validation |
| --- | ---: | ---: | --- |
| Full pending plus cursors/previous | 6,641 B | 7,357 B | Accept |
| Full v3-style ready plus cursors/previous | 8,580 B | 9,386 B | Refuse existing 8,192-byte logical/string bound |
| Proposed compact ready | 3,492 B | 4,072 B | Accept |

These conservative probes used a longer unique-work key than the proposed slot
key. They do not replace maximum escaped-scalar/current-producer measurements.
Both probe logs, including the refusal, are retained under `_build`.

The [prior complete private recipe ledger](document-whole-recipe-ledger.md) has
5,277 live initial / 6,910 retained rebuilt records. Unique per-job/page claims
would add 2,500 after initial+rebuild, reaching 9,410 and violating the live-key
ceiling. Thirty-two reusable slots avoid that specific permanent growth; pending
liabilities and terminal-proof/maintenance records still need actual accounting.

For its exact 10,000-vector geometry, 1,250 vector pages formerly used five
mutations each (four fused prepares plus consume). Six mutations per newly
inferred ready page would add 1,250 per build, if all other units and reuse stay
exact. That projects 19,890 initial + 10,868 rebuild = 30,758 permanent IDs before
new fact-claim/producer/cleanup/import costs. This leaves only 2,010 IDs under
32,768; it is **not a whole-recipe fit claim**. Full raw/lexical/shared/fact producer,
replacement/GC/migration, native object/control/orphan allocation and journal
events/bytes must be remeasured after the actual recipe exists. Original journals
already exceed one Session's limits; known stage-free handoff points remain
mandatory. No aggregate ledger or native capacity run was restarted for this design.

## Root-owned Host addition for review

Proposed guard version 2 keeps the existing five fields: `version`, `claim_key`,
`claim_revision`, `claim_sha256`, `batch_index` (0..3). It permits only the fixed
v4 slot family and pending-v4 body/key ordinal relation. Embedding.create remains
version 2, with mandatory expected selection and one/two inputs; result v2 and
legacy guard1/v3 behavior stay exact. Host extends its narrow ordered-position
check to the eight positions starting at authenticated `vector_cursor`, verifies
captured total chunk count, and retains the existing exact ranges/hash/chunk-ID
relation. It need not implement domain chunking or group-finalization policy.

Live Session claim admission must recognize the known successful **single
`value.put_inline`** action, including a safely reused positive expected revision,
and bind its real action operation ID to the retained claim. No worker operation
ID is accepted. Existing next-batch spending, failed/unknown poisoning, trusted
UTC after blocking authentication, current operator identity/route and plain
EgressGate final one-use admission remain mandatory. This addition is not yet
implemented or enabled; no new public route is opened by this proposal.
