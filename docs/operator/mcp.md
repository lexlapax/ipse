# Connect an MCP server

Use MCP to give Ipse selected tools, text resources, or prompts from a service you
choose. MCP is disabled unless you pass `--mcp-config PATH`. Ipse does not discover
MCP files from a project or install server executables. A skill cannot enable a
server or authorize its calls.

Choose a trusted service and review its executable, dependencies, credentials,
remote effects, and exact capability names before starting. Local server startup
and discovery can themselves have effects.

## Configure a local stdio server

Install/review the server separately. Save this complete configuration as a
private file, replacing the executable and allowlisted names with the server's
actual values:

```json
{
  "servers": [{
    "id": "notes",
    "command": "/opt/tools/notes-server",
    "args": ["--stdio"],
    "tools": ["write_note"],
    "resources": ["notes://workspace/README"],
    "prompts": ["summarize_note"],
    "sandbox": "off",
    "env": {},
    "timeout_ms": 30000
  }]
}
```

This is a template for your selected server, not an executable shipped at that
path. Remove capability types you do not need. At least one exact tool name,
resource URI, or prompt name is required; the combined allowlist is at most 16
entries per server. Templates/subscriptions are not enabled by listing a resource.

Launch a real conversation with your chosen model:

```sh
ipse chat --provider chatgpt --mcp-config /private/path/mcp.json --cwd /path/to/workspace
```

The startup manifest shows the server ID, executable, redacted arguments,
capability allowlists, environment variable names, timeout, sandbox selection,
and fingerprint. Inspect it before submitting work. The example uses subscription
requests after task submission, plus your explicitly selected local server.

Ask for a specific permitted operation:

```text
Read the configured notes guide resource. Summarize its instructions with source
references. Do not write a note until I request one.
```

Ipse exposes tool IDs such as `mcp__notes__write_note`. Resources/prompts use stable
digest-based IDs. Discovery supplies descriptions/schemas as untrusted service
data. Every model-requested call, resource read, and prompt retrieval requires
approval. Check the namespaced item, exact URI/name, fingerprint, sandbox, and
full validated arguments, then use its printed `allow CODE` or deny with `n`.

Prompt messages retain user/assistant roles as untrusted data; they do not become
system instructions. Resources expose bounded text. Invalid/non-text
resource/prompt results stop as unknown; ordinary tool results identify omitted
unsupported blocks. Returned content grants no permissions.

## Allow a reviewed extension to use a selected item

