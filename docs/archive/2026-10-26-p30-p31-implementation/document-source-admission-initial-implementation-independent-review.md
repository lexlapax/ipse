# Document admission wiring — initial implementation review

Read-only source review, 2026-10-29, of Root's initial implemented
[wiring direction](document-source-admission-wiring-direction-independent-review.md).
**Hold final implementation acceptance for the binding/deadline amendments below
and the separate actual evidence freeze.** No live egress bypass was found in
the reviewed path. No tests, effects, Saved replays or model calls were rerun.
The [plan](../../plan.md) owns overall acceptance.

## Source provenance

The supplied `_build/document-embedding-admission-sol-20261029/admission-source.sha256`
lists 175 full-host inputs. At inspection all ten document-owned owners below
matched that list. Only Lifecycle's actively changing ManagedLineage and
ManagedToolUse differed among the 175 current files. The earlier 47196 strict
compile/47197 four pure cases are author-reported retained work, not independent
runtime verification or a final immutable integration cohort.

| Inspected owner | Initial SHA-256 |
| --- | --- |
| CollectionStore | `2a9e1607b3cc97df212debab992fbf75320b7657da6373f117b69dcf8282ac67` |
| Inference / EmbeddingCall | `657f1e434b784a1046f504b7d032d0624b069e7fe3e970fe22315dca5697b12f` |
| Host | `2d169e1b1a95a3202cd7a37f65caf4222178053b06694cc226a58e871d131fb1` |
| Actions | `c49494289cc07690761281f83138cfa407ac454cec47719785b4255f7ca1cc56` |
| Registry | `c8cfca9829deb19bce18f8d8be99f86c009f97706ab776a48c3ceca4900e3e11` |
| Session.DocumentEmbedding | `f5389cd0231cd16b24e13558915f8eb71f64bd9a567f249acde99a3714b8f97d` |
| Invocation | `b684ee22a2d77ed012b7e76fdea4a4e6f19228288cbcff3383340fe702e169c8` |
| Session.InferenceDispatch | `9e595019b25dd625c75652f1ef4175a4ce278ad350241d9fd2e9d8715c7eb82b` |
| InferenceDispatch | `91f591387695a10b8c430ee0d1c2780d35b344a56f84d091862da408bd1dffa3` |
| Session | `8bf2c19bd9a7652e8af81d76dacc90020b219481d7d6e6d3b3fda6a6876b37ef` |

These identify initial source inspected during implementation; Root will freeze
the amended source/runtime separately. This review does not authorize changes
to Lifecycle's independent source-tool owners.

## Concrete amendments before acceptance

1. **Bind the source Session in historical Actions validation.**
   `CollectionStore.valid_source_binding?` format-checks `session_id`;
   `EmbeddingCall.valid_identity?` validates the parent identity but receives no
   Session namespace. The initial Actions embedding branch does not compare
   `source_binding.session_id` with `event.namespace`, which is the authenticated
   Session ID for an embedding action. Live prepare/bind/admit correctly compare
   `s.id`, so this is a historical binding/provenance gap rather than a demonstrated
   live egress exploit. Add the exact equality for guarded actions in the existing
   identity-aware Actions owner. A self-consistently retied foreign Session field
   must not be accepted as a valid saved source binding.
2. **Repeat pure identity expiry at final source time.** Root independently
   identified this gap: Registry's `live?` check runs in the Session spend RPC,
   while source UTC is sampled after that RPC. Carry the exact bound identity
   into dispatch data and apply `Registry.live?(identity, div(now, 1000))` using
   the same final trusted UTC as `DocumentSourceUse.current?`. Perform no new
   blocking RPC/IO after the sample. Exclusive expiry equality remains refusal.
3. **Carry the original invocation monotonic bound.** The initial plain gate
   uses `mono() + runtime_timeout`; `Invocation.output_timely?` is checked in the
   Session RPC, while its existing output clock may have an earlier original
   120-second deadline. Narrow the final gate deadline with that existing
   `started_ms + 120000` when present, or check that same original bound after
   the final wall checks. This preserves the existing admission restriction;
   it adds no new duration or physical-completion promise. Already-admitted IO
   may still complete late/unknown.

No counterexample runtime was executed for these source-supported conditions.
Focused pure/history mismatch and final expiry/deadline controls can accompany
Root's amended cohort. Do not repeat passing workloads merely to repair receipts.

## Source-supported behavior already present

The exact operator binding v2 selects fixed `shared_producer_v1`; exact v1 remains
accepted. Host calls source prepare before the action begins, resolves actual
ProjectIdentity outside Session and binds project/worktree/document namespace,
identity, Session and complete request hash. A selected caller cannot omit the
guard, including legacy create shapes; an unselected caller cannot supply it.
Read-only profile lookup remains unchanged. Embedding binding v2 retains the
execution/destination/selection binding and adds the prepared source binding.

Session's one live producer state is populated only after exact validated action
results have been durably committed. It records a new inline claim prepare with
expected revision zero and one exact matching stage commit in the same parent,
namespace/project/identity. The resulting operation ID and revision join the
prepared key/hash. Saved result arrays do not initialize this state. A shaped
prepare or unrelated commit does not authenticate source bytes: the held actual
row must still match revision/hash and that original commit operation ID.

