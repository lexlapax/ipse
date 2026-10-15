# Local MCP servers

Ipse can connect to explicitly configured local stdio MCP servers. MCP is
disabled unless you pass `--mcp-config PATH`. Ipse does not discover config in
the workspace or `~/.ipse`, and instructions or skills cannot enable a server.
Discovery does not install executables.

## Configure and start

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

Resume with the same `--mcp-config` file. Public configuration changes—including
allowlists or sandbox mode—refuse resume. Private environment values are not
stored in the fingerprint; each new process uses values from the supplied file.
An in-flight approval retains its immutable configuration snapshot.

The supported protocol is MCP 2025-11-25 over local stdio. Each server supports
at most 16 combined allowlist entries. Pagination, protocol messages, schemas,
arguments, and results are bounded. Tool and prompt schemas allow the canonical
JSON Schema Draft 2020-12 dialect (or no `$schema`), supported scalar/object/
array types, a narrow keyword subset, and nullable type pairs. Defaults are
validated as bounded data but never inserted into calls. References, arbitrary
dialects, combinators, patterns, formats, and remote loading fail closed.

Network transports, resource templates/subscriptions, sampling, elicitation,
MCP tasks, an Ipse MCP server, and automatic fetching of links or embedded
resources are unavailable. Local serial subagents are a separate opt-in feature;
they do not inherit MCP servers. See [local delegation](subagents.md) and the
[developer contract](../developer/mcp.md).

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