An extension can call one explicitly bound MCP item when it declares
`host.actions` and `host.mcp`. Import and review the artifact using the
[extension procedure](extensions.md#import-an-independently-built-artifact).
Its author must supply its options, capabilities, export schema and binding
aliases. Binding an item does not approve its execution.

For the independently built [MCP reader example](../../examples/mcp-actions/README.md),
save this complete operator configuration. Replace `DIGEST` in both places with
the imported artifact's printed digest. The selected MCP server must have ID
`fixture` and an allowlisted `fetch` tool accepting the example's `text` field.
Use the example verifier for a credential-free temporary fixture; this template
does not install or start a document service.

```json
{
  "version": 1,
  "extension_trust": [{
    "artifact": "DIGEST",
    "capabilities": ["invoke.command", "host.actions", "host.mcp", "host.results",
      "host.actions.mixed", "host.state.read", "host.question"],
    "allow_project": false,
    "allow_children": false,
    "mcp_bindings": [{"instance":"reader","alias":"documents","tool":"mcp__fixture__fetch"}]
  }],
  "extensions": [{
    "instance": "reader", "artifact": "DIGEST", "enabled": true,
    "options": {}, "order": 10, "lifetime": "persistent"
  }]
}
```

Launch with both selected configurations:

```sh
ipse chat --provider chatgpt --config /private/path/extensions.json \
  --no-project-config --mcp-config /private/path/mcp.json --cwd /path/to/workspace
```

The explicit command below uses no conversation-model inference. Its MCP service
still has its own execution permissions and possible service costs:

```text
/ext ext__reader__read {"request":{"op":"mcp.call","version":1,"binding":"documents","arguments":{"text":"Public synthetic request"},"timeout_ms":5000},"read":true}
```

Approval displays the extension identity, complete request, alias, descriptor
schema, manifest and redacted server configuration. Check those fields before
allowing the call. Startup/discovery can happen before that decision; denial
prevents call dispatch. Changed descriptors refuse before dispatch. Project
configuration cannot supply bindings. Children cannot use them, even if an
extension otherwise permits child use.

Successful text is saved privately before the command receives its descriptor.
The reader consumes UTF-8 windows of at most 4096 bytes and displays only the
complete byte count and hash. The complete source is bounded to 65536 bytes.
It remains in the journal; a short displayed answer is not a privacy erasure.
`host.results` reads only earlier successful sources in the same invocation.
The encoded source can occupy 256 KiB because JSON escaping adds bytes. A custom
operator `journal.max_record_bytes` below 262144 refuses an extension MCP call
before discovery or approval, even when you expect a short reply. Remove that
override or select a limit that supports the complete contract before starting a
fresh invocation. Total journal byte/event limits still apply during execution.

`host.actions.mixed` is a separate explicit grant for workflows that need many
reads before taking an approved action. It permits up to 512 reads and 16 other
calls, with a two-minute admission deadline. Each operation still needs its own
capability and approval policy. Existing scan grants keep their original limits.
Interrupted work remains unknown and idle resume never dispatches it again.

## Set a local server's permissions

`sandbox: "off"` runs a trusted server with your user permissions, separately
from shell policy. CLI `--sandbox native` does not constrain that MCP process.
For a server that fits the fixed profile, explicitly set its own
`sandbox: "native"`. Unavailable or failed setup refuses without fallback.

Linux native mode permits workspace/private-temp writes and selected system
reads while denying external networking. macOS uses its signed worker and declared
App Sandbox policy. Ordinary process groups are cleaned up, but detached
descendants can survive and retain workspace access. See
[the native contract](../developer/sandbox.md) for the boundary you are selecting.

The helper/supervisor use `PATH=/usr/bin:/bin` and `LANG=C.UTF-8`. The server gets
those defaults plus only configured environment entries. Native mode supplies a
private HOME/TMPDIR. An interpreted launcher may need an explicit reviewed `PATH`
entry for its runtime. Provider credential variable names are refused. Never put
secrets in arguments. Protect private-valued configuration with mode `600`.
Selected known values are redacted from output; this is not a general secret
detector or an OS permission boundary. The macOS native helper transfers the
selected environment through a private pipe prefix and stages no environment
file. This transport does not erase files left by older installations.

## Configure a remote HTTP endpoint

Save a separate configuration using the endpoint and exact tools you intend to
allow. This example URL/name is a placeholder:

```json
{
  "servers": [{
    "id": "remote",
    "transport": "http",
    "url": "https://mcp.example.test/mcp",
    "tools": ["lookup"],
    "bearer_env": "IPSE_MCP_REMOTE_TOKEN",
    "timeout_ms": 30000
  }]
}
```

Supply that server-specific bearer token privately in the launch environment.
Omit `bearer_env` for an unauthenticated service. Missing/invalid selected tokens
fail configuration; HTTP 401/403 fails the request. Token rotation takes effect
after restart. Ipse does not load `.env`, perform OAuth discovery/login/refresh,
or reuse model-provider credentials for MCP.

```sh
ipse chat --provider chatgpt --mcp-config /private/path/remote-mcp.json --cwd /path/to/workspace
```

Verify the manifest's endpoint, exact allowlists, timeout, selected credential
name, and fingerprint. Review each call's full arguments. Local shell/server
sandboxes cannot isolate a remote service or establish that its work stopped.

HTTPS checks system trust and hostnames. There is no insecure HTTPS mode.
Literal loopback test URLs such as `http://127.0.0.1:PORT/mcp` or
`http://[::1]:PORT/mcp` require `allow_insecure_loopback: true`. That exception
does not accept `localhost` or other HTTP hosts. URLs cannot contain userinfo,
queries, or fragments. Redirects are rejected, and calls never retry automatically.

HTTP MCP honors `HTTPS_PROXY`/`HTTP_PROXY`, their lowercase variants, and
`NO_PROXY` using the shared operator proxy policy. Supported proxies use HTTP
URLs, including encoded credentials. Failed/unsupported selected proxies do not
fall back to direct connections. Literal loopback endpoints bypass ambient
proxies.

## Know what the transport supports

The protocol is MCP 2025-11-25 over stdio or bounded Streamable HTTP POST.
HTTP responses can be JSON or finite SSE; long-lived GET streams, reconnection,
subscriptions, and event replay are unsupported. Session DELETE on close is best
effort. Resource templates, OAuth negotiation, sampling, elicitation, MCP tasks,
an Ipse MCP server, and automatic link/embedded-resource fetching are unavailable.
Children do not inherit the parent's MCP servers.

A configuration file is at most 64 KiB and contains up to four servers. Server
IDs use lowercase letters/digits/underscore, beginning with a letter, up to 24
characters. Tool/prompt names have at most 32 supported name characters.
Timeouts range from 1 to 120000 ms. Stdio arguments allow 16 entries, each at most
4096 bytes and 16384 bytes combined. Selected environment allows 16 values of at
most 4096 bytes each. Exact resource URIs are at most 2048 bytes.

Pagination, messages, schemas, arguments, and results are bounded. Supported
schemas use the canonical JSON Schema Draft 2020-12 dialect or no `$schema`,
plus the explicitly checked identical-keyword Draft-07 subset. Scalar/object/
array types and nullable pairs are supported within a narrow keyword subset.
References, arbitrary dialects, combinators, patterns, formats, and remote schema
loading refuse. Defaults are validated data and are never inserted into a call.
If your server needs a larger schema contract, it cannot be fixed by an approval.
See [the MCP reference](../developer/mcp.md).

## Recover after a failed call

Ipse uses short-lived discovery/call connections. Before dispatch it rediscovers
and checks the reviewed schema/description. A changed descriptor prevents the
call; review the change before a new request.

Connection loss, timeout, malformed response, or RPC error after dispatch can
leave an unknown outcome. The remaining batch stops. Inspect affected files or
the remote service before explicitly asking again. Resume never replays the
call. A helper launch refusal before startup is a known error; correct the
executable/workspace/profile before a new attempt.

A helper that started must acknowledge cleanup. Exit zero or a terminal frame
alone is insufficient. An output-read error or a pipe still open after the
500 ms post-exit drain deadline is a transport failure. Detached children can
retain pipes/workspace access. Unconfirmed cleanup stops the session; inspect
running work before resuming.

Resume with the same `--mcp-config` public fields, including allowlists and sandbox.
Changed public configuration refuses resume. Private environment values are
reloaded and excluded from the public fingerprint. In-flight approvals keep
their immutable snapshot. Follow [Recovery](recovery.md) when uncertainty remains.

## Try the bundled credential-free example

From an already-built source checkout with its Elixir toolchain:

```sh
mix run scripts/demo-mcp.exs
```

A scripted model requests a scratch write, a fixed guide resource, and a summary
prompt through `priv/mcp-notes.exs`. The demo approves only its exact synthetic
proposals and checks file bytes and journal outcomes without a model service.
It does not install a general-purpose server. For real research retrieval, follow
[Research](research.md) with your own explicitly chosen service.
