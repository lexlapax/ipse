# Local subagents

Local delegation is disabled by default. Source, fixture, and live subscription
checks passed on Arch; see [actual evidence](../developer/testing.md#p6-local-delegation-2026-10-15).

## Enable delegation

```sh
./bin/ipse chat --provider chatgpt --subagents --cwd /path/to/workspace
```

The startup notice confirms the option. The model can propose one `delegate`
call with a task and selected context. Review both fields before approving:
starting a child makes additional model requests using the selected profile/role,
or the parent provider/model when no routine role is configured. See
[model profiles](model-profiles.md) for explicit mixed-provider routing. There is no automatic billing or model
switch. A child shares the workspace and saved workspace instructions, but gets
its own conversation and journal instead of the parent's full transcript.

The parent CLI displays each required child approval with the child session ID,
tool name, and complete arguments. Approving delegation does not approve its
later writes, edits, or shell commands. Ordinary file reads and skill loading
retain their existing policy. Rejecting one proposal grants no permission to
evade it. Children cannot delegate recursively or use configured MCP servers.

Headless delegation is denied without `--yes`. With explicit `--yes`, the session
allowance also covers child mutations:

```sh
./bin/ipse run --provider chatgpt --subagents --yes --cwd /path/to/workspace \
  'Delegate a small review task, inspect its evidence, then finish'
```

Use that option only when the selected workspace and tools are appropriate.
Shell commands keep the parent's requested `--sandbox off|native` policy.
Sharing a workspace is not isolation: a child may change files the parent is
using. Existing native/trusted execution limits, including detached descendants,
still apply. See [shell policy](usage.md#shell-policy).

## Bounds and recovery

Children run serially by default, with at most two child tasks in one parent
turn. Each child has at most six model steps and two minutes of active work;
waiting for your approval pauses that budget. Tasks
and selected context are each limited to 8 KiB; final child results to 16 KiB.
Oversized results stop with uncertainty instead of silently truncating evidence.
Required child approval arguments must fit the full 32 KiB display bound.

`/cancel` stops active parent/child work and clears queued input. A stopped,
interrupted, timed-out, or oversized child result marks the parent delegation
unknown and stops its remaining tool batch. Previously executed effects may
remain; inspect the workspace and both journals before requesting another try.
Stopping a child does not roll back its actions.

Parent sessions resume using the usual `--resume ID` command. The saved
delegation opt-in is restored and displayed; a conflicting `--subagents` or
`--no-subagents` refuses resume. Start a new session to change that opt-in.
Resume never restarts a child or replays its tools.
Child journals are separate private files under
`STATE_DIR/subagents/PARENT_SESSION_ID/CHILD_SESSION_ID.jsonl`, with parent/call
provenance. They cannot be resumed as standalone root CLI sessions. The parent
history retains the selected task, approvals, relationship, bounded untrusted
result and a parent-side completion receipt. The receipt distinguishes an observed
bounded result from an unknown outcome and records whether the child acknowledged
cleanup. A process exit alone is insufficient; an abruptly killed parent may
leave an incomplete start. None of these statuses certifies a child's claims.
Selected lifecycle consumers can observe metadata through
[event feeds](extensions.md#live-event-feeds); task/result text is not included.

See [usage](usage.md), [the developer contract](../developer/delegation.md), and
[the plan](../plan.md#p9-parallel-local-subagents). Remote agents, automatic
retries, and child MCP remain unavailable.

## Parallel local children

```sh
./bin/ipse chat --subagents --subagent-concurrency 2 --cwd /path/to/workspace
```

This exposes `delegate_parallel` for exactly two bounded task/context objects.
The parent approves the complete group before either child starts. Children use
configured profiles/roles or inherited provider/model, separate journals and individually routed mutation
approvals; results return in task order. One group consumes the two-child turn
budget, at most twelve child model calls in total. Serial delegation remains
available. The concurrency setting is saved and must match on resume.

Only one child mutation executes at a time. Approved write/edit targets are
claimed by that child for the group; another child's request for the same
normalized path is denied. Shell claims the whole workspace and conflicts with
every other child's mutation in either ordering. Parallel children cannot mutate
hardlinked files. Reads/model work may overlap writes and observe changing data;
this is not filesystem isolation or protection against unrelated processes or
hostile path replacement. Conflict denials are journaled as `conflict_denied`
by the parent and denied in the child's own journal.

Approvals queue behind the current decision/effect, pausing the child's active
budget. `/cancel` and parent death stop both owned children. A failed/unknown
child stops its sibling and leaves the group unknown without replay. Run
`mix run scripts/demo-subagents.exs` for credential-free serial/parallel demos.
See [P9 evidence](../developer/testing.md#p9-parallel-local-delegation-2026-10-15).
