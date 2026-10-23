> Historical reference only. Snapshot of `docs/developer/delegation.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../2026-10-22-before-structural-consolidation/docs/developer/delegation.md).

# Local delegation contract

This guide owns serial/parallel child policy, parent-controlled approvals and
result recovery. Lifecycle consumers use the shared
[child outcome contract](lifecycle-events.md#delegated-child-outcomes).
The [plan](../plan.md) owns current delivery status; dated P6/P9 evidence below
does not establish checks for later lifecycle additions.

## Scope and context

An explicit `--subagents` option enables one `delegate` function in the existing
session loop. Defaults remain disabled. The parent reviews the complete task
and selected context before a child starts. A child is another ordinary
`Ipse.Session`, with its own conversation, lock, and private journal. It uses
a configured profile/role or the parent's provider/model, with shared workspace,
shell policy and saved workspace-instruction snapshot. The
[profile contract](model-profiles.md) defines mixed-provider isolation. It receives only the explicit task/context,
never the parent's transcript or provider continuation items.

Children cannot delegate recursively or use MCP in this first slice. They may
use the existing workspace tools and skills. Ordinary reads remain permitted
under the existing read policy. Writes, edits, and shell calls retain the
parent's approval policy; a child cannot approve its own proposals. There is
no automatic provider/model selection, billing switch, service, plugin loader,
or new dependency. A shared workspace is not filesystem isolation.

## Approval and effect ownership

Parent `tool_started` intent is durable before starting delegation work. Before
prompting the child, the worker registers it synchronously against the parent's
active job reference. The parent records the child journal ID and exact origin
call ID, including the selected parallel suffix. Registration checks that origin
against the active tool; the child header and request accounting retain the same
parent/request/call relationship. The separately granted
[child-accounting reader](usage-accounting.md#registered-child-accounting) checks
that binding without running the child or exposing its conversation.
A stale registration fails before inference or tools. Required child approvals
return through the parent UI with the child ID, tool name, and full arguments.
Each decision binds to the exact child/reference/arguments and is journaled;
only the literal boolean `true` authorizes a native, delegated or extension effect.
an earlier delegation approval does not approve a later child effect.

Interactive approval remains individual. Headless delegation is denied without
`--yes`; explicit session allowance also covers child mutations. Repository
instructions and child/model output cannot enable delegation or change policy.
Oversized forwarded approval arguments are denied without truncation.

## Lifetime and recovery

Serial mode runs one child at a time. Its owner is the parent's monitored delegation worker;
parent loss kills the worker and child owner loss stops child work. Explicit
parent cancellation cancels and closes registered children before reporting
completion. Child calls use existing tool supervision and OS process cleanup.
Detached-descendant limitations of trusted/native execution remain unchanged;
delegation does not strengthen the sandbox boundary.

Children have at most six model steps, a two-minute active task budget, and a 16 KiB final
result. A parent may start at most two child tasks in one user turn. Each task
and selected context is at most 8 KiB; forwarded approval display is at most
32 KiB. Child stream traffic is bounded and final child text is explicitly
untrusted data, returned through the ordinary parent tool-result boundary.
Waiting for a required parent approval pauses the active budget; `/cancel` and
owner-loss cleanup remain available while waiting.

Incomplete, crashed, cancelled, timed-out, or oversized child outcomes stop the
parent tool batch as unknown. Inspect both journals/workspace before an explicit
new attempt. Parent resume never starts a child or replays its effects. Child
journals retain parent/call provenance and cannot be resumed as standalone
root sessions. Completed child results stay in the parent history; complete
child transcripts remain separate private data.

The existing `delegation_started` record retains its original format. Before
returning a child result, the registered worker reports to the parent's active
job after closing the child. Parent syncs `delegation_finished` against the actual
start source, child/request/turn IDs and process-local elapsed duration. Only that
registered worker may report the result. A monitor exit is kept separate so it
cannot race ahead and erase the worker's completion identity. Retaining that
identity does not keep the exited child's approvals active: new proposals,
queued approvals and stale decisions refuse once it is down or settled.

`result_recorded` means a bounded child result was observed and the child's owned
session acknowledged cleanup before exiting, including actual native-helper
acknowledgments for registered task-owned shell groups and extension VMs. Task
death, a missing receipt or a closure timeout cannot establish that acknowledgment.
It does not certify the
result's assertions or strengthen OS containment. `Session.close_confirmed/1`
requires that acknowledgment; ordinary `close/1` retains its existing idempotent
dead-process behavior. Timeout, failure, cancellation and lost workers yield an
`unknown` receipt with a fixed reason; an abrupt parent kill may leave only the
start. Parent-driven cancellation records no speculative child cleanup success.
Per-turn child and durable request ceilings bound these records.

Restore rejects duplicate outcomes, mismatched parent/request/turn/start bindings
and malformed statuses. Physical source resolution runs before tail repair.
Idle resume leaves incomplete historical children incomplete and starts none.
The metadata `child.finished` event exposes correlation, status, fixed reason,
elapsed duration and cleanup acknowledgment, with no task, result or raw call ID.

## Required verification

Fixtures must establish opt-in and headless denial, exact child approval binding,
intent-before-dispatch and separate journals, bounded context/result/budgets,
no recursive delegation or inherited MCP, serial children, normal completion,
cancel/owner-death cleanup, stale references, and unknown-outcome resume without
replay. Live subscription evidence must be recorded separately. Supported-host
source and package checks and developer/operator documentation review remain
completion requirements.

See [actual evidence](testing.md#p6-local-delegation-2026-10-15), including the
live subscription check, for completed checks and remaining limits.

## Parallel groups (P9)

`--subagents --subagent-concurrency 2` adds `delegate_parallel` with exactly two
validated tasks. The coordinator authorizes at most two linked workers against
the active parent job. Only those workers may register children and forward
approvals; stale jobs/unrelated callers fail closed. Children remain owned
sessions with recursion/MCP disabled. Six steps per child, two children per turn,
two minutes of active time per child, and 16 KiB per child result bound aggregate
work/results. Results are assembled in input order.

The parent serializes child mutation decisions/effects and retains per-group
path claims using `Tools.path_key/1`. After expansion against the workspace, the
key applies canonical Unicode normalization and case folding, removing format
controls, combining grapheme joiners and variation selectors. Cross-child
equivalence is denied even where the underlying filesystem distinguishes those
spellings. Original paths remain intact in approvals, journals and execution.
The file-tool metadata guard uses the same comparison for reserved `.git`
components. OTP's Unicode functions provide the comparison without a dependency
or an approval-time filesystem probe.

This conservative policy addresses filesystem-dependent case and normalization
behavior, described in Apple's [APFS guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/APFS_Guide/FAQ/FAQ.html).
It is not an exhaustive filesystem identity test. Hosted Mac checks establish
actual alias inode identity before asserting protection; portable fixtures cover
conservative denial on other volumes. Distinct write/edit keys may proceed after
separate approvals. Shell gets a wildcard claim, preventing another child's
writes/shell, including a shell after a prior file claim. Parallel file tools
reject existing hardlinks. Reads, other sessions, detached descendants and hostile
path replacement remain outside this shared-workspace conflict policy. It uses
ordinary OTP tasks/messages with no new package or framework.

An unknown child outcome closes its sibling before returning an unknown group
result. Parent cancellation/death stops all children and preserves unknown-effect
recovery. Saved concurrency binds resume; old journals default to serial.
Source/bundled demos exercise the group. The [P9 record](testing.md#p9-parallel-local-delegation-2026-10-15)
separates fixtures, live providers, and supported-host results.
