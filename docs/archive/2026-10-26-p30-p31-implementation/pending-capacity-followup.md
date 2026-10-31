# Host-enforced pending proposal capacity

2026-10-27. Uncommitted P31 component work; this is not milestone acceptance,
native-profile qualification, or the typed retention workflow.

The Knowledge worker counted retained `pending.` records before publication,
but `NormalizerV3` did not independently enforce that bound. A synthetic
checked-page fixture with 64 pending records showed the normalizer accepting a
new proposal (seed 46552). An earlier version of the test asserted inside the
Identity callback and only reported an unknown callback outcome (seed 46551);
the revised fixture sent the result back to the test owner and exposed the
successful normalization. The records were synthetic; this did not execute an
unauthorized production publication.

The managed Collection callback now has a fixed `pending_summary` read. While
the transaction lock and original-owner capability are held, it walks at most
64 already-loaded `pending.` references and totals their stored encoded byte
sizes without reading value objects. The operation costs eight units in the
existing 32-unit callback budget. The version-3 normalizer refuses a proposal
when 64 references already exist or when retained bytes plus the candidate's
encoded bytes exceed 256 KiB. Exactly 256 KiB is admitted. This includes expired
and malformed public values under the prefix and does not silently prune them.
Literal-note publication is unchanged. Other publication or import paths need
their own capacity rules; this change does not establish a global store quota.

The isolated diagnostic selection passed 46 tests (seed 46558) with the
test-only 7.2.11 helper. Controls include 63/64 retained records, exact byte
boundary and one byte over, actual Collection byte-limit refusal with unchanged
root, owner-only summary reads and the shared fail-closed read-budget latch. A
two-task publication control admitted one proposal; the other attempt can fail
at the Identity lock or conflict, and a subsequent fresh attempt at the full
queue refuses. That control does not independently prove a simultaneous
Collection-lock race. Actual records in the capacity fixtures are synthetic,
and the full diagnostic snapshot predates this change. A separately engineered
proposal control combined anchor repair, live insertion and the new summary at
exactly 32 units (seed 46560). That single synthetic geometry does not prove
every page configuration. Native durability, exhaustive page repair, lifecycle
reclamation, cross-process races with actual Consent reservation and the
30/90/365-day workloads remain open.

A later Collection-level control holds the real lock after a summary of 63
pending references and starts a second owned task directly against Collection,
without the Identity lock. The competing callback does not enter; after the
first publication, a fresh checked summary sees 64. The expanded directory,
managed-callback and normalizer selection passed 48 tests (seed 46563). The
control uses a synthetic normalizer and two BEAM tasks with native owners, not
two independent BEAM VMs or the complete signed-domain workflow. A diagnostic
Collection attempt returned `collection_unavailable` while the lock was held
(seed 46562). The earlier Identity-level test expected a conflict but observed
`project_identity_unavailable` (seeds 46555 and 46556). Both refusal outcomes
are distinguished from success.

The Collection-lock control was then extended to a separate BEAM VM. While the
first owner held the lock after its 63-record summary, the other VM returned
`collection_unavailable` without entering its callback. After publication, the
same stale request returned a conflict; a fresh-generation request in the other
VM observed 64 references and refused publication. The expanded selection
passed 48 tests (seed 46565). Both VMs used the test-only helper and a synthetic
normalizer. This verifies that isolated lock boundary, not a complete signed
domain race, cross-machine behavior or production-profile qualification.

A further two-VM control uses `ProjectIdentity.with_domain_publication`, the
actual version-3 normalizer and signed metadata. While the first publication
held Identity and Collection, the other VM was refused before its callback;
afterward its stale request conflicted and a fresh request was refused at the
full queue. The root stayed at the single successful publication. The focused
control passed (seed 46567), and the expanded selection passed 49 tests (seed
46568). The first attempt failed before the operation because the synthetic
options were truncated when rendered into the child program (seed 46566); the
fixture now renders the complete options. Authorization callbacks and sources
are synthetic, both VMs use the test-only helper, and this does not exercise a
real Consent reservation or qualify production storage, crash durability or
cross-machine behavior.

