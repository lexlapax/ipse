# Troubleshooting Ipse

See [setup](arch-linux.md) for prerequisites, [usage](usage.md) for operation,
and [verification results](../developer/testing.md) for known limits. Source
commands run from the repository root; replace `./bin/ipse` with `./ipse` in a
bundled release.

If Rust compilation under `--sandbox native` fails to start a subprocess with
`Operation not permitted`, rebuild an older helper before retrying. The Linux
profile now permits the private Unix sequence-packet channels used by Rust's
subprocess implementation; external sockets remain denied. User-installed
toolchains and caches outside the allowed system/workspace roots still remain
unavailable. See [the native boundary](../developer/sandbox.md).

## macOS native shell policy

Keep the installed application outside the target workspace and use an owner-only
`IPSE_HOME` with mode `0700`. A changed signature, unsafe cache entry, or full
32-generation cache stops the command before execution. The cache is under
`IPSE_HOME/sandbox/macos`; do not remove it while commands or detached children
may still be running. Cancellation cannot guarantee termination of detached
children, which can retain workspace write access. See
[macOS policy and limits](../developer/sandbox.md#macos-production-boundary).

## Build and sockets

- Missing `mix` or `rustc`: check packages and `PATH` against the
  [prerequisites](arch-linux.md#install-the-toolchain).
- Missing or incompatible native helper: run `./scripts/build.sh` on this machine.
- Mix reports `:eperm`, or tests cannot bind sockets: check execution permissions.
  Mix needs loopback TCP for locks; HTTP fixtures also bind loopback. Use the
  tool's permission flow or a local terminal. Do not disable TLS verification
  or weaken tests to bypass sandbox failures.
- Dependency fetch fails: check GitHub access. Jason is pinned in `mix.lock`.

## Browser callback refused

Keep the login terminal open and inspect its error. The listener expires after
five minutes. Start a fresh `./bin/ipse login` and open that attempt's new URL.
Do not reuse old authorization/callback URLs or share authorization codes.

The browser must reach the same `127.0.0.1` listener as the login process. SSH
and containers may need explicit port forwarding. Check that the browser
bypasses its proxy for loopback. If another login holds the credential lock,
finish or interrupt it before starting another attempt.

## Account, model, and provider errors

If HTTP clients are busy, retry after another request finishes. The application
limits simultaneous clients to 64; cancelled requests release their client
resources without stopping another session's request.

Run `./bin/ipse status` locally. For a missing session or failed renewal, run
`./bin/ipse login` and complete fresh authorization. If plan usage was declined,
authorize it through ChatGPT Settings and sign in again.

| Failure | Recovery |
| --- | --- |
| Terminal refresh-token error | Ipse clears unusable tokens and retains the app registration. Run `ipse login`; later requests do not retry the rejected token. |
| Client registration rejected | Verify the saved client configuration; credentials are retained. Repeating requests or changing billing does not repair the registration. |
| Subscription account/workspace not eligible | Stop and check the selected account or workspace policy. Repeating OAuth is not an eligibility fix. |
| Subscription usage limit reached | Pause requests and check ChatGPT Settings → Usage. The error does not establish a reset time or whether an app-specific limit caused it. |
| Temporary routing/usage-check failure | Credentials remain intact. Retry later after reviewing the service/network state. |

If a refresh rotates tokens but removes permission to use your plan, Ipse saves
the replacement token set and refuses inference. `ipse status` reports plan usage
disabled; reauthorize plan usage explicitly. Raw server messages are not printed.
Keep the displayed request ID and error code for diagnosis, without sharing tokens
or private journals. These recovery rules follow the official
[ChatGPT plan guidance](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery).

Choose an available model with `--model`; check your plan and usage limits for
rejected requests. Subscription errors never authorize switching to API billing.
See [provider setup](usage.md#1-chatgpt-subscription).

A usage-limit error can also mean Ipse's plan permission is disabled. Check
ChatGPT Settings > Usage > App limits; do not assume your allowance is exhausted
or infer a reset time from the error code alone.

If identity discovery or key fetching fails after renewal, Ipse retains the
rotated tokens in protected pending storage and retries validation on your next
request. It does not use the unverified identity or resend the consumed refresh
token. If that identity expires before validation succeeds, run `ipse login`.
Logout revokes the newest pending token too. A response lost before durable
storage may require fresh login.

If logout reports unconfirmed remote revocation, local tokens have been cleared.
Disconnect Ipse in ChatGPT Settings to end remote access. Never borrow another
application's credentials or use private inference endpoints.

## Session locks and interrupted work

For a session already open error, close its other Ipse process. Do not delete
lock files; OS locks release when their owners exit. Use the
[resume commands](usage.md#working-with-the-agent).

Interrupted effects may already have happened. Resume marks their outcome
unknown and does not automatically replay them. Inspect affected files before
requesting another mutation.

If automatic compaction cannot fit the pinned user history, recent exchanges,
or a valid summary, work stops and the original journal is retained. Review it
and start a new session with necessary context supplied explicitly.
`--no-compact` disables summary requests; `--context-bytes` adjusts the conservative
byte ceiling. See [compaction behavior](usage.md#context-compaction).
A damaged committed checkpoint stops resume; keep the original journal for
diagnosis rather than deleting checkpoint records blindly.

## MCP failures

MCP is disabled without an explicit `--mcp-config` file. Invalid configuration,
unsupported schema keywords, missing allowlisted tools/resources/prompts,
duplicate names, or the wrong protocol version stop discovery before dispatch.
Check the selected executable, exact URI/name allowlists, and the
[supported subset](mcp.md#recovery-and-limits). Resources and prompts are
untrusted data; they do not authorize a call or become privileged instructions.

A changed descriptor requires rediscovery and fresh approval. A malformed
response or RPC error after a request may have been dispatched is an unknown
outcome; inspect the affected files or service before asking for a new call.
Resume never replays it. If cleanup cannot be confirmed, the session stops.
Resume requires the same public server configuration, including resource/prompt
allowlists and per-server sandbox mode.

Local MCP servers default to trusted user permissions outside the shell sandbox.
Setting that server's `sandbox` to `native` requests its independent fixed OS
profile and fails closed if unavailable; it does not inherit the CLI shell mode.
Provider executable setup errors can occur after a transport Port exists, so
check the call result rather than inferring activation from startup alone. A
successful shutdown does not reverse prior effects. See the
[MCP guide](mcp.md#server-permissions-and-sandbox).

For HTTP MCP, check the explicit endpoint, named bearer variable, system CA trust,
and certificate hostname. Ipse rejects redirects, missing/invalid tokens,
non-loopback plain HTTP, and unfinished/oversized response streams. It does not
perform OAuth login, refresh, or reconnect/replay. Restart to load a rotated token.
Cancelling the local connection cannot confirm that remote work stopped; inspect
remote effects before requesting another call. See
[network setup and limits](mcp.md#configure-a-network-endpoint).

## Bash descriptor paths and sibling repositories

Linux native mode now supports Bash process substitution and standard descriptor
paths through a private PID namespace. If `/dev/fd/63` is unavailable, check that
the installed helper includes the
[descriptor repair](../developer/testing.md#native-bash-and-visibility-repair-2026-10-15).
The initial [live assessment](../developer/testing.md#p11-live-project-assessment-2026-10-15)
records the older failure; do not silently rerun a failed call unsandboxed.

A separate `USER: unbound variable` means a script assumed a host variable that
native mode does not supply. For a reviewed test suite that stubs account/system
operations, an explicit synthetic value can be used, for example
`USER=ipse-fixture tests/run.sh`. This does not apply host changes or import an
account environment. Real operations may need access the selected policy does
not provide; report the limitation instead of expanding permissions.


Native shell calls also see only the selected workspace and allowed system
roots. A documented sibling source checkout may exist on the host while being
invisible to the command. A skipped dependency check is not a verification pass
or proof of host absence. Report that limitation and retain the selected policy;
Ipse never automatically reruns an unsuccessful call outside the sandbox.
See [native policy and current limits](../developer/sandbox.md#observed-bash-and-dependency-visibility-limits).

## Sharing diagnostics

Report the command, toolchain, sanitized error, and whether it ran in a sandbox.
Redact credentials, authorization URLs/codes, account identity, and private
transcripts. Never share `~/.ipse/auth/` or environment dumps.

## Model answers about its own version

The startup banner shows the configured provider and requested model, not a
verified backend revision. Use `/info` in chat for the active Ipse application
version, configured provider, requested model, and last provider-reported model.
This command is local and does not call a model or change billing mode.
The same allowlisted facts enter model context on every turn, but conversational
answers can still be incorrect. Aliases do not prove an exact backend revision.
Before a response, or when the provider omits an identifier, the current-run
reported model is unavailable. Resume labels saved response metadata separately.
See [runtime identity](usage.md#runtime-identity) and the
[design boundaries](../plan.md#runtime-identity-and-extension-boundaries).
