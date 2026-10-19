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
| `Ipse.MCP.Client` | Handshake, selected tool discovery, descriptor binding |
| `Ipse.MCP.Catalog` | Selected resource/prompt metadata |
| `Ipse.MCP.Transport` | Owned stdio framing and cleanup |
| `Ipse.MCP.HTTPTransport` | Owned finite Streamable HTTP requests |
| `Ipse.Session` | Review, approval, synced intent, effect/result admission |

Every server selects exact tools, resource URIs, or prompt names, at most 16
combined entries. Missing, duplicated, malformed, or changed allowed descriptors
refuse. Provider IDs combine server identity with selected item identity;
resources/prompts use `mcp__<server>__r_<digest>` and `mcp__<server>__p_<digest>`.
Flattened IDs are collision-checked, including the provider's 64-byte name limit.
Descriptions/schemas and exact selected targets reach model/approval manifests as
untrusted data. Advertised capabilities do not expand the allowlist.

Before approved dispatch, a short-lived client rediscovers and compares the
reviewed descriptor digest. Session syncs `tool_started` before a request may
execute. Resources and prompts require external-call approval too. Once dispatch
may have happened, timeout, connection loss, malformed reply, or RPC error yields
unknown and stops the batch; later calls are not started. Resume never replays.
Remote effects are not undone by closing local IO.

Follow this in `test/mcp/session_test.exs`, then read the catalog Session fixture
for a selected resource. Both should reach the same approval/intent boundary.
Resource text and prompt messages remain data, with returned roles preserved;
they never become system instructions. Non-text resource/prompt results refuse.
Ordinary tool results can report omitted unsupported blocks.

## Schema subset

`MCP.Schema` bounds schemas to 32 KiB, depth 8, and 256 nodes. The root may omit
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

`Ipse.HTTPProxy` supplies selected proxy options without origin-header credential
leaks. Loopback bypasses ambient proxies; a chosen proxy failure does not fall
back to direct egress. Each request uses a private one-connection HTTP/1 Finch pool
owned by an `HTTPProfile` guardian. IO runs outside the transport GenServer; the
guardian lease remains through cancellation and pool cleanup. Closure attempts a
bounded authenticated DELETE for an assigned session, without claiming remote
work stopped.

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
mix test test/mcp/schema_test.exs test/mcp/config_test.exs
mix test test/mcp/client_test.exs test/mcp/session_test.exs test/mcp/http_test.exs
```

Schema tests establish the closed subset. Local server/HTTP fixtures establish
real framing, matching, descriptor drift, cleanup, and unknown-after-dispatch.
Add catalog suites for resource/prompt changes. These tests use local servers;
they do not establish interoperability with every server or live authorization.
