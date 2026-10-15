# Local MCP client contract

The initial client uses explicitly configured local stdio servers and allowlisted
tools. It is an adapter around the existing session, approval, and journal, not
a second agent loop. See [operator setup](../operator/mcp.md),
[protocol proposal](protocol-proposal.md), and [P5](../plan.md#p5-local-mcp-tools).

## Package decision

Evaluate OTP facilities and existing Mix packages before implementing common
protocol machinery. This client reuses the third-party MIT-licensed
[MCP Elixir SDK 1.1.0](https://hex.pm/packages/mcp_elixir_sdk/1.1.0) for handshake,
protocol types, request matching, and client operations. It targets MCP
2025-11-25. [JSONSchex 0.10.0](https://hex.pm/packages/jsonschex/0.10.0) evaluates
Draft 2020-12 schemas after Ipse enforces its keyword and resource policy.
Neither package is represented as an official OpenAI or MCP SDK.

Compared SDK sources and published contracts: ExMCP has broader client/server/ACP
and HTTP dependencies and documented VM-global stdio logging changes; Hermes'
older release did not establish the selected revision; Anubis has a different
LGPL license and broader stack. The selected SDK has a smaller client interface
and replaceable transport. Its advertised optional Req/Plug dependencies are
unconditionally referenced by source and required to compile on Elixir 1.20.
They are included and documented, with patched Req 0.7.5. No HTTP server or MCP
network transport is enabled. See [all dependencies and approvals](dependencies.md).

The SDK's shipped stdio adapter has no demonstrated process-group cleanup,
clean environment, output limits, or bounded backpressure. `Ipse.MCP.Transport`
implements its public behaviour using the existing Rust helper for those OS
facilities. Rust never parses MCP JSON or owns approvals. This is the concrete
reason for custom transport code; protocol and schema evaluation are reused.
No vendor source is copied or patched.

## Module and trust boundaries

- `MCP.Config`: explicit file validation, launch identity, environment policy,
  private-value detection/redaction, and public manifest.
- `MCP.Schema`: JSON keyword/shape/size/depth policy, then JSONSchex compilation
  and validation with no remote loader.
- `MCP.Client`: SDK adapter, bounded discovery, descriptor binding, result policy.
- `MCP.Transport`: strict message admission, byte framing/bounds, and lifecycle.
- `Ipse.MCP`: catalog bounds and session-facing definitions/validation.
- `Ipse.Session`: owns tasks, approvals, tool intent, cancellation, and recovery.
- `Ipse.Runner` and `native/ipse-stdio.rs`: directly executed OS pipes, bounded
  queues, process groups, watchdogs, and confirmed cancellation.

No default config is discovered from a workspace or `~/.ipse`; the CLI must pass
an explicit file. Embedded callers supply validated `mcp_servers` from
`MCP.Config.load/1`. Server executables/args/env are immutable configuration;
model output only selects a namespaced allowlisted tool and JSON arguments.
All external calls use the existing approval policy. Server instructions,
annotations, unknown capabilities, and notifications cannot enable features.
Client sampling/elicitation/roots/task capabilities are not advertised.
Remote tool names keep their original identity at dispatch. Dots become
underscores in provider-facing names; all resulting collisions are rejected,
and the 63-character maximum fits the existing provider function-name limit.

Configuration fingerprints include server ID, executable, redacted public args,
enabled tool names, environment names, and timeout. Private values are excluded,
avoiding an offline guessing oracle in manifests/journals. Environment changes
between processes are explicit through the supplied file; a running approved
call uses its existing snapshot. Fingerprints identify configuration, not
executable code authenticity or a server's honesty.

## Connection and effect lifecycle

Each discovery/call runs in a session-owned task and a short-lived SDK client.
Before launching an OS process, the transport synchronously registers with the
session using the active job reference. Cancelled/stale registrations fail before
launch. Owner death tears down the linked client/transport and closes the helper.
Transport crash status hides buffers and private environment values.

Discovery initializes revision 2025-11-25, negotiates only tools, and follows
bounded pagination. Duplicate names, missing allowlisted tools, unsupported
schemas, changed-list notifications, required MCP tasks, and oversized catalogs
fail closed. Only configured descriptors are exposed. Before each approved call,
a fresh connection rediscovers and compares the reviewed schema/description digest.
Approval remains bound to the exact descriptor, server config, and full arguments.

Session `tool_started` is synced before the worker can send `tools/call`; external
intents include validated arguments, descriptor identity/digest, and approval.
Complete tool results enter the existing tool-result message/outcome format.
Connection loss, timeout, or invalid response after dispatch returns `unknown`:
the session stops the batch, marks remaining calls not started, and never replays
an unknown call during resume. Nominal read-only labels do not alter this rule.
Loss before dispatch may conservatively remain unknown after owner death.

Normal close sends the helper's cancel control and awaits actual exit status.
Only an unsent cancel control can retry under Port backpressure; tool bytes never
retry. A linked Port EXIT alone is not exit-status confirmation. Cleanup failure
stops the session and reports uncertainty. The server is unsandboxed; detached
processes may escape group cleanup on Linux and macOS. An acknowledged group
shutdown does not prove external effects were rolled back.

## Bounds and supported schema subset

| Boundary | Limit |
| --- | --- |
| Explicit config file | 64 KiB, regular non-symlink file |
| Servers / enabled tools | 4 / 16 per server |
| Server ID / remote tool name | 24 / 32 ASCII characters; flattened IDs collision checked |
| Launch args / selected env | 16 args, 16 KiB aggregate; 16 variables, 4096 bytes each |
| Server lifetime | Configured 1–120,000 ms, fixed across handshake and call |
| Native queues | Input 128 × 8192 bytes; output 32 × 8192 bytes |
| Protocol data | 256 KiB per JSON line; 1 MiB aggregate traffic; 256 messages |
| Discovery | 8 pages, 64 discovered tools per server; 128 KiB exposed catalog |
| Schema | 32 KiB, depth 8, 256 nodes |
| Arguments | 16 KiB JSON, depth 12, 8 KiB strings, 128 items/properties |
| Approval display | 32 KiB pretty JSON; oversized calls denied |
| Retained result | 64 KiB UTF-8 text, 128 content blocks |
| Cancellation confirmation | One two-second helper-close deadline |

Schema types are object, string, integer, number, boolean, null, array. Supported
keywords: `properties`, `required`, boolean `additionalProperties`, `items`,
scalar `enum`, `minLength`/`maxLength`, `minItems`/`maxItems`, `minimum`/`maximum`,
and bounded `description`/`title`. Every schema node has an explicit type; array
items must be schemas. Numeric equivalence follows JSON Schema, so `1.0` satisfies
integer type and numeric enum `[1]`. References, regex/format, combinators,
dialects, and other keywords are rejected before compilation. JSONSchex's wider
feature set is not implicitly enabled; no loader is supplied.

Server stderr is drained and discarded; protocol error prose/data is replaced by
fixed errors before reaching SDK logs. Strict JSON-RPC envelope and ID admission
prevents mixed request/response payloads from crashing the SDK with raw data.
Known configured environment values are detected on decoded structures before
JSON escaping and redacted in text results. This cannot identify unknown secrets
or restrict a trusted server's ambient filesystem/network permissions.

## Evidence and remaining scope

See [actual tests and demos](testing.md#p5-local-mcp-2026-10-15). Fixtures exercise
real OS pipes and local servers; they do not prove interoperability with arbitrary
third-party servers or live models. The SDK-to-SDK source demo is credential-free.
Network transports, persistent server sessions, resources/prompts, sampling,
elicitation, tasks, delegation, and Windows stay outside this milestone.
