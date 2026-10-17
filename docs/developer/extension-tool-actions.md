# Extension workflow tool actions

P22A10 adds `host.tools` to the [finite host-call protocol](extension-host-calls.md).
It calls the existing `read`, `write`, `edit` and `shell` tools through host-owned
schema, context, approval and execution boundaries. It does not register a new
agent loop or authorize arbitrary tool IDs. [Value-service composition](extension-services.md)
is implemented separately; context contributions and the independent package
proof remain P22 work.

## Request and permission

An artifact explicitly declares `host.actions` and `host.tools`; operator trust
must allow both. A callback may return:

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

These are the exact request keys. Arguments reuse the existing tool's closed
schema and SDK plain-JSON limits. `timeout_ms` is required, integer 1–30,000.
An optional shell argument `timeout_ms` cannot exceed the outer deadline; when
omitted, shell execution uses that explicit outer deadline. All host calls,
including questions/state and resumed continuations, share the 16-operation cap.

Write/edit/shell require separate full mutation approval unless execution was
explicitly enabled for the session. Read follows ordinary read-tool policy and
still needs the trusted capability. Operator command invocation, original model
tool approval and question answers cannot approve a later effect. Approval shows
the full request, extension/artifact and null state namespace. Unknown tools,
MCP IDs, recursive extension calls and delegation IDs are refused by this API.

## Workspace context and owned execution

Before tool admission, the owned host task snapshots the Session's current
workspace instructions and performs existing nested-path discovery outside the
GenServer. Newly discovered guidance is persisted and stops the invocation before
tool intent/approval/effect. The operator can inspect `/context` and explicitly
choose a fresh invocation. No callback or effect automatically retries.
Already loaded instruction drift follows the existing explicit `/context refresh`
policy. Worker code does not receive instruction contents or a Session PID.

The Session binds reviewed request and workspace snapshot digest in a consumable
admission gate. Action intent includes `context_sha256`, checked against the
current journaled workspace snapshot on recovery. State/question receipts use
null for this field. The mandatory intent sync precedes tool execution.

`ToolAction` reuses existing file tools and native Runner. A linked leaf task owns
IO; cancelling/killing its host task also stops that leaf and its shell Port.
File operations have the explicit outer deadline. Shell calls additionally allow
the existing supervisor setup window (5 seconds, or 25 for macOS native setup).
Owner cleanup, deadlines and native process groups do not constitute an OS sandbox;
the selected Session shell policy is forwarded unchanged and fails closed when
unavailable. macOS detached-descendant cleanup retains its documented limits.

File path/symlink/workspace/.git and parallel-child hardlink checks remain in
`Ipse.Tools`. Child extensions still need explicit `allow_children`; mutation
approval relays through the existing parent path. Extension approval names take
the parent's conservative whole-workspace conflict claim, rather than gaining
an exemption from child mutation coordination. No MCP or recursive delegation
capability is supplied to children by this tool API.

## Results and recovery

Successful file tools return `{"text": ...}`. Normally completed shell calls
return `text`, `exit_code`, `output_bytes`, `output_truncated: false`. A nonzero
exit code remains visible; `ok` describes recorded execution, not semantic
success of the command. Runner counts all drained output bytes and exposes
truncation/incomplete-tail metadata while preserving existing terminal output.

Returned text is at most 4 KiB and must fit the complete escaped SDK envelope.
Timeout, signal/ambiguous failure, incomplete output or oversized encoding yields
an unknown action result and stops the callback chain. Partial text is not
silently treated as complete or automatically streamed to another callback.
Read errors return a known `failed` result with fixed `reason: tool_failed`;
oversized read results use `reason: result_limit` without returning partial data.
A bounded callback can then choose an explicit smaller read or another action,
still subject to the same budgets/approval. Write/edit errors are conservatively
unknown because a failed write may have partially happened. Cancellation can leave
only intent; it is never replayed.

Results sync before returning to the worker. Their source/context/request hashes
and final invocation action-chain digest validate before tail repair. A committed
receipt restores without rerunning the tool; an interrupted effect stays unknown.
Inspect the workspace before explicit recovery. An exact host upgrade changes
activation identity; use a frozen runner or reviewed fresh-session handoff for
older pinned sessions rather than editing receipts.

No dependency was added: existing JSONSchex/Jason, tools, OTP linked tasks and
native Runner are reused. Independently compiled fixtures exercise real approved/
denied writes, nested instruction refusal, bounded shell completion/output,
actual process-group cancellation and altered context receipt refusal. See
[verification](testing.md) and [operator procedures](../operator/extensions.md#workflow-tools).
