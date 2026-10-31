# Bounded shared producer v1 — 2026-10-29

This implementation contract follows the concrete public-producer gap in the
[whole-recipe ledger](document-whole-recipe-ledger.md). It adds no Core/native
API, quota, model service or provider fallback. Existing adapters, canonical
SHA/JSON, Collection stages and Generation codecs are reused. OTP modules and
the existing SDK already supply the required encoding, transport and storage;
there is no new common protocol framework or dependency.

The first section produces one canonical 1024-dimensional shared vector page
for the first at-most-eight chunks of a captured eight-source Job group.
Facts, remaining pages, group header/summary append and selected-root completion
remain subsequent required sections. It writes the actual shared `genvec`
layout, never a per-source vector layout. This explicit supported first section
does not redefine the full target or claim final public producer completion.

## Public boundary

An opt-in `collection-dense` Corpus preset adds existing `host.embedding` and
`host.results` capabilities to the existing document Collection preset. Old
presets/grants remain exact. Normal full-argument approvals apply to Collection
mutations and registered inference. It adds no model-completion capability.

`generation_produce` accepts exactly `store`, `version: 1`, `action: "page" |
"inspect"`, `embedding`, `job_id`, `job_revision`, `vector_selection` and
`fact_selection`. Selections are expected immutable bindings, not inference
receipts. Embedding must resolve to the explicitly configured registered host
profile; actual returned profile/model/selection hash must match the captured
expectation. No service, endpoint, billing mode or model is chosen implicitly.
The existing embedding request accepts no expected-selection guard. A changed
alias destination/model can therefore be approved and contacted before its
returned selection mismatch is detected. This post-response check prevents
publication and retains pending work; it is not a pre-egress selection pin.
No caller source bodies, vectors, filesystem paths, namespace, quotas, stages
or private continuation positions are accepted.

The producer derives catalog membership, group cursor, source/chunk identities,
complete source bundles, original typed locators and raw/canonical input hashes
from authenticated Collection reads and the current Job. It binds the exact
Job revision/id, catalog digest/floor and selected root revision/digest. The
captured Job must remain in `groups`, with the expected selections.

## Claim before inference

One `genproducer.<partition>` record has a closed versioned shape. Its pending
claim binds the Job/catalog/root/group/source-set and exact ordered input
identities. It is staged and selected with the existing generation CAS before
the first inference request. Stage contents and current anchor hashes/revisions
are checked at one pinned native generation immediately before that CAS.

Only the same in-memory invocation which receives the confirmed claim commit
can issue inference. A subsequent inspect/page invocation finding `pending`
reports non-resumable pending work and makes no inference request. Unknown,
denied, failed, malformed or mismatched inference/storage stops without a retry
token. Active Collection stages and Session-owned effect-result pages are
never adopted by another Session. Known complete page output is stage-free;
this first section refuses another page rather than pretending it implements
the remaining production state machine.

The existing Adapters embedding path sends at most two raw chunks per
`embedding.create` v2 request and reads bounded `effect.result.read` f32 pages.
It validates the complete vector hash, canonical input digest and finite
coordinates. The producer additionally requires all selection fields and
raw-input hashes to match the claim. Per-call operation/source/input receipts
are retained in the ready producer record. This executes a validated receipt
flow; it does not independently authenticate arbitrary historical receipts.
The existing `model_receipt_provenance` flag remains false.

After at most four inference calls, a pure Generation adapter emits exactly
the first canonical shared v1 vector page: original source/chunk ordinals,
canonical input hashes, float32 bytes/hash and the original shared source-set
digest. Existing shared bytes and readers remain exact. The page and ready
producer record are prepared, fully checked, and consumed together at a final
pinned CAS after rechecking Job/catalog/root and the exact pending claim.
Until later group/root completion, old selected evidence remains selected.

## Bounds and outstanding full recipe

Each explicit invocation enforces the existing 512-read / 16-effect budget
across Collection and adapter calls together. At 1024 dimensions, eight vector
rows form the existing approximately 45 KiB canonical page; an additional row
would exceed its 48 KiB logical bound. Actual escaped SDK frames are checked,
not inferred from decoded text lengths. Pending/ready metadata must fit 8 KiB;
there is no trimming. Claim needs one prepared record and one CAS; final output
needs at most two simultaneous stage slots and one CAS. The first section
preflights a conservative fourteen effects, including four inference effects,
and must measure actual control/read/frame counts with its final schema.

Durable claim and progress writes add operation IDs to the private recipe.
The existing 28,258 initial+rebuild IDs cannot be treated as the final public
recipe. Provenance packing, remaining-page checkpoint strategy and fused group
completion must be costed against the same 32,768 ceiling; no blanket increase
or free history is assumed. Full source+raw+lexical+projection+native metadata,
journal, old/staged rebuild, GC/migration and terminal reservation remain open.
Actual ordinary Word fidelity and inference quality are separate from local
synthetic registered-provider fixtures.
