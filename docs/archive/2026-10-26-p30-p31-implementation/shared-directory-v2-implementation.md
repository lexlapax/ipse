# Explicit paged shared-directory implementation — 2026-10-29

This section implements the accepted [directory-v2 design](shared-directory-v2-design.md)
and its [independent conditions](shared-directory-v2-design-independent-review.md).
It follows the [ordinary native/public finalization](shared-finalization-native.md)
and [maximum-label counterexamples](shared-metadata-geometry.md). Current goal
acceptance remains in the [plan](../../plan.md). The
[manifest](shared-directory-v2-implementation/manifest.json) binds exact source,
chronological logs, compiled feature cohorts, actual artifacts and the copied
host runtime. Generated BEAMs remain under `_build`.

## Implemented contract

The public `generation_job` action explicitly adds `finalize_paged`. Only a
complete captured Job1 in `manifests`, before v1 reduction, can enter this path;
only that action can continue Job3. Existing `finalize`/Job2/root1 behavior and
canonical directory bytes remain unchanged. Old readers explicitly refuse
root2; new readers accept both. Inspection, abort and selected-job reconstruction
dispatch by version. There is no budget-triggered conversion or fallback.

`Paged` reuses v1 manifests and shared group/source/vector/fact formats. It
produces explicit recipe-two entity run/page values with at most32rows, checks
the unchanged48KiB client value and64KiB packed native envelope before emission,
and merges at most eight sorted runs with complete unioned memberships. Captured
summaries remain ordinary approved extension data; they are not host seals or
model receipts. No source, locator, warning or membership is truncated.

Root2 omits `entity_rows_sha256`. Its `entity_pages_sha256` names the canonical
SHA256 commitment to the exact closed `ordered_entity_pages` object in the
design: version/recipe, entity/group counts,32-row geometry and every ordered
content-key/hash/size reference. Source-head hashing remains the v1 flat digest.
Current catalog hash/generation/floor and exact model/extraction selectors remain
bound. Directory entity hydration validates every complete page and its global
row order, uniqueness, canonical label-to-ID relationship and membership bounds.
A commitment to refs alone is not described as full semantic validation.

Job3 durably verifies one entity page per step. Its closed reduction schema
enforces cursor/verified-count/last-ID relationships, initial zero/nil state,
exact terminal remainder and complete agreement before selection. Every resume
reconstructs its semantic input from the current stored job, including first,
later and direct-finish metadata tokens. Tokens cannot supply a cursor/verdict.
Known partial byte staging retains its exact body/hash/offset plan. Unknown
effects return no replay continuation.

The old root stays selected until the final owned root/job/catalog three-stage
CAS. Both immutable prerequisite passes, exact sealed-stage/slot/epoch/body/
revision checks and final-generation-pinned `value_commit_at` remain in place.
No snapshot refresh occurs between the last proof and the commit. Final stats
prove current byte existence; durable semantic progress is established earlier
by the page-verification path. Neither is a new host authority attestation.

No Core/native/helper, dependency, namespace, quota, capability or writer change
was made. `Store.Collection` remains byte-identical to the reviewed pre-v2
client. The actual runtime is the verified copied7e1913 document-decision graph;
later unrelated host/MCP graphs were not overlaid. Normal operator trust,
project binding and full-argument approvals remain required; managed document
and other existing gates are unchanged.

## Focused pure and complete protocol evidence

The pure protocol model dispatches no Core/native effect. It uses the actual
SDK frame validator and closed CollectionStore request/outcome validators,
models the exact host read-slice and packed-wrapper rules, and counts every
nested snapshot/stat/read/prepare/inspect/commit. These are envelope/resource
and integrity checks, not populated storage or source acquisition evidence.

