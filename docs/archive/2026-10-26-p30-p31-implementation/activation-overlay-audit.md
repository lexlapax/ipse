# Independent activation overlay audit

Dated **2026-10-26**. Historical independent component evidence, copied verbatim
from `p31-verification/independent-activation/activation-audit-2026-10-26.txt`.
Original report SHA256: `c5585ba356b79f5eaa55b39c59290596b8971bf8a94d6b1978b2da48da14ecb1`.
The code fence preserves the report text and its exact frozen-runtime references.

The original pending-reclamation finding is historical and was repaired afterward. Read the [reader repair](activation-readonly-repair.md), [writer repair](activation-writer-repair.md) and [final incremental closure](activation-writer-audit.md) before assessing current behavior.

```text
INDEPENDENT INCREMENTAL ACTIVATION OVERLAY AUDIT — 2026-10-26
Checkpoint: 60fbf656603a19e802393f23d3881d1009d84d80
Outcome: one confirmed actionable P2; no additional authority bypass reproduced.
This report is not final P30/P31 or whole-implementation acceptance.

SCOPE AND FROZEN EVIDENCE
The auditor did not author this activation component. Reviewed AGENTS.md, the
activation-overlay component receipt, relevant implementation and matching tests.
The target was the immutable-intended private checkpoint
/tmp/ipse-activation-overlay-20261026-05/{project,build}, including its compiled
MIX_ENV=test graph. The root CLI draft was present in the graph but its unwired
setup/UI flows are outside this component acceptance and were not tested.

Before probes, copied the complete 134-file source-manifest graph, private priv,
and app/dependency runtime into /tmp/ipse-independent-activation-aLJgvl.
Unrelated repository development/qualification inputs were not copied or read.
The source manifest validated every copied bound file. A copy utility reported
an unrelated broken telemetry/src symlink; the auditor separately compared all
571 actual app/dependency ebin files byte-for-byte and verified both helper copies.
No host/native compilation, shared helper rebuild, repository edits, staging,
index changes, live model/network calls, credentials, gold inputs, qualification
corpus, private transcripts or PTY tests were performed. Only newly created
synthetic private homes, synthetic Git metadata, and an independently compiled
inert SDK-2 artifact were used.

BEFORE/AFTER INTEGRITY
before.sha256 was written before probes and binds all 128 application/bundled
source files, every compiled Ipse-app ebin file and both copied helper files:
294 entries. It was checked successfully after native probes, after overlay
probes, after the final standalone reproduction, and before preservation.
SHA-256 of before.sha256:
dfbe873bbaf8fb66738fc50b2e95519b0f7d90a0164cd34bf03673c4eb0886e6
SHA-256 of the original complete 134-file frozen source manifest:
b7094354c856eddeea861ebdd556c5d2b0481bf3b876940d2b6eb43342e9573f
Helper, identical before and after probes:
108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29
The pure managed-policy fixture and public knowledge contracts source were also
bound separately in fixture-before.sha256 before loading them.

The private runtime's packaged inventory was deliberately replaced only inside
this auditor-owned copy with a newly built inert synthetic artifact for overlay
controls. Temporary installed artifacts, policies and Session journals belonged
to isolated fixture homes. These fixture data changes are not application source,
BEAM or helper changes. The durable replay runner makes a new temporary copy
before recreating these fixtures; it must not mutate the durable evidence runtime.

CONFIRMED FINDING
[P2] Config.Activation.current/2 repairs/reclaims pending files during a promised
non-repairing read, including before returning an error for malformed control.
The parent explicitly confirmed the non-repairing read contract and accepted this
finding for both Identity and Consent; no implementation repair was made here.

Exact source paths in this bound checkpoint:
- lib/ipse/config/activation.ex:90 calls ProjectIdentity.with_binding, which enters
  the ordinary mutation-capable ProjectIdentity transaction.
- lib/ipse/extension/project_identity.ex:305 invokes reclaim_pending before its
  index read at line 307.
- lib/ipse/config/activation.ex:267 calls ordinary Consent.snapshot.
- lib/ipse/extension/consent.ex:421 invokes reclaim_pending before decoding the
  selected control file at line 422.

Minimal reproduction, executed against unchanged source/runtime:
1. Create an isolated private home/workspace and explicitly admit a folder.
2. Add a safe owner-only .pending-<32 lowercase hex> file to project-identities.
3. Call Config.Activation.current(%{home: home}, cwd).
   It returns :ok and deletes that pending file, even with no Control tree.
4. With a valid existing Consent ledger, add the same safe pending-name class
   under knowledge-control/<project_id> and call current again.
   It returns :ok and deletes the control pending file.
5. Replace control.json bytes with {} while preserving its safe mode, add another
   safe pending file, and call current again.
   It returns :error but has already deleted the pending file.
The selected index/control JSON bytes remained unchanged in every case. The
contract violation is the unrequested reclamation itself, not an index rewrite
or an inferred membership/effect permission bypass.

Standalone exact reproduction: nonrepair-current-repro.exs and its log. Output:
identity_pending: result :ok, pending_before true, pending_after false.
valid_control_pending: result :ok, pending_before true, pending_after false.
malformed_control_pending: result :error, pending_before true, pending_after false.
All three recorded logical_bytes_unchanged true.
Driver SHA-256:
629682114d634943e3625b4bd667de344ead6edb1f1729e56fbf9b42224c15b3

Critical exact source SHA-256:
Config.Activation:
196b7e23f1b8086437ab335abe630261c8e4ba369442de07ee5620f57eea4c70
ProjectIdentity:
ef972ee465410fe15bc4cba11613c564022c17f061b09d4dde8755622c12a08c
Consent:
effd69cae0819c70e9929a16ddd995ad66de4540a136e78a08cec942f95eda51
The preserved before manifest supplies exact compiled BEAM and other source
bindings. The root intends a repair using explicit non-repairing existing native
locked reads while retaining ordinary mutation reclamation contracts. That repair
is not part of this audit; these frozen drivers/runtime remain available for
independent closure review.

FRESH CONTROL RECEIPTS
native-adversarial.exs: 3 driver cases completed, seed 318079, 0.1s test time.
Two defensive controls passed: absent current/existing creates no files and
malformed index bytes stay untouched; killing the actual native flock holder
inside a checked reciprocal-worktree authorization callback yields unknown,
leaves index bytes unchanged, and publishes no linked binding. The flock holder
was identified via retained .lock FD among native supervisor descendants, not
assumed from the outer stdio supervisor PID. The third case deliberately asserts
and documents the P2 read-side reclamation behavior; its passing test is not a
claim that the non-repairing contract passed.

The independent inert SDK-2 artifact accepts a marker option and returns only an
explicit local command result. It makes no model or network request. The pure
managed-policy construction helper was reused for valid setup data; fresh control
sequences were independently written rather than rerunning author tests.

overlay-adversarial.exs: 3/3 cases passed, seed 592183, 1.3s test time.
- An actual Session saved with nil activation did not adopt a subsequently enabled
  A overlay. A saved A/90s Session retained exact A options/catalog and timeout
  after a B/70s replacement with different options; fresh admission selected B.
  Idle A resume did not alter journal bytes. B did not authorize A's inert command
  (the attempted explicit command completed with error). After revocation and
  removing current packaged inventory, exact installed A still resumed while new
  fresh admission stayed inactive. Ordinary Config fingerprint remained unchanged.
- A/90s could not widen a base 30s timeout. Changed actual model/origin and changed
  installed sidecar bytes refused. Child policy restored ordinary base timeout,
  registry and entries and dropped activation state; base config stayed unchanged.
- Standalone SemanticRoutes.review derived service IDs from the actual canonical
  origin deterministically, rejected an injected selector endpoint and wrote no
  home files. No endpoint/profile was obtained from JSON route claims.
This driver emitted one unused Journal alias warning in its own code; there was
no production compiler change or production warning repair.

join-adversarial.exs: final 2/2 cases passed, seed 741023, 1.3s test time.
- Wrong-worktree, expired and revoked grants did not join a new reciprocal linked
  worktree. Changed actual route also refused without membership. Index bytes
  stayed unchanged until an actual valid project grant was checked and joined.
- A poisoned backlink and interrupted authorization callback could not publish.
  Revoking Consent inside a trusted authorization callback could leave the newly
  admitted membership, but subsequent Host.fresh and an actual Session were off
  with no activated extension catalog/effect authority.
First driver version required callback exceptions always return unknown. The API
returned known error before any publication; accepting error or unknown while
requiring no index change corrected only the driver. Both original driver/log
and corrected driver/log are preserved. This was not a production defect.

STATIC REVIEW
Read current/fresh/resume/admitted/restore_base/child_base, raw configuration and
fingerprint ownership, exact saved Session admission, Identity existing/join
publication ordering and native metadata checks, route review, installed
Artifact/Registry matching, sidecar/capability/option and trust derivation,
child filtering and base ceilings. Current enabled selection is not a saved
Session selector; saved pin/catalog reconstruction is not current effect consent.
No ordinary shell or delegation approval grant was found in the overlay path.

LIMITS
No exhaustive race schedule, every unsafe Git metadata substitution, all
capability/options/trust tamper combinations, all alias/profile combinations,
platform/filesystem/kernel qualification, full suite, installed release, UI,
paid/live inference, or final milestone audit was performed. Root managed recall,
withdrawal and unimplemented Root CLI workflows are not findings here. The
existing same-UID cooperative-host threat boundary remains unchanged.
The accepted P2 is open in this frozen checkpoint. No repair or closure claim is
made. Absence of another reproduced bypass does not certify the whole milestone.

REPLAY AND PRESERVATION
The durable bundle includes this report, unchanged and corrected drivers/logs,
setup helpers, complete frozen manifest-bound source graph, supplemental public
fixture sources, every compiled app/dependency ebin file, the private runtime
priv files and exact helper, and before/after verification receipts.
Run replay/run.sh only in a compatible Elixir/OTP environment; it copies evidence
into a fresh private temporary runtime before executing fixtures. No network
permission is needed for these activation probes. The standalone P2 driver
asserts the frozen bad behavior, so a repaired runtime is expected to change its
output and fail those bad-behavior assertions; closure must assess the intended
non-repairing expectation without silently editing this preserved reproduction.
```
