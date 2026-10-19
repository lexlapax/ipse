# Build typed tools, commands, and services

An export gives a worker a named entrypoint with argument and result schemas.
Tools enter the model's function catalog. Commands are invoked explicitly by an
operator. Services return typed values to embedded callers or explicitly routed
extensions. They share the same owned invocation path and durable no-replay rules.

Start with `examples/extension-lab/src/lookup.ex` for a value-only service, then
read `src/memory.ex` for tools and commands that continue through host actions.
Keep domain values separate from the outer invocation protocol.

## Inert declarations

A manifest with `invoke.tool`, `invoke.command`, or `invoke.service` declares a
nonempty matching group in `exports`. Its normalized version-1 catalog contains
`tools`, `commands`, `services`, and optional `jobs`. For example:

```json
{
  "version": 1,
  "tools": [{
    "id": "echo",
    "description": "Return a typed text value",
    "arguments_schema": {
      "type": "object", "additionalProperties": false,
      "properties": {"text": {"type": "string"}}, "required": ["text"]
    },
    "result_schema": {"type": "object"}
  }],
  "commands": [],
  "services": []
}
```

This is an `exports` fragment, not a complete artifact. Each group allows at most
eight descriptors. Local IDs are unique lowercase ASCII identifiers up to 32
characters; descriptions are UTF-8 up to 1,024 bytes. Both schemas are object
schemas from the [bounded subset](mcp.md#schema-subset). External references and
executable registration are unavailable. The complete manifest still fits 16 KiB.
A nonempty group requires its capability, and a capability requires its group.

`Catalog` creates names such as `ext__memory__remember`. Names are at most 64
bytes and resolve by exact name and stage. It refuses ambiguous names,
cross-instance collisions, builtin/MCP shadowing, more than 32 total exports,
and a catalog above the 16 KiB plain-JSON bound. Kind-specific namespaces allow
a tool and service with the same local ID. Jobs have separate event admission
and cannot be called as ordinary exports.

The activation identity pins normalized exports and any logical state binding.
Executable `describe/0` must match the inert catalog exactly. Omitted declarations
for transform-only artifacts normalize to empty. This handshake happens after
journaled startup authorization, so it cannot certify safe arbitrary code before
execution.

## Trace a value invocation

`Session.exports/1` inspects the active catalog without starting code.
`Session.invoke_export(pid, :command, name, arguments)` and the corresponding
`:service` call run only while idle. The terminal uses `/ext NAME JSON_OBJECT`;
`/ext` lists active commands. Calling a command authorizes that callback, while
later effects require separate admission.

The host supplies this closed payload to the declared `invoke.*` stage:

```json
{
  "api_version": 1,
  "invocation_id": "00000000000000000000000000000000",
  "session_id": "11111111111111111111111111111111",
  "turn_id": "22222222222222222222222222222222",
  "id": "echo",
  "arguments": {"text": "example"}
}
```

IDs here illustrate the shape; the host generates real IDs. The whole payload,
including arguments, must fit 16 KiB. No Session PID, provider configuration,
auth, transcript, workspace instructions, or native continuation crosses the SDK.

A value-only callback can return:

```elixir
{:ok,
 %{"api_version" => 1, "kind" => "result", "value" => %{"text" => "example"}},
 state}
```

`value` must satisfy the export's result schema. Action-looking keys inside it
remain data. To request an effect, return the separately negotiated
[`host_call`](extension-host-calls.md) outer protocol.

## Owned invocation

For model tools, the host validates the schema, provider call IDs, lease, and
reviewed arguments before execution. Every model tool needs full argument approval
unless session-wide execution is explicitly enabled. Only literal boolean `true`
approves. Headless denial and child policy apply. Provider call IDs follow
`Ipse.ToolCall`: opaque UTF-8, 1–256 bytes, unique within the proposed response.
They are different from catalog names and internal invocation IDs.

Session validates the owned task's PID/job reference and syncs
`extension_invocation_intent` before opening a worker. Host then reverifies the
immutable artifact, initializes it, and calls the declared stage with separate
five-second initialization/callback bounds. Worker cleanup, reply schema, and
current lease checks precede the synced `extension_invocation_result`.

A tool's saved text is JSON encoding of `value`, with a host receipt binding call
ID, approval, artifact, and output digest. Saved assistant/native messages remain
unchanged. Commands/services display separately and cache in
`Session.info.extension_result`; they do not overwrite the assistant answer or
automatically enter model context.

Crash, timeout, invalid schema, or unconfirmed cleanup stops the invocation with
an unknown outcome. The callback may already have executed, so the host does not
retry it. Cancellation and owner death stop the job and its worker process group
within the documented OS cleanup boundary.

## Durable recovery and bounds

`Invocation` validates closed records, exact metadata/catalog/identity,
argument/output digests, unique IDs, original parent request/call provenance,
reviewed arguments/approval, and tool receipts. Final results bind the action
count and ordered action-chain digest. Orphaned, duplicate, reordered, or altered
records refuse recovery before tail repair under the actual session lock.

A committed tool result restores its exact ordinary tool message if interruption
prevented the redundant message append. If the message also exists, it is added
once. Uncommitted intents remain unknown. Idle resume initializes no callbacks
and restores the last command/service value without rerunning or printing it.

A session admits at most 10,000 invocations. Intent records are at most 64 KiB
and result records 128 KiB; SDK objects remain 16 KiB and worker envelopes 32 KiB.
The larger journal bound accommodates separately bounded schemas, values, and
escaped rendered text. There is one serialized invocation lane per Session;
slow execution runs outside its GenServer.

## Add an export without a host branch

For an exercise, trace the lab's `stats` command from its descriptor in
`examples/extension-lab/spec.exs` to `Memory.handle/3`. It performs one state read
and returns counts. Find the assertion in `proof.exs` that checks no inference
and no tombstone mutation. A similar read-only command should require changes to
its extension descriptor, worker, and tests, rather than a command-specific CLI
case.

```sh
mix test test/extensions_catalog_test.exs test/extensions_invocation_test.exs
```

Use catalog tests for inert schema/naming negotiation and invocation tests for
approval, receipts, interrupted work, and resume. Continue with
[host calls](extension-host-calls.md) when the value needs state, questions, tools,
services, model calls, history, or context.
