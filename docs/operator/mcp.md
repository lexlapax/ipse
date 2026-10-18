# MCP servers

Ipse can connect to explicitly configured stdio or Streamable HTTP MCP servers. MCP is
disabled unless you pass `--mcp-config PATH`. Ipse does not discover config in
the workspace or `~/.ipse`, and instructions or skills cannot enable a server.
Discovery does not install executables.

## Configure local stdio and start

Create a JSON file in a location you trust, for example `~/.ipse/mcp.json`.
Select exact capabilities and use the absolute path to an installed executable:

```json
{
  "servers": [
    {
      "id": "notes",
      "command": "/opt/tools/notes-server",
      "args": ["--stdio"],
      "tools": ["write_note"],
      "resources": ["notes://workspace/README"],
      "prompts": ["summarize_note"],
      "sandbox": "off",
      "env": {},
      "timeout_ms": 30000
    }
  ]
}
```

Each server must allowlist at least one exact tool name, resource URI, or prompt
name. The combined allowlist is at most 16 entries per server. Remove capability
types you do not need. MCP resources use exact configured URIs; templates and
subscriptions are not enabled. Prompts use exact names. Provider-facing names
look like `mcp__notes__write_note` for tools; resources and prompts get stable
digest-based IDs such as `mcp__notes__r_<digest>` and `mcp__notes__p_<digest>`.

```sh
./bin/ipse chat --mcp-config "$HOME/.ipse/mcp.json" --cwd /path/to/workspace
```

The startup display shows each server ID, executable, redacted arguments,
enabled tool names, exact resource URIs, prompt names, environment variable
names, timeout, sandbox selection, and configuration fingerprint. Resource
metadata is validated and bound to the descriptor; descriptions and supported
argument schemas are shown to the model as untrusted server data. Review the
configured URIs/names and full approval details before allowing any call.

Every model-requested tool, resource read, or prompt retrieval requires approval.
The approval displays the namespaced item, exact resource URI or prompt name,
server fingerprint and requested sandbox policy, and validated arguments. Prompt
messages retain their `user` or `assistant` role, but their text remains
untrusted data and does not become system/developer instruction. Resources expose
only bounded text; invalid or non-text resource/prompt results stop as unknown.
Ordinary tool results report unsupported blocks as omitted. Neither feature grants
permissions, changes billing, or enables additional tools.

## Server permissions and sandbox

The default `"sandbox": "off"` launches a trusted server with your user
permissions, outside the shell sandbox. Server startup and discovery may have
effects. Use only server executables you trust. Ordinary process-group children
are cleaned up; detached descendants can escape cleanup.

To request the fixed OS sandbox for one MCP server, set `"sandbox": "native"`.
This per-server choice is independent of the CLI `--sandbox` setting for shell
commands. It fails closed if that profile is unavailable or setup fails; there
is no fallback to trusted execution. Linux currently permits workspace and
private temporary writes, selected system reads, and denies external network
access. The macOS profile uses a signed worker and the declared App Sandbox
entitlements; check the current [native verification record](../developer/testing.md)
before relying on platform coverage. Native setup can fail after the Port is
allocated, so successful startup text alone does not establish sandbox
activation. See the [native policy and limits](../developer/sandbox.md).
The macOS profile retains its ordinary process-group cleanup limit: detached
children may survive with workspace access. An abrupt supervisor crash can also
leave owner-only temporary environment data; normal worker execution removes it
before starting the server.

The helper and supervisor receive a fixed `PATH=/usr/bin:/bin` and `LANG=C.UTF-8`.
The final server process receives those values plus only the environment entries
selected in the config. Native mode also gives it a fresh private HOME/TMPDIR.
An interpreted launcher must find its runtime through the selected `PATH`; add
an approved runtime directory explicitly if it is outside `/usr/bin:/bin`.
Provider credential environment names are refused. Do not place secrets in
arguments; protect config files containing private values with mode `600`.
Known selected values are redacted from visible output, but this is not a general
secret detector or an ambient-permission boundary.

