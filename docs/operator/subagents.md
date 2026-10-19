# Delegate a bounded task to a local subagent

Use a child for a small task whose result you can inspect, such as reviewing one
module or comparing a proposed change with tests. Children share your workspace;
they are separate conversations, not isolated checkouts. Delegation is disabled
by default and makes additional requests to the selected model service.

## Enable a read-only child review

Choose a provider you have configured, then launch:

```sh
ipse chat --provider chatgpt --subagents --cwd /path/to/project
```

This example uses real ChatGPT subscription requests. For another provider,
select it explicitly or use [model profiles](model-profiles.md).
At the prompt, ask:

```text
Inspect the current diff. Delegate a read-only review of the changed error
handling with only the necessary context. Check the child's findings against
the source and report actionable problems with file locations. Do not edit.
```

The model proposes `delegate` with a task and selected context. Review both before
approving. The child receives those fields and the saved workspace-instruction
snapshot, not your full transcript. It uses a selected configured profile/role,
the configured routine role, or the inherited provider/model. No route silently
changes billing.

After it finishes, inspect the evidence in the parent's result. The child's
claims are untrusted output. A completion receipt establishes observed completion
and cleanup status, not correctness of the review.

## Approve effects separately

The CLI displays child proposals with the child session ID, tool, and complete
arguments. Approving delegation does not approve later file writes, edits, shell
commands, or permitted extension effects. Read each proposal and use its own
printed `allow CODE`, or deny with `n`.

Children cannot use MCP, delegate recursively, or ask structured operator
questions. Ask the child to return missing information to the parent. Explicitly
allowed child extensions keep their separate grants, approvals, and tree budget.
Shell commands use the parent's selected shell sandbox. Workspace sharing does
not protect files against concurrent reads or unrelated processes.

Headless work denies delegation/effects without `--yes`. This deliberately broad
example permits them for the task:

```sh
ipse run --provider chatgpt --subagents --yes --cwd /path/to/scratch \
  'Delegate a small review task, inspect its evidence, and finish'
```

Use interactive mode when you need to approve each effect.

## Run two independent children

```sh
ipse chat --provider chatgpt --subagents --subagent-concurrency 2 --cwd /path/to/project
```

Then ask for two bounded tasks, for example a source review and a test review of
the same small change. `delegate_parallel` contains exactly two task/context
objects. You approve the full group before either starts. Results return in task
order, while each child has a separate journal and its own approval route.

Only one child mutation runs at a time. A file write/edit claims that target for
the group. Equivalent Unicode/case spellings also conflict; hardlinked targets
cannot be mutated in parallel mode. A shell command claims the whole workspace
and conflicts with another child's mutation. Reads and model work can still
observe changing files. These rules reduce conflicting effects; they do not give
each child a filesystem snapshot.

## Keep tasks within the limits

A parent turn admits at most two children, serially by default. A parallel group
uses that full allowance. Each child gets at most six admitted main/helper model
calls and two minutes of active work; approval waiting pauses active time. Task
and selected context are each at most 8 KiB. A final result is at most 16 KiB, and
full child approval arguments must fit the 32 KiB display bound. Oversized results
stop with uncertainty instead of silently losing evidence.

Parent and child accounting remain separate in their journals. Optional
[tree cost reports](usage-accounting.md) can combine registered children under an
additional read grant. A configured [budget](budgets.md) shares reservations
across the tree, including selected extension model requests.

## Cancel, inspect, and resume

`/cancel` stops parent and owned children and clears queued input. An interrupted,
timed-out, failed/unknown, or oversized child makes the delegation unknown and
stops remaining work; a failed parallel child also stops its sibling. Started
effects can remain. Inspect the workspace before requesting another attempt.

Resume the parent with its original configuration and delegation settings:

```sh
ipse diagnose --resume PARENT_SESSION_ID
ipse chat --resume PARENT_SESSION_ID
```

Add the original `--state-dir` when customized. Resume restores the saved opt-in
and concurrency and refuses conflicting choices. It never restarts children or
replays their tools. Start a fresh session to change those choices.

Child journals live under
`STATE_DIR/subagents/PARENT_SESSION_ID/CHILD_SESSION_ID.jsonl`. They are private
and cannot be resumed as standalone root CLI sessions. Parent receipts record
whether a bounded result and cleanup were observed. An exited task or helper
alone cannot confirm all cleanup; deliberately detached descendants retain the
[documented shell limits](usage.md#shell-policy). If cleanup is unconfirmed,
inspect running work and use the [recovery procedure](recovery.md).
