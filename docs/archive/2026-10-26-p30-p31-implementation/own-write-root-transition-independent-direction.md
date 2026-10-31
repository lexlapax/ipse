# Own-write root transition — independent source direction

Read-only investigation, 2026-10-29, of the
[proposal](own-write-root-transition-investigation.md), SHA-256
`7934e0b0a924b72bda27b79ac97880bab3a4305199c5f4a1d86692301195f18c`.
**Existing publication/CAS evidence is sufficient for a narrow predecessor proof
within Collection's stated cooperative filesystem trust boundary. A new native
or managed-receipt format is not justified by this case.** Model projection and
fresh final admission still need an explicit bounded implementation and focused
qualification; neither is already supplied by write success. No implementation,
gate, test, replay, native read or model request was changed or run here.
The [plan](../../plan.md) owns acceptance.

## What existing generation evidence proves

Collection's actual publication path is `apply_mutation` → prepare → publish →
one native root switch. It checks expected generation and affected revisions,
adds one new local operation receipt at generation `n + 1`, validates next state
and publishes its content-addressed manifest/root. Already-known operation IDs
return existing evidence without executing again. Valid state requires generation
equal to local operation count, unique operation generations and valid record/
floor lineage. Manifest/root bytes and selected profile/project are checked on
load. **Valid-state shape alone does not prove historical uniqueness**; the
authenticated observation plus the actual supported transition path does.

Imports, their staged pages/operation transfer/commit/abort, and checkpoint
restoration return their prepared state to that same outer mutation publisher.
Their imported operation history is distinct from the monotonically advancing
local generation. Rolling records back to a checkpoint is another publication,
not resetting the local generation. Collection encoding explicitly preserves
local operation generations. Cleanup/reclamation removes pending or unselected
objects/manifests and never selects an older root. Invalid selected bytes refuse;
there is no inspected automatic repair path that rewrites a selected root at
the same generation or silently resets its operation ledger.

Thus, for the **same actual existing project/namespace/profile/control path**,
an authentic cached complete old root at generation `n`, followed by this
Session's exact known newly committed v3 capture at expected generation `n`,
has one supported successor at `n + 1`. Reacquire actual Identity/Consent and
authenticate the exact currently selected root at that generation, its own
operation/receipt and advancing floor anchor. Any intervening supported mutation
makes the current generation later and refuses this adjacent transition.

For `n == 0`, authenticated absence is still necessary: a shaped generation-zero
map is not proof of absence. But the original host cache already binds actual
absent root bytes/state, and no supported publication materializes/replaces a
generation-zero root. The same native expected-generation first commit therefore
provides the needed adjacent proof. Do not add a repeated prior-root digest to
every receipt simply because the outcome does not repeat that cached witness.

This conclusion depends on existing authority boundaries. It does not defend
arbitrary operator-state deletion/replacement, rollback of the filesystem by an
external actor or forged host memory. Collection is internal and explicitly
requires callers to hold project control authority for consent publications;
public workers cannot supply raw collection roots or bypass their owned mutation
routes. If a concrete exposed writer violates those rules, fix that route rather
than treating generation shape as a cryptographic defense against it.

Use the actual bound action intent/result and existing managed receipt/normalization
digests, not a worker-supplied receipt or any operation merely found in the ledger.
Require a newly confirmed own publication, not existing/unknown/interrupted
adoption. Same Session/project/pin/epoch, complete common predecessor root and
positive cache classification for **every** old dependency remain necessary.
Do not generalize this to record/content observations, another writer, missing
history, mixed roots or nonadjacent generations.

## Projection is the remaining semantic gap

`ManagedUse.observe_all` rejects a changed v3 root before a useful verdict;
`ManagedReference.current?` requires exact old subject/root equality. Generic
withdrawal refuses assistant tool-call messages and some provider-data shapes.
Consequently the current settled-but-refused fixtures are not evidence that the
existing projector can already complete their final model request.

Do not rewrite an old root map, request/result digest or cached dependency to
pretend its original empty index/nil get/snapshot observed the new root. Such a
result remains a historical statement. Preserve original source IDs, payloads,
receipt hashes, journals and provider continuation/tool-call envelopes. Successful
capture is not permission to call old note content current.

The small supported extension is an explicit **payload-free-root-only** projection
at the existing preflight/reference seam. Journal its exact old dependencies,
own committed action/receipt relation, authenticated fresh current-root observation
and before/after message/guard binding using existing bounded digest conventions.
The new current guard must represent that fresh observation, with its own actual
request/result identity; it must not reuse old empty-result hashes as a purported
current observation. Any derived cache classification must be admitted only by
that exact validated host transition, never by a bare worker root label.

Use a bounded host-owned historical metadata notice/reference at a safe message
boundary: earlier root/absence observations describe generation `n`; the exact
own publication committed `n + 1`; current record eligibility is not established
by those old observations. Existing source payloads and completed tool-call pairs
can remain unchanged under that explicit historical presentation when all causal
dependencies are verified payload-free root metadata. Do not apply generic
withdrawal to opaque provider/tool structures merely to make the case pass.
Preserve native call/result pairing and provider data; refuse unsupported
projection shapes rather than discard continuation. The exact notice/message
format needs implementation review, not a new generic conversation framework.

