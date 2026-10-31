# Document recipe, rebuild and migration feasibility — 2026-10-29

This completed request-level investigation finds concrete implementation and
capacity blockers before a populated native qualification. It does not lower
the accepted 1,000-source / 20 MiB / 10,000-chunk / 5,000-entity / 20,000-fact
target, change quotas, implement migration or establish Word acquisition or
model quality. The [plan](../../plan.md) owns acceptance. The
[Root2 receipt](shared-directory-v2-implementation.md),
[physical-layout receipt](document-packed-layout.md),
[maintenance proposal](document-collection-maintenance-v2-design.md) and
[epoch/ID requirements](document-maintenance-epoch-clarification.md) retain
their separate scopes.

The accompanying [manifest](document-whole-recipe-ledger/manifest.json) pins
executed developer sources, chronological logs, reductions, retained input
hashes and the frozen artifact/runtime ancestors. Compiled code, helper
binaries and model checkpoints remain under `_build`; none is copied into the
archive. Detailed synthetic request traces remain retained at the manifest's
paths and hashes. This is a new ledger, not a rerun or amendment of Root2's
qualification. All process handles listed below are terminal.

Manifest SHA-256:
`a06f8940224472bbb3da5feec88e26d97a70716a9eecc77dba410b2d8de4213f`.
It contains fifteen source snapshots, eleven archived logs, fourteen reports,
669 runtime-file hashes and twenty-five artifact-file hashes. Earlier archive
script syntax/deprecation/self-log bookkeeping diagnostics remain under
`_build`; the final `47119` freeze completed cleanly. They caused no repeated
recipe or runtime effects. The mutable handoff is preserved as a dated copy,
rather than pretending its current contents cannot change.

## What actually ran

The developer driver loads the frozen public Root2 artifact and runs the
actual extension `C`, `Generation` and `Job3` continuations. A closed host model
checks every request/result through the real SDK and CollectionStore
validators, and enforces 512 reads / 16 effects per invocation. The model does
not dispatch native effects, approvals, inference or external acquisition.

Two generated DOCX extraction templates supply 252 texts of 20,979 bytes and
748 texts of 20,969 bytes: exactly 20,971,520 bytes, ten segment-local chunks per
source. The private shared producer supplies 10,000 1024-dimensional vectors,
5,000 entities and 20,000 facts. These are explicit synthetic inputs, not model
receipts. Rebuild changes every vector coordinate by `+0.5` and appends a suffix
to every fact predicate, recomputes lexical/shared selection, and reuses only
exactly equal immutable values. Unchanged raw sources are retained.

The model begins with an empty public map at synthetic generation **1,000**.
It has no matching native manifest or supplied baseline operation history.
Reported IDs are unique modeled wrapper IDs/request hashes, not native commit
receipts. Real admission must add the exact `Known(target)` / incoming union
and all still-new local/reserved IDs. Generation 1,000 is not free history.

| Run | Outcome |
| --- | --- |
| `47083`, handle `91686` | Full initial private recipe selected Root2; exit 0 |
| `47092`, handle `59315` | Separate finalization/public encoder measurement; exit 0; all 5,277 final descriptors and generation exactly match `47083` (`47094`) |
| `47095`, handle `57206` | Initial per-value `C.value_prepare` / real validators; exit 0; no import acceptance |
| `47096`, handle `47008` | Full changed-projection rebuild selected Root2; exit 0, polled terminal before this freeze |
| `47112`, handle `98463` | Rebuilt per-value client costs; exit 0; no import acceptance |
| `47110`, `47114` | Rebuilt/initial byte-authenticated modeled-record compression and bounded inflate controls; exit 0 |
| `47111`, `47113`, `47115` | Read-only reductions, unique-ID union and exact original-part comparison; exit 0 |

The separate `47092` finalization is not counted again in initial mutation
totals. No historical recipe was restarted while waiting for the long rebuild.
Earlier raw/lexical-only runs and pilots remain retained as earlier scopes.

## Actual client sequence and limits

| Quantity | Initial recipe | Full rebuild | Combined |
| --- | ---: | ---: | ---: |
| Modeled mutation requests | 18,640 | 9,618 | 28,258 |
| Explicit invocations | 8,782 | 2,782 | 11,564 |
| Host reads | 183,191 | 142,309 | 325,500 |
| Action intent/result events | 403,662 | 303,854 | 707,516 |
| Request/outcome pair accounting | 663,501,911 B | 608,504,983 B | 1,272,006,894 B |
| Maximum SDK host frame | 13,561 B | 13,559 B | — |

Each byte figure counts two complete request copies plus the actual modeled
outcome JSON at the synthetic generation width. It excludes Session metadata,
headers, invocation inputs, approvals, messages and output records. It is not
an exact fresh-native journal measurement. Raw-source action events alone are
**128,084**, independently exceeding a single 100,000-event Session. Within the
initial sequence, the first event-limit crossing is source 786, invocation
4,717, with zero known active stages; the modeled byte crossing is source 899,
invocation 5,399, with three stages. Waiting until byte exhaustion is therefore
not a safe handoff strategy.

