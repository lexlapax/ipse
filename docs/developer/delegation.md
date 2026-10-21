# Owning local child sessions

Delegation creates another ordinary `Ipse.Session`, with its own conversation,
lock, journal, and approval history. It does not copy the parent's transcript or
make the shared workspace isolated. Learn the parent/worker/child ownership chain
before changing scheduling or cancellation.

`lib/ipse/delegation.ex` supplies pure policy and tool definitions.
`delegation/worker.ex` owns one child's active work; `delegation/group.ex`
coordinates a pair. Session admits the parent tool, registers workers and children,
forwards approvals, and records outcomes. Profile routing has its own
[configuration rules](configuration.md#trace-main-and-child-profile-selection).

## Follow a serial task

Delegation is disabled unless `--subagents` is explicit. A child cannot delegate
or use MCP. The parent proposes a complete task and selected context:

```json
{"task":"Inspect the failing module","context":"Explain the failure without changing files."}
```

The host validates the exact fields and selected route before approval. Parent
`tool_started` intent is durable before work begins. The worker then synchronously
registers the child against the parent's active job before prompting it. The
registration includes the exact origin call ID; a parallel child uses its actual
suffix. Child metadata/accounting retain parent session/request/call identity.
Unrelated workers and stale jobs cannot register work.

The child receives explicit task/context, workspace policy, saved instruction
snapshot, and selected execution route. Its separate journal retains full child
conversation. Parent history receives only a bounded result, prefaced with host
routing facts and labelled as untrusted child output.

Child mutations still require the parent UI's approval. Each forwarded decision
binds the exact child, reference, tool, and full arguments. Only literal `true`
authorizes an effect. Approving delegation does not approve later mutations.
Headless execution requires `--yes`; oversized approval arguments refuse without
truncation. Approval waits pause the active child budget and remain cancellable.

| Boundary | Limit |
| --- | --- |
| Task and selected context | 8 KiB each, valid UTF-8 |
| Forwarded approval JSON | 32 KiB; depth 12 and collections at most 128 |
| Children per user turn | 2 |
| Model/helper calls per child | At most 6, also narrowed by parent policy |
| Active child duration | 120 seconds |
| Final child text | 16 KiB |

## Understand completion before using it

The worker closes the child before reporting to the active parent job. Session
syncs `delegation_finished` against the real start source, child/request/turn, and
process-local duration. A monitor exit is separate from that authenticated report;
it cannot erase a report that arrived first or certify cleanup itself.

`result_recorded` requires a bounded result and actual owned-session cleanup
acknowledgment, including native helper receipts for registered shell groups and
extension VMs. `Session.close_confirmed/1` requires this acknowledgment; ordinary
`close/1` retains idempotent dead-process behavior. A dead PID, timeout, or missing
receipt cannot prove cleanup. Business assertions in the result remain untrusted.

Failure, cancellation, timeout, oversized output, and lost worker yield an unknown
outcome and stop the parent tool batch. Parent cancellation closes registered
children; owner loss stops dependent workers and child sessions. Detached process
limitations remain those of the selected [sandbox](sandbox.md).

On resume, incomplete children remain incomplete. No child or effect restarts.
A child journal cannot be resumed as a standalone root. Restore rejects duplicate
outcomes and mismatched origins/sources before tail repair. Inspect both journals
and the workspace before an explicit new attempt.

## Coordinate two children in one workspace

`--subagent-concurrency 2` adds `delegate_parallel`, accepting exactly two validated
tasks. Results preserve input order. Only the group's two authorized linked
workers can register children or forward approvals. An unknown result closes its
sibling before returning an unknown group result.

Parent serialization covers child mutation decisions and effects. Per-group path
claims use `Tools.path_key/1`: workspace expansion, Unicode normalization/case
folding, and removal of format controls, combining grapheme joiners, and variation
selectors. Original spelling stays in approval, journal, and execution. Equivalent
cross-child write/edit keys refuse even on filesystems that distinguish them.
A shell claims the whole workspace, conflicting with another child's file/shell
mutation, including a shell proposed after a file claim. Parallel file tools
reject existing hardlinks.

This is conservative conflict avoidance, not exhaustive filesystem identity.
Other sessions, hostile replacement, reads, and detached descendants remain
outside it. Preserve the restriction when changing profile inheritance.

## Practice a lifecycle change

Read the pure child-config fixture in `test/delegation_test.exs`. Identify each
removed parent field. Then follow a real approved write in
`test/delegation_session_test.exs` from parent proposal to child receipt. Finally
read sibling cancellation in `test/parallel_delegation_test.exs`.

```sh
mix test test/delegation_test.exs test/delegation_session_test.exs test/parallel_delegation_test.exs
mix test test/lifecycle_child_test.exs
```

These suites establish routing, exact approval binding, bounded results, ownership,
conflict policy, cleanup uncertainty, and inert recovery. Add a real Session
fixture for a scheduling change; pure configuration assertions cannot establish
that a child actually stops when its parent dies.
