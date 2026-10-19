# Run file and shell work from an extension

Use `tool.call` when a workflow needs Ipse's existing `read`, `write`, `edit`, or
`shell` tool. Session retains schema validation, workspace instructions,
approval, sandbox selection, and durable outcomes. A worker's ordinary value or
question answer cannot execute a tool.
Use the separate [MCP action contract](extension-mcp-actions.md) for a selected
external service; `tool.call` does not route MCP names.

Read the `workflow` export and answered continuation in
`examples/extension-lab/src/memory.ex`. It turns a selected note into this typed
proposal rather than writing directly from extension code.

## Propose a bounded tool call

Declare `host.actions` and `host.tools` in the artifact and operator trust ceiling:

```json
{
  "api_version": 1,
  "kind": "host_call",
  "request": {
    "op": "tool.call",
    "name": "write",
    "arguments": {"path": "result.txt", "content": "reviewed result"},
    "timeout_ms": 1000
  }
}
```

The request has exactly those keys. Arguments use the existing tool's closed
schema and SDK JSON bounds. `timeout_ms` is required and ranges from 1 through
30,000. A shell argument's optional inner timeout cannot exceed the outer one;
when omitted, shell uses the explicit outer deadline. The call consumes one of
the ordinary 16 host-action steps, including across question continuations.
An explicit `host.actions.mixed` grant permits reads before those approved
actions under its separate counters; it does not add tool authority.

Write, edit, and shell require full separate mutation approval unless the session
explicitly enables execution. Read uses ordinary read policy but still requires
the trusted capability. Approval shows the complete request, instance/artifact,
and null state namespace. Unknown tool names, MCP, delegation, and recursive
extension calls refuse. Neither invoking a command, approving its enclosing model
tool, nor answering a question approves this effect.

## Workspace context and owned execution

Before admission, the host task snapshots current workspace instructions and
performs nested-path discovery outside the GenServer. If new guidance is found,
it persists that guidance and stops before approval, intent, or execution.
The operator can inspect `/context` and explicitly invoke fresh work. Existing
loaded-instruction drift follows `/context refresh`. There is no automatic retry,
and instruction text does not enter the worker's payload.

Session consumes an admission gate binding the exact reviewed request and
workspace snapshot digest. Its action intent records `context_sha256`; recovery
compares that hash with the journaled workspace snapshot. State/question calls
use null for this field. The intent sync precedes execution.

`ToolAction` reuses `Ipse.Tools` and native `Runner`. A linked leaf task owns IO;
cancelling the host task stops that leaf and its shell Port. File operations use
the outer deadline. Shell also allows the existing supervisor setup window,
five seconds or 25 seconds for macOS native setup.

Path, symlink, workspace, `.git`, and parallel-child hardlink checks stay in
`Ipse.Tools`. Session shell policy passes through unchanged and fails closed when
unavailable. Workers themselves are trusted OS-level code; host tool ownership
and shell sandboxing do not sandbox arbitrary worker operations.

A child extension still needs explicit `allow_children`. Its mutation approval
relays through the parent and uses the conservative whole-workspace conflict
claim. This API does not grant child MCP or recursive delegation.

## Interpret recorded outcomes

Successful file tools return `{"text": "..."}`. Normally completed shell calls
return `text`, `exit_code`, `output_bytes`, and `output_truncated: false`.
A nonzero exit code remains visible. Status `ok` means execution was recorded,
not that the command achieved its domain goal.

Returned text is at most 4 KiB and must fit the complete escaped SDK envelope.
Timeout, signal, ambiguous failure, incomplete output, or oversized encoding
stops the chain as unknown; partial output is not fed to another callback as a
complete result. Runner counts drained bytes and preserves truncation/incomplete
tail metadata.

Read errors are known `failed` outcomes with `reason: tool_failed`. Oversized
reads return `reason: result_limit` without partial text. A callback can propose
an explicitly smaller read within its remaining budget. Write/edit failures are
conservatively unknown because an effect may have partially happened.

Session syncs results before continuing the worker. Recovery checks exact
source/context/request bindings and the final action-chain digest before repair.
Committed receipts restore without running tools; missing results stay unknown.
Inspect the workspace before explicitly deciding to repeat an effect. A host
upgrade changes activation identity, requiring the documented frozen-runtime or
reviewed fresh-session handoff for old sessions.

## Exercise denial and interrupted output

Follow `ToolAction.validate/1`, `Operation.mutating?/1`, and the execution branch
in `Host`. Find the fixtures for a denied write and a shell that outlives its
owner. Confirm that denial records a known result without a file, while an
interrupted intent never becomes successful merely because its process exited.

```sh
mix test test/extensions_invocation_test.exs test/extensions_event_job_test.exs
```

Those fixtures exercise full approval, nested instruction discovery, shell output
bounds, process-group cancellation, and tampered context receipts. Use the
[installed lab](extension-proof.md) to check the same workflow against a packaged
runtime. No provider or paid service is needed for these synthetic scenarios.
