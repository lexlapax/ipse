# Independent directory-v2 design review — 2026-10-29

This scoped review covers the proposed [directory-v2 design](shared-directory-v2-design.md),
the frozen [metadata geometry](shared-metadata-geometry.md) and additive
[metadata sizing](shared-directory-v2-sizing.md). It permits implementation of
the explicitly versioned direction subject to the conditions below. It does
not accept an implementation, open a gate or qualify populated capacity. The
[plan](../../plan.md) owns milestone acceptance. No implementation, quota,
native helper, production artifact or runtime gate changed in this review.

## Requirements and evidence

The frozen original [baseline, lines 711–722](baseline.md) requires 1,000 active
document sources, 20 MiB extracted evidence, 10,000 chunks, 5,000 entities and
20,000 assertions, within a 256-MiB total envelope including notes. It explicitly
includes index metadata and old-plus-staged rebuild overlap and requires the
target workload and rebuild to qualify together. Lines 732–740 also require
complete export, fencing, checkpoints, validation, atomic switch and suppression
floors for migration. A representational refusal cannot reduce those targets.
The original [commit contract, lines 103–112](contracts.md) requires complete
immutable staging and atomic publication; unknown publication is inspected,
not retried. The proposed extension-only paging change is consistent with these
requirements and introduces no new host authority or expiry waiver.

The design SHA-256 is
`22dff7b5d85f020daab29dec271a574c2420e85b545c7acc7efbd2b86798014b`.
The geometry manifest
`3334a9f145f5b407d5f0e440356048129bf190ec4f5a8d617843ac3a9d49812a`
verified against seven frozen sources, five chronological logs, 48 compiled
files in three cohorts, four rejected diagnostic files, the design and its
referenced runtime manifest. The sizing manifest
`4325747cf7a180b4c9f42a274f68ee99d72a62ab4e38b92fb5bfb7584c16d44c`
verified all five bindings and three retained script/log records. The copied
sizing script was also inspected. Manifest checks read retained files only;
passing probes were not rerun.

The retained `47063` result establishes two distinct v1 counterexamples:
704 complete read replies exceed the 512-read invocation budget, and a legal
37,503-byte page becomes a 70,064-byte native packed value, exceeding 65,536.
The proposed 32-row page with all 125 memberships measures 31,181 body bytes
and 47,547 packed bytes. This is a conservative page envelope, not a populated
5,000-entity graph or an actual native publication. The unchanged writer's
8-KiB decoded-string limit and 16-KiB complete encoded-frame limit remain
distinct from the read reply's encoded-string slicing rule. The rejected
restrictive writer is not a prerequisite or accepted repair.

## Disposition and mandatory implementation conditions

No architectural blocker was found in explicit `finalize_paged`, Job version
three and Directory root version two. The direction addresses both demonstrated
v1 failures without a new framework, hash algorithm, dependency or Core quota.
Implementation can proceed with these conditions:

1. **Keep formats explicit.** Existing `finalize`, Job version two and all v1
   canonical bytes/digests retain their current interpretation. Only a complete
   captured v1 job in `manifests`, before v1 reduction starts, may enter the new
   recipe; only the matching action may continue Job3. Update public action
   schema, dispatch, inspection, abort and selected-job reconstruction together.
   Readers dispatch by exact version/recipe: the upgraded reader accepts both;
   a retained old reader refuses root2. There is no budget-triggered conversion,
   resumed-recipe substitution or implicit fallback. Test replacing an existing
   v1 selection and inspecting a selected Job3 without falsely marking it stale.

2. **Preserve the complete source catalog.** Manifest batching still authenticates
   all 125 canonical groups for 1,000 sources, in exact captured catalog/head
   order, with groups of eight except the precise final remainder. All 63
   captured catalog-page bindings, catalog digest/generation/floor, source-head
   sequence, text/chunk/fact totals and common selectors remain checked. Eight
   manifest pages and their existing flat source-head digest remain v1. A new
   entity paging recipe must not weaken catalog completeness or silently select
   only the groups that fit a read pass.

3. **Name the new digest honestly.** `entity_pages_sha256` commits the exact
   closed `ordered_entity_pages` object specified at design lines 37–42,
   including ordered references, counts, row geometry and recipe. Root2 omits
   `entity_rows_sha256`; no page digest is substituted under that old name.
   Validate exact content key family/partition/hash, full byte count, page
   version/recipe/kind/ordinal, complete count and final remainder. A root2
   entity reader must authenticate the ordered commitment and retain complete
   row validation, including global ordering/uniqueness, canonical label-to-ID
   regeneration and nonempty sorted unique memberships within the actual group
   count. Checking references alone is not the old entity-hydration contract.

