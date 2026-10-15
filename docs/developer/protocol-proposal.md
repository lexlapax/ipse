# Protocol and delegation proposal

**Status:** design proposal for P4; none of the protocol features below are
implemented. This document covers boundaries and acceptance criteria, not an
authorization to add a dependency or enable tools by default.

Ipse's current session, approval, and journal behavior is the baseline. A
protocol adapter must not create a second permission system or weaken the host's
recovery rules. MCP, delegated agents, and remote execution are separate
capabilities with separate trust reviews; completing one does not authorize
the others. See [architecture](architecture.md) and the [development plan](../plan.md#p4-packaging-and-protocols).

## Goals and scope

Keep the agent loop, tool policy, approvals, ownership, and persistence in
Elixir/OTP. Protocols may describe or transport requests, but they do not own
session state. The initial MCP scope, if approved for implementation, should be
an explicitly configured client for local stdio servers and a small allowlist
of tools. Network transports, server-side MCP, MCP resources/prompts, sampling,
extensions, subagents, and remote command execution stay out of that first
scope unless separately designed and approved.

The MCP specification defines wire messages such as `tools/list`,
`tools/call`, `Tool.inputSchema`, and `CallToolResult`. Ipse should normalize
discovered tools into a versioned internal descriptor and keep wire-specific
fields inside an adapter. The specification's annotations are descriptive
hints; they never establish safety or grant execution permission. See the
official [MCP tools specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
and the current draft's [protocol versioning page](https://modelcontextprotocol.io/specification/draft/basic/versioning).
Pin and document the protocol revision used by an implementation; do not treat
the moving draft as a stable contract.

## Proposed internal descriptor and call envelope

This is a proposed Ipse schema, not an MCP schema:

```text
ToolDescriptor v1 = {
  schema_version: 1,
  tool_id: bounded stable identifier,
  server_id: explicit configured identifier,
  name: bounded identifier,
  description: bounded untrusted text,
  input_schema: bounded JSON Schema subset,
  origin: { transport, configured_endpoint_fingerprint },
  risk: host_assessed classification
}

ToolCall v1 = {
  schema_version: 1,
  call_id: unique within the session,
  server_id: configured identifier,
  tool_id: exact descriptor identifier,
  arguments: JSON object validated against input_schema,
  session_id: owning Ipse session
}
```

Use only a documented JSON Schema subset initially: object properties,
`required`, scalar types, arrays, enums, and explicit size/depth bounds. Reject
unknown schema features and invalid or oversized arguments before dispatch.
Keep descriptor versions independent of MCP protocol versions. Do not accept a
model-supplied endpoint, executable, environment variable, credential, or
schema as configuration. Discovery returns untrusted descriptions and
schemas; it cannot add an executable server, select credentials, or enable a
tool.

## Configuration and trust

Every server must be named and enabled by the user in explicit local
configuration. A configuration entry should state transport, exact launch
command or endpoint, inherited environment policy, working-directory policy,
permitted credentials, enabled tool identifiers, resource limits, and whether
tools are exposed to the model. Defaults are disabled. Show the resolved
configuration and server identity before first use. Avoid shell interpolation;
pass executable and arguments directly. Never inherit all environment values
silently, and never pass Ipse provider credentials unless the user explicitly
configured that exact credential for that server.

For local stdio, treat the child process as running with the user's OS
permissions. Process supervision is not a sandbox. Network access, filesystem
access, and credentials are ambient capabilities unless the OS sandbox
milestone proves otherwise. A remote server additionally receives user data
over the network and needs a separate endpoint/authentication/privacy review;
transport encryption alone does not make it trusted. Do not add remote MCP to
the initial implementation by implication.

Discovery, tool descriptions, annotations, and tool results are untrusted data,
not instructions or permission grants. They cannot change provider, billing,
approval mode, server configuration, or allowed tool set. A server cannot
approve its own effects. Reject name collisions or bind tools to the exact
configured server identity, never to a bare name chosen by model output.

## Approval and effect boundary

Route every call through the existing Ipse tool-intent and approval boundary.
Before an effect, present the server identity, tool name, full validated
arguments, and the local effect classification. Do not truncate arguments in
the approval view; if they exceed a safe display limit, deny and explain how to
reduce the request. Approval is for that one exact call. Any argument, target,
server, or effect change requires a new approval. Headless execution remains
denied unless the existing explicit `--yes` policy applies; protocol discovery
must not create a bypass. Risk annotations from a server may inform display,
but host policy determines approval.

Read-only labels are not proof that a call is harmless: a read can disclose
private data, contact an external service, or cause server-side effects. The
host must classify each exposed call and may require approval for reads as
well as mutations. Initially, use the conservative existing interactive
approval model for every model-invoked external tool; only relax it after a
specific capability and data-flow review.

## Ownership, cancellation, and concurrency

The Ipse session owns each active call and its child task/process. Calls must
run under the session's monitored task supervision and be cancelled when the
session owner dies, `/cancel` completes, or the session is explicitly closed.
Cancellation must terminate the local transport process tree where possible,
close streams, and wait for cleanup before releasing a server slot or reusing
its resources. Bound concurrent calls and per-server queues. No server may
outlive its owning session unless a separately approved application-level
service design establishes ownership and shutdown behavior.

Remote cancellation is best effort. A lost connection or local timeout does
not prove the remote operation stopped. Do not automatically retry a call
that may have produced an effect. Report when cancellation or outcome cannot
be confirmed and retain the unknown outcome in recovery state.

## Journal and recovery contract

Journal host-authored events around each external call, without relying on
protocol logs as the source of truth:

```text
tool_intent: call_id, server_id, tool_id, validated arguments, approval result
tool_result: call_id, bounded result or sanitized error, completion status
```

Record intent durably before dispatch. Record a result only after receiving a
complete outcome. If the process exits, cancellation interrupts the call, or
the connection fails after dispatch but before a conclusive response, resume
must mark the call outcome **unknown**. Never automatically replay an
unknown call, including a nominally read-only call. Calls denied or cancelled
before dispatch are recorded as not started and may be safely distinguished
from in-flight calls. Preserve server/tool identity and approval provenance;
redact secrets from errors and bound journaled result size. Journals are
private user data and may contain prompts, arguments, and tool output.

Any future retry UI must require inspection and a new explicit user decision;
it must create a new call ID and new intent record. The interface must not
claim that “cancelled” means no effect unless the transport can prove the
request was never dispatched.

## Subagents and remote execution

Do not treat MCP as a delegation design. A future subagent proposal must define
whether a child shares or gets a separate session/journal, which context and
credentials it receives, how its tool intentions enter the parent's approval
boundary, how cancellation propagates, how results are bounded and attributed,
and how interrupted child work becomes unknown without replay. Parent death
must stop children or explicitly report that it could not.

Remote execution needs its own endpoint identity, authentication, data
minimization, authorization, transport-loss, cancellation, and outcome
reconciliation contract. Local approval cannot imply remote sandboxing. Do
not claim isolation unless a separately verified remote OS boundary provides
it. Keep remote code execution disabled until threat modeling and adversarial
tests show what the remote host can read, change, and retain.

## Deferred implementation gates

Before implementing an MCP client, require a focused design review and tests
for schema validation/bounds, duplicate or changed discovery, explicit
configuration, credential isolation, full-argument approval, headless denial,
session ownership, cancellation cleanup, concurrent calls, journal ordering,
unknown-outcome resume, secret redaction, and a credential-free demo. Exercise
malformed and adversarial local fixtures; do not need paid credentials. Record
the exact MCP revision and transport behavior. Update the dependency inventory
and obtain any approvals required by repository policy before adding a package.

Subagent and remote-execution implementation each require a separate proposal,
threat review, recovery contract, and focused tests. They remain deferred even
if MCP support is later accepted. Revisit this proposal only after P4 packaging
is repeatable and session, approval, cancellation, and journal recovery
acceptance checks remain green.
