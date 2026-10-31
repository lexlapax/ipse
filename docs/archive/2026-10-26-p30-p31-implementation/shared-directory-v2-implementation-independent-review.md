# Independent review of Root2 and Job3 implementation

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the implementation](shared-directory-v2-implementation.md) and frozen manifest
`382d9cf81e29259611cc9481363da54437cbe82cbeee92f70495d3498b0529dd`
against the accepted [design conditions](shared-directory-v2-design-independent-review.md),
prior [finalization review](shared-generation-finalization-independent-review.md)
and [native/public review](shared-finalization-native-independent-review.md).
The frozen Root2 handoff was also inspected. No implementation edits, model or
network calls, native dispatch or repeated passing tests were made by this
review.

## Disposition

Accepted for the explicit paged directory implementation and its scoped recorded
controls. No concrete blocker was found in version dispatch, semantic progress,
continuation reconstruction or final selection. This accepts neither the full
populated profile nor its initial/rebuild ledger, source acquisition, real model
provenance, later-use authority, quality, reclamation or migration. The unchanged
Core/native/gate boundary and all remaining workload requirements still apply.

## Formats and semantic integrity

Only `finalize_paged` starts the new recipe from a complete captured Job1 in
`manifests`; only that action continues reducing Job3. The existing `finalize`
path remains Job2/root1. Public schema, dispatch, continuation action, inspection,
abort and selected-job reconstruction cover the new versions together. There
is no automatic conversion on budget refusal. Strict literal versions and closed
fields prevent float aliases and recipe substitution. The retained v1 reader
refuses root2; the recorded exact-v1 regression preserves canonical v1 output.

Root2 commits the closed `ordered_entity_pages` object under
`entity_pages_sha256`, including exact recipe/version, entity/group counts,
32-row geometry and ordered key/hash/size references. It omits the old
`entity_rows_sha256` field. Content references bind the partition, family, digest
and byte count. Duplicate root references refuse. Full hydration separately
checks page ordinal/version/recipe/kind, exact page and final remainder lengths,
canonical label-to-ID regeneration, valid complete labels, nonempty sorted
unique memberships inside the actual group bound, and strict global ID order
across page boundaries. Rehashing a page or root does not waive those semantic
checks.

The paged batch reuses the v1 summary, manifest and catalog-binding logic. Each
batch authenticates at most sixteen complete summaries and its exact captured
catalog pages, including selectors, head pairs, group count/remainder and totals.
The output runs use explicit recipe-two pages; eight-way merge validates run
ordinal/count/page references and bounds memberships to their originating batch,
requires equal labels for equal IDs and unions all memberships. No row or
membership is truncated. A locally sorted merge output is not sufficient:
Job3's later per-page verification carries the preceding final ID and refuses
cross-page duplicates or reversals.

The complete heads phase consumes all eight manifests for 125 groups and 1,000
heads, checks group cursor/remainder structure and global source-key uniqueness,
and derives the unchanged flat source-head digest. The initial batch phase
establishes equality to the captured 63-page catalog; this later digest phase
does not independently reauthenticate every source payload or every catalog
page. Both remain ordinary approved extension data and durable checkpoints,
not host seals. As in the accepted design, declared entity membership integrity
does not independently prove its derivation from every group's facts.

Job3's closed reduction schema relates phase, cursor, verified count and last
ID. Zero progress requires zero/nil state; each successful semantic step verifies
exactly the next page, advances by its complete row count, and preserves its last
ID. Later phases require the exact number of full pages plus terminal remainder.
Selection requires complete cursor/count agreement and the named commitment.
The stored checkpoint is still within the cooperative extension trust boundary;
editing an entire stored job is not equivalent to a host-attested verification
history.

## Continuation and atomic selection

Every invocation starts from current catalog/root/job records at one coherent
boot generation. A caller token binds job ID/revision, captured catalog and old
root revision. It does not carry a semantic cursor or verdict. Finalization
reconstructs the current stored phase's needed immutable inputs and exact next
job before applying a token's byte-staging position, including first/later
metadata units and direct finish. Missing semantic input therefore refuses even
when a caller supplies a recomputed plan digest and skips metadata positions.
Known partial staging retains the same body/hash/offset plan. Unknown effects
stop without a replay continuation.

Before preparing metadata, the controller checks every required immutable
key/hash/size at its boot generation. After exact metadata stage inspections,
it checks them all again at the single generation shared by those inspections.
Inspections bind owned slot/epoch, sealed state, complete offset/body/hash and
expected revision. The final call uses `value_commit_at` directly at that proved
generation; there is no intervening snapshot refresh. Root, selected Job3 and
captured catalog switch in one three-stage CAS. Earlier staging changes neither
the exact old root nor its selected payloads. Current byte existence and durable
semantic progress remain separate claims.