Initial mutations comprise 8,000 raw-source, 383 lexical, 3 shared-begin,
7,879 shared-append and 2,375 finalization requests. Rebuild comprises 254
lexical, 3 begin, 7,629 append and 1,732 finalization requests. The final selected
calls use respectively 9 effects / 369 reads and 9 effects / 381 reads.
The combined ordered unique mutation-ID digest is
`4c5137b3f542fd0e6b676b639a91f3c3d9b9acbe7a22a981ab3ceb8a3304e489`.
No quota or operation-history erasure was used.

| Selected/public-map quantity | Initial | Rebuilt, preserving old immutable projections |
| --- | ---: | ---: |
| Live public records | 5,277 | 6,910 |
| Logical body bytes | 94,043,729 | 155,207,382 |
| Packed physical bytes | 96,223,258 | 157,965,754 |
| Sum of 4,096-byte rounded objects | 108,474,368 | 175,738,880 |

All modeled physical object hashes are distinct within each final map. The
maximum observed public-record count is 6,910 and active-stage count is three,
at invocation boundaries. Conservatively adding all sixteen maximal stages
(ten parts, header and ready record each) gives 7,102 live keys before future
maintenance control keys. This does not measure inner-action physical staging,
old control blocks, orphans or rollback allocation. **8,192 is a live record-map
bound**, not a lifetime key-name bound. **32,768 is permanent operation history**.
Earlier lifetime-key wording is superseded by this distinction.

The reductions retain exact per-family counts. Rebuild includes 2,000 raw data
blocks, 1,000 source heads, 64 catalog records, 2,500 vector pages, 250 fact
pages, 250 group headers, 250 summaries, 125 source-reference pages, 157 entity
pages, 157 run pages, eight run-directory pages, sixteen manifest pages and
the lexical/job/root records. This is a stored-map census, not a whole-profile
native allocation pass.

## Actual small Session boundary and public-output accounting

`47085` passed one actual independent public Corpus/SDK/Session/native control
(40 excluded, 16.8 s). Two supplied **5,320-byte** plaintext sources were stored
through normal full-argument approvals in the same admitted project, closing
the first Session before opening the second. The exact synthetic JSONLs are
399,598 bytes / 121 events and 452,644 bytes / 145 events, six invocations each.
The read-only `47088` analyzer classifies every JSONL byte/event by record type,
checks distinct Session and mutation IDs, the same namespace/artifact, and
zero recorded active stages at each close. Twelve known native mutations,
eight records and 61,440 allocated bytes were observed. The first fixture log's
5,130-byte label was a reporting typo; retained invocation bytes prove 5,320.
The executed source snapshot is preserved before that label correction.

This small control does not extrapolate full-recipe journal sizes or prove
transfer/replay of a live/unknown stage. Document stages remain Session-owned.
Known stage-free durable builder progress can be a basis for explicit
reinspection, subject to the public producer/maintenance bindings; an unknown
effect is never replayed or adopted simply by opening another Session.

The frozen **legacy full** public finalization encoder, excluding the extra
checkpoint inspection, produced 654 replies: 320 SDK2 paged and 334 inline,
10,719,368 encoded document bytes, 3,344 output begin/chunk/seal events and a
maximum document of 39,764 bytes. The 320 paged sources alone require at least
five Sessions under the 64-source limit. These are actual ResultPublication
encoder measurements, not actual Session appends. Source+lexical+shared inputs,
other output and safe handoff costs still apply. The parent is separately
implementing an explicit compact public result; this frozen ledger does not
claim its costs or silently replace legacy behavior.

Only encoder counts, not all 654 complete coverage/continuation objects, were
retained in the original result trace. Exact bulk compact re-encoding cannot
be claimed from those cost rows. Intermediate results were not fabricated or
the modeled recipe repeated to hide this retention limit.

## Migration variants and their remaining authority gaps

| Optimistic mutation arithmetic | Initial | Rebuilt complete history |
| --- | ---: | ---: |
| Known modeled source IDs | 18,640 | 28,258 |
| Actual independent per-value preparations | 11,168 | 16,684 |
| Prepare plus one proposed accept per value | 35,085 | 51,852 |
| Prepare plus proposed accept batches of eight | 30,468 | 45,806 |
| Proposed native artifact page accept only | 19,300 | 29,122 |

The first two acceptance variants exceed 32,768 after rebuild before any
missing reservations. The proposed native-page variant has only 3,646 IDs of
headroom before baseline, plan, epoch, adoption, progress, commit/abort,
checkpoint, close and reclaim. It is **not implemented** and the arithmetic is
not an admission. Initial and rebuilt per-value controls confirm zero changes
to original part boundaries for all 5,277 / 6,910 records. Exact per-value body
hashes, counts, parts and preparation histograms are retained; maximum frame
is 13,531 bytes. Isolated preparation targets do not prove a shared incoming-ID
allocation or terminal reservation.

Existing `Migration`, `Planning` and `Transaction` offer concrete reuse:

