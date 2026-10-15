# Local delegation contract

Status: P6 is complete within this scope. Arch source, package, and live checks
passed; Linux/macOS hosted source/package checks also passed.
The developer selected local subagent
delegation with parent-controlled approvals, followed by expanded MCP in P7.
See the [plan](../plan.md), [architecture](architecture.md), and prior
[protocol proposal](protocol-proposal.md).

## Scope and context

An explicit `--subagents` option enables one `delegate` function in the existing
session loop. Defaults remain disabled. The parent reviews the complete task
and selected context before a child starts. A child is another ordinary
`Ipse.Session`, with its own conversation, lock, and private journal. It uses
the parent's provider, requested model, workspace, shell policy, and saved
workspace-instruction snapshot. It receives only the explicit task/context,
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
active job reference. The parent records the child journal ID and relationship.
A stale registration fails before inference or tools. Required child approvals
return through the parent UI with the child ID, tool name, and full arguments.
Each decision binds to the exact child/reference/arguments and is journaled;
an earlier delegation approval does not approve a later child effect.

Interactive approval remains individual. Headless delegation is denied without
`--yes`; explicit session allowance also covers child mutations. Repository
instructions and child/model output cannot enable delegation or change policy.
Oversized forwarded approval arguments are denied without truncation.

## Lifetime and recovery

One child runs at a time. Its owner is the parent's monitored delegation worker;
parent loss kills the worker and child owner loss stops child work. Explicit
parent cancellation cancels and closes registered children before reporting
completion. Child calls use existing tool supervision and OS process cleanup.
Detached-descendant limitations of trusted/native execution remain unchanged;
delegation does not strengthen the sandbox boundary.

Children have at most six model steps, a two-minute active task budget, and a 16 KiB final
result. A parent may start at most two delegations in one user turn. Each task
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
