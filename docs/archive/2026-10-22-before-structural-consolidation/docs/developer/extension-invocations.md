> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/developer/extension-invocations.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Build typed tools, commands, and readable results

An export connects a worker callback to a named tool, command, or service. Its
argument schema controls admission. Its result schema controls the domain value
that the caller receives. The host owns approval, execution, durable receipts,
and cleanup. Keep those responsibilities out of extension domain code.

This chapter follows a result from its inert declaration through publication and
later reading. Start with the [artifact and SDK training](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-artifacts.md)
for compilation and import. Use [host calls](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-state.md#read-a-revision-and-propose-a-write) when a
callback needs approved effects before it returns a value.

## Declare the caller's contract

A manifest with `invoke.tool`, `invoke.command`, or `invoke.service` declares a
matching nonempty group in `exports`. Tools enter the model's function catalog.
Operators invoke commands explicitly. Services return typed values to embedded
callers or explicitly routed extensions.

The following `exports` fragment declares a tool that accepts and returns text:

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
    "result_schema": {
      "type": "object", "additionalProperties": false,
      "properties": {"text": {"type": "string"}}, "required": ["text"]
    }
  }],
  "commands": [],
  "services": []
}
```

This fragment is not a complete artifact. Each group allows at most eight
descriptors. Local IDs are unique lowercase ASCII identifiers up to 32
characters. Descriptions allow 1,024 UTF8 bytes. Both schemas use the checked
[object-schema subset](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/mcp.md#schema-subset). External schema references cannot
load code or fetch documents.

`Catalog` creates exact names such as `ext__memory__remember`. It rejects
ambiguous names, cross-instance collisions, builtin or MCP shadowing, names above
64 bytes, more than 32 total exports, and a catalog above 16 KiB. Tools and
services have separate namespaces. Event jobs use their own admission path.

The activation identity pins the normalized catalog, SDK version, and any logical
state bindings. Executable `describe/0` must match those declarations. That
handshake runs after startup authorization, so it cannot certify arbitrary code
before execution.

## Return a value through the SDK

The host supplies the declared `invoke.*` stage with this closed payload:

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

The host generates the real IDs. The complete payload fits the SDK's 16-KiB
object limit. It contains no Session PID, credentials, transcript, workspace
instructions, provider configuration, or native continuation.

An ordinary callback returns a bounded reply and private worker state:

```elixir
{:ok,
 %{"api_version" => 1, "kind" => "result", "value" => %{"text" => "example"}},
 state}
```

The host checks `value` against the declared result schema. Action-looking keys
inside `value` remain data. Request an effect through the separate
[host-call protocol](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-state.md#read-a-revision-and-propose-a-write).

For a tool or command that needs complete larger results, declare SDK version 2
and capability `invoke.result.pages` in the manifest and matching description.
Keep the ordinary invocation capability too. Use the SDK helper at completion:

```elixir
alias Ipse.Extension.ResultPublication

