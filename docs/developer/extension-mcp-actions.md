# Build an extension that calls a selected MCP service

Use `mcp.call` when an extension needs a configured external tool, resource or
prompt. Use `effect.result.read` to consume its complete text without enlarging
the worker SDK envelope. The host owns routing, approval and IO. The extension
owns how it interprets the returned evidence.

This exercise needs a built checkout and its Elixir toolchain. It uses synthetic
stdio and loopback HTTP servers, with no account or model service:

```sh
elixir examples/mcp-actions/build.exs --sdk _build/dev/lib/ipse/ebin --output /tmp/ipse-mcp-artifact
mix run examples/mcp-actions/verify.exs /tmp/ipse-mcp-artifact
```

Read `examples/mcp-actions/src/read.ex` beside the proof. It is compiled with only
the public SDK on its code path. Its command requests an external call, retains
the returned descriptor in private state, reads byte windows, then returns a
small byte-count/hash summary. The conversation provider is never invoked.

## Bind an alias before proposing a call

The artifact declares `host.actions` and `host.mcp`. Operator trust supplies a
route for a specific operator-scoped instance:

```json
{"mcp_bindings":[{"instance":"reader","alias":"documents","tool":"mcp__fixture__fetch"}]}
```

This is a fragment of the artifact's trust record. The selected server must also
be present in the explicit MCP configuration. See the [operator procedure](../operator/mcp.md#allow-a-reviewed-extension-to-use-a-selected-item).
Project configuration cannot supply or override the binding. An alias uses a
lowercase letter followed by lowercase letters, digits, underscores or hyphens,
up to 32 characters. Trust permits 64 bindings, unique by instance/alias; an
identity contains at most eight sorted alias/tool pairs.

Propose the call through the ordinary `host_call` reply:

```elixir
{:ok,
 %{"api_version" => 1, "kind" => "host_call", "request" => %{
   "op" => "mcp.call", "version" => 1, "binding" => "documents",
   "arguments" => %{"text" => "Public synthetic request"}, "timeout_ms" => 5000}},
 state}
```

All request fields are required. Arguments must satisfy the selected descriptor's
schema and existing SDK, privacy and approval bounds. The deadline is 1..30000 ms.
Workers supply no executable, endpoint, credential, descriptor or server settings.
Every call requires mutation approval, including resources and read-only tools.
The operation has no state namespace. A child, missing grant, invalid alias or
unconfigured target refuses before discovery. Schema validation needs discovery;
a user may therefore deny after discovery, with zero call dispatch.

## Read the successful source

An `ok` action outcome returns a descriptor, rather than the entire MCP text:

```json
{"version":1,"operation_id":"11111111111111111111111111111111","kind":"mcp.text","source_sha256":"0000000000000000000000000000000000000000000000000000000000000000","byte_count":12000}
```

The IDs and hash illustrate host-issued values. Copy the actual descriptor into
the next request. With `host.results` and `host.actions`, propose:

```json
{"op":"effect.result.read","version":1,"operation_id":"11111111111111111111111111111111","source_sha256":"0000000000000000000000000000000000000000000000000000000000000000","offset":0,"limit":4096}
```

An `ok` window has exactly `version`, `operation_id`, `kind`, `source_sha256`,
`offset`, `next`, `complete` and `text`. Append `text`, then request the returned
`next` byte offset. Stop only when `complete` is true and `next` is null. Windows
contain at most 4096 UTF-8 bytes and never split a codepoint. An interior offset
or a limit too small for the next codepoint returns `result_refused`.

Only an earlier successful call in this invocation is readable. Arbitrary old
journals, another invocation's descriptor and an interrupted source are refused.
The complete source is at most 65536 UTF-8 bytes, with a 256 KiB encoded source
record ceiling, and remains private journal data.
Paging does not erase it, publish context or grant another external action.
Public SDK objects remain 16 KiB; private worker state may contain arbitrary
Elixir terms. A durable question checkpoint is separately limited to 8 KiB.

## Separate long reads from action authority

`host.results` permits result reads through step 512 with a two-minute admission
deadline. Its grant alone does not permit an effect after ordinary step 16.
An artifact that needs reads followed by an approved write, model or MCP call
must explicitly declare `host.actions.mixed` as well as every operation grant.
That contract permits at most 512 reads and 16 other calls, 528 total.

The closed read set is state get/list/scan, history read, usage read/children/
child-read and effect-result read. Questions, context publications, services,
model requests and external calls count against the other-call allowance.
Denials count too. Host, Session and saved-record validation independently derive
counts from the committed action chain. Legacy grants retain their step limits.

## Follow admission, effect and recovery

Trace `Host`'s MCP preparer into Session, then `MCPCall.target/3` and `discover/5`.
Session checks the current owned invocation before discovery. Discovery runs
outside the GenServer. Session pins the private descriptor and displays the
complete public binding and arguments for approval. The existing Client
rediscovers and compares descriptor identity before actual dispatch.

New operations and explicitly mixed invocations use version-two action records
with `effect_binding`. Existing version-one records keep their exact shape.
The public binding identifies the alias, schema, selected manifest and redacted
server configuration. Server fingerprints are recomputed during pure validation;
descriptor hashes bind live rediscovery but cannot be recomputed from a redacted
description. Hashes establish consistency, not publisher authenticity.

Before returning an `ok` descriptor, the owned task asks Session to persist one
`extension_effect_result` for its exact pending approved action. The source binds
parent, operation, identity, request, effect binding and complete data digests.
Session persists it before the action result. `Actions.restore/1` checks that
ordering and recomputes every successful window from the saved source. The
pre-repair recovery path runs this validation before repairing a torn tail.

An unfinished call remains unknown. A saved source without its successful action
result cannot be consumed. Idle resume performs no IO. A pending question can
retain earlier successful sources within the same invocation; only an explicit
answer starts its saved continuation. Cancellation closes owned transports and
local HTTP pools; it cannot undo remote effects. No call is automatically retried.

## Prove the boundary you change

```sh
mix test test/extensions_effect_result_test.exs test/extensions_mcp_call_session_test.exs test/mcp
```

The module cases distinguish a syntactically valid window from one that matches
the source. Session cases exercise actual isolated workers, exact approval,
pre-discovery refusal, descriptor drift, mixed counters, question recovery and
interruption. Keep the strict cleanup assertions. HTTP closure needs a confirmed
local resource receipt after SDK owner death, not just a dead process.

For a worker or runtime change, follow the example's extracted-package verifier
and the [verification manual](testing.md). These fixtures establish transport and
authority behavior. They do not measure retrieval relevance, citation support,
or model quality.
