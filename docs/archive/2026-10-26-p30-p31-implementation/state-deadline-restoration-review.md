# State deadline restoration design review

Historical read-only technical review, **2026-10-29**, of
[the proposed restoration](state-deadline-restoration-design.md), against
checkout `7afc3f26617a79eecab5f6d97cef8b48bf6375b1` plus its uncommitted working
tree. This additive disposition changes no code, gate, approval or milestone
status. The [plan](../../plan.md) owns current status; current behavior belongs
in the [State training](../../developer/extension-state.md) and
[Memory manual](../../operator/memory.md). No tests, diagnostics, model calls or
network requests ran for this review.

## Disposition

The direction is faithful to the original accepted generic State contract and
needs no new effect authority or user waiver of expiry. The
[P26 design](../2026-10-19-p26-remediation/expiry-write-design.md), lines 8–14,
records the user choice to reject renewal when approval crosses target expiry;
lines 94–100 explicitly select the final locked publication decision and
disclaim physical rename completion within the same wall-clock millisecond.
Restoration lines 12–26 preserve that boundary and do not move it to initial
reservation. Its native-owner requirement addresses a distinct real ownership
gap rather than using that disclaimer to justify unfenced IO.

Proceeding requires the concrete amendments below to be treated as implementation
requirements. This review does not approve physical completion before expiry,
authorize opening any other gated path, or claim implementation qualification.
The [requirements audit](expiry-requirements-audit.md) remains the wider matrix.

## Required amendments

| Item | Source evidence / issue | Required design commitment |
| --- | --- | --- |
| All mutations share one native owner | Restoration lines 74–76 call moving ordinary writes merely “preferable.” Current [State](../../../lib/ipse/extension/state.ex), lines 87–102 and 317–334, separates native flock from file-server write/rename, including unconditioned put/delete. | Make native-owned replacement mandatory for **every** State put/delete admitted by this runtime. A surviving untimed file-server request can otherwise overwrite a successor timed writer after its old lock helper dies. Do not preserve it as fallback or compatibility route. |
| Preserve full deadline domain and precedence | State lines 120–130 and 371 admit integer deadlines **0 through 2^53−1**. Lines 185–200 select record CAS, namespace generation CAS, initial elapsed refusal, then quota checks. | Keep zero as a valid already-expired deadline. Preserve CAS → initial elapsed → quota precedence, as well as the final post-staging native clock decision. The initial sample may remain trusted-host state validation under the retained namespace lock; it does not replace the final native sample. |
| Native elapsed evidence is not the existing `T` reply | [Native transaction](../../../native/ipse-transaction.rs), lines 602–647, restricts `T` to positive deadlines and `root.json`; lines 699–702 and 972–979 return only error code8 for elapsed. [Controller](../../../lib/ipse/runner/transaction.ex), lines 489–526, accepts one-byte errors, without a clock value. | Add a distinct closed State operation/result contract with the actual native `checked_at_ms` for final elapsed refusal. Validate safe range and `checked_at_ms >= request.deadline`; never synthesize that evidence from a later BEAM clock. Preserve old Collection `T` semantics and its gate. Clock acquisition/validation failure remains unavailable/unknown, not elapsed. |
| Bind the observed current file to final replacement | Restoration binds observed JSON and names target identity checks but leaves the retained observation shape unspecified. Existing native read chunks carry size/device/inode; [Controller](../../../lib/ipse/runner/transaction.ex), lines 433 onward, checks cross-page identity. | Capture the exact current `state.json` identity/length, or validated absence, under the same native namespace lock. Bind that observation to one replacement attempt and verify it before the final decision. Only ENOENT at offset0 is absence; empty, oversized, malformed, symlink, nonregular and unsafe files must not become an empty namespace. Elixir validates namespace/schema and CAS against these exact bytes. |
| Native fixed-target, one-use framing | Existing transaction read/switch allowlists exclude `state.json`; their generic frame sequence is not by itself a State replacement lifecycle. | Specify a fixed-State private protocol/owner mode or equivalent constrained host adapter. Bind namespace lock/capability, request/operation, observed target, exact byte count, complete opaque replacement and optional deadline. Accept exactly ordered bounded chunks; finish and sync all bytes before the final clock sample. Spend the staged replacement on its first finish attempt; reject duplicate finish, changed body/deadline/target, trailing bytes and reuse. Keep Rust ignorant of policy/note JSON. |
| Release and uncertainty apply to reads and failures too | [Transaction](../../../lib/ipse/runner/transaction.ex), lines 21–25 and 315–336, requires final check/release and acknowledged cleanup. State's existing `after Runner.unlock` discards its result. | Do not publish read/list/scan data, CAS conflicts, quota failures, elapsed failures or success until the required final lock check and release acknowledgment succeed. A lost/partial response, unknown cleanup, sync failure after rename or dead owner produces the existing unknown path. No result wrapper may overwrite it with a previously computed known value. |
| Resource supervision is not the effect fence | [Resources](../../../lib/ipse/session/resources.ex), lines 819–881, starts/tracks an effect worker but cannot recall file-server IO already sent by it. Transaction lines 173–180 and 230–260 propagate the original effect owner and resource scope into the native controller. | Reuse original-owner and actual-caller monitoring plus resource registration. All data-file read/write/sync/rename/unlink operations owned by this transaction stay inside the same native flock owner. Never retain a BEAM data-file descriptor or queue file-server IO that can survive its death. The OS lock remains held until that actor's syscall stops; cancellation and process exit alone do not prove a completed response. |
| Preserve the generic State limits and layout | State lines 6–8, 268–282 and 380 onward impose 1MiB encoded namespace, 256 records including tombstones, safe revisions, sum-of-revisions generation and bounded individual values. | Keep namespace identity, JSON version/fields, deleted-key revisions, value bounds, operation IDs, scan paging/generation and receipt schemas. Streaming transport is an internal bound, not permission to raise State capacity. An encoded-size quota failure remains distinct from malformed state or IO loss. |
| Preserve authorization separation | [Invocation](../../../lib/ipse/session/invocation.ex), lines 491–519 and 533–546, has a general timed-put gate and a separate managed State/service denial. [Host](../../../lib/ipse/extension/host.ex), lines 421–444 and 535–536, executes only the admitted action and maps unexpected results to unknown. | Removing only the timed-put gate must leave capability, mode/deny, full-argument approval, durable intent, actual namespace and invocation binding intact. Managed `state.put`, `state.delete` and `service.call` remain denied independently; no saved knowledge consent or no-deadline substitution bypasses them. Keep historical gate receipt validation for inert reconstruction. |