The previously reviewed native stage expiry/final locked decision applies
unchanged. Paging adds no waiver, new host authority, native protocol, capability,
quota or alternative writer. Existing source/citation hydration and current-use
checks remain separate from this directory commitment.

## Verified evidence and bounds

[The manifest verifier](shared-directory-v2-review/review-manifest.exs) and
[its result](shared-directory-v2-review/review-manifest.log) verify 32 frozen
sources, 14 chronological logs, six ancestor bindings, 204 compiled files in
12 feature cohorts, 160 files in seven actual artifact inventories, and all
669 runtime files. The runtime inventory exactly equals the previously reviewed
native-finalization graph. Helper
`7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067`
and client writer source
`2811dc2be11955495b43e853371385f3148d3052485bac5ae5fc4969174ff599`
are unchanged. This is the copied document-decision graph, not a qualification
of later unrelated Host, MCP or maintenance graphs.

The closed protocol model uses actual SDK frame and closed host request/outcome
validators, including nested reads and the actual escaped read-slice rule. It
models preparation and native packed envelopes; it dispatches no native effect.
The observed bounds are:

| Modeled control | Reads/effects and size evidence |
| --- | --- |
| Final selection | 165 refs, 330 stat proof reads; complete invocation377reads/9effects. Root35,203body/37,481packed bytes; selected Job42,871/45,712; catalog7,390body. Largest frame13,604bytes, maximum seven parts. |
| Final metadata resumes | Units0/1/2/direct-finish3:377/367/362/355reads and9/5/4/1effects. Missing prerequisite has zero effects at every position. |
| Semantic page/known partial | One worst-width page46reads/6effects. A known12,288-byte metadata checkpoint resumes the exact semantic plan in46reads/5effects; missing semantic input refuses before more writes. |
| Summary batch | Sixteen schema/native-upper-bound summaries,23explicit invocations; at most280reads/5effects per invocation,90modeled effects total. Largest summary43,748body/65,534packed bytes. |
| Eight-way merge | Two invocations; at most112reads/6effects,10modeled effects total. Summary/merge largest frame13,622bytes. |
| Full source-head reduction | Eight manifests/125groups/1,000heads/63captured catalog refs:85reads/6effects; cross-batch duplicate, rehashed reordered/missing group rows and missing manifest refuse with zero effects. |

Maximum-width legal counters/revisions and escaped 128-byte selectors are
structural stress inputs. The upper summary fixture preserves declared profile
totals while maximizing legal metadata; it is not an actual producer, acquisition
or model workload. The final-selection fixture starts with trusted completed
semantic metadata. Separate page controls establish the verification path.
Neither per-invocation fit nor those trusted counters establish full native
population, initial/rebuild operations, lifetime keys or peak bytes.

Actual47072 uses full proposed arguments and programmatic Session approvals:
25approvals include begin and22native finalization mutations after a trusted
pending seed. Exact root1 stays selected through drafts and final approval, then
canonical root2/Job3, current inspection, cited retrieval, receipts and Saved
reconstruction pass. The source/group/old-root/pending seeds are trusted synthetic
inputs; reusable immutable values are not fresh capture acceptance. The final
28operations/17records/90,112allocated bytes is a component status, not a profile
peak or human tty approval.

Actual47073 changes native generation while final approval waits and observes
selection refusal. Its owner-loss control kills Session after native root2
publication and before the action result, not midway through native commit.
Saved reconstruction retains the exact prior prefix and pending action; the
observed resume tail is only owner/release lifecycle records, native status is
unchanged and nothing is replayed. Actual47076 exercises SDK2 result paging and
materialization for40,801bytes/157refs with exact saved value/hash and no native
mutation. That metadata-only inspection proves neither populated referenced
payloads nor semantic completion or selection.

Earlier clause-grouping, `Code.eval_file` arity, JSON alias and output-parsing
failures remain retained. The alias/output-parsing47078 run is not counted as a
passing control;47079 is its corrected focused result. Historical BEAM cohorts
remain identified separately from the final source; no aggregate was repeated
for this review.

The complete source/vector/fact producer geometry, measured initial and rebuild
ledger, exact lifetime keys/operations, notes coexistence and old-plus-staged/raw/
lexical/native/journal peaks remain required. Safe orphan reclamation, suppression
floors, tombstone lifetime behavior and migration also remain open. The tested
7e host cohort lacks the later independent value-index API; that newer inventory
work does not retroactively qualify this frozen runtime or complete maintenance.
Representative ordinary Word acquisition, real model receipts and quality remain
separate obligations. No broader milestone completion follows from this review.
