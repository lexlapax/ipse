# First public shared vector page — 2026-10-29

This implements the first coherent section of the
[bounded producer contract](shared-producer-v1-design.md): a durable claim,
registered embedding inference and one canonical shared 1024D vector page.
It closes the supplied-vector-only gap for this section. It does not complete
remaining pages, facts, group/header/summary append or selected generation
publication. The [plan](../../plan.md) and
[whole-recipe ledger](document-whole-recipe-ledger.md) retain the full targets.

The [manifest](shared-producer-first-page/manifest.json) pins exact production,
developer and executed fixture source, chronological logs, the immutable
artifact/runtime identities, actual synthetic journal and receipt reduction.
No BEAM, helper or model checkpoint is copied into the archive. The native
fixture uses the unchanged frozen Root2 host graph and its `7e191344...fd067`
helper on actual `/tmp` tmpfs. It is not an installed-host or all-current-Core
qualification. No Core/native/quota code changed.

Manifest SHA-256:
`92c215154e5d948f66f02adb12af21793f9619d3c69cdb83a5a66c9c1d6a5245`.
Fifteen source snapshots, eight chronological logs, four actual-data reports,
twenty-six artifact files and 669 runtime-file hashes are pinned. Read-only
`47144` verified all 725 rows including the two ancestors and design snapshot,
with zero hash/size failures. The final formatting check passes. An earlier
freeze before a test-wrapper whitespace correction is retained under `_build`;
no runtime control was repeated for it.

## Public surface and compatibility

The new opt-in `collection-dense` Corpus preset adds existing `host.embedding`
and `host.results` capabilities to the document Collection/tools grants.
`collection-documents` keeps exactly its old grants; no preset gains
`host.model`. Artifact trust and configuration remain explicit, and existing
full-argument approvals apply. Existing compact/full Job response behavior is
preserved. The build/spec helpers include the new domain-owned producer.

`generation_produce` accepts `store`, `version: 1`, `action: "page" | "inspect"`,
an explicitly configured embedding alias, expected Job id/revision and exact
vector/fact selection objects. It accepts no supplied vectors, source body,
private cursor, stage, filesystem path, namespace or quota. Job/catalog/root
and at most eight source bundles are read and validated through the existing
Collection client. The first at-most-eight chunks are captured with original
source/chunk ordinals and canonical/raw text hashes.

Before any inference, the producer stages and selects a closed pending claim
under `genproducer.<partition>`. It verifies the complete stage and rechecks
exact catalog/root/Job anchors at one native generation, then commits without
rebasing or replay. Only that confirming volatile invocation proceeds into
the existing Adapters embedding v2 path. It validates reported profile/model,
selection digest, finite float32 bytes, complete vector hash, canonical input
digest and raw input hashes. Per-call operation/source/input receipts are
retained in ready metadata. No service/provider/billing choice is implicit.

Expected selection is checked after the result. The existing host embedding
request has no expected-selection guard; a changed alias/model can be approved
and contacted before mismatch is detected. Such a mismatch blocks publication
and leaves pending work. This is not a pre-egress selection pin. Public
bootstrap/discovery of an initial expected selection remains later work;
the actual fixture derives its declared expectation from the existing trusted
host binding API, not from an invented extension capability.

`Generation.vector_page/6` reuses the exact shared v1 row/page encoder. Existing
`pack_group` bytes remain unchanged. Final vector page and ready metadata are
prepared and consumed together after complete stage and anchor checks at the
final pinned generation. Old selected evidence stays selected; this section
does not write the selected root or advance the Job cursor.

Pending or unknown work offers no retry/adoption token, including after a lost
commit acknowledgement. Inspect does not call historical receipt shapes
authenticated or claim the current invocation executed them. The existing
`model_receipt_provenance` flag stays false. Explicit abandonment/recovery,
subsequent page progression and receipt packing are still required; this first
route conservatively refuses another completed/pending page rather than
silently repeating inference or adopting another Session's stages.

## Focused evidence

| Control | Result and scope |
| --- | --- |
| `47133` strict package build | `corpus/collection-dense`, zero diagnostics |
| `47135` closed host | Four passed; full eight-vector page, exact old Generation bytes, pending-before-inference, selection/unknown refusal, post-commit unknown/no retry, old grants unchanged |
| `47139` portable isolated fixture | Strict current-source compile and five passed, adding a catalog change during inference that refuses final publication; outer test passed |
| `47138` actual public Session | One passed, 11.1 s: supplied 5,500-byte source, compact Job begin, actual registered loopback embedding request, bounded result pages, normal full approvals, native shared page, Saved reconstruction and conservative inspect |
| `47140` read-only actual journal reduction | Claim commit precedes embedding intent; operation/source/canonical/raw input hashes match actual EffectResult; shared page float32 bytes equal actual host source; zero active stages at captured boundary |

The full eight-vector closed-host case uses **69 reads, 12 effects**, four
embedding calls, a **45,064-byte** shared page, **4,354-byte** ready metadata and
a maximum complete SDK host frame of **12,759 bytes**. The implementation
preflights fourteen effects and reserves 128 reads before claiming, then
enforces the existing 512-read / 16-effect limits across both adapter families.
No input, receipt, warning or vector is trimmed to fit.

The actual public case produces two vectors through one real registered
inference admission: **51 reads / 6 effects**, ready metadata **1,786 bytes**.
Its captured source→Job→page journal is exactly **783,207 bytes / 287 events**,
including eight invocations, 127 action pairs and one embedding source.
The selected root remains absent and all recorded stages are consumed. This
is actual local synthetic transport/receipt evidence, not paid/live model
quality or independent authentication of arbitrary historical stored receipts.

The first pure positive fixture (`47134`) contained only two chunks, so its
expectation of four inference calls failed while three other controls passed.
The fixture was enlarged to exercise eight vectors; limits were unchanged.
The first Session attempt (`47136`) hit sandbox `EPERM` binding loopback before
Session/native work. The explicitly approved loopback retry (`47137`) reached
page_ready but failed a test-only comparison with `event.sha256`; the actual
field is `event.source_sha256`. Its source/log are retained. The corrected
single case passed and captured its synthetic journal before cleanup. No
aggregate suite or unrelated positive cohort was rerun.

The portable tests now compile/build their own feature package; the exact
executed earlier snapshots are retained separately. The current Session
fixture's new default-build wrapper is routine portability plumbing, not an
additional executed native qualification beyond the pinned `47138` source.

## Required continuation

The first page deliberately remains intermediate. Next implement bounded
remaining-page checkpoints, actual model-extracted facts, compact per-group
receipt/proof pages, canonical group header/summary append and selected-root
completion. Selection bootstrap, pre-egress pin semantics where required,
explicit unknown recovery/abandonment and stage-free fresh-Session boundaries
must remain explicit.

Durable claims/progress add operation IDs beyond the private 28,258-ID
initial+rebuild ledger. The public recipe must be recalculated and fit the
unchanged 32,768 ceiling, with exact incoming/history and terminal reservations.
Source/raw/lexical/native/journal/old+staged peaks, GC/migration and representative
Word acquisition/fidelity remain open. Neither this first page nor the small
native case qualifies the complete C1b/F profile.
