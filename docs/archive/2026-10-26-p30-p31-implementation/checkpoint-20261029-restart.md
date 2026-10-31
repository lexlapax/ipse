# Restart checkpoint — 2026-10-29

User requested: **save state for resume; do not kill ongoing processes and do
not start new ones**. Root stopped starting work immediately and sent the same
instruction to Lifecycle, Word and Shared. No process was killed. Goal remains
active; no completion, blocked or pause transition was requested/performed.
On resume, inspect exact live handles before continuing; an observation timeout
is not permission to restart an operation. Preserve all original stores, graphs,
logs, failures, `.serenity-*` state and unrelated edits.

## Goal and work conventions

Implement full P30/P31, required tests, adversarial post-implementation audit and
reviewer handoff, without shortcuts. The [plan](../../plan.md) owns acceptance;
[task status](status-20261029-current.md) and the
[preceding checkpoint](checkpoint-20261029-public-producer.md) retain the wider
unfinished ledger. Branch `codex/p30-p31`; last known pushed HEAD `be7bc9e`.
Most interdependent runtime work remains uncommitted. Never `git add -A`, erase
failed evidence, reset generations/operation IDs or force-push. Commit/push
coherent verified sections when their completion checks actually pass.

User authorized subagents. Four slots: Root, Lifecycle, Word, Shared. Implement
coherent sections and focused checks first; do not repeat aggregate suites or
full resource ledgers before implementation. Full baseline/package/final audit
remain pending. No live model call this turn; remote allowance still226/300
conservatively charged,74remaining. All new inference below was synthetic local
loopback. No new dependency, provider substitution or quota increase.

## Delivered this turn: reviewed own-root continuation

Lifecycle froze [own-root transition](own-root-transition.md), manifest
`899cc69b4eea94b1aa84b7b2a597cc8e7ebe932f686ffcc1caba8907d4da64ca`.
[Independent implementation review](own-root-transition-independent-review.md)
accepts that exact scope. Actual synthetic-model saved-consent capture, later
source list/read, final turn`:ok`, settlement, Saved and confirmed close pass.
All earlier settled-but-final-error stores remain preserved. The frozen original
graph omits Root's document Session delegates; the next combined control below
tests those sources together. No generic stale-root rebase, repeated capture,
current-record output, opaque-provider/compaction or owner-loss acceptance.

Root integrated the current behavior into Session sources, Collection SDK,
Knowledge developer and permissions operator manuals, plan/status/archive index.
Whole final manuscript/baseline qualification is still open.

## Delivered this turn: reviewed v4 Host infrastructure

The [v4 domain proposal](shared-producer-v4-progression-design.md) has
[independent direction approval](shared-producer-v4-progression-independent-direction.md).
It uses32reusable slots `genproducer4.<partition>.<ordinal0..31>`, pendingv4,
compact readyv4, guard2, eight-position aligned vector pages, existing pinned
inline CAS and fused page writes. Guard1/v3 remains distinct. Domain must prove
old ready belongs to an actually completed/selected group before slot reuse.
Pending/unknown cannot be adopted/retried. Full facts/group/capacity still open.

Lifecycle implemented `DocumentSourceUse.pending?/2`, `ready?/2`, guard2 and
complete authenticated head-derived ordered slice/count. Evidence:
[document-source-use-v4.md](document-source-use-v4.md), manifest
`ff35d3a1b24985ea1bd5a96ea60b5c4f13820677a6269f70b4c6302fdc0353ca`;
source SHA`ea0dcd6555b7d88f281a58682677263e5ffd44222d60baa9dbfa6355d270625b`.
Strict compile, two focused v4 relations and two selected v3 regressions pass.
The11-chunk/page0+8 relation is synthetic; slot31/count256 is structural only.

Root implemented the required actual-old-phase pre-put seam:

- `CollectionStore.execute` observes a pending-v4 inline claim after approval,
  under actual Identity and retained document reader. Expected0requires actual
  absence; positive revision requires exact same-key closed ready. Native witness
  generation equals the original request generation. Release the short read,
  then use the existing unchanged-generation CAS; no refreshed epoch.
- `Session` accepts the observation only from the exact current task/registered
  file-effect peer and active action. `DocumentEmbedding.prepare_inline/3` binds
  actual operation ID, complete request digest, identity, parent, namespace and
  project. Only its exact validated durable known inline result creates a live
  guard2 origin; unknown/failed/mismatched results consume and poison it.
- Original live clocks, batch spending, source authentication and final one-use
  transport gate remain. Saved results never recreate this volatile authority.

