# Independent activation reader repair audit

Dated **2026-10-26**. Historical independent component evidence, copied verbatim
from `p31-verification/independent-activation-repair/activation-repair-audit-2026-10-26.txt`.
Original report SHA256: `3f01b9e90dfe87643963545a70493d0d6e9d37f895cae6684b8f7cbbf678c257`.
The code fence preserves the report text and its exact frozen-runtime references.

This historical audit confirms pending preservation and records a second finding about ancillary writer creation. The later [writer repair](activation-writer-repair.md) and its [independent closure](activation-writer-audit.md) supersede the open disposition here.

```text
Independent activation read repair component audit — 2026-10-26

Disposition
The original accepted P2 pending-reclamation behavior is closed in the tested
checkpoint. A separate P2 remains open: both new noncreating read APIs create a
missing ancillary .writer.lock. The parent accepted this finding and is assigning
author repair. This is incremental component evidence, not final milestone approval.

Scope and frozen provenance
Checkpoint 10012302fd7d4db91101eb58051794f8e4a6067a, supplied complete frozen graph
/tmp/ipse-activation-nonrepair-20261026-02 copied before probes into
/tmp/ipse-independent-activation-repair-f27cX0. No current working-tree source was used for execution. Inspected the
activation-readonly-repair archive, new Identity and Consent read APIs, activation
current/readiness policy and Registry identity checks, matching author tests, and
native quota/writer implementation. Independent probes below are new controls,
except the explicitly unchanged original exploit and its assertion-only variant.

The author 294-path source/app BEAM/helper manifest verified before execution.
The independent before manifest binds 701 source/app/dependency BEAM/helper paths;
after probes it is byte-for-byte identical. Manifest SHA256:
80bc81a857789369a2c9d3d64683deab5cc4df5df435fb78de16764ba0b42a1a.
Helper SHA256 (both retained copies):
108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29.
Critical source SHA256:
activation.ex e5e6bbd9ce1bd7608bbf6101d45b09d8656e2e56421f4d143af743fa8a3d38ca
project_identity.ex 3f4fa94ff329fa05621c60e46189182ae9ae09f4dd85439cadcb00736ccf1e5a
consent.ex dff082071f01eb48281a3499a30d28579cd1dc0ccdf14f84af4c34c88671393f
native/ipse-transaction.rs 63e2374667e29fc1f4b9fc8da51e02b5c0a98373692b921c95440f78e199912c
Complete source/runtime byte bindings are retained in manifests, not inferred from
commit labels. Private copy removed its unused shared project/deps symlink. Copying
build dereferenced runtime links; only a broken telemetry/src development link was
unavailable. All executable runtime files used by probes were copied and verified.

Open finding: P2 — noncreating readers recreate missing ancillary writer locks
Identity source lib/ipse/extension/project_identity.ex:149 and Consent source
lib/ipse/extension/consent.ex:464 call Transaction.quota after validating the
retained logical .lock. Neither requires an already existing safe .writer.lock.
Native quota command native/ipse-transaction.rs:515-521 calls scope_writers,
which calls writer at lines 168-174, opening .writer.lock with CREATE on line 169.

Reproduction (drivers/writer-lock-probe.exs unchanged): use an isolated owner-only
home and folder; admit an ordinary Identity, remove only its .writer.lock, then call
ProjectIdentity.with_existing_binding with the exact binding and a read callback.
It returns {:ok,:read} and recreates .writer.lock. Persist a Control through the
ordinary revoke mutation, remove only its .writer.lock, then call
Consent.existing_snapshot; it succeeds and recreates that file too. Retained .lock
and JSON remain valid. There is no concurrent deletion/replacement in this probe.
Exact observed output:
missing_writer_lock: {:identity, {:ok, :read}, true}
missing_writer_lock: {:consent, :ok, true}

This violates the promised noncreating read contract and permits current/readiness
inspection to repair ancillary state without an explicit mutation. Missing required
writer locks should refuse unchanged; explicit mutations/recovery may create them.
Parent accepted the P2. No production fix was made by the auditor. This report does
not claim a new native no-create primitive or protection against raw same-UID
concurrent unlink/replacement beyond the documented retained-identity boundary.

Closed original behavior, independently observed
The original unchanged exploit is retained with SHA256
629682114d634943e3625b4bd667de344ead6edb1f1729e56fbf9b42224c15b3.
It now exits 1 on its original false=File.exists?(pending) assertion: Identity's
safe pending file survives and index bytes remain unchanged. This expected failure
is evidence that the old exploit condition no longer holds, not a passing suite.
The assertion-only preservation variant changes false to true and executes all
three original cases: Identity pending, valid Control pending, malformed Control
pending. All preserve pending bytes; valid cases return ok, malformed Control
returns error. Logical JSON bytes remain unchanged in all three. Variant SHA256
ca2bd1023b0c2a82b68c20c72949b2c92d8be1ea18f0eba6aa5cc81e209143a5.

Fresh independent controls actually executed
1. read-adversarial.exs: 3/3 passed, ExUnit seed 601727, serialized max_cases=1.
   Existing Consent read accepts unselected safe pending bytes that are invalid
   JSON without deleting them. A hardlinked pending file refuses and remains.
   Missing required logical .lock refuses unchanged for both Consent and Identity;
   Identity callback does not execute. A dense 4MiB Identity pending file exceeds
   its 3MiB allocation ceiling, refuses without callback, and remains 4MiB.
   Ordinary Identity.with_binding then reclaims it and succeeds. Existing Consent
   read preserves its safe orphan; ordinary Consent.snapshot subsequently reclaims
   it. This checks explicit mutation recovery still operates.
   During each new callback, find the actual native flock holder via /proc child
   and file-descriptor observations and kill that PID. Both callbacks return an
   unknown outcome, never release their sentinel result, preserve JSON and staging,
   and a subsequent explicit existing read succeeds after lease cleanup.
2. readiness-adversarial.exs: 1/1 passed, seed 144609, max_cases=1.
   Absent readiness returns false with nil binding/snapshot and zero home entries.
   Valid readiness returns only binding/ready/snapshot, preserves safe staged
   invalid JSON, and the advisory map is rejected by admitted as effect authority.
   An otherwise coherent valid policy whose identity_sha256 no longer matches the
   actual Registry is inspectable via current but refused by readiness.
   This uses a freshly compiled inert SDK fixture only in the private copied graph.
3. writer-lock-probe.exs: exit 0 with the two creation observations above.

Execution and retained reproduction
Runtime: Erlang/OTP 29 erts-17.1; Elixir 1.20.4 compiled with OTP29, Linux native.
Commands use elixir -pa 'build/lib/*/ebin' DRIVER.exs from the independent root.
All fixtures use isolated random temporary owner-only homes. Durable replay/run.sh
copies evidence to a fresh temporary root before any execution; it never runs tests
against durable evidence. It expects the unchanged old exploit to exit 1, then
runs preservation, fresh controls, readiness and writer creation observation. The
writer probe intentionally prints observed booleans so it remains useful against
a later repair; current vulnerable behavior is the exact true/true output above.
Logs, original and derived drivers, source graph, runtime BEAMs/helper, byte manifests
and receipt are included. The complete payload has a relative SHA256 manifest.

Limits
No author's suite was recharacterized as independent proof. No full suite, broad
race stress, new platform/backend, CLI/operator PTY, live provider/model/network,
qualification corpus, credentials, or private transcript was accessed. No source,
index, repository, shared build or native helper mutation occurred. Actual owner
loss was checked on Linux callback boundaries, not every possible instruction or
race schedule. Safe pending malformed content, hardlinks, missing logical locks,
quota refusal and ordinary recovery were sampled, not every filesystem fault.
No repair of the new writer-lock P2 has been assessed. CLI review is held until a
new frozen graph is supplied after that repair. Final whole-implementation and
milestone audits remain required, and this report does not mark them complete.
```
