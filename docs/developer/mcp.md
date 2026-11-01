# Extending the MCP client without bypassing Session

MCP is an external-tool adapter within Ipse's existing turn loop. Session still
owns approval, durable intent, cancellation, and uncertain outcomes. Servers are
explicitly configured; discovery never grants additional capabilities. The
[operator manual](../operator/mcp.md) supplies setup examples.

The client reuses MCP Elixir SDK 1.1.0 for protocol types, request matching, and
client operations, targeting MCP 2025-11-25. JSONSchex validates Ipse's admitted
schema subset. Custom transports provide required ownership, bounded IO, no-retry,
and privacy behavior; Rust handles only local OS facilities. See the
[dependency inventory](dependencies.md) for scope and licenses.

## Trace one approved call

Read these modules in runtime order:

| Module | Work |
| --- | --- |
| `Ipse.MCP.Config` | Load one explicit bounded config and public fingerprint |
| `Ipse.MCP` | Handshake, selected tool/resource/prompt discovery, descriptor binding |
| `Ipse.MCP.StdioTransport` | Owned stdio framing and cleanup |
| `Ipse.MCP.HTTPTransport` | Owned finite Streamable HTTP requests |
| `Ipse.Session` | Review, approval, synced intent, effect/result admission |

Every server selects exact tools, resource URIs, or prompt names, at most 16
combined entries. Missing, duplicated, malformed, or changed allowed descriptors
refuse. Provider IDs combine server identity with selected item identity;
resources/prompts use `mcp__<server>__r_<digest>` and `mcp__<server>__p_<digest>`.
Flattened IDs are collision-checked, including the provider's 64-byte name limit.
Descriptions/schemas and exact selected targets reach model/approval manifests as
untrusted data. Advertised capabilities do not expand the allowlist.

