# MCP client contract

Ipse connects only to explicitly configured stdio or Streamable HTTP MCP servers. Its MCP
client is an adapter around the existing session, approval, and journal, not a
second agent loop. See [operator setup](../operator/mcp.md), the
[protocol proposal](protocol-proposal.md), and [P7](../plan.md#p7-expanded-mcp-capability).

## Package decision

The client reuses the MIT-licensed [MCP Elixir SDK 1.1.0](https://hex.pm/packages/mcp_elixir_sdk/1.1.0)
for protocol types, request matching, and client operations. It targets MCP
2025-11-25. [JSONSchex 0.10.0](https://hex.pm/packages/jsonschex/0.10.0)
validates the supported JSON Schema subset after Ipse applies its own strict
keyword and resource policy. Neither package is an official OpenAI or MCP SDK.
The choice reuses the selected SDK's small client interface and replaceable
transport; broader alternatives added server/HTTP surface or had different
license/revision tradeoffs. Its stdio adapter did not provide the lifecycle and
bounds Ipse requires, so the transport uses the existing Rust OS helper rather
than copying or patching vendor code. Package scope and licenses are listed in
the [dependency inventory](dependencies.md).

## Protocol and implementation

`Ipse.MCP.Config` accepts only an explicitly selected JSON configuration file;
there is no workspace or `~/.ipse` discovery. `MCP.Client` performs bounded
handshake and tool discovery, `Ipse.MCP.Catalog` discovers the configured resource
and prompt metadata, `Ipse.MCP.Transport` owns bounded stdio framing, and
`Ipse.Session` owns approvals, intent journaling, cancellation, and recovery.
Rust owns only OS pipe/process facilities. Elixir owns MCP and JSON-RPC parsing.

The official [2025-11-25 transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
defines stdio as newline-delimited JSON-RPC with protocol output on stdout and
optional diagnostics on stderr. Ipse uses that protocol over local pipes, with
its own bounded native-helper framing beneath it. P10 adds the bounded Streamable
HTTP slice described below. See the official
[resources](https://modelcontextprotocol.io/specification/2025-11-25/server/resources)
and [prompts](https://modelcontextprotocol.io/specification/2025-11-25/server/prompts)
specifications for the protocol surfaces Ipse selectively exposes.

## Configuration and capability policy

Every server entry must select one or more exact tools, resource URIs, or prompt
names. The combined allowlist is limited to 16 entries per server. The server's
advertised capabilities do not expand that selection. Discovery fails closed
if an allowed item is missing, duplicated, malformed, or changes between
review and dispatch. Resources are addressed by their exact configured URI;
prompts by exact configured name. Provider-facing IDs are generated from the
server ID plus item identity: resources/prompts use stable SHA-256-derived
suffixes, and all flattened IDs are collision-checked across the full config.
Resource identifiers fit the provider's 64-byte function-name limit.
The client requests only the tools, resources, or prompts capabilities needed
by that server's nonempty allowlists; an empty capability category is not
implicitly enabled.

Resource metadata (URI, name, title, MIME type, size) and prompt
names/descriptions/argument schemas are validated and bound to descriptor
identity. Descriptions, supported schemas, and the exact configured URI/name
are passed to the model; the public config and approval manifests also identify
those targets.
All of this remains untrusted server data. The resource path exposes only
bounded text content for the configured URI; invalid/non-text resource or prompt
results stop as unknown. Ordinary tool results report unsupported blocks as omitted.
Prompt results are bounded messages whose `user`/`assistant` roles are preserved
as data. Neither resource text nor prompt messages become system/developer
instructions, grant permissions, enable a tool, or change billing. Ipse does
not implement resource templates, subscriptions, sampling, elicitation, MCP
tasks, or server mode. The [official resources spec](https://modelcontextprotocol.io/specification/2025-11-25/server/resources)
describes templates and subscriptions separately; they are not implied by
fixed-URI resource support.

Tools, resource reads, and prompt retrieval all pass through the existing
external-call approval policy. Every call displays the exact server/item and
arguments. A resource's or prompt's read-like semantics do not waive approval.
Headless mutations still require `--yes`; MCP data never supplies that flag.
MCP tool descriptions, server instructions, annotations, resource metadata,
prompt text, and results are untrusted. None can grant permissions or select a
new capability.

Provider-facing tool names remain bounded and collision checked. Tool remote
names allow 1–32 ASCII characters. Resource and prompt IDs are `mcp__<server>__r_<digest>`
and `mcp__<server>__p_<digest>`; their suffixes are derived from the configured
URI/name and do not reveal long identifiers. Configuration fingerprints cover
the exact public allowlists and sandbox mode. Secret environment values are
excluded from fingerprints and manifests and are rejected if they overlap
public identifiers or metadata.

## Schema subset

Tool input and prompt argument schemas are bounded to 32 KiB, depth 8, and 256
nodes. The root may omit `$schema` or use exactly
`https://json-schema.org/draft/2020-12/schema`. The canonical
`http://json-schema.org/draft-07/schema#` identifier is accepted only for the
checked identical-keyword subset, then explicitly adapted for JSONSchex. Other
dialect identifiers and draft-specific keywords remain rejected; see
[research compatibility](research.md#mcp-compatibility-evaluation). Supported types are object, string, integer, number, boolean, null,
and array. A two-element type array is accepted only when it pairs one supported
non-null type with `null`. Supported keywords are `properties`, `required`,
boolean `additionalProperties`, `items`, scalar `enum`, string and array length
bounds, numeric bounds, and bounded title/description/default data. Defaults
are validated as bounded JSON data and are never filled into arguments.
References, regex/format, combinators, remote loading, and every other keyword
are rejected before compilation. JSONSchex's broader feature set is not
implicitly enabled.

## Local process boundary and sandbox

Servers inherit only `PATH=/usr/bin:/bin`, `LANG=C.UTF-8`, and explicitly
selected environment variables. The helper itself receives only the fixed
PATH/LANG. A per-server `sandbox` setting defaults to `off`; `native` requests
the fixed `linux-workspace-v1` or `macos-workspace-v1` profile for that MCP
server process, independently of the shell's `--sandbox` option. Unsupported
profiles and setup failures fail closed with no trusted-mode retry. Native
launch uses a bounded private launch frame, keeps selected loader variables out
of the supervisor's environment, and provides a fresh private HOME/TMPDIR.
On macOS the already sandboxed worker reads and removes an owner-only environment
file in its private run directory before executing the server. Normal cleanup
removes that directory; abrupt supervisor termination can leave private temporary
data behind. The native profile is not
a general per-server permission system: see the
[native policy](sandbox.md) for OS-specific roots and limitations.

For both transports, discovery and each call use a short-lived SDK client. Before launching, the
session registers the transport against the active job reference. Before an
approved dispatch, the client rediscovers the descriptor and checks its
reviewed digest. The synced `tool_started` event precedes a write-capable tool
request. Once a request may have been dispatched, connection loss, timeout,
malformed response, or RPC error yields `unknown`; the session stops the batch,
marks later calls not started, and resume never replays the uncertain call.
Errors before dispatch do not imply the external effect started. A confirmed
ordinary process-group shutdown does not prove effects were rolled back;
detached processes remain an OS-specific limitation.

Both transports also register with the owned turn's cleanup scope. Their final
closure result survives transport exit until the task's receipt is consumed.
A known refusal before the stdio helper starts settles the ticket and returns a
launch error while the Session remains usable. A rejected launch frame after
spawn requires the helper's closure acknowledgment. The SDK connection runs in
a nested scoped task that traps SDK link exits; an explicit caller monitor kills
it on caller loss. The outer owned worker keeps its ordinary link to the scope,
so SDK initialization errors cannot mask scope death during blocked IO.
A stdio supervisor exit outside normal cleanup statuses is unconfirmed even if
its Port has disappeared; disappearance alone cannot turn forced helper death
into a successful Session close. This confirms local helper/pool cleanup only,
not remote effects or detached descendants.

After initial server exit, the helper retries ordinary group cleanup during idle
drain polls within the fixed 500 ms deadline. A pipe retained beyond that limit
still yields an error frame without successful completion. See the
[Mac load investigation](testing.md#macos-stdio-cleanup-load-2026-10-15)
and [repeatable diagnostic](testing.md#stdio-cleanup-load-diagnostic).

## Streamable HTTP boundary

P10 pins MCP 2025-11-25 Streamable HTTP. `Ipse.MCP.HTTPTransport` implements
POST requests with JSON or finite SSE response bodies and optional session IDs.
It reuses the SDK's client/request matching, SSE parser, and Ipse's existing
strict message admission, catalogs, schema validation, descriptor digest,
approvals, and journal contract. It does not implement another agent loop.
The SDK's supplied HTTP adapter performs blocking IO in its GenServer, uses
unbounded/default-retrying requests, logs raw errors, and omits authentication
on session DELETE. Those concrete lifecycle/privacy/bound gaps require this
small replaceable transport; the JSON-RPC and SSE machinery is reused.

Endpoints require HTTPS with Mint's default peer verification, hostname checking,
and system CA trust. There is no TLS-disable option. Plain HTTP requires
`allow_insecure_loopback: true` and literal `127.0.0.1` or `::1`; DNS `localhost`
does not qualify. Userinfo, query strings, fragments, control characters, and
unsupported schemes fail configuration. Redirects and retries are disabled;
credentials never follow a Location header. HTTP entries cannot specify command,
args, env maps, or a local sandbox. The private Finch pool receives proxy connection
options from `Ipse.HTTPProxy`, shared with OTP auth/inference clients. Selected
HTTP(S)_PROXY variables accept HTTP proxy URLs, optional encoded credentials and
NO_PROXY bypasses; unsupported schemes or malformed URLs refuse before connection.
Proxy authorization belongs to CONNECT/forward-proxy headers, not origin headers.
Loopback deliberately bypasses ambient proxies. No fallback to direct egress occurs
when the selected proxy fails. TLS verification remains Mint's default.
The explicitly configured endpoint is trusted by the operator, never chosen
from model text, a repository, or a server response.

Optional bearer authentication resolves one named server-specific environment
variable at config load. Provider credential names are rejected. The environment
name, endpoint, loopback exception, allowlists, and timeout bind the resume
fingerprint; credential values are excluded. Rotating a token requires restarting
with the same public configuration. Bearer values and session IDs are private,
redacted from results/identity and excluded from manifests/journals. Authentication
failures discard raw response bodies and fail closed. This slice does not implement
OAuth discovery/registration/negotiation or token refresh; servers that require
those flows remain unsupported. See the official
[authorization specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).

Every request uses a private Finch HTTP/1 pool with one connection, owned by an
`HTTPProfile` guardian allocated before the request task starts. A task performs
IO outside the transport GenServer;
monitors stop the worker on transport/owner death, and the guardian closes the
pool before releasing its fixed-name lease. The transport retains that exact
guardian lease through cancellation, including before borrower registration.
Abnormal worker exit still waits for its guardian; it cannot confirm cleanup early.
Closing waits for local cleanup and
makes a bounded best-effort authenticated DELETE for an assigned session. DELETE
failure does not establish whether remote work stopped. Cancelling local IO,
a local approval, and OS sandboxing cannot confine or undo remote effects.

A server deadline is fixed across handshake/catalog/call. Request bodies are at
most 32 KiB; responses at most 256 KiB, headers 16 KiB, aggregate traffic 1 MiB,
protocol messages 256, and queued POSTs 16. Endpoint/session ID limits are
4096/1024 bytes. The response stream must terminate within these bounds; all
messages are validated before delivering a successful response. Session headers
are accepted only during initialization and cannot change afterward. Requests
require a matching response; notification acceptance uses HTTP 202. Only the
existing server `ping` request is supported. GET streams, subscriptions,
reconnection, event resumption, automatic 404 reinitialization, and replay are
excluded. Interrupted dispatched calls retain unknown outcomes.

See [P10 evidence](testing.md#p10-streamable-http-mcp-2026-10-15) for fixture,
independent-server, live-provider, bundle, and host verification. No package or
external runtime was added: existing Req/Finch/Mint are listed in the
[dependency inventory](dependencies.md).

## Bounds and evidence

| Boundary | Limit |
| --- | --- |
| Explicit config file | 64 KiB, regular non-symlink file |
| Servers / combined allowlist | 4 / 16 tools, resources, and prompts per server |
| Server ID / tool name | 24 / 32 ASCII characters; all model IDs collision checked |
| Resource URI / prompt name | 2048 bytes / 32 ASCII characters |
| Stdio launch args / selected env | 16 args, 16 KiB aggregate; 16 variables, 4096 bytes each |
| Server lifetime | Configured 1–120,000 ms, fixed across handshake and call |
| Stdio native queues | Input 128 × 8192 bytes; output 32 × 8192 bytes |
| Protocol data | 256 KiB per stdio line/HTTP body; 1 MiB aggregate traffic; 256 messages |
| Discovery | 8 pages, 64 items per catalog; 128 KiB exposed catalog |
| Resource/prompt data | 64 KiB text; 128 content blocks |
| Schema / arguments | 32 KiB schema, depth 8, 256 nodes; 16 KiB JSON arguments |
| Approval display | 32 KiB pretty JSON; oversized calls denied |
| Local cleanup confirmation | Stdio: two-second helper close; HTTP: three-second transport-close call |

The [P5 evidence](testing.md#p5-local-mcp-2026-10-15) records earlier tool-only
fixture, bundle, and live subscription checks. P7 adds resource/prompt catalog
and MCP-native sandbox behavior; do not infer verification of arbitrary server
interoperability, all platforms, or other live providers from P5 evidence.
Consult the current [testing record](testing.md) for P7 checks and remaining
platform gates. The SDK-to-SDK demo is credential-free.
