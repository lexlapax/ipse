# Troubleshooting Ipse

See [setup](arch-linux.md) for prerequisites, [usage](usage.md) for operation,
and [verification results](../developer/testing.md) for known limits. Source
commands run from the repository root; replace `./bin/ipse` with `./ipse` in a
bundled release.

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

The context ceiling stops work instead of silently dropping history. Automatic
compaction is not implemented; review the saved session and start a new session
with the necessary context supplied explicitly.

## Sharing diagnostics

Report the command, toolchain, sanitized error, and whether it ran in a sandbox.
Redact credentials, authorization URLs/codes, account identity, and private
transcripts. Never share `~/.ipse/auth/` or environment dumps.
