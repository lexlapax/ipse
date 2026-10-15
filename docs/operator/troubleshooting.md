# Troubleshooting Ipse

See [setup](arch-linux.md) for prerequisites, [usage](usage.md) for operation,
and [verification results](../developer/testing.md) for known limits. Source
commands run from the repository root; replace `./bin/ipse` with `./ipse` in a
bundled release.

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

Choose an available model with `--model`; check your plan and usage limits for
rejected requests. Subscription errors never authorize switching to API billing.
See [provider setup](usage.md#1-chatgpt-subscription).

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