When a model proposal depends on managed knowledge, follow
`Session.ManagedApproval` before the ordinary dispatch below. Session binds the
exact call, arguments, external target manifest and complete dependency union to
its native display/input operation. Current original journals, Identity, policy,
Collection and consuming Session/Writer ownership protect the displayed bytes.
Display settlement releases those owners before the operator answers; execution
then needs fresh current-use admission. Saved capture consent grants no MCP
permission, and a subscriber's `Session.approve/3` call cannot replace this native
review. Keep the [source-owner flow](session-sources.md#reconstruct-without-giving-old-tokens-authority)
and transport effect boundary separate: a valid display does not prove that a
later service start or request was admitted.

Before approved dispatch, a short-lived client rediscovers and compares the
reviewed descriptor digest. Session syncs `tool_started` before a request may
execute. Resources and prompts require external-call approval too. Once dispatch
may have happened, timeout, connection loss, malformed reply, or RPC error yields
unknown and stops the batch; later calls are not started. Resume never replays.
Remote effects are not undone by closing local IO.

`MCP.call/4` distinguishes `{:error, text}` before dispatch from
`{:tool_error, text}` after a server returns `isError: true`. The latter retains
redacted diagnostics and says nothing about rollback. The turn records an error
and warns about possible effects. Extensions retain a bounded `mcp_tool_error`
action outcome. Exercise both transports in
`test/ipse/extension/mcp_call_session_test.exs`; its error fixture writes a marker
before returning the error, then verifies that idle resume does not repeat it.

Shared MCP response admission rechecks tool text after redaction, before returning
either success or tool error. Resource and prompt rendering applies the same
private-value check to the complete published text. A collision returns unknown
with no server text, stopping the batch. This belongs at the shared publication
boundary so ordinary and extension calls cannot diverge.

Extensions use the separate [MCP host-call contract](extension-effects.md#bind-and-call-an-external-mcp-item).
Their action intent replaces the model tool's `tool_started` record; routing,
descriptor rediscovery, transport ownership and unknown-outcome rules are shared.

Preserve uncertainty during discovery itself. `MCP.discover/3` stops its server
reduction on `{:unknown, message}` without downgrading the tag. The extension
adapter `MCPCall.discover/5` returns sanitized `{:unknown, %{}}` for its bounded
unknown result; malformed input still returns a validation error before network
dispatch. Host stops context setup before admitting the requested tool action.
Initialization can already have reached the server, so this is not proof of
remote cancellation. A managed discovery intent without its matching bound
result remains incomplete on reconstruction; idle resume must not reconnect.
The focused `extension_discovery_unknown` case in `test/ipse/mcp/http_test.exs`
interrupts an actual HTTP transport and checks both the returned tag and the
absence of a tool call, alongside validation and healthy-discovery controls.

Follow this in `test/ipse/mcp/session_test.exs`, then read the catalog Session fixture
for a selected resource. Both should reach the same approval/intent boundary.
Resource text and prompt messages remain data, with returned roles preserved;
they never become system instructions. Non-text resource/prompt results refuse.
Ordinary tool results can report omitted unsupported blocks.

New sessions record `mcp_fingerprint_version: 2` in metadata. Config's public
manifest carries `fingerprint_version: 2`; its endpoint fingerprint hashes
`["ipse.mcp.endpoint", 2, public_fields]` with `Ipse.JSON.digest/1`, excluding the
fingerprint and version fields themselves. This sorts object keys and preserves
array order. Tool and catalog descriptors use the same canonical encoder with
separate `ipse.mcp.tool` and `ipse.mcp.catalog` tags. The public-field validator
and loader share Config's fingerprint implementation.

Load-time and resumed version-two hashes use the same cross-server redaction
set. Legacy hashes and public arguments use only the original server's argument
redaction rule, as their writer did. A final check rejects public arguments that
still contain any configured private value. Response redaction still covers every
configured server's secrets. The overlapping-secret controls exercise approval,
dispatch, saved binding validation and idle resume, not just opening a journal.

An absent metadata version means legacy version one; an explicit one is refused
because no writer produces it. Only an explicit integer two selects the new format.
Resume selects that scheme before comparing configuration, discovering descriptors
or writing more records.
Legacy public manifests omit the version field. Their exact deterministic Erlang
term encoding remains unchanged, including its
[within-major-OTP guarantee](https://www.erlang.org/doc/apps/erts/erlang.html#term_to_binary/2).
No journal is migrated or silently rehashed. Unknown versions and metadata/binding
version mismatches refuse; a torn tail is not repaired before that refusal.

Run these controls when changing either format:

```sh
mix test test/ipse/mcp/config_test.exs test/ipse/mcp/session_test.exs \
  test/ipse/mcp/catalog_test.exs test/ipse/mcp/catalog_session_test.exs \
  test/ipse/mcp/http_test.exs \
  test/ipse/extension/effect_result_test.exs \
  test/ipse/extension/mcp_call_session_test.exs
```

The config tests pin both the historical fingerprint and the new canonical bytes.
The Session tests exercise ordinary and extension calls through legacy journals,
both extension transports, idle resume without replay, and refusal of unknown or
mismatched versions. Changing the canonical fields requires another explicit
format version, even if a new hash looks equivalent.

For model-tool approval based on actual stored notes, build the matching native
helper and host, then run the native journey serially:

```sh
mix test test/ipse/session/operator_assertion_integration_test.exs --only managed_mcp_approval:true --max-cases 1
```

The fixture explicitly selects one local stdio server through the normal config
loader and recalls a genuinely captured signed statement. Its positive requires
native approval, separate `mcp.start`/`mcp.send` admissions with confirmed cleanup,
one server call, exact target bytes and the service reply in the next provider
tool-result message. The paired control changes the original source while input
waits; approval must then produce no tool-call admission or service effect.
Both consumers reconstruct strict Saved state and resume idle without another
call. Ordinary discovery may already have started the explicitly selected server;
absence of `tools/call` does not prove zero discovery effects. These automated
Linux/stdio controls do not qualify HTTP, all fault boundaries, human input or
live-model quality. Broader transport controls below retain their separate scope.

Keep root-metadata approval separate from that signed-note journey. The
`native_root_mcp_boundary` selection in
`test/ipse/extension/managed_collection_call_session_test.exs` pairs actual
native approval and allowed calls with revocation between admitted start and send,
for stdio and explicit loopback HTTP. Follow the
[native testing flow](testing.md#exercise-actual-os-policy-and-native-protocols)
to coordinate the existing catalog gate after initial discovery, require the
precise admitted/withheld effects and verify strict idle recovery. A successful
connection is not permission for the later request. The separate
`native_root_prestart` selection checks HTTP refusal without another connection
after native-input revocation/expiry and a successful stdio call that ignores
an unpinned helper override. Preserve the allowed control and actual traffic
observations when changing either admission boundary.

## Schema subset

`Ipse.JSON` bounds schemas to 32 KiB, depth 8, and 256 nodes. The root may omit
`$schema`, use exactly `https://json-schema.org/draft/2020-12/schema`, or use
`http://json-schema.org/draft-07/schema#` only for the explicitly equivalent
admitted keyword subset. This is not full Draft-07 support.

Supported types are object, string, integer, number, boolean, null, and array.
A two-element type array may pair one supported non-null type with null.
Keywords cover `properties`, `required`, boolean `additionalProperties`, `items`,
scalar `enum`, string/array lengths, numeric bounds, and bounded
title/description/default data. Defaults are validated but never filled in.
Refs, regex/format, combinators, remote loaders, and all other keywords refuse
before compilation. Do not expose the validator's broader feature set implicitly.

## Own a local process

Stdio uses newline-delimited JSON-RPC on stdout, with separate bounded stderr.
The native helper adds its private framing underneath; Elixir parses MCP/JSON-RPC.
Servers inherit fixed `PATH=/usr/bin:/bin`, `LANG=C.UTF-8`, and explicitly selected
environment values. The helper starts with only fixed PATH/LANG. Per-server
`sandbox: native` requests the fixed OS profile independently of shell settings;
unsupported setup refuses without a trusted retry.

A bounded private launch frame installs selected values after the OS boundary.
Native processes receive fresh HOME/TMPDIR; loader values do not enter supervisor
startup. On macOS the signed worker consumes exactly the private environment
prefix without overreading subsequent stdin. Credentials are not staged in the
shared writable data root. Initial launch-write flush waits at most five seconds
without blocking owned cancellation. This is transport readiness, not proof of
server or sandbox activation.

Session registers the transport before launch. Both transport and nested SDK task
belong to the turn cleanup scope. Caller monitors stop blocked SDK work on owner
loss. Final cleanup receipts survive transport exit until consumed. Known refusal
before spawn settles the ticket; after spawn a rejected frame still needs helper
closure acknowledgment. Port disappearance or abnormal helper exit cannot certify
cleanup. Ordinary group drain retries fit within 500 ms; detached pipe holders
still fail transport completion. OS limits remain those in [sandbox](sandbox.md).

## Own a finite HTTP exchange

HTTP supports POST with JSON or finite SSE response and optional session ID.
HTTPS keeps peer/hostname verification and system CA trust. Explicit insecure
loopback requires literal `127.0.0.1` or `::1`; `localhost` is insufficient.
Userinfo, queries, fragments, controls, and unsupported schemes refuse. Redirects
and retries are disabled. HTTP entries cannot specify local command/env/sandbox.

Optional bearer auth resolves one server-specific environment name at config
load; provider credential names refuse. Values and session IDs remain private;
public endpoint/name/allowlists/timeout bind the fingerprint. Rotation requires
restart with the same public config. Authentication failures discard raw bodies.
OAuth discovery, registration, negotiation, and refresh are unsupported.

`Ipse.HTTP` supplies selected proxy options without origin-header credential
leaks. Loopback bypasses ambient proxies; a chosen proxy failure does not fall
back to direct egress. Ordinary requests use a private one-connection HTTP/1
Finch pool owned by an `Ipse.HTTP` guardian. Managed POST requests instead use the
owned `MintTransport` socket path inside a controlled cleanup scope, binding the
exact discovery/start/send request to the Session's current-use admission before
egress. Neither path runs IO inside the transport GenServer. The ordinary
guardian remains through cancellation and pool cleanup; the managed path must
confirm its owned socket boundary. Closure attempts a bounded authenticated
DELETE for an assigned session, without claiming remote work stopped. A missing
cleanup receipt stays unknown even if the socket later appears closed.

The HTTP transport monitors the SDK owner and registers with the task cleanup
scope. It starts without a process link because owner-exit system termination
would interrupt its asynchronous pool closure. Owner loss enters the same
bounded close path as cancellation. `test/ipse/mcp/http_owner_cleanup_test.exs`
checks the actual receipt and normal transport exit after abnormal owner death.

When testing idle resume, capture traffic after the old transport finishes its
cleanup exchange. Closing an active POST socket precedes the separate DELETE
request. In `test/ipse/extension/mcp_call_session_test.exs`, the HTTP fixture assigns
each initialized connection a synthetic session ID. Its DELETE barrier lets you
hold that request, observe POST closure, then release and confirm the exact
session's DELETE before taking the full traffic snapshot. Compare all recorded
traffic after resume. Filtering cleanup requests would hide unexpected activity.

A single deadline covers handshake/catalog/call. Initialization alone may set the
session header; later changes refuse. Requests need matching responses and
notifications use HTTP 202. Only server `ping` is supported. No GET subscription,
reconnection, event resumption, automatic 404 reinitialization, sampling,
elicitation, tasks, resource templates, or server mode is implemented.

## Check a protocol change at its actual boundary

| Resource | Limit |
| --- | --- |
| Explicit regular non-symlink config | 64 KiB |
| Servers / combined selected items per server | 4 / 16 |
| Server ID / remote tool or prompt name | 24 / 32 ASCII characters |
| Resource URI | 2,048 bytes |
| Launch arguments / selected env | 16 args, 16 KiB aggregate; 16 variables, 4,096 bytes each |
| Server lifetime | 1–120,000 ms |
| Stdio native input/output queues | 128 × 8,192 / 32 × 8,192 bytes |
| Stdio line or HTTP body | 256 KiB |
| Aggregate traffic / messages | 1 MiB / 256 |
| Discovery | 8 pages, 64 items/catalog, 128 KiB exposed catalog |
| Resource/prompt content | 64 KiB text, 128 blocks |
| Arguments / pretty approval | 16 KiB / 32 KiB |
| HTTP request / headers / queued POSTs | 32 KiB / 16 KiB / 16 |
| HTTP endpoint / session ID | 4,096 / 1,024 bytes |
| Local close calls | Stdio 2 seconds; HTTP 3 seconds |

```sh
mix test test/ipse/json_test.exs test/ipse/mcp/config_test.exs
mix test test/ipse/mcp/client_test.exs test/ipse/mcp/session_test.exs test/ipse/mcp/http_test.exs
```

Schema tests establish the closed subset. Local server/HTTP fixtures establish
real framing, matching, descriptor drift, cleanup, and unknown-after-dispatch.
Add catalog suites for resource/prompt changes. These tests use local servers;
they do not establish interoperability with every server or live authorization.
