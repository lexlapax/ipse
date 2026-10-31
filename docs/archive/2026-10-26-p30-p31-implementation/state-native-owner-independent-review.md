# Independent State native-owner review

Historical scoped review, **2026-10-29**, of the
[native-owner backend](state-native-owner.md) against
[the restoration design](state-deadline-restoration-design.md) and
[its requirements review](state-deadline-restoration-review.md).
Current status belongs to the [plan](../../plan.md); current State behavior belongs
in [developer training](../../developer/extension-state.md).
The reviewer changed no runtime, helper, gate or test and ran no runtime suite,
model request or network operation. The author's passing controls were inspected
and reused. One newly identified decoder defect prompted a narrow author repair
and targeted controls; those are distinguished from reviewer execution below.

## Disposition and scope

No remaining concrete defect was identified in the reviewed **backend-only**
scope after the frozen v6 decoder repair. All current ordinary State replacements
use the same native process that owns their namespace flock. The new private
timed operation uses the final post-staging locked clock decision required by
the original P26 contract. It makes no physical-before-expiry guarantee.

Public timed State execution remains closed in both State and Invocation, with
State's private timed-write backstop also retained. Managed State/service denial
is independent and remains in Invocation. This review does not authorize gate
removal or qualify complete timed State, Memory delayed approval, Collection,
Consent, stage TTL, retention, Review or managed-output journeys.

## Finding and verified repair

The pre-review Controller decoded a `state_commit` response before falling through
to its generic `{_, <<>>} -> :ok` clause. An empty completion therefore became
known success. Its nine-byte result also lacked safe-clock, deadline-presence
and decision-order checks: an impossible elapsed result for an unconditioned
operation, or a success at/after a finite deadline, was not rejected.
This was a source-demonstrated closed-protocol defect, not a claim that the
unmodified helper emitted those responses.

The owner repaired the decoder before freezing v6. Every State completion now
enters `state_decision_reply/2` before the generic empty-response clause.
It requires exactly one decision byte and one safe unsigned clock value;
success requires no deadline or `checked_at < deadline`; elapsed requires a
finite deadline and `checked_at >= deadline`. All other inputs become unknown.
The controller then invokes its normal failure/cleanup path rather than returning
a known write result. Source inspection confirms the actual caller uses this
decoder, not merely a test-only equivalent.

The retained [v6 decoder control](state-native-owner/ipse-state-owner-v6-decoder.log)
passes two selected cases: pure valid/invalid reply shapes and an actual private
zero-deadline native elapsed decision. The
[malformed completion control](state-native-owner/ipse-state-owner-v6-malformed.log)
passes one selected actual-State case. Its separately compiled native hook
performs the replacement and then truncates the V payload; State returns unknown
while a new operation can inspect the new value. The hook is compile-time gated,
not an option in the standard helper. These controls were run by the owner and
read by this reviewer; no duplicate runtime run was necessary.

## Contract assessment

