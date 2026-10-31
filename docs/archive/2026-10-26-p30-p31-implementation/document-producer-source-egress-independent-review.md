# Document producer source egress — independent requirements and partial-repair review

Scoped read-only review, 2026-10-29, of the
[source investigation](document-producer-source-egress-gap.md) and
[worker policy repair](shared-producer-worker-policy-repair.md). The
[plan](../../plan.md) owns acceptance. This record narrows the proposed repair;
it does not implement or qualify producer dispatch.

Disposition: accept the worker checks as a **partial repair only**. The original
producer remains held for missing trusted source admission after approval.
Accept the investigation's factual gap and bounded source-authentication needs,
but amend its mandatory architecture and tests as below. The original contract
does not require document locks until socket quiescence, a new independent lease
owner, a general recipe interpreter or a general workflow engine.

## Original contract, before later proposals

The frozen [baseline](baseline.md), paragraphs beginning “Before each dispatch”
and “Automatic seed recall,” requires current source/expiry/permission checks
before every actual model dispatch, including continuations. Its retention
section says reads do not renew TTL and expired/missing support invalidates use.
The [original plan](../2026-10-26-p30-p31-plan/index.md#persistent-consent-without-repeated-prompts)
requires current permission/source-version/budget recheck and explicit ordering
against revocation. An embedding request over managed captured document bytes
does not gain an exemption through full-input or destination approval.

The same baseline's permission section expressly calls for a **short** control
lock, released during model requests and other long IO. It says already admitted
remote requests may still send bytes after revocation acknowledgment. The original
[contracts](contracts.md#consent-commit-order-and-process-coordination) likewise release
the lock during work and preserve remote in-flight uncertainty. These clauses
support a final locked, one-use admission decision; they do not promise physical
recall, clock-atomic network syscalls or no remote bytes after acknowledgment.
The [expiry audit](expiry-requirements-audit.md) explains the distinction, but its
later proposed local-publication machinery must not be imported as a new universal
remote-send requirement. A later local **active publication** still needs its own
current source/policy and generation checks; remote admission cannot authorize
an unrelated late root switch or revive expired evidence.

Consequently, a source already expired at the final admission must refuse. A
source live at that decision can expire while the one admitted request is in
flight. That is admitted liability, not permission for another batch or replay.
After possible dispatch, timeout/loss must preserve uncertainty and reservations;
it cannot be reported as proof that nothing was sent.

## Smallest supported host direction

Use the existing plain `Provider.EgressGate.capture/before_dispatch` for this
document route, leaving existing managed-note `capture_owned` behavior unchanged.
The plain gate already checks actual serialized target/body hashes, the exact
caller, one use, upstream liveness and an existing monotonic request deadline.
Its trusted verification callback can make the final source decision under short
ProjectIdentity → documents Collection ownership, then return `:ok` and release
the owners before transport/long IO. Define admission at that locked decision;
the gate's subsequent process-local `:authorized` flag is bookkeeping, not a
second policy decision. No new approval, queuing workflow or independently
reusable grant may intervene. A failed/killed callback that cannot return `:ok`
cannot authorize; loss after the decision is accounted as already admitted work.

This is a proposed use of an existing seam, not evidence that it is wired today.
The inspected current `HTTP.finch_bounded_request` invokes `before_dispatch`
with the serialized request immediately before its one Finch request. HTTP and
the embedding provider are outside the 28-file investigation snapshot; an
implementation freeze must include those actual boundary owners and its selected
transport/runtime. Finite pool/connect/send time after admission does not itself
require holding the source lock through response or socket close. No automatic
retry, redirect or alternate route may turn the one admission into another send.

The callback and live owner need these bounded facts:

- Require the reviewed document source-use binding for embedding actions from
  this admitted producer artifact/tool invocation. Do not let an omitted binding
  fall through the ordinary or unregistered branch. Other embedding callers keep
  their existing behavior. Bind operator-selected artifact/instance, descriptor,
  collection profile/namespace, project/worktree, Session/job/action and live
  Registry identity using their existing owners.
- Authenticate the actual current pending claim and its revision, Job/catalog,
  selected root including absence, source heads and complete bundles under the
  retained document owner. Match source order, bundle/source-set/chunking hashes,
  chunk ordinals/IDs and exact raw/canonical input bytes to the next batch and
  prepared wire. Reproduce the bounded reviewed recipe relation; a pending JSON
  record, matching-looking hash or arbitrary path supplied by a worker is not a
  source authority.
- Read observation, expiry and historical fields from authenticated complete
  bundles. Heads do not contain those fields. After all blocking validation,
  sample host UTC and require `observed_at_ms <= now`, `historical === false`,
  and nil expiry or `now < expires_at_ms`; equality refuses. Preserve the original
  times and lineage. This authenticates current stored content, not an external
  author's truth, an original Session's current availability, or model provenance.
- Match the configured registered route, exact profile/selection pin and actual
  serialized target/body to the current approved action. The separately accepted
  selection bootstrap/pin does not supply source authority.
- Reuse bounded live invocation state or existing current-action evidence to bind
  the confirmed original claim CAS and next batch. Spend/mark a batch in flight
  at admission; enable the next batch only after its known matching result.
  Unknown, denied or mismatched outcomes terminate/poison this volatile path.
  Stored pending records and resumed journals cannot reconstruct it. This is a
  single claim and at most four batch positions, not a generic durable workflow.

A small held **document** read callback is a justified Collection/SDK gap:
`ReadView` releases ownership, while the existing managed-read callback is a
32-unit notes path. Reuse packed-value readers, JSON/hash validation and retained
native ownership; keep worker code outside the host lock callback. A closed
additional reviewed source-use recipe/adapter is sufficient. A programmable
interpreter with an open instruction set is not established as necessary. Domain
schema/chunking behavior stays extension-owned except for the narrowly reviewed
verification relation that the trusted boundary needs to reproduce.

The proposed extra claim-CAS precondition API is also not required just to fence
egress: pending metadata is not active evidence or a dispatch capability. Existing
generation/revision CAS captures that claim; the final host callback must reject
an expired, changed or unauthenticated claim before inference. A separate atomic
claim hook would need its own concrete invariant beyond preventing source egress.
Keep the worker's useful pre-claim checks without turning this optional stronger
check into a new native prerequisite.

The investigation's 269-logical-record / 17,629,184-record-value-byte estimate is
an arithmetic upper bound, not a measured IO/memory qualification. Packed reads,
bundle assembly, escaping, duplicate/depth validation and total live bytes need
explicit bounds and accounting in the document callback. Do not silently reuse
the notes cap or advertise full eight-source support from the estimate alone.

## Worker repair and retained evidence

Independently verified source-investigation manifest SHA-256
`1baa506e5b88280923b2ed0251ad529d9be2370e4230e706a9a86fe51807966c`,
both named archive hashes and all 28 regular tar members against `source.sha256`.
Verified worker manifest
`7f880bd4bc594fea9dfb8026c1aaa530e98b958ddf8f568bcb758b88225b9ad7`,
its three source snapshots plus freezer, three logs, ancestor manifest and exact
26-file candidate artifact tree. Producer source bytes agree across both freezes.
The [verification script](document-producer-source-egress-review/verify.exs) and
[result](document-producer-source-egress-review/verify.log) retain those checks.

Source inspection confirms `Evidence.current?` checks before claim preparation,
claim commit request, each batch and after the final batch. Actual head revision
and hash join the v2 source bindings. Before each batch the worker reloads the
exact pending revision/value, pins one fresh read generation and checks captured
Job/catalog/root/head/pending anchors. Static captured bundles remain bound by
those heads; UTC is resampled rather than accepting a worker-supplied deadline.
Old private v1 records refuse. Unknown inference/storage stops, and a later
invocation finding pending work supplies no retry or adoption token.

Retained 47145 demonstrates the original expired-source counterexample through
four modeled calls and `page_ready`; it is a failing desired-refusal assertion,
not a native egress observation. Retained 47146 has eight focused nested passes:
expired/historical/future inputs make no claim or inference call; expiry and
source/root/catalog changes stop subsequent batches; unknown does not replay.
The finite-TTL positive retains four calls, twelve effects, 114 worker reads,
4,795-byte ready metadata, the unchanged 45,064-byte page and a 12,759-byte maximum
host frame. Retained 47147 records a strict candidate artifact build. This is
worker/model-fixture evidence, not a new native provider or host admission test.

These checks cannot close approval waiting or the worker-to-host race. The
source-only snapshot is not an atomic whole-worktree build; the worker artifact
is retained but is not a new complete host runtime cohort. The independently
reported public zero-claim/zero-egress gate is separate containment, not complete
producer acceptance, and its forthcoming freeze is outside this review.

## Required focused implementation qualification

Qualify the actual final callback with a current finite-TTL positive; expiry
during approval and exclusive equality refusal; historical/future observation;
changed bundle/metadata/head/catalog/Job/root/claim/chunk/order/route; omitted
binding and unregistered-route refusal; duplicate batch, foreign invocation,
pending adoption and unknown/no replay. Observe zero request-body egress on a
pre-admission refusal, exact approved wire on admission, and unchanged old
selection. Demonstrate concurrent mutation orders before or after the short
admission decision. Do not require the concurrent writer to wait until a remote
socket closes: it may proceed after admission while that request remains liable.
Owner-loss and cleanup controls must preserve ordinary unknown/accounting and
prevent a new admission, without claiming rollback or physical byte recall.

No tests/effects, model calls, runtime edits or gate changes were repeated for
this review. The complete producer, source acquisition, full capacity, lifecycle
and quality acceptance remain open.