Each guarded embedding is allowed only at the next position. Final admission
sets it inflight and fixes the bounded batch count; only a matching known
successful embedding action result at the durable action-commit seam advances.
Nonmatching/denied/failed/unknown embedding result poisons the state. Existing
interruption/Host-stop rules block continuation when no confirmed action result
can be committed. A pending stored claim grants neither adoption nor retry.

Inference begin requires a registered route and empty managed dependency union
for this document path. The separate plain-capture branch also refuses mixed
managed-note inference. Existing notes `capture_owned`/Mint behavior is not
replaced. The generic unregistered runner still exists for unrelated callers;
the actual selected Session path refuses it before dispatch.

The actual serialized target/body are checked by EgressGate and recomputed in
Session `wire_use` against the current active action, execution, admission,
expected binding and route. A private message reference/challenge bridges the
slot worker to the Session-owned callback; arbitrary process ancestry is not
accepted as Session authority. Source authentication runs under same-owner short
Identity → held document Collection ownership with no extension code. Actual
claim/anchors/source bundles/ranges/wire inputs are authenticated by the accepted
bounded helper; final source UTC follows the spend RPC. Cleanup/refusal leaves
inflight or poisoned liability, not reusable admission.

The successful short-lock decision precedes provider IO. Holding locks until
socket close, remote-byte recall or instantaneous owner-death atomicity is not
required by the original contract. A pre-admission failure sends no body; a later
loss may leave an already-admitted effect unknown. Actual request/owner-loss and
expiry observations, full runtime/helper provenance, public producer wiring and
the still-open acquisition/capacity/quality work remain separate qualification.

## Additive amended-source disposition

The subsequent source-only recheck accepts the three concrete amendments above.
It verified all five exact rows in
`_build/document-embedding-admission-clock-sol-20261029/admission-clock-overlays.sha256`:

| Amended owner | SHA-256 |
| --- | --- |
| Registry | `dc02f6a2090c9ae73ecfb3bd9f793c2537edf63bfa63e613bd2412c766da4cf4` |
| Inference / EmbeddingCall | `73316746e75c706165125ea02552c00653858dc276d9e0fd6b648a71042c5500` |
| Actions | `11a96c9ccfdf765718b32f68630149f50dd014718063d7ec35aae31ccdbbf916` |
| Session.DocumentEmbedding | `dc528ad4e26dc6e8734a73cf156cefc3deef826ae97821b45e71304d75c5e533` |
| InferenceDispatch | `3fc48533e23055aefb2b9ddb0afb6848e000f5d7157012c352fc54d013ed9d00` |

Actions now supplies the authenticated event namespace to
`EmbeddingCall.valid_identity?/4`; guarded source Session equality is decisive
there, while live `s.id` checks remain. Dispatch data carries the exact bound
identity; the callback uses the final same UTC for both source currentness and
Registry exclusive expiry, after blocking authentication/spend. The plain gate
deadline is narrowed by the original output-clock start plus 120000 ms rather
than renewing that bound. EgressGate's post-callback monotonic check therefore
also covers the earlier original deadline. These fixes preserve late admitted
IO liability and do not add a socket-lifetime lock.

The Registry outer trust schema also now admits version 2 and the fixed source-
use property; exact CollectionStore v1/v2 validation still rejects missing or
extra fields. Root reports that the first actual Session configuration attempt
found the old schema enumeration before effects, followed by strict 47200 and
three focused configuration/foreign-Session/deadline controls. Those results are
not rerun or relabeled as independently verified actual egress here.

No remaining source blocker was found in this amended slice. This disposition
does not replace the forthcoming exact actual Session/transport evidence and
runtime freeze, which still own live qualification. No fuller replay, test loop,
model request or effect was performed for the recheck.

## Additive callback-return correction

The subsequent narrow source-only correction is accepted. Exact
`admission-return-overlay.sha256` in
`_build/document-embedding-admission-return-sol-20261029` identifies only
DocumentEmbedding source SHA-256
`dd95dac4c48792962fadbf2cae523ae6ef7d935269cfa78046ea8fc45fba27b9`,
independently checked against the inspected source.

The initial callback returned bare `:ok`, whereas the actual Collection
document-read owner admits only `{:ok, _}`, `{:error, _}` or `{:unknown, _}`.
Word's reported diagnostic therefore spent the batch but correctly refused the
unsupported return before body dispatch. That is a functional refusal defect,
not an authority bypass or successful egress. The preserved initial source and
diagnostic remain historical evidence.

The repaired caller creates a fresh private reference and returns `{:ok, marker}`
only after source authentication, exact Session/wire/spend and final source/
Registry time checks. Collection seals/checks the read and checks/releases its
actual native guard; ProjectIdentity performs its checked callback/unwind; the
resource owner completes its return. Only the exact outer `{:ok, ^marker}` is
then translated to the `:ok` expected by EgressGate. An unrelated successful value,
error, unknown, exception or cleanup loss cannot be promoted to admission.
Underlying uncertainty remains refusal; the already-spent batch is not reset or
made replayable. No reader/native protocol or authority predicate changed.

The source recheck inspected the actual wrappers and performed no effect, test
or replay. The author's strict 47212 and Word's forthcoming fresh four-batch/
expiry controls are separate qualification; no native positive is inferred from
this return-shape repair.