| Control | Observed result |
| --- | --- |
| 47071 | Root2 and affected exact-v1 regression: two pass,6.2s. Seventeen groups/136sources/272entities produce two v1 manifests, nine v2 entity pages and nine durable verification steps. Complete hydrated entity rows, manifest bytes and source-head digest match v1. Retained old reader refuses root2. Missing/reversed/duplicate/rehashed pages, float version aliases, bad memberships, cross-page duplicate IDs, cursor/action mismatch and edited metadata positions refuse. |
| 47077 | Complete maximum-width final selection and resumes: one pass,4.6s.165refs require330stat proof reads; whole invocation377reads/9effects. Root35,203body/37,481packed bytes; selected Job42,871/45,712; catalog7,390body bytes. Largest actual emitted SDK frame13,604bytes, maximum seven parts. Maximum-width legal counters/revisions and escaped128-byte selectors are included. |
| 47077 resume positions | Metadata units0/1/2/direct-finish3 require377/367/362/355reads and9/5/4/1effects. Missing prerequisite refuses before any effect at every position. One worst-width semantic page requires46reads/6effects. A known12,288-byte partial metadata write resumes the exact semantic plan in46reads/5effects; missing semantic input refuses before further writes. |
| 47075 | Conservative schema-valid/native-usable maximum summary batch and eight-way merge: one pass,61.3s. A16-summary batch uses23explicit continuations, at most280reads/5effects per invocation,90total modeled effects. Its largest summary is43,748body/65,534packed bytes. Eight-way merge uses two continuations, at most112reads/6effects,10total effects. Largest frame13,622bytes. This upper-bound summary fixture is not a claim of group/model production or payload hydration. |
| 47079 | Full eight-manifest/125-group source-head reduction binds1,000ordered source heads and the63-page captured catalog.85reads/6effects; cross-batch duplicate IDs, rehashed reordered/missing rows and missing manifest refuse with zero effects. One pass,3.4s. This is metadata completeness, not raw-source population. |

The worst summary fixture preserves exact full-profile declared source/text/
chunk/fact totals while maximizing legal metadata shape; it does not simulate
the entire producer, native history or quality of every referenced group.
Per-invocation fit does not establish the full initial/rebuild operation ledger.

## Actual protected native and public Session evidence

These use independent ordinary Corpus artifacts, actual/tmp tmpfs fixture homes,
the unchanged fixed document profile and full proposed approval arguments. The
fixture provider raises on inference. Source/group/old-root/pending-job seeds
are explicitly trusted synthetic inputs, isolating finalization from capture.

| Control | Actual result |
| --- | --- |
| 47072 | One pass,42.0s. Twenty-five approvals include actual begin and22native finalization mutations after the trusted pending seed. A real root1 remains exact throughout drafts and before the final three-stage approval, then becomes the exact canonical root2/Job3. Current inspection, cited public retrieval, action receipts and saved reconstruction pass. Final component status28operations/17records/90,112allocated bytes is not a whole-profile peak. |
| 47073 | Both new-format fault schedules pass,73.7s total. A changed native generation during final approval refuses root2 selection. Owner loss after actual root2 publication but before its result preserves the pending intent; resume adds only owner/release lifecycle records, retains the exact prior event prefix and pending action, and does not replay or mutate native storage. |
| 47076 | One pass,15.0s. Read-only inspection of synthetic maximum Job3 metadata traverses actual SDK2 result publication/materialization:40,801bytes and157entity refs, exact bytes/hash/value, valid saved display, and unchanged native status. Referenced payloads are not a populated source store and no root selection or semantic-completion claim follows from this inspection. |

## Retained failures and cohort boundaries

47066 stopped on a strict compiler clause-grouping warning;47067 stopped on a
test-only `Code.eval_file` arity mistake.47068 passed the first root2 pipeline.
47069 stopped on a test model's JSON alias;47070 passed the first complete
maximum-width invocation.47074 added resume/per-page controls before47077's
known-partial test.47078 completed its checks but output parsing failed because
of an unused test alias;47079 removes that alias. No failure is called a passing
runtime control. Actual runtime/domain sources were stable before47072; later
changes only add focused test/support coverage. Earlier frozen manifests remain
immutable.

## Remaining required work

The accepted1,000sources/20MiB/10,000chunks/5,000entities/20,000assertions and
1,024-dimensional vector profile is unchanged. A measured populated initial
build and rebuild, complete source/vector/fact producer geometry, exact lifetime
keys and native operations, notes coexistence, and old-plus-staged/raw/lexical/
native/journal peaks remain required. This section does not reclassify the old
dry codec calculation as a complete recipe ledger.

Safe reclamation must account for immutable values published before durable
job metadata and unknown outcomes without replayable tokens. The tested host
cohort lacks published-value scan/delete/export/import operations. The later
[descriptor inventory slice](document-descriptor-inventory.md) supplies a
separately reviewed, read-only physical-metadata scan in another host graph;
it does not add deletion/export/import or change this frozen runtime.
Destructive maintenance/migration needs its separate reviewed host contract.
Correction from current Core inspection: deletion removes a record-map entry
and frees that live-key slot. The 8,192 bound is on current records, not lifetime
public key names; the earlier receipt's lifetime-tombstone assertion was
unsupported. Successful operation IDs and their replay history remain retained
under the independent 32,768 limit. Physical orphan cleanup and metadata bytes
also need separate accounting. Captured floors,
selected-root protection, migration/suppression integrity and full profile
qualification remain open. Representative ordinary Word acquisition/quality,
actual model receipt provenance and later-use authority remain separate work.
