# Document producer admission wiring — independent direction

Read-only source/design review, 2026-10-29. **The proposed bounded integration
is supported with the conditions below.** This accepts an implementation
direction, not enabled behavior, provider egress or a completed producer. No
production edits, tests, effects or model calls were performed. Root owns the
binding/dispatch/Invocation changes; Lifecycle's source-tool owners are separate.
The [plan](../../plan.md) owns acceptance.

This follows the original [short-lock admission direction](document-producer-source-egress-independent-review.md)
and the accepted, still-unwired [stored-byte relation](document-source-use-independent-review.md).
Inspected seams include CollectionStore/Registry identity validation,
EmbeddingCall in `lib/ipse/extension/inference.ex`, Actions effect binding,
Session.Invocation action commit/inference completion, Session.InferenceDispatch,
the registered InferenceDispatch runner, Provider.Embedding, HTTP and EgressGate.
These are current-source seam observations, not a new frozen whole-source cohort.

## Fixed opt-in and authenticated binding

An exact operator documents binding v2 with fixed
`source_use: "shared_producer_v1"` is a small existing-owner extension. Preserve
the exact v1 form and its behavior. Registry must retain the selected v2 value in
the authenticated artifact/instance identity and saved metadata. This is operator
configuration, not a worker-supplied permission field.

For that selected identity, every `embedding.create` must carry a valid guarded
request; omission, including an old version-1 create, refuses without an ordinary
fallback. A guard on an unselected identity must also refuse rather than be
silently ignored. Read-only `embedding.profile` remains unchanged. The fixed
guard shape is the reviewed version/claim key/revision/logical hash/batch index;
it is an untrusted reference until actual owned authentication succeeds.

Resolve actual existing ProjectIdentity outside the Session GenServer, using
the CollectionStore prepare/bind pattern. Bind the prepared project/worktree,
fixed document profile/namespace/operator selection, exact identity, Session and
complete request digest into the embedding v2 effect binding. Existing execution,
destination and selection pin still have to match. Guard/source fields are Host
authority data, not additional provider request-body fields.

Actions intent/result and Saved validation must compare this binding against
the actual parent identity and frozen metadata, including mandatory-versus-
forbidden source binding. A permissive structural validator with optional scope
must not erase that identity comparison. Historical validation need not acquire
OS locks or recreate live project authority; fresh dispatch owns those checks.
Approval continues to show the complete request, effect binding, execution and
destination. The selection digest authenticates configured identity, not provider
model weights or source permission.

## One live claim and bounded batch state

Use the existing volatile invocation and committed action-result chronology.
Track one original successful `collection.store` claim CAS, with its exact
project/namespace, parent invocation, identity, committing operation ID and
actual claim relation. The held reader must authenticate the current pending
claim revision/hash and return that same committing operation ID. Matching any
old successful commit, a worker-reported operation or a newly restored pending
row is insufficient. Do not replace this original claim origin after poison.

Maintain at most four sequential batch positions: next, inflight and terminal/
poisoned state suffice. Final admission consumes exactly the current batch for
the exact active embedding action/admission. Duplicate, skipped, reordered,
concurrent, foreign-invocation or mismatched claim requests refuse. No durable
workflow, resume token or new interpreter is needed.

Enable the next position only after a known matching embedding response has
passed the existing full bounded capture, vector/input/selection and action
binding validation. Prefer the existing committed action-result seam to avoid
advancing from an intermediate transport tuple that later fails validation or
journaling. Unknown, timeout, owner loss, denied or mismatched outcome poisons
the path; it cannot reset to the previous next position. A known successful
transport followed by unconfirmed result commit is not retry authority. Session
resume can validate historical events but cannot restore this volatile origin
or inflight batch permission.

## Final short-lock decision

The selected registered route must enter plain `EgressGate.capture` even when
the ordinary managed-note dependency union is empty. Current `managed_execute`
only activates its protected branch for nonempty managed dependencies, so that
predicate alone cannot cover documents. Refuse unregistered/alternate fallback
for this source-use path. Preserve ordinary unrelated embeddings and the notes
`capture_owned`/Mint transport behavior.

If a guarded document action also inherits managed note/content dependencies,
the smallest safe initial choice is refuse that mixed case until both existing
barriers are composed. The new plain branch must not bypass ManagedUse or weaken
the notes owned-send contract merely because document admission is available.
This is an implementation scope choice, not a permanent ban on composition.

The actual transport supplies the serialized target/body. Match it to the
current approved action/selection/registered route, then use same-owner short
Identity → document Collection ownership for the stored relation. No worker
code runs under those locks. Authenticate exact claim/anchors/catalog/bundles/
byte ranges/ordered inputs through the reviewed bounded helper; check exact
current Session/job/action/invocation, Registry identity and original claim
commit before returning success.

The last trusted UTC sample must follow **all blocking checks**, including any
queued Session spend RPC. A safe ordering is mark the exact batch inflight in
that RPC, then sample and require `observed <= now`, nonhistorical source and
nil expiry or `now < expiry`, under retained ownership. If this final time or
subsequent wrapper/owner-release check refuses, retain poison/inflight liability;
do not roll the batch back into reusable authority. Equality at expiry refuses.
EgressGate's own upstream/monotonic check remains required after the callback.

Return `:ok` for exactly one admitted request, release short locks and perform
transport IO afterward. Mutation/revocation/expiry ordered after admission may
coexist with already-admitted bytes or a later response. That is admitted
inflight liability; it neither authorizes another request nor requires locks
through socket close, syscall atomicity or recall of remote bytes. A killed peer
before callback completion cannot return authorization. Unknown cleanup cannot
become known success or a replay token. Existing single-send behavior must not
grow an automatic retry, redirect or alternate route under one admission.

## Focused qualification before enabling this slice

Use a fresh finite-TTL positive through actual selected artifact/Session/Host,
registered transport and exact source claim. Observe exact approved wire and
unchanged old selection. Exercise omitted guard/v1 downgrade, unselected guard,
foreign project/identity/invocation, stale or resumed claim, duplicate/skip batch,
unregistered route and changed approved wire. All pre-admission refusals should
produce zero request-body egress.

Exercise expiry during approval, equality and expiry during blocking validation;
source/head/bundle/catalog/Job/root/claim changes; and real current-owner loss.
Observe mutation ordered before refusal versus after successful short admission
without claiming socket-lifetime exclusion. Include a known response advancing
one position, malformed/unknown/denied response poisoning and no automatic replay.
Existing note behavior and unrelated legacy embeddings need focused compatibility
coverage. These are required new qualification directions, not checks run here.

The implementation freeze must pin actual transport/provider/HTTP/EgressGate and
selected runtime, not only the helper or source-only verifier. Keep full source
acquisition, later pages/facts/group completion, physical/journal/peak capacity,
GC/migration, output and representative document quality acceptance separate.