- Planned `import.open` already validates the complete operation/receipt set,
  aliases and page hashes; it need not restream operation pages when a complete
  authenticated plan fits. Its current notes formats cap values at 6,144 bytes,
  descriptor data at 24 MiB and the complete plan at 8 MiB. These are not a
  document import API; a reviewed version is required.
- Native read/stage transfers are bounded to 8 MiB, with 16 KiB native chunks,
  128 staged entries and top-only IO under the actual owner. Up to eight 64 KiB
  original physical objects fit one proposed bounded host page. Native IO
  chunks need not each consume a Collection mutation identity.
- `prepare_files` already reuses an object only when exact physical bytes
  match its hash-named target; publication stages immutable objects and switches
  the selected root atomically. Reusing existing objects within the same root
  is materially different from assuming hardlink sharing between roots.
- A new operator-selected opaque **data-artifact** handle is necessary.
  Code-artifact admission and Session result objects are unsuitable substitutes.
  Worker-supplied paths, quotas, profiles or handles that evade project binding
  are not authorized. Native ownership/capability order must cover source,
  artifact and target; ordinary BEAM IO after a lease check is insufficient.
- A document-only batch accept must validate/consume at most eight exact sealed
  refs atomically into the migration pending map. Ordinary consume8 fits at most
  24 changes, within the document limit of 32. Current ordinary preparation is
  fenced during migration; it cannot be reused as a bypass.
- Complete incoming IDs, actual known receipt equality, epoch invalidation
  after close, monotone adoption, explicit unknown inspection and all terminal
  reservations remain mandatory. Random IDs are not proof of disjointness.
  Imported floor may exceed local generation; current document summary readers
  require a reviewed version rather than lowering that floor.

No artifact handle, import-page mutation, epoch, GC, migration or replay-history
change was implemented by these developer controls.

## Compression is favorable here, not a space guarantee

The compression script reconstructs modeled logical bytes only if their full
hash/count match the original complete write, restores original ordered part
lengths, and invokes production `Migration.encode` for the physical wrapper.
Packed counts match every retained descriptor. No checkpoint retains observed
native physical object hashes: **zero** such hashes were available. These are
byte-authenticated modeled physical records, not observed native object files.

Every record was independently compressed with OTP zlib, bounded-inflated and
compared byte-for-byte. An output larger than the declared bound refuses.
A 65,536-byte random binary compressed to 65,562 bytes; a proposed explicit
`identity` or `zlib` codec therefore bounds payload expansion without treating
decoder failure as fallback. A separate valid group of eighty 1,024-dimensional
finite uniform-coordinate vectors gives 452,960 packed bytes and 335,349 zlib
bytes across ten vector pages. This is a synthetic entropy control, not model
output or a worst-case compression guarantee.

| Byte geometry | Initial | Rebuilt |
| --- | ---: | ---: |
| Independent zlib payload | 6,451,065 | 9,015,971 |
| One file per record, rounded payload allocation | 22,220,800 | 29,487,104 |
| Proposed at-most-1 MiB packs aligned to eight-row pages | 7 packs / 6,471,680 | 9 packs / 9,035,776 |
| Source + per-record compressed payload | 130,695,168 | 205,225,984 |
| Source + proposed packed payload | 114,946,048 | 184,774,656 |
| Distinct source + target + proposed packed payload | 223,420,416 | 360,513,536 |

Document allocation has 192 MiB (201,326,592 bytes) after reserving the existing
64 MiB notes envelope within the accepted 256 MiB total. Even this favorable
compressed dataset cannot support distinct full source+target copies inside
that bound. Rebuilt one-file-per-record export also exceeds it before metadata.
The proposed pack geometry omits manifests/index/control, locks/directories,
native staging/terminal peaks and retained rollback data. Existing vector/text
repetition makes compression unusually favorable. No minimum ratio, external
space, hardlink or unmeasured deletion is assumed.

## Next necessary implementation

First expose a bounded **public shared producer** using selected source/chunk
refs, existing registered inference selection or explicitly supplied typed
projection pages, and durable progress. The private `Job.append` consumes
whole bundles/projections; that input cannot pass a 16 KiB SDK request for an
eight-source 1024D group. Public `generation_job` currently lacks append and
the State/MCP projection path is not the Collection shared producer. Acquisition
and existing per-source embedding/extraction APIs are reusable inputs, not
proof this missing bridge exists. A bounded final-page producer should avoid
storing and consuming every temporary vector separately; actual inference
receipt provenance must stay separate from a supplied-page producer.

For migration, the next reviewed backend slice is an immutable opaque artifact
handle with bounded exact physical-record reads and a same-owner/epoch
document import page. Evaluate same-root exact-object reuse or explicitly
budgeted GC before assuming two whole copies. Reserve the full actual operation
union and terminal sequence before body staging. Native control metadata,
orphan/staging/rollback allocation, full Session segmentation, representative
ordinary Word packages, quality, acquisition and installed-host acceptance all
remain required. The ledger is refusal/planning evidence, not a populated
profile pass. No aggregate suite or new live model call was run.