## Recovery and limits

Ipse uses a short-lived connection for discovery and each approved call. It
rediscovers and checks the reviewed schema/description before dispatch. A changed
descriptor prevents dispatch. A connection loss, timeout, malformed response,
or RPC error after a request may have been dispatched is recorded as `unknown`;
the remaining batch stops and resume never retries it. Inspect the affected
service or files before explicitly requesting another call. If process cleanup
cannot be confirmed, the session stops with recovery guidance.
If the helper cannot start at all, Ipse returns a launch error and keeps the
Session usable. Correct the configured command, workspace or sandbox availability
before another explicit attempt. A helper that started but failed to acknowledge
shutdown remains an unconfirmed cleanup, even when its server reported exit zero.

The helper also treats an output-read error or a pipe that remains open past
its 500 ms post-exit drain deadline as a transport failure. Stdout alone is not
successful completion. Ordinary group cleanup retries within that deadline;
detached children can still retain pipes and workspace access. Inspect effects
before requesting another call. Developers can use the credential-free
[stdio load diagnostic](../developer/testing.md#stdio-cleanup-load-diagnostic)
to distinguish these failures without connecting to a model or real MCP server.
The cleanup fix passed local Mac load checks and Linux/macOS source/package CI;
see the [verification record](../developer/testing.md#macos-stdio-cleanup-load-2026-10-15)
for evidence and remaining limits. The subsequent
[Serenity return check](../developer/testing.md#linux-return-after-macos-cleanup-2026-10-15)
passed actual Linux enforcement, the concurrent cleanup regression, and fresh
Linux package verification without a live provider or fresh sign-in.

Resume with the same `--mcp-config` file. Public configuration changes—including
allowlists or sandbox mode—refuse resume. Private environment values are not
stored in the fingerprint; each launch loads selected values from the supplied
stdio config or the named HTTP credential environment variable.
An in-flight approval retains its immutable configuration snapshot.

The supported protocol is MCP 2025-11-25 over stdio or bounded Streamable HTTP. Each server supports
at most 16 combined allowlist entries. Pagination, protocol messages, schemas,
arguments, and results are bounded. Tool and prompt schemas allow the canonical
JSON Schema Draft 2020-12 dialect (or no `$schema`) and the explicitly checked
identical-keyword Draft-07 subset, supported scalar/object/
array types, a narrow keyword subset, and nullable type pairs. Defaults are
validated as bounded data but never inserted into calls. References, arbitrary
dialects, combinators, patterns, formats, and remote loading fail closed.

OAuth negotiation, GET streams, resource templates/subscriptions, sampling, elicitation,
MCP tasks, an Ipse MCP server, and automatic fetching of links or embedded
resources are unavailable. Local serial/parallel subagents are a separate opt-in feature;
they do not inherit MCP servers. See [local delegation](subagents.md) and the
[developer contract](../developer/mcp.md).

## Configure a network endpoint

Use a trusted endpoint and its exact capability allowlist. For example:

```json
{
  "servers": [
    {
      "id": "remote",
      "transport": "http",
      "url": "https://mcp.example.test/mcp",
      "tools": ["lookup"],
      "bearer_env": "IPSE_MCP_REMOTE_TOKEN",
      "timeout_ms": 30000
    }
  ]
}
```

Set `IPSE_MCP_REMOTE_TOKEN` privately in the launching environment to the
server-specific bearer token, then pass this file with `--mcp-config`. Ipse does
not automatically load `.env` files. Omit `bearer_env` for an unauthenticated
server. Never put the token in the URL/config or reuse provider credentials.
Missing/invalid credentials fail configuration; HTTP 401/403 fails the request.
Ipse supports static bearer authentication, not OAuth discovery/login/refresh.
A token change takes effect at restart and does not change public resume identity.

HTTPS verifies certificates and hostnames against system trust. There is no
insecure HTTPS mode. A separately selected literal loopback test endpoint can
use `http://127.0.0.1:PORT/mcp` or `http://[::1]:PORT/mcp` with
`"allow_insecure_loopback": true`; this exception does not accept `localhost` or
other HTTP addresses. URLs cannot contain userinfo, queries, or fragments.
Redirects are rejected and requests are never automatically retried.

Network MCP honors `HTTPS_PROXY`/`HTTP_PROXY` (or lowercase variants) and `NO_PROXY`
using the same policy as auth and inference. HTTP proxy URLs may include encoded
credentials. Unsupported proxy schemes refuse; a failed selected proxy never
falls back to a direct connection. Loopback endpoints bypass ambient proxies.

The startup manifest shows the endpoint, allowlists, selected credential variable
name, timeout, exception flag, and fingerprint; token/session values are private.
Calls use the same full approval and intent journal as stdio. The transport is
MCP 2025-11-25 Streamable HTTP POST with JSON or finite SSE responses. Servers
requiring long-lived GET streams, OAuth negotiation, reconnection, subscriptions,
or event replay are unsupported. Session DELETE on close is best effort.

The local shell/server sandbox cannot isolate a remote server or stop its work.
A disconnect after dispatch can leave a completed or continuing remote effect;
Ipse records unknown, stops the batch, and never replays it on resume. Inspect
remote state before requesting another effect. Configure only endpoints you trust
with the selected arguments; MCP content cannot change endpoints or credentials.
See the [transport contract](../developer/mcp.md#streamable-http-boundary) and
[actual verification](../developer/testing.md#p10-streamable-http-mcp-2026-10-15).

## Credential-free source demo

After building the source checkout:

```sh
mix run scripts/demo-mcp.exs
```

A scripted model requests three calls using `priv/mcp-notes.exs`: one scratch
write, the fixed guide resource, and a summary prompt. The host demo prints and
approves only those exact proposals, then verifies file bytes and journaled
results without contacting a model service. The demo requires the Elixir
toolchain. Ipse does not bundle or install arbitrary server runtimes.

P5 fixture, package, and live tool checks are recorded in the
[verification record](../developer/testing.md#p5-local-mcp-2026-10-15). They do
not establish P7 resource/prompt or cross-platform sandbox coverage; consult the
current [P7 record](../developer/testing.md#p7-expanded-local-mcp-2026-10-15)
for those results. See [usage](usage.md) and
[troubleshooting](troubleshooting.md).

## Optional independent memory-server check

For a separately reviewed and built `mcp-memory` executable, developers can run:

```sh
mix run scripts/verify-independent-memory-mcp.exs /path/to/reviewed/mcp-memory
```

This optional source check uses a scripted model, a disposable local graph, and
per-server native enforcement. It denies one write, then approves exact synthetic
create/get/search and missing-record calls, checks journal outcomes, and resumes
idle without replay. It creates no persistent memory service or normal-session
configuration, and never downloads, builds, or installs a server. Supported
Linux native enforcement is required for the recorded check; unavailable setup
fails closed. The independently tested 2.0.0 release needed a documented upstream
build patch. See [exact evidence and limits](../developer/testing.md#second-independent-local-mcp-server-2026-10-15)
and [source/dependencies](../developer/dependencies.md#second-independent-mcp-investigation-memory)
before reproducing it with an executable you have reviewed. This is separate
from the credential-free bundled SDK demo and live provider evidence.

To repeat the independent check over authenticated literal loopback HTTP instead
of native stdio:

```sh
mix run scripts/verify-independent-memory-mcp.exs /path/to/reviewed/mcp-memory --http
```

This starts that reviewed executable as a temporary loopback daemon with a
synthetic server-only token, runs the same approval/recovery checks, then stops
its process group and removes disposable state. It does not claim remote
isolation or install a service. The bundled runtime verifier additionally runs
`priv/mcp-http-demo.exs` using only its extracted OTP runtime and local sockets.