value = %{"items" => Enum.to_list(1..256)}
{:ok, delivery} = ResultPublication.prepare(value)
```

Run this example in `iex -S mix`. Return `{:ok, delivery, state}` from your callback.
The 256-member array exceeds the
ordinary SDK collection bound, so `delivery` is a private
`ResultPublication.Output` value. A small value instead produces the ordinary
`kind: "result"` reply when its whole wrapper fits 12,000 encoded bytes and all
SDK bounds. The helper returns
`{:error, :invalid_result_document}` for an invalid or over-cap document. Handle
that error with the extension's declared bounded refusal response. Do not drop
items to make a successful response fit.

The SDK helper creates the private Output value. Bootstrap recognizes it,
freezes the encoded bytes, discards domain callback state, and enters a terminal
transport phase. Bootstrap intercepts `result.output`; it does not call domain
code for fragments. Worker independently enforces the grant and transition.
Later domain callbacks, effects, questions, and another offer refuse.

Paged publication is available only to an original top-level `invoke.tool` or
`invoke.command`. Services, event jobs, transforms, and recovered question
continuations retain inline results. Ordinary host-action continuations inside
the original invocation retain that invocation's eligibility. SDK-1 artifacts
keep their existing contracts. Protocol framing and `api_version` remain 1.

## Follow ownership through publication

Read these modules in execution order:

| Owner | Responsibility |
| --- | --- |
| `Catalog` and `Invocation` | Resolve the export, validate arguments, and bind identity and approval to the invocation intent |
| `Session` | Admit the owned job, sync its intent, enforce the current lease, reserve capacity, and authorize reads |
| `Host` | Initialize and call the worker, perform admitted host actions, drain frozen output, validate the document, and confirm worker close |
| `ResultSource` | Check pure source transitions, identities, fragment commitments, quotas, and final source closure |
| `Journal.Writer` | Admit owner-only reservations and durably append within those reservations |
| `ResultReader` and `ResultView` | Materialize exact committed bytes and expose bounded structured views outside Session's GenServer |

Model tools require ordinary full-argument approval unless the operator explicitly
enables session-wide execution. Only literal boolean `true` approves. Headless
and child policies still apply. Provider tool-call IDs are opaque UTF8 values of
1–256 bytes, unique within the response. They differ from export names and
internal invocation IDs.

Session syncs `extension_invocation_intent` before opening a worker. Host
reverifies the artifact and initializes it. Each initialization or callback keeps
its five-second bound. Slow execution stays outside Session's GenServer; Session
checks the caller PID and current job reference before accepting durable work.

An eligible SDK-2 invocation also has a 120,000-ms aggregate deadline. Session
starts that clock at original admission, before initialization. Computation,
approval, actions, draining, validation, appends, cleanup, and final publication
share the same clock. Each callback gets at most its ordinary deadline and the
remaining aggregate time. Offering output or reading another fragment never
resets the clock. An SDK-2 invocation can therefore expire while waiting for an
operator's approval.

For saved output, Session reserves journal capacity before source begin. Host
then submits begin, fragment, and seal requests through Session. Host never gets
a writer handle or chooses a journal path. Session checks the lease before each
append. Host validates the full bytes and declared schema, seals the source,
and confirms ordinary worker cleanup. Session can then sync the version-2 final
invocation result. That final receipt alone publishes the saved descriptor.

The elapsed checks guard admission to each boundary. They do not promise that a
filesystem sync finishes before a realtime deadline. A durably committed final
receipt remains committed after a later timer fires.

## Follow current facts through the owner

`Ipse.Extensions.Invocation` validates the durable invocation protocol.
`Ipse.Session.Invocation`, aliased as `CurrentInvocation` in Session, holds only
the current parent/request, action, step, bound effect sources, results and
interrupted-outcome flag. It is a value inside Session, not another process or
an admission authority. Session installs proposed facts only after the required
intent or result append succeeds.

Read these transitions in `lib/ipse/session.ex` alongside the value definition
in `lib/ipse/session/invocation.ex`:

| Transition | Current facts | Session's retained responsibility |
| --- | --- | --- |
| Operator export request | Exact stage, name and arguments | Own the worker and fence its messages |
| Parent admission | Fresh parent and empty action history | Validate identity/catalog and sync intent before installing it |
| Approval needed | Proposed action; step not yet consumed | Keep the reply caller, approval reference and return phase |
| Approval or denial | Recorded action and incremented step | Sync the decision before replying; denial dispatches no effect |
| Effect/usage source | Source bound to the current operation | Validate and commit the source before exposing it |
| Action result | Append result, clear action, mark an unknown outcome interrupted | Commit usage/context changes and refuse further effects or publication after unknown outcomes |
| Question suspension/resume | Parent, action step, prior results and sources | Own the question/wait; require an explicit answer before continuation |
| Output publication | Retain the parent and complete action results | Own the output index, reservation token and deadline; final receipt publishes the value |
| Completion/cancel/timeout | Clear current facts when returning idle | Release publication capacity, stop owned work and retain unknown-effect evidence |

Publication resources and pending action facts are separate dimensions. Do not
add a second lifecycle enum to the value or assume that one boolean summarizes
all owner states. Session's existing phase and resource checks remain the
authority. Recovered extension questions construct current facts from validated
records; they never reconstruct an approval caller, timer or reservation token.

For a worked change exercise, follow the approval, unknown-result, question-resume
and output-deadline cases in `test/extensions_invocation_test.exs` and
`test/extensions_result_session_test.exs`. Trace each append before its state
update. A change to the value should preserve these refusal and cleanup paths,
not merely the successful callback result.

## Keep wire bounds separate from document bounds

Saved output does not enlarge ordinary callback objects or model messages:

| Resource | Bound |
| --- | --- |
| Encoded SDK object | 16,384 bytes |
| SDK string, depth, collection | 8,192 bytes, 12 levels, 128 members |
| Worker frame and lifetime traffic | 32,768 bytes and 64 MiB |
| Encoded output fragment reply | 12,000 bytes |
| Raw fragment and maximum fragment count | 4,096 bytes and 1,024 fragments |
| Complete document | 4 MiB received and canonical encoded JSON |
| Aggregate string, depth, collection | 8,192 bytes, 12 levels, 4,096 members |
| Aggregate nodes, including keys | 262,144 |
| Begun source attempts per Session | 64, including interrupted attempts |
| Encoded source records per Session | 64 MiB, including unreadable prefixes |

The [aggregate adapter](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-artifacts.md#independent-worker-sdk) checks a
map root, duplicate decoded keys, lexical resource bounds, finite numbers, and
the declared result schema. It does not weaken `Ipse.Extension.validate/1`.
Operator journal byte, event, and record limits can refuse publication earlier.
A legal combination of large claims and provenance can still exceed 4 MiB.
Return an explicit capacity refusal rather than an incomplete success.

Writer reservations cover begin, every fixed-stride fragment, seal, final result,
and the ordinary quota-marker headroom. Other appends cannot consume reserved
capacity. Cancellation releases unused reservation before its control outcome.
Already written bytes remain charged. A reservation cannot guarantee successful
IO and does not authorize replay after restart. Read
[persistence training](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/persistence.md) before changing reservation or lock logic.

## Read a delivery without repeating execution

An inline delivery already contains its domain `value`. A saved delivery is this
small descriptor instead:

```json
{
  "version": 1,
  "kind": "saved.result",
  "output_id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "byte_count": 16911,
  "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "historical_receipt": true
}
```

The IDs illustrate the shape. Real hashes bind the exact source. The version-2
`extension_invocation_result` retains the original intent and ordered action-chain
commitments. Its display text encodes the descriptor, not the domain value.
Never validate that descriptor against the domain schema or treat it as the
complete domain answer.

An embedded caller materializes a committed saved delivery through its Session:

```elixir
{:ok, %{bytes: bytes, value: value, provenance: "historical_receipt"}} =
  Ipse.Session.materialize_result(session, delivery)
