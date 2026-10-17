# Typed extension catalogs and invocations

P22A7 adds inert manifest-declared tools, operator commands and standalone typed
services. They share the independent worker SDK and owner chain used by the
[prompt/presentation hooks](extension-hooks.md). This increment does not complete
P22: scoped storage/context contributions, worker-to-host service composition,
approved action proposals, workflows, worker text handles and observability
controls remain separate work. No provider or store is selected implicitly.

## Inert declarations

`extension.json` optionally adds `exports`. Its presence is required when
declaring the corresponding `invoke.tool`, `invoke.command` or `invoke.service`
capability. Discovery/import validates data without calling extension code.
The closed version-1 object always has `version`, `tools`, `commands`, `services`:

```json
{
  "version": 1,
  "tools": [{
    "id": "echo",
    "description": "Return a typed value",
    "arguments_schema": {
      "type": "object",
      "additionalProperties": false,
      "properties": {"text": {"type": "string"}},
      "required": ["text"]
    },
    "result_schema": {"type": "object"}
  }],
  "commands": [],
  "services": []
}
```

Each group has at most eight descriptors with unique lowercase ASCII local IDs
of at most 32 characters and UTF-8 descriptions of at most 1024 bytes. Both
schemas must be object schemas from the existing [bounded subset](mcp.md#schema-subset).
There are no external references, executable schemas or registration callbacks.
The original 16 KiB manifest limit still applies. Empty/missing groups cannot
declare an invocation capability, and nonempty groups require that capability.

`Catalog` derives `ext__INSTANCE__ID` names, at most 64 bytes. Names are looked up
directly with an explicit stage; delimiter ambiguities cannot select another
instance. Cross-instance collisions are refused, as are more than 32 total
exports or a catalog exceeding the 16 KiB plain-JSON bound. Kind-specific
namespaces allow a tool and service to expose the same local ID. Only tools
enter the model's function catalog. These names cannot shadow builtin/MCP names.

Activation identities now pin operator/project scope, SHA-256 of the config
source path and the normalized export digest, in addition to artifact/options/
runtime/host identity. Options remain private. `Registry.prepare` performs the
whole catalog check using one admission clock; Session rechecks real current
time. `describe/0` must report SDK/capabilities and the exact declared exports;
for old transform-only artifacts, omitted exports normalize to the empty catalog.
The executable handshake is checked only after journaled startup authorization;
inert declarations cannot certify that arbitrary code is honest or side-effect-free.

## Owned invocation

Every model tool invocation needs full argument approval unless the operator
explicitly selected session-wide execution. Headless denial, child policy and
lease checks remain core-owned. Invalid schemas, duplicate provider call IDs and
duplicate JSON keys refuse execution before approval/code initialization.

An explicit idle embedded call
`Session.invoke_export(pid, :command | :service, name, arguments)` starts an owned
command/service without a model request. `Session.exports/1` is inert inspection.
The terminal exposes commands through `/ext NAME JSON_OBJECT` and lists the
active catalog with `/ext`. Calling a command authorizes its selected callback,
not arbitrary host effects. Service composition from another worker is not yet
implemented by this standalone embedding interface.

The Session verifies the owned task PID/job reference, exact reviewed arguments,
descriptor and lease. It syncs `extension_invocation_intent` before opening the
worker or executing `on_load`, `describe` or `init`. `Host.invoke_export` then
uses the same reverified immutable artifact, private options, initialization and
five-second worker-call bounds as transforms. Callback stages are the declared
`invoke.*` strings and payloads are closed:

```json
{
  "api_version": 1,
  "invocation_id": "00000000000000000000000000000000",
  "session_id": "00000000000000000000000000000000",
  "turn_id": "00000000000000000000000000000000",
  "id": "echo",
  "arguments": {"text": "example"}
}
```

Identifiers above are illustrative; the host generates the actual values.
No Session PID, provider settings, auth, transcript, workspace instructions or
native continuation crosses this boundary. Arguments must fit the full 16 KiB
payload envelope, not just their own object.

The only implemented reply is
`%{"api_version" => 1, "kind" => "result", "value" => object}`.
`value` must satisfy the declared result schema; the whole reply obeys SDK bounds.
Action-looking fields inside `value` remain data. Unknown reply kinds, including
host-action proposals, are refused. New action capabilities must explicitly
negotiate a typed outer protocol and reuse approval/intent boundaries; they cannot
retroactively reinterpret domain JSON or command strings as executable actions.

After confirmed normal worker cleanup, Session validates the exact result and
current lease, then syncs `extension_invocation_result`. Tool text is the saved
JSON encoding of `value`, with a host receipt tying native call ID, approval,
artifact and output digest to that result. Original assistant/native messages
remain untouched. Command/service values are displayed separately and cached in
`Session.info.extension_result`; they do not overwrite the assistant answer or
automatically enter model context. Worker crashes/timeouts/schema failures stop
the turn with an unknown outcome; callbacks are never automatically retried.

## Durable recovery and bounds

The pure `Invocation` validator checks closed records, versions, pinned metadata
catalog/identities, descriptor/argument/output digests, unique invocation IDs,
native parent request/call provenance, matching reviewed arguments/approval,
reply schemas and tool receipts. Orphaned, replayed or inconsistent records refuse
recovery. Historical expiry is not reinterpreted as a successful callback; current
activation leases must still be valid. These are integrity checks, not signatures.

Validation reloads the journal under its actual session lock before tail repair.
Idle resume never initializes a callback. A committed tool result is a durable
projection: if interruption occurs before its redundant ordinary tool-message
record, restore reconstructs that exact message from the receipt. If both exist,
it adds the message once. Uncommitted intents remain unknown and are not replayed.
The last committed command/service display is restored without printing/rerunning it.

There are at most 10,000 invocations per session, then explicit admission refuses
before initialization. Intent events are bounded to 64 KiB; result events to
128 KiB because they include separately bounded schemas/payload/value and escaped
rendered text. SDK messages remain 16 KiB and worker framing 32 KiB. Invocation
state is serialized per Session, outside its GenServer for worker/file IO other
than required synchronous journal commits. Cancellation/owner death kills the
host job and its VM/process group; detached OS descendants retain the documented
[execution limits](../operator/extensions.md#recovery-and-execution-boundaries).

This adds no dependency. Jason/JSONSchex/shared JSON bounds and the existing native
worker supervisor are reused. Ordinary maps and receipts implement Ipse's static
registration and journal-specific no-replay rules, without a workflow framework.
Fixtures are in `extensions_catalog_test.exs`, `extensions_invocation_test.exs`,
registry/worker/session tests and the terminal fixtures; see [actual evidence](testing.md).