Evidence [document-inline-v4.md](document-inline-v4.md), manifest
`4e3707b2170c413fe9d084121c8a6b5f3c53ba16f42b3142156d220b995c36df`;
[independent review](document-inline-v4-independent-review.md) accepts both Host
infrastructure slices. Actual v4 producer/Session integration remains open.

Graph `_build/document-inline-v4-complete-sol-20261029` compiled175current host/
bundled sources to216modules with zero diagnostics (47233). Complete input
snapshot/hash list and regenerated app module inventory are frozen. First47231
omitted four bundled source files and failed Registry compile-time builtin lookup;
its graph/log remain. Nine focused Session tests47235pass. First47234test compile
used the shadowed Ipse.JSON.encode! alias and failed before tests; corrected to
Elixir.JSON. Selected native47236passes old-ready observation, intervening-write
original-CAS refusal, fresh observation/new pending write, and retained-pending
fresh-origin refusal. Home retained:
`/tmp/ipse-inline-v4-a92d7c3d203c6e897d2eca3c07a32728`.

Root source owners: `lib/ipse/session/document_embedding.ex`,
`lib/ipse/extension/collection_store.ex`, new Session handler,
`test/ipse/session/document_embedding_test.exs`. Existing Host/Invocation/global
dispatch owners remain Root's. Lifecycle owns SourceUse and notes code.

## Delivered this turn: combined notes control with fresh full artifact

[combined-notes-current.md](combined-notes-current.md), manifest
`5a387e279337eaa3aa2d17ded2c61d4bfe609800d5d71c646fc45a5ca629e6cd`.
Graph `_build/combined-notes-assets-sol-20261029` forks the complete inline-v4
Host graph with **no Host BEAM change**, then builds current full native knowledge
against that SDK and explicitly selects it in the copied catalog. Artifact:
`69eb134365d73256a75d31c99987502df809451c6d244396018a79dcee59447d`.
It includes recall export and before-request subscription. Helper stays40fa.

Actual47243passed genuine saved consent, typed host outcome, model-selected
source list/read, capture, historical-root notice, later source list/read, final
turn`:ok`, status-only previews, denied write/shell, Saved and confirmed close.
Home `/tmp/ipse-combined-notes-full-47243`, Session
`b94bf0e8603bd11648bd9c4bba6d06f0`. Read-only47244passes native exact receipt,
floor anchor, settled Consent and signed release claim; original213879B journal
unchanged. No effect replay. Shared is independently reviewing this evidence.

Failures preserved separately in
[combined-notes-artifact-diagnostic.md](combined-notes-artifact-diagnostic.md),
manifest`f604c946ea9b15e6b90aacfb18d6740e97c576b60f32412a7e1d1aa798f0cd11`:
47239loopback EPERM before Session;47240redirected display had no matching native
terminal;47241proper PTY selected inherited minimal e719knowledge artifact with
no recall subscription, so its known saved capture had no surviving old-root
dependency and correctly no historical notice, failing that fixture assertion.
Do not replay47241. The final run deliberately selected a freshly built full
artifact. Initial evidence freeze47245stopped on hidden release glob;47246only
finished archive copy with `match_dot:true`, not another runtime run.

Root processes all terminal: compile80340failed,28224passed; combined90510failed,
3189passed; docs18957failed. All named native, inspection and freeze commands
are terminal. No Root process needs termination or restart.

## Current agent work at stop request

**Word** owns domain Producer.Progress/C/Generation/Job/Corpus/schema/build/tests.
Latest: coherent v4 strict builds pass after retained clause-grouping failures.
11source chunks produce page0(8)+page1(3), six validated embedding calls,
canonical assembly47reads. Full page6storage mutations/10effects; final3row page
4storage mutations/6effects. Unknown claim/inference/page/ready cases pass no
continuation/replay. Valid explicit facts→private Job append→same-job completed
group proof→slot0reuse passes. Last reported remaining corruption fixture had
`Map.fetch!` on missing object; correcting fixture to real Host failed-read shape.
Guard1 preservation/targeted bounds and frozen candidate precede actual new v4
Session fixture. Public candidate version2page/inspect adds vector_cursor and
previous_ready to existing fields; v1unchanged. Actual v4 native Session production
has NOT yet passed. User stop instruction sent; obtain Word checkpoint/live handle
before any continuation. Earlier reported61102must be revalidated, not restarted.

