# Fused bounded document writes — 2026-10-29

This historical component follows [packed fact projections and the operation
refusal](packed-fact-projections.md). Current procedures belong in the
[Corpus manual](../../operator/corpus.md) and [developer manual](../../developer/knowledge-extensions.md);
the [plan](../../plan.md) retains full C1b/F acceptance. This receipt qualifies
bounded transport/publication controls, not the complete populated profile.

`value.write_parts` accepts one or two existing UTF-8 parts of at most 6,144
bytes each. The complete actual SDK frame must still fit 16 KiB. Requests bind
slot/epoch, target and expected revision, complete original body count/hash,
exact next offset and publication mode. The first CAS opens and stores its first
parts. A final CAS reconstructs and validates the complete bytes/hash/JSON, then
either publishes the packed value or seals a private ready value while consuming
the previous parts. Publication does not leave a separate cleanup window.

The ten-part, 60-KiB body, 16-slot and eight-ref final selection bounds remain.
The largest final change set fits the existing document-only 32-change bound;
notes/control limits are unchanged. All mutations reuse the same host-validated
document profile, normal full-argument approval, current operator/project binding,
owned resources and trusted final native deadline switch. No worker path, quota,
profile or trusted-deadline field was added.

Snapshot feature marker version two explicitly advertises `write_parts: 2` and
the unchanged 8-KiB inline limit. The current client accepts earlier version-one
inline markers and historical marker-free hosts. It never retries a refused or
unknown effect through another protocol. Fused open stages bind their publication
mode and cannot mix with legacy append/seal operations. Inspection adds only an
optional mode field; historical inspection/receipt shapes remain accepted. The
closed write receipt binds exact request, byte progress, mode, state and target
revision. A known partial write may return a bounded explicit continuation;
unknown effects return none and never replay.

The client tests the complete frame and selects one part when two do not fit.
Exact byte and recipe identities are unchanged. Existing root/catalog multi-ref
selection remains atomic. Source-local adapters reuse this transport without
changing Source, chunk, vector, fact or citation formats. No dependency or common
workflow framework was introduced.

## Focused evidence

- `46850`: three native controls passed in 5.1 s: exact UTF-8 bytes, private
  preparation and consuming CAS, owner/mode/offset/epoch/digest refusal, closed
  request limits, expiry refusal and explicit abort. A test-only implicit range
  step warning was corrected before the enlarged case.
- `46851`: the enlarged near-60-KiB/ten-part native case passed, exercising a final
  change set beyond the old notes limit. Two Session setups initially refused a
  fixture with nine exports. The fixture now reuses its existing `put` command;
  the eight-export ceiling was preserved.
- `46852`: actual owner loss after the final fused publication passed. The
  continuation test initially applied its packed-value decoder to a plain stage
  header; that fixture inspection was corrected.
- `46853`: current marker/transport compatibility and the portable historical
  Source consumer passed. The continuation test observed four mutations rather
  than its expected five: the final 6,144-byte part plus a small tail fit together.
  The test was corrected to check adaptive packet sizes.
- `46854`: actual synthetic Word ingestion through complete source/run packing
  and exact source-local cited query passed in 17.7 s. It used 21 fused writes,
  25 total native mutations and nine final live records. The largest actual SDK
  frame was 14,827 bytes. The citation retained the original digest and paragraph
  locator. This is synthetic DOCX evidence, not installed Word quality.
- `46855`: the explicit known-partial continuation passed in 3.7 s. Two writes
  paused at the invocation effect bound, inspection authenticated the same owned
  stage, and the next explicit invocation completed exact escaped bytes. Four
  actual frames were 12,645, 12,661, 12,661 and 12,731 bytes. Forged progress/mode
  receipts refused. No uncertain callback was replayed.

All failed attempts remain in the [manifested evidence](fused-document-writes/manifest.json).
These are fresh, taint-empty explicit Session commands. They do not qualify the
separate managed-input worker-send boundary. The isolated SDK copied the stable
managed-action cohort plus its retained-parent check repair, then compiled only
DocumentStage and the narrow CollectionStore result surface. The executor was
preserved. Exact BEAM/helper hashes are recorded; this does not import unrelated
historical lifecycle tests as qualification. Build artifacts stay under `_build`,
and native fixture homes use actual `/tmp` tmpfs under private Linux 7.2.11 helper
admission, not production kernel admission.

## Recalculated recipe and remaining refusal

The dry Elixir preflight now invokes the existing namespace group packer as well
as Source/vector/fact packers, validates encoded frames, counts growing job
rewrites and distinguishes fresh values from immutable reuse. It executes zero
native operations and performs no inference. The unchanged weighted geometry is
1,000 sources, 20 MiB extracted evidence, 10,000 chunks/1,024-dimensional vectors,
5,000 source-distinct labels and 20,000 assertions.

| Current implemented recipe | Staged v1 | Fused v2 |
| --- | ---: | ---: |
| Source, vector and fact preparation/selection minimum | 36,000 | 20,000 |
| Namespace lexical index | 1,543 | 504 |
| Initial total minimum | 37,543 | 20,504 |

Fused Source/vector/fact minima are eight/eight/four mutations per source.
The namespace has 125 groups and 250 immutable values. Its 126 job writes cost
250 mutations because the job grows; the estimate does not count each rewrite
as one automatically. A same-source vector replacement, fact reselection and
lexical rebuild add a minimum 11,254 mutations, for 31,758 combined. This still
excludes global graph indexing, all-profile atomic generation/rebuild, migration,
collection, retention and notes. Its largest namespace preflight frame was
13,579 bytes. It is not a complete qualified recipe or peak-space measurement.

The hard refusal is now **8,316 live keys before staging**, above 8,192: 3,064
Source/catalog keys, 3,000 vector keys, 2,000 fact keys and 252 lexical keys.
Old plus staged vector pages alone increase that minimum to 10,316. No full
populated run was started. A shared packed projection catalog/generation must
remove per-source root/page waste and support old/staged selection, safe explicit
GC and migration under the unchanged limits before qualification can proceed.