Apply the proven current-guard projection consistently to active occurrence and
producer/call dependency resolution. Merely updating the model occurrence index
while selected source producers still return old-root obligations will reproduce
a mixed/stale refusal on the next source call or capture. Preserve the historical
dictionary/events; only an explicit validated transition may change the *current
projection* of payload-free guard obligations. Record/content dependencies keep
their existing checks and cannot be stripped or reclassified by this path.

Saved must recompute the transition chronologically from original cached read,
bound successful publication and recorded observation/projection. A historical
event does not recreate a volatile send/effect permit or authorize automatic
mutation replay. Every later dispatch still needs fresh actual current authority.

## Final admission and bounded qualification

The recorded preflight observation is not final send permission. Revalidate the
exact current successor and own-operation relation at the existing final owned
send callback with current Identity/Consent and policy/source times. Use either
the retained Collection callback or the demonstrated project-control exclusion
already required of every protected writer. Do not add a lock-through-socket-close
or new native subsystem merely because an ObservedRead view closes before its
return; identify an actual writer race before requiring stronger ownership.
Already-admitted IO and uncertainty retain the existing contract.

Before acceptance, qualify a genuine new model-selected capture followed by a
completed final turn, actual known worker-result delivery, exact ledger/root/
settlement and Saved reconstruction. Include foreign/missing/unknown receipt,
wrong/absent predecessor, stale/mixed/record dependency, changed pin/epoch,
intervening write, tampered transition/replay and the actual tool-call/provider
shape. Check a subsequent selected-source read/capture retains complete projected
lineage, not only the immediate final answer. Preserve the two original
settled-but-error stores without replay. These are future focused controls,
not passing observations from this source review.

Inspected unchanged Collection source is
`8115f10d5c251261bf2aaa2e2aa4e6202934724c113850d1f41803e6fd622a56`;
Migration `90387e266dc5f2d05f4ab12af3a9d37ce8578ab6037b79f2743b7cae19c33900`;
Encoding `fb43986d1f8d984b4425fc6df0c645ed692dea34ae6a852803a80e002d07b377`;
ManagedReference `916ef4e4423c92222b5d8561d121df9abc76e970fd156643195a4b13ea57fead`;
ManagedUse `5a81882447bcc6ac2061b4392b07edecad927ea615eb3a5835eec09b8949762b`;
ManagedLineage `f7dcce1055deab1a30292c34148553d05a2cc6df9ace966c8fe1ea4a34e75c95`;
Reference `bd7058deaa289734da26ff1141a42903f9c0289a6cf3add3b0e2bd9eade97499`.
These identify read source, not a new compiled or tested freeze.

## Additive concrete projection proposal

Lifecycle's subsequent proposal places the closed version-2 root transition
inside the existing `managed_preflight_result` projection. That placement is
supported: reuse its chronological Saved path and existing binding/plan/before/
after message hashes rather than introduce another workflow. The proposed fields
bind Session, complete old dependencies/digest, exact own action and receipt
digests/operation, actual fresh snapshot observation/dependency and notice digest.
The concrete encoder/validator and runtime remain subject to source review.

Retain the full host-validated newly successful v3 capture result with its effective
prepublication union, using the existing new-capture predicate. The small current
`write_facts` alone does not validate the complete request/normalization/receipt
relation. Retained actions, transitions, links and generated projection events
must participate in existing entry/byte bounds. Link resolution is bounded,
strictly generation-increasing and same project/pin/policy; cycle, missing entry,
content dependency or inconsistent root refuses. Original dictionary/cache
entries remain immutable facts; admitting a fresh snapshot guard requires the
exact authenticated transition, not generic worker cache insertion.

Actual operation inspect plus snapshot/recheck under existing Identity → Consent
control can establish the relation under compliant-writer exclusion. No new
same-native-transaction inspection protocol or prior-root receipt commitment
is needed merely to combine those existing reads. Fresh final send admission
must still validate that same successor/own-operation relation after preflight.

Use an existing Reference message only if its exact marker/content semantics
fit. Do not attach a misleading old reference marker to arbitrary new notice
text. A single closed host-owned notice marker in the bound projection is a
small permissible alternative. Its model-facing user-role transport must not
make it a native operator event, unattended original input or new attested
SourceIndex occurrence. Preserve original tool pairs/provider continuation and
source bodies; emit only fixed historical metadata/operation/root information,
not the cached action's note/request payload. This provenance check is required
alongside exact message hashes and safe-tail validation.

The first draft source review also identified two functional consistency points,
which Lifecycle confirmed and amended while the candidate was still unfrozen:

- The model plan can contain only the inherited recall root while the successful
  capture's complete prepublication union contains that root plus two own nil
  gets. Requiring exact equality of those unions preserves the observed refusal.
  Validate every member of the complete stored write union and every plan member,
  require the plan to be a subset under the same full root/scope, and project the
  entire authenticated write union so later source-producer lookups agree.
- The appended notice must be admitted as its own fresh-guard occurrence in the
  reference state. Updating only earlier occurrences leaves the notice untracked
  if later projection/compaction removes those earlier messages. Keep its owned
  provenance and test that it creates no native SourceWindow input attestation.

These are draft-review conditions, not a frozen implementation or passing runtime
claim. No counterexample runtime or test was run by the reviewer.