**Lifecycle** next owns real pending proposal acceptance. Exact typed proposal:
[pending-acceptance-proposed-contract.md](pending-acceptance-proposed-contract.md),
latest revised SHA`ff033042...` from Shared (inspect current file, not old a4c9).
[Independent direction](pending-acceptance-independent-direction.md) releases
bounded implementation, not effect enablement. A retained
`ObservedRead.with_managed_proposal/7` and exact card preparation strictly compile
and pass one actual signed pending native fixture. First launcher lacked Ipse
supervision and returned pre-publication callback unknown; original home/log
retained, fresh corrected fixture passed. Publication remains closed.

Acceptance must preserve original proof/origin and signed pending clock in a
distinct accepted_decision, deterministic separate lineage and immutable accept
link. Actual native `accept CODE` event binds exact ID/key/revision/value/text hash,
source/policy/recipe/client/Session/render/input; no OperatorAssertion/literal
promotion. Atomic typed CAS removes exact pending/live, inserts accepted note/link
and signed metadata; both original/accepted suppression and shorter clocks apply.
Concrete remaining gates: closed encoding/schema, actual32-unit read/page splits,
6144B signed metadata,64KiB input,2KiB receipt,8KiB escaped display, no assumed
five-sidecar fit. Latest ownership question: ManagementTerminal has exactly four
lease roles (journal,Identity,Consent,Collection), while genuine pending-source
verification may need an original Session/source lock; determine whether that
fifth lease must survive display or needs fresh admission under original rule.
Do not silently borrow the forget exemption or extend native roles speculatively.

**Shared** completed own-root and inline-v4 reviews and pending acceptance direction;
now reviews combined notes evidence without rerunning effects. Stop/checkpoint
instruction sent; obtain its final disposition/checkpoint on resume.

Additive stop confirmations: Lifecycle saved
[its exact pending checkpoint](checkpoint-pending-acceptance-20261029.md).
Its handles91062/44241exited0,35600exited2; cells1719/1738completed. No live
test/PTY/native process is known from that section. Shared saved
[its review checkpoint](shared-controller-review-restart-20261029.md) and
[combined-notes scoped acceptance](combined-notes-current-independent-review.md).
Verification is terminal:36archive rows,1697parent/1727candidate runtime rows,
zero Host BEAM differences, only two catalog aliases changed and30added artifact/
build-input paths; nine tar sources and exact166-event/213879B journal verify.
Shared owns no live exec/native/test handle. No new process started after the
restart request. Original source revalidation before proposal publication remains
required; whether faithful local pending/historical display itself needs a fifth
source lease is an open purpose question, not an assumed native role expansion.

Word's final stop checkpoint is `_build/shared-producer-v4-design-20261029/HANDOFF.md`
(current state first). It reports no live handles:97049terminal0(corruption case),
93178terminal2; all other handles already terminal. No process was killed or
started after the request. Current v4 source is uncommitted and not yet frozen;
`artifact` and `artifact-preflight-fixed` are historical intermediates, not an
actual-Session-ready candidate. Actual v4 Session fixture has not been written
or run. Next code is version2-only Corpus complete public continuation: current
next arguments are inside coverage. Then final coherent artifact/freeze and one
fresh public v4 Session case on the reviewed Root graph. Its checkpoint also
corrects the printed239B frame claim: that was hydrate-only, not the maximum
whole-producer frame. All agents now report no live owned process handles.

## Unfinished documentation check — next safe repair

Root reconciled current manual/plan/status/index but the one batched docs47247
FAILED:938Markdown files/7841local links,73errors. All73are raw frozen manual
snapshots under `shared-producer-public-adoption/source/docs/` (collection-sdk,
knowledge-extensions, operator corpus): their original relative links resolve
inside the evidence snapshot tree. Existing private-ledger permission warnings
are separate. Raw log `/tmp/ipse-docs-check-47247.log`; process18957terminal.

Do not modify frozen snapshot bytes/manifests or hide the broken links. No fix
was implemented before the user stop. Root was considering a narrowly explicit
provenance `link_base` for raw archived snapshots in `dev/check-docs.exs`, with
validation against repo-relative actual source and hash-bound snapshots; existing
transformed archives must retain their old resolution. This is only an idea,
not a selected implementation. Avoid recursive navigation symlinks (earlier cycle
already fixed in HEAD). Inspect current checker/archive policy and choose the
smallest legitimate fix; add meaningful focused checker controls if behavior
changes, then one corrected batched check. `dev/check-docs.exs` itself has not
been changed this turn.

Do not claim new docs pass, combined document acceptance, full baseline,
installed/quality/capacity qualification, final audit or commit/push completion.
Whole P30C–E, full notes lifecycle/recall/acceptance/quality, complete document
facts/production/GC/migration/capacity, real Word fidelity/invalidation/local model
qualification, research transfer/planning residuals and final P31J remain active.
