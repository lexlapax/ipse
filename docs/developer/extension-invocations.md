# Declare a typed invocation and publish its complete result

An export connects worker code to a tool, explicit command, or bound value service.
Argument schemas control admission; result schemas control the returned domain
value. Follow one invocation through approval, effects, publication, and historical
reading. [Extension authoring](extensions.md) covers build/import/activation;
[state continuations](extension-state.md) teach approved work before completion.

## Declare what the caller can invoke

The matching `invoke.tool`, `invoke.command`, or `invoke.service` capability needs
a nonempty group in `exports`. Tools enter the model catalog. Commands run at an
operator's explicit request. Services return values to embedded or routed callers.
This is an export fragment, not a complete manifest:

```json
{
  "version": 1,
  "tools": [{
    "id": "echo",
    "description": "Return a typed text value",
    "arguments_schema": {
      "type":"object","additionalProperties":false,
      "properties":{"text":{"type":"string"}},"required":["text"]
    },
    "result_schema": {
      "type":"object","additionalProperties":false,
      "properties":{"text":{"type":"string"}},"required":["text"]
    }
  }],
  "commands": [],
  "services": []
}
```

Each group permits eight descriptors. IDs are unique lowercase ASCII identifiers,
at most 32 characters; descriptions permit 1024 UTF-8 bytes. Both schemas use the
[checked object subset](mcp.md#schema-subset), without external loading.
[`Catalog`](../../lib/ipse/extension/catalog.ex) constructs qualified names such as
`ext__memory__remember`. It rejects ambiguity, cross-instance collisions, native/MCP
shadowing, names beyond 64 bytes, more than 32 exports, or catalogs over 16 KiB.
Tools/services have separate namespaces; event jobs use a separate lane.

Activation pins normalized exports, SDK, and logical state bindings. Executable
`describe/0` must match after startup authorization. That handshake cannot certify
arbitrary code before execution. A provider's opaque call ID is a different
identity from the qualified name or host-generated invocation ID; validate the
whole response before admitting any of its calls.

## Return inline data or prepare complete output

The host sends a closed purpose-specific payload:

```json
{
  "api_version":1,
  "invocation_id":"00000000000000000000000000000000",
  "session_id":"11111111111111111111111111111111",
  "turn_id":"22222222222222222222222222222222",
  "id":"echo",
  "arguments":{"text":"example"}
}
```

Real IDs come from the host. The entire object fits 16 KiB. It carries no Session
PID, credentials, transcript, instructions, provider config, or continuation.
An inline callback fragment returns public JSON and private state:

```elixir
{:ok,
 %{"api_version" => 1, "kind" => "result", "value" => %{"text" => "example"}},
 state}
```

Only `value` is validated against the original domain schema. Action-like data
inside it executes nothing; use the host-call protocol for effects.

To publish a larger complete tool/command value, declare SDK 2 and
`invoke.result.pages` in both manifest and description, with the normal invocation
capability. In `iex -S mix`, compare aggregate validation to ordinary wire validation:

```elixir
alias Ipse.Extension.{ResultDocument, ResultPublication}
schema = %{"type" => "object", "additionalProperties" => true}
value = %{"items" => Enum.to_list(1..256)}
{:ok, bytes} = ResultDocument.encode(value, schema)
{:ok, ^value} = ResultDocument.decode(bytes, schema)
{:error, :invalid_extension_value} = Ipse.Extension.validate(value)
{:ok, delivery} = ResultPublication.prepare(value)
true = match?(%ResultPublication.Output{}, delivery)
```

The 256-member collection exceeds wire limits. `prepare/1` freezes a private
`Output`; a smaller wrapper fitting 12000 encoded bytes and all SDK bounds remains
an inline result. Invalid/over-limit values return `invalid_result_document`.
Handle that with an explicit domain refusal rather than dropping items to fit.
Return `{:ok, delivery, state}` from the original callback.

Bootstrap consumes `Output`, discards domain state, and answers terminal
`result.output` requests from frozen bytes. It does not rerun domain callbacks for
fragments. Worker independently enforces eligibility, offsets, and commitments.
Later domain calls, effects, questions, or another offer refuse. Original top-level
SDK-2 tools/commands and their ordinary host-action continuations are eligible.
Services, transforms, jobs, and recovered question continuations stay inline.
SDK-1 contracts and protocol/API version 1 remain unchanged.

## Trace the Session and worker owners

| Read in execution order | Responsibility |
| --- | --- |
| `Extension.Catalog` / `Extension.Invocation` | Resolve/validate export, arguments, identity, and durable protocol |
| `Session` / `Session.Invocation` | Admit work, commit intent, retain decisions/resources/capacity, and apply transitions in one process |
| `Extension.Host` / `Worker` | Execute owned work outside the GenServer, negotiate output, validate bytes/schema, and confirm close |
| `Extension.ResultSource` | Validate source transitions/closure, materialize committed bytes, and derive read/quota indexes |
| `Journal.Writer` | Durably append using owner-only reservations |
| `Extension.ResultView` | Construct bounded structured views of authorized historical output |

Model tools need ordinary full-argument approval unless session-wide effects are
explicitly enabled. Only literal boolean `true` authorizes. Headless/child policies
still apply. Provider call IDs are valid opaque UTF-8, 1..256 bytes, unique within
the response. Invalid batches execute no first apparently valid call.

Session syncs `extension_invocation_intent` before worker startup. Host rechecks
the artifact and initializes it, with ordinary five-second callback bounds.
Session admits slow-worker messages by caller, active reference, and phase.
[`Session.Invocation`](../../lib/ipse/session/invocation.ex) contains current
parent/action/step/results/source facts and the synchronous transition implementation.
It is not another process or a separate approval authority.

Follow `invoke_export/4`, `begin/6`, `begin_action/4`, and final result transitions.
Session retains public handler guards, actual resource completion, and applicable
accounting before calling these functions. It installs proposed facts only after
required durable appends. An action decision consumes its step only after the
record succeeds. An unknown action blocks dependent effects/publication. Questions
retain the parent and prior sources but reconstruct no timer, approval caller,
or writer reservation after restart. Publication resources and current domain
facts remain separate; do not add a competing lifecycle enum.

## Reserve capacity and commit publication

Eligible SDK-2 calls share a 120000-ms deadline from original admission, before
initialization. Approvals, computation, actions, transfer, validation, appends,
cleanup, and publication consume it. Each callback is bounded by ordinary and
remaining time. Offering output or reading a page never resets the clock; waiting
for operator approval can exhaust it.

Before begin, Session reserves journal capacity. Host submits begin/fragment/seal
requests through the owning Session, without getting a writer handle or choosing
a journal path. Lease checks precede every append. Host verifies the complete
document/schema and confirms worker cleanup. Only the final version-2 invocation
result publishes the saved descriptor. A complete source/seal alone does not.
Elapsed checks guard admission, not realtime completion of filesystem sync.
A committed final receipt remains committed after a later timer fires.

| Resource | Bound |
| --- | --- |
| SDK encoded object | 16384 bytes |
| SDK string/depth/collection | 8192 bytes / 12 levels / 128 members |
| Worker frame / lifetime traffic | 32768 bytes / 64 MiB |
| Encoded fragment reply / raw fragment | 12000 / 4096 bytes |
| Fragments / complete received and re-encoded document | 1024 / 4 MiB |
| Aggregate string/depth/collection | 8192 bytes / 12 levels / 4096 members |
| Aggregate nodes, including keys | 262144 |
| Begun attempts per Session, including interrupted | 64 |
| Encoded source records, including unreadable prefixes | 64 MiB |

ResultDocument requires a map root, duplicate-free decoded keys, lexical resource
checks before decoding, finite numbers, and the original result schema. Integer
tokens retain the maintained decoder's 1024-byte limit, including a minus sign.
General `Ipse.JSON.decode_bounded/2` instead defaults to 32 KiB, permits at most 1 MiB
explicitly, and limits nesting to sixteen. Raising that general limit cannot
replace the dedicated aggregate checks or enlarge SDK wire values.

Reservations cover begin, fixed-stride fragments, seal, final result, and quota
marker headroom. Other appends cannot spend them. Cancellation releases unused
capacity before its control result; written bytes remain charged. Lower operator
journal limits can refuse earlier. Reservations guarantee neither successful IO
nor replay authority. [Persistence](persistence.md) teaches their completion owner.

## Materialize without repeating execution

Inline delivery contains the value. Saved delivery instead contains this illustrative
descriptor, whose real hashes identify exact retained bytes:

```json
{
  "version":1,"kind":"saved.result",
  "output_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "byte_count":16911,
  "sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "historical_receipt":true
}
```

The final invocation record also binds original intent and ordered action-chain
commitments. Do not validate a descriptor against the domain schema or treat its
display text as the domain answer. An embedded API fragment materializes it:

```elixir
{:ok, %{bytes: bytes, value: value, provenance: "historical_receipt"}} =
  Ipse.Session.materialize_result(session, delivery)
```

The complete size/digest/aggregate/schema checks precede a usable value. Failure
returns no partial document. Reading starts no worker, query, or model call.
[Operator reading](../operator/extensions.md#invoke-a-command-and-inspect-its-complete-result)
covers the CLI. `Session.read_saved_result/2` provides an authorized bounded root/
path view, with exact returned cursors for continuation. Views allow sixteen
children or 1024 UTF-8 bytes and fit 12000 encoded bytes plus all SDK bounds.
Large children/keys carry references. Ordinal cursor paths keep long escaped
keys reachable. `complete` describes the target, not every referenced subtree.

A cursor grants no authority. Model `saved_result_read` sees only outputs previously
disclosed through that Session's model tools. Direct commands and operator views
remain outside model history. Children/unrelated extensions gain no access through
an ID, service route, history, or `host.results`. Historical receipts retain older
bytes after expiry/forgetting/replacement. They assert no current eligibility,
freshness, truth, or semantic support.

## Restore closure before repairing a journal

Invocation validates closed records, exact identity/argument digest, approval,
parent provenance, tool receipts, and ordered actions. ResultSource restoration
validates every source before permitted tail repair, deriving quota/read indexes
without executable initialization.

An interrupted begin/fragment prefix remains unreadable, even if it contains all
declared bytes of invalid JSON or a schema-invalid value. Seal requires a complete
valid document. Foreign/missing/corrupt/mismatched sources behind seals or final
receipts refuse recovery. A valid seal without final publication is an orphan.

A committed tool receipt reconstructs its exact message if the redundant message
append was interrupted; an existing message is added once. Command/service displays
restore separately from assistant answers. Idle resume starts no callback, action,
query, or unfinished output. Inspect unknown evidence before new work.
One serialized lane permits at most 10000 invocations. Intent records permit
64 KiB and final records 128 KiB; those journal bounds do not enlarge SDK messages.

## Practice a complete change

Trace lab `stats` from [its spec](../../examples/extension-lab/spec.exs) and
[worker](../../examples/extension-lab/src/memory.ex) into a state read and typed
result. Find [the proof](../../dev/verification/lab.exs) asserting no inference or
tombstone mutation. A similar command needs a descriptor/callback and behavioral
proof, without a feature-specific CLI branch.

```sh
mix test test/ipse/extension/catalog_test.exs test/ipse/extension/invocation_test.exs
mix test test/ipse/extension/result_document_test.exs test/ipse/extension/result_publication_test.exs
mix test test/ipse/extension/result_source_test.exs test/ipse/extension/result_view_test.exs
mix test test/ipse/extension/result_session_test.exs
```

Follow preparation/terminal transport, source closure, disclosure, then Session
publication. Preserve interruption, identity, cleanup, quota, and denial cases.
The [saved-result example](../../examples/README.md) verifies one callback and
1024 fragments totaling 4 MiB, inert resume, and no model request. Run source and
installed variants through [testing](testing.md); a pure source reducer pass does
not prove actual worker cleanup or packaged runtime behavior.