A saved-consent Session control now initializes real V3 metadata through the
fixture worker, directly seeds 62 synthetic pending records, then publishes a
second real sourced proposal at a count of 63. A further Session's proposal at
64 fails with the public `collection_unavailable` outcome; its root is unchanged,
the Consent operation is settled, journal validation and reconstruction succeed,
and reopening does not rerun the worker. The fixture worker deliberately skips
its own capacity check. The focused test passed with seed 46573 after correcting
the expected public failure representation in seeds 46571 and 46572. These are
isolated synthetic records and sources on the private test-only helper: this is
not a cross-process Consent race, a production storage qualification, or a real
user intake journey. Collection, directory, normalizer, Session and managed-call
source hashes matched the working tree for the test.
The related Session and signed-Collection integration selection passed 50 tests
(seed 46574). Removing only the host capacity call in the isolated diagnostic
copy caused the full-queue Session assertion to fail because publication succeeded
(seed 46575); restoring it passed the focused test again (seed 46576).

Another control synchronizes two separately owned fixture workers after each
reads the same 63-record generation and releases their Session-managed requests
together. It requires at most one successful publication, verifies the resulting
generation, validates both journals, and checks that each consent operation is
either absent after refusal or settled. If both refuse, a fresh Session must
publish successfully. The focused test passed (seed 46580); earlier attempts
exposed a possible pre-reservation refusal (46577), read contention before the
barrier (46578), and two simultaneous refusals (46579), so the control no longer
assumes one competitor must win. The two Sessions share a host VM and use
synthetic seeded records and sources with the test-only native helper; this does
not establish a cross-VM Consent race or production-profile qualification.
The full Session test file passed 24 tests (seed 46581). That revision compared
the Collection summary, which does not contain the root digest; the test was
then strengthened to compare checked before-and-after root witnesses as well.
Both focused controls passed after that correction (seed 46582). The 24-test
run predates the witness assertion.

The broader directory, managed callback, normalizer, actual publication,
observation, read-view, managed Session, capture and Notes/Records selection
passed 131 tests (seed 46559) in the earlier private diagnostic graph. Strict
working-tree compilation, formatting, documentation links and `git diff --check`
also passed. These checks do not change the native-profile or workload limits
above.

## Legacy managed pending publication

On 2026-10-28 a synthetic version-2 normalizer accepted a `pending.` proposal
despite a supplied 64-record summary (seed 46603). The working tree now shares
the bounded host check between version 2 and version 3 for proposals under that
prefix. The legacy read uses eight of the existing 32 locked-read units; its
remaining maximum is one override plus eight anchor and four live reads. Exactly
256 KiB remains allowed. Version-2 recipes using other prefixes are unchanged,
and direct Collection writes, import and other routes still need separate rules.
Old journal outcomes are not replayed or retroactively changed.

Count, byte, malformed-summary and other-prefix controls passed (seed 46605).
The actual saved-consent Session fixture initialized V2 metadata, directly
seeded synthetic pending records, and refused a full queue with a settled action
and unchanged checked root (46606). The legacy/V3 normalizer, signed-Collection
and Session selection passed 66 tests (46607). Removing only the V2 capacity
call in the private diagnostic graph caused the same Session to publish and the
regression to fail (46608); restoring it passed (46609). The three normalizer
and helper source hashes matched the working tree after restoration. These
controls use synthetic sources and the private test-only 7.2.11 helper, not a
production filesystem or global multi-instance quota. The full fixed-source
diagnostic started before this change and does not cover it.

The synchronized two-Session boundary control was also run for both V2 and V3
after sharing the same test body; both passed (seed 46611). It allows either
contention refusal or one success, checks the root generation and consent
settlement, and requires a fresh successful attempt if both contenders refuse.
This is not a cross-VM Consent race or evidence that each attempt entered the
normalizer simultaneously.

The legacy full-queue Session control was then extended to close and reopen the
same Session and verify that its worker is not re-entered. That focused check
passed (seed 46620); it is not a crash or power-loss test.