4. **Make semantic progress durable and phase-specific.** Job3's closed schema
   must enforce cursor/count/last-ID relationships, rather than merely bounding
   those fields separately: zero cursor implies zero verified rows and nil last
   ID; each known step verifies exactly the next page; verified rows equal the
   consumed full pages plus the precise terminal remainder. Only complete
   cursor/count agreement permits selection. Runs preserve exact identities,
   equal labels for duplicate identities and full unioned memberships; missing
   inputs never count as empty. Cross-page identity order must be checked at
   the durable verification boundary, including a merge boundary that otherwise
   appears locally valid. No label, membership or warning may be truncated.

5. **Reconstruct before trusting continuations.** The caller token never sets
   the semantic cursor or supplies a verdict. Recompute the phase's exact
   semantic input and next job from current stored bindings on every resume,
   including first metadata unit, later metadata units and direct finish.
   Plan hashes bind the exact proposed job/catalog/immutable values, but do not
   prove a skipped write or verification happened. Preserve both prerequisite
   passes, exact owned sealed-stage checks and the final generation-pinned
   `value_commit_at`; do not refresh the epoch after proof. Unknown returns no
   next operation or replay continuation. Inspection is not an automatic retry.

6. **Keep integrity and authority claims separate.** Captured summaries and
   stored reduction checkpoints retain the existing cooperative approved
   extension trust boundary. Their ordinary JSON is not a host attestation.
   Directory validation proves canonical structure and authenticated declared
   membership; it does not independently reread every group's facts to prove
   membership derivation. Later selected payload hydration, exact source/input/
   citation validation, current-use authority and real model provenance remain
   separate. No serialized OTP hash state, new attestation or custom SHA is
   needed for this change.

## Budgets and controls before implementation acceptance

The additive `47065` proposed records fit the existing client, SDK and native
wrapper without changing the writer:

| Proposed record | Body bytes | Packed bytes | Parts | Preparation effects | Largest frame |
| --- | ---: | ---: | ---: | ---: | ---: |
| Root2 | 35,192 | 37,470 | 6 | 3 | 13,318 |
| Job3, including 165 page refs and eight run refs | 44,451 | 47,375 | 8 | 4 | 13,576 |
| 63-page captured catalog | 7,371 | 8,048 | 2 | 1 | 8,259 |

Those eight modeled preparation effects plus one final commit fit sixteen.
The script uses a maximum-length partition, strongly escaped legal selector
strings and maximum root generation/root revision/floor. For precision, its
catalog generation is 1,000, catalog entities/assertions are zero, and its
modeled request expected revision is zero. Thus it is strong structural sizing
with ample margins, not literally every maximum-width scalar and envelope.
The final implementation control must use the finalized closed schemas and
maximum-width legal counters/revisions/generations. `47064`'s omitted modeled
inline receipt branch remains a retained fixture failure, not runtime evidence.

The complete final-selection proof has 165 references checked twice: **330 raw
read requests**, leaving 182 of 512 for catalog/root/job startup, actual escaped
value replies, preparations, stage inspections, resume checks and any semantic
inputs. Do not count an object as one read or omit nested client calls. Measure
the complete final invocation and the worst manifest batch, eight-run merge,
per-page verification and all metadata resume positions. Record every emitted
SDK frame, both counters, exact part counts and complete public result handling;
the proposal-only preparation simulator does not establish these paths.

Required focused negatives include missing/reordered/duplicate/rehashed pages,
forged keys/counts/memberships, cross-page duplicate IDs, skipped/altered cursor,
stale catalog/floor/root/job, action/version mismatch and edited first/later/
direct-finish metadata tokens. They must refuse before the proposed selection
effect. Known partial writes must retain the same semantic plan; interrupted
effects must stop unknown without replay. A native/public root2 control must
retain the exact old selection through drafts, select once through the final
three-stage CAS, refuse stale approval/generation, and preserve unknown after
publication and before its result receipt. Reuse unchanged passing controls;
add tests for the new format and newly exercised schedules.

The extra page/run keys, 157 durable verification steps, repeated job/catalog
staging and proof traffic must enter the exact lifetime-key/operation and
old-plus-staged byte ledger. Per-invocation fit does not prove the unchanged
8,192-key/32,768-operation/192-MiB native ceilings support the complete initial
build and rebuild. Safe run/job reclamation, selected-root floors, migration,
notes coexistence and populated peak remain required work, as the original
baseline requires. No complete native/full-profile/Word or GC qualification
follows from this design review. No runtime suite, native effect, model call or
docs checker ran; the parent owns global documentation checks and integration.
