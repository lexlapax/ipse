# Local MCP tools

Ipse can use explicitly configured local stdio MCP servers. MCP is disabled
unless you pass `--mcp-config PATH`. Repository instructions and skills cannot
enable a server. No executable is downloaded or installed by discovery.

## Configure and start

Create a JSON file outside untrusted workspaces, for example
`~/.ipse/mcp.json`. Replace the command with your installed server's absolute
executable path and choose only the tools you intend to expose:

```json
{
  "servers": [
    {
      "id": "notes",
      "command": "/opt/tools/notes-server",
      "args": ["--stdio"],
      "tools": ["write_note"],
      "env": {},
      "timeout_ms": 30000
    }
  ]
}
```

```sh
./bin/ipse chat --mcp-config "$HOME/.ipse/mcp.json" --cwd /path/to/workspace
```

Ipse displays the resolved server ID, executable, arguments, enabled tool names,
environment variable names, timeout, and configuration fingerprint. Environment
values are hidden. It discovers tools when a task begins, then exposes only the
configured allowlist, using names such as `mcp__notes__write_note`.

**The server runs with your user permissions, outside the shell sandbox.**
Selecting a config authorizes launching those executables for discovery and
calls; startup itself may have effects. Use trusted installed servers. The
working directory is the session workspace, but this is not a filesystem or
network restriction. `--sandbox native` applies to the shell tool, not MCP.
Ordinary process-group children are cleaned up; detached descendants can escape
that group. Do not claim that stopping the transport reverses earlier effects.

Every model-invoked MCP tool requires approval, including tools labeled read-only.
The approval shows the namespaced server/tool and all validated arguments. A
server's annotations never grant permission. Headless runs deny external calls
without the existing explicit `--yes` policy. Tool descriptions, server
instructions, and results are untrusted data; they do not change billing,
permissions, or enabled tools.

Pass credentials only through explicitly selected environment values, never
command arguments. Protect config files containing private values with mode
`600`. The server inherits only a fixed PATH/LANG plus the selected environment;
Ipse's provider credential names are refused. This does not prevent an
unsandboxed server from reading your files. Known configured values are redacted
from results and rejected in model-visible schemas and call arguments; it is
not a general secret detector.

Interpreted server launchers must also find their runtime through that selected
environment. If Erlang or another approved runtime lives outside `/usr/bin:/bin`,
include its installed `bin` directory in the config's explicit `PATH` value.
An absolute launcher path alone does not select the interpreter it invokes.

## Recovery and limits

Ipse uses a short-lived server connection for discovery and for each call. It
rechecks the reviewed descriptor before dispatch. A changed schema or description
prevents dispatch; start a fresh turn to discover the change. Servers requiring
persistent state across calls are outside this first slice.

On cancellation, Ipse closes and waits for the ordinary server process group
before returning. If cleanup cannot be confirmed, the session stops with recovery
guidance. Connection loss, timeout, or invalid results after dispatch mark the
call outcome unknown and stop the remaining batch. Resume never replays it.
Inspect the affected service/files before explicitly requesting a new call.

Resume with the same `--mcp-config` file. Changes to server IDs, executable,
public arguments, enabled tools, environment variable names, or timeout refuse
resume. Private environment values are excluded from the persistent fingerprint,
so credential rotation does not expose a password-verification hash. Each new
process uses the currently supplied values; an approval retains its immutable
configuration snapshot.

Limits: four servers; sixteen enabled tools per server; bounded pagination,
JSON messages, schemas, arguments, and text results. Unsupported schema keywords
fail closed rather than being silently ignored. The initial schema subset
supports objects, required properties, scalar types, arrays, enums, lengths and
numeric bounds. References, combinators, patterns, formats, and remote schema
loading are disabled. See the [developer contract](../developer/mcp.md).

Only MCP **2025-11-25** over local stdio is supported. Network transports,
MCP resources/prompts, sampling, elicitation, tasks, server mode in Ipse,
subagents, and remote execution remain unavailable. Non-text result blocks are
reported as omitted; links and embedded resources are never fetched automatically.

## Credential-free source demo

After the normal source build:

```sh
mix run scripts/demo-mcp.exs
```

This uses the existing MCP SDK as both client and example server, with a scripted
model. It prints and approves only one exact scratch call, writes `mcp-note.txt`,
and verifies the result. It uses a new temporary workspace and home, and contacts
no model service. The example server is `priv/mcp-notes.exs`. This source demo
requires the Elixir toolchain; arbitrary third-party server runtimes are not
bundled or installed by Ipse.

A separate live ChatGPT subscription check passed one individually approved
scratch write through this SDK example server, streamed completion, and resume
without replay on Arch. This does not establish compatibility with arbitrary
servers or other live providers; see the
[live evidence](../developer/testing.md#live-chatgpt-mcp-follow-up).

See [usage](usage.md), [troubleshooting](troubleshooting.md), and
[actual verification](../developer/testing.md#p5-local-mcp-2026-10-15).