```

Materialization verifies the complete byte count, digest, aggregate limits, and
original result schema before returning a usable value. A failed read returns
an error, not a partial document. It starts no worker, model request, or query.
The local CLI's complete-reader procedure is in the
[operator manual](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/extensions.md#read-a-saved-result).

For structured inspection, call `Session.read_saved_result/2` with `output_id`
and a `path` of object keys or array indices. Submit a returned cursor under the
single `cursor` key to continue. Views enumerate at most 16 children or 1,024 raw
UTF8 bytes. Each complete view fits 12,000 encoded bytes and every SDK bound.
Large children and key names carry explicit references. Cursors use ordinal
paths, so an 8-KiB escaped key remains reachable without repeating it in a
request. `complete` describes the requested target, not all referenced subtrees.

Session authorizes every read against committed source identity. A cursor grants
no authority. Model `saved_result_read` can inspect only a saved result disclosed
through a tool in that Session. An operator's `/ext` command result stays outside
the model conversation. Its output ID does not let the model read it. Child
Sessions and unrelated extensions gain no access through `host.results`, history,
or service routing.

These reads return historical receipts. Forgetting, expiring, or replacing source
records controls future retrieval; it does not erase earlier output bytes.
Reads do not assert current eligibility, truth, or freshness. Do not feed hidden
source records into model history automatically.

## Recover committed results and inspect interrupted work

`Invocation` validates closed records, exact identities, argument digests,
approval, parent call provenance, tool receipts, and ordered host actions.
`ResultSource.restore/1` also checks every source record before allowed tail
repair. It derives quota charges and the committed read index without executing
extension code.

A valid interrupted prefix can contain begin and fragments without a seal. It
can even contain every declared byte of invalid JSON or a schema-invalid value.
That prefix remains unreadable diagnostic evidence. A seal requires a complete
valid document. A missing, foreign, corrupted, or mismatched source behind a
sealed or final result refuses recovery before repair. A seal without a final
receipt remains an unreadable orphan.

A committed tool receipt restores its exact tool message if interruption
prevented the redundant message append. An existing message is added once.
Commands and services restore their last display separately from the assistant
answer. Idle resume starts no callbacks. Unknown intents, effects, and unfinished
publications never replay automatically. Inspect their saved evidence before
starting new work.

A Session has one serialized invocation lane and at most 10,000 invocations.
Intent records allow 64 KiB and final result records allow 128 KiB. The larger
journal record bound accommodates separately bounded schemas and rendered text;
it does not enlarge SDK messages.

## Practice a change at the correct owner

Trace the lab's `stats` command from `examples/extension-lab/spec.exs` into
`src/memory.ex`. Follow its state-read action to the final typed value. Then find
the assertion in `proof.exs` that checks no inference and no tombstone mutation.
A similar command needs an extension descriptor, callback, and behavior checks.
It needs no command-specific CLI branch.

For a saved-result change, follow `test/extensions_result_publication_test.exs`
through preparation and terminal transport. Next read the source closure and
structured-view tests. Run the focused checks for the owner you change:

```sh
mix test test/extensions_catalog_test.exs test/extensions_invocation_test.exs
mix test test/extensions_result_document_test.exs test/extensions_result_publication_test.exs
mix test test/extensions_result_source_test.exs test/extensions_result_view_test.exs
mix test test/extensions_result_session_test.exs
```

Keep interruption, identity, cleanup, quota, and disclosure cases when extending
this path. Use [installed compatibility training](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/testing.md#learn-a-complete-workflow-through-the-compatibility-lab) for the
separate packaged-worker checks. Passing a pure source test does not verify
Session publication or native cleanup.

Run the [saved-result example](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/examples/saved-results/README.md) to publish
exactly 4 MiB through an independently built artifact, then recover the same
historical bytes. Its source and installed-runtime verifiers check one callback,
1,024 fragments, unchanged journals on resume, and no model requests.