## Reuse and compatibility conclusions

The existing native transaction is the suitable ownership/transport foundation:
it already retains the exact `.lock` inode and private parent, performs bounded
chunked staging/read operations, checks ordered sequence/depth, and acknowledges
release. Its `stage_data` syncs complete files before publication
([native transaction](../../../native/ipse-transaction.rs), lines 547–599).
The State restoration needs a narrow OS-only extension for its fixed filename,
one-use replacement and clock-bearing reply; no new JSON parser, package or
general workflow system is justified.

Do not simply broaden `switch_before` to accept `state.json`: its zero handling,
reply payload and caller-facing contract differ. Likewise, do not reuse a
generic stage-name supplied by a worker as permission to replace arbitrary files.
Same-process opaque transport plus trusted Elixir policy/CAS validation is the
boundary, not confinement of hostile same-user BEAM code. No new authority is
obtained from a command name or deadline field.

The newer native checks require exact private-file/directory properties and
safe ancestors, while old State accepted some additional permission shapes.
Assess ordinary existing `0700`/`0600` stores, first creation and absent files
explicitly. Unsafe or unsupported layouts must refuse clearly; never weaken
the helper checks to preserve a fixture. Do not claim concurrent safety against
older running runtimes that still use the unfenced file-server replacement path.
An upgrade must stop those writers or state the excluded mixed-runtime condition.

Temporary files cannot accumulate without bound across failures. Define
same-owner cleanup of its own stage and bounded explicit abandoned-stage
inspection/reclamation under the namespace lock. Reclamation must never select
an active stage or delete/replace the retained `.lock` inode. A cleanup failure
stays visible and cannot trigger automatic replay or hide an existing effect.

## Evidence implications

The draft's proposed before-decision and after-decision scheduling controls are
correctly distinct. Extend its future evidence with:

- CAS conflict versus elapsed versus quota precedence, deadline0, exact equality,
  clock failure and original closed elapsed/gate receipt tamper controls.
- Untimed put **and delete** owner/helper-loss races against a second-process
  timed contender, plus timed replacement loss after rename/before sync/reply,
  and read-result refusal when final release becomes unknown.
- A real body held after synced staging until expiry, actual native checked time
  in the unchanged-record failure, immutable body/deadline/target substitution,
  duplicate finish and mixed old-helper refusal with no fallback.
- Full 1MiB transport boundary, retained tombstone/key quota, generation/revision
  validation, absent-versus-empty current state, safe first creation, permission
  and target/lock identity substitution, and bounded stale-stage cleanup.
- Positive ordinary read/write/delete and live timed updates; actual Memory
  delayed approvals and original expired-backup behavior; managed State remains
  denied before intent even when an ordinary timed counterpart now succeeds.

These are required future controls, not executed results. Completion still needs
the relevant source/native/package baseline and whole-document reconciliation.
No restored State outcome qualifies Collection, stage TTL, retention, Review,
egress or managed-display lifetime guarantees.