| Concern | Inspected implementation and evidence | Assessment / remaining limit |
| --- | --- | --- |
| Ordinary untimed compatibility | State routes reads and all put/delete replacements through `Transaction.acquire`, `state_begin`, native read/stage/commit and acknowledged release. No State `File.write`/`File.rename` replacement remains. v5 integration passes five cases; v4 compatibility passes seven existing cases including tombstones, quota, pagination/CAS and corrupt/unsafe input. | Original JSON layout and public result shapes remain. An owner-private `0400` legacy file is read and replaced in an actual control. Older running file-server writers cannot be retroactively fenced; mixed old-writer operation is explicitly excluded. Earlier failed compatibility/cross-process logs remain failures, not implied passes. |
| CAS, deadline0 and quotas | State preserves record CAS, optional namespace-generation CAS, initial elapsed check, then revision/key quotas; complete encoded bytes remain capped at 1MiB, 256 records including tombstones and safe revision totals. Native fixed-State staging rejects oversized bodies; deadline0 is valid in private V. | Source preserves precedence. Public timed execution is gated, so source inspection/private native tests do not establish an integrated timed CAS/elapsed/quota journey. Quota and schema controls use ordinary State execution. |
| Actual lock ownership | Native `Held` retains the private parent and `.lock` descriptors/identities. It reads, writes, syncs, renames and unlinks under that same ownership; no data-file descriptor crosses to BEAM. Controller monitors actual caller and propagated original effect owner and registers the resource scope. | This closes the separate lock-helper/file-server replacement pattern in this backend. Before/after-rename owner-loss controls show contenders refused while the holder is paused, then inspect old/new bytes after it dies. This is available-host evidence, not a blocked-kernel-syscall cancellation proof. |
| Final decision / elapsed timestamp | Native completes chunked staging and sync, validates stage/observed target/retained lock, samples its own wall clock, and only then decides and renames fixed `state.json`. V returns that exact sample. Equality expires; clock failure refuses; elapsed staging is removed and directory-synced before its reply. | Before-decision delay across expiry returns actual elapsed time without changing active state. After-decision delay permits physical rename after expiry, exactly the original decision contract's disclosed limitation. No timer or precheck is claimed to make rename clock-atomic. |
| One-use binding | `StateIntent` captures observed target identity/length or validated absence. Native State mode restricts reads to fixed `state.json`, permits one fixed-size reserved stage, marks staging started once, requires complete ordered chunks, and consumes the intent before V. After finish only release is allowed. Controller capabilities remain actual-owner-bound. | A second finish, wrong target/mode, oversized stage and substituted target/staged inode refuse. Elixir binds admitted operation/request and validates exact JSON/CAS; native treats the bytes as opaque. This protects cooperative trusted-host execution, not hostile same-user code rewriting an inode's contents outside locking. |
| Unknown / release semantics | State retains its provisional result until `Transaction.release` succeeds. Controller requires framed root release, successful native exit and confirmed transport cleanup. Native uncertain rename/sync paths use unknown framing; malformed, partial or lost response invokes cleanup and unknown. Host maps unexpected State results to unknown. | The v6 malformed-response control demonstrates an actual effect plus unknown result. Lost response is not known refusal, and neither receipt loss nor operation-ID inspection grants replay. Read/conflict/quota results also wait for release. Full fault injection of every cleanup/sync failure is not claimed. |
| Bounded cleanup | Only mutating State mode scans reserved `.state-pending-` files under the namespace lock: at most 1,024 entries, 256 files and 256 MiB total, each bounded/private/owned/regular/single-link. Reads do not clean. Mutation removes only reserved safe stages; unsafe reserved entries refuse. | Actual controls preserve unrelated names, preserve unsafe symlinks, and reclaim a dead owner's stage only after contender admission. Failures leave inspection/recovery necessary; no automatic effect replay or deletion of retained `.lock` occurs. Exhaustive filesystem fault/maximum-cleanup qualification remains open. |
| Existing gates / authority | State's public timed refusal and historical receipt validator remain; its write backstop refuses deadlines. Invocation retains its pre-intent timed gate and separate managed `state.put`/`state.delete`/`service.call` denial. Private APIs are internal host primitives, not SDK authority. | No new scope, approval bypass or user expiry waiver follows from this backend. Original request/approval, JSON schema, operation ID, intent-before-effect and no-replay rules remain required. Full Session integration must precede any gate change. |

## Frozen provenance

The reviewer verified every file listed in the
[manifest](state-native-owner/manifest.sha256) with `sha256sum -c`; all matched.
The final [source archive](state-native-owner/source.tar) hashes to
`828ba49087d222fa8cad3d96c51c0851e54b94fb44edef5eb68d32ba463aa96e`.
Its inspected implementation files match the working-tree bytes:

| Source | SHA-256 |
| --- | --- |
| `lib/ipse/extension/state.ex` | `ae63fcbc68fadbd875e1d973ae63c1ec461172adf1cd23bac1ef359584e19e15` |
| `lib/ipse/runner/transaction.ex` | `42712ec98540941f29ff33aff15c97ba50dabe41611bfe3dcad1c03c452278b0` |
| `native/ipse-transaction.rs` | `63d539664de74b8d9f9fec5fe783cf6c3f7cffcd8a34be8849242916abef6a34` |

The [v6 inventory](state-native-owner/runtime-v6.sha256) records standard helper
`7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067`;
the [hook-v2 inventory](state-native-owner/runtime-hook-v2.sha256) records the
separate repaired instrumented runtime. v4/v5/hook/old-helper evidence is
individually identified by the owner's receipt, not relabeled as all-v6 execution.

The first pre-review source tar was replaced while freezing the repair. The
owner reconstructed the three earlier v5 implementation files by reversing only
the decoder/hook changes. Their hashes match the values this reviewer independently
observed in the original tar before replacement: State `ae63fcbc…e19e15`,
Controller `c3f240c8…3441ce2`, native `1d18ac7d…9294e1f`.
Those files are retained under `source-v5/` in the manifest and expressly
identified as reconstructed/hash-verified; the original whole tar is not claimed
preserved. Earlier logs and runtime inventories remain independently retained.

## Acceptance still required

The backend is a prerequisite, not restored timed State acceptance. Before a
State-only gate change, complete real timed State success and typed elapsed
receipt integration, actual Memory remember/active-import approvals on both sides
of target expiry, fresh expired-backup behavior, timed CAS/quota precedence and
separate managed-State refusal. Reconcile current manuals with the final decision
contract and run the appropriate coherent source/native/package baseline.

The available-host controls do not qualify macOS, every filesystem/profile,
all blocked IO or cleanup fault schedules, a live upgrade with old writers,
or another lifecycle primitive. The earlier unexplained cross-process fixture
readiness timeout remains retained and does not become resolved merely because
the separately pinned two-VM control passed. No P30/P31 completion or physical
no-late-effect guarantee is inferred.
