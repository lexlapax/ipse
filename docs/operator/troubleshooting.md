# Troubleshoot Ipse

Start with the failing command and its exact sanitized error. Check whether it
started an effect before retrying. Use the original workspace, configuration,
and state directory while investigating.

The following commands are local and need no model request:

```sh
ipse status
ipse config --no-project-config
ipse sessions --json
ipse diagnose --resume SESSION_ID
```

Replace the ID with one from the listing. Add the original `--config` and
`--state-dir` where applicable. Do not share authentication files, authorization
URLs/codes, environment dumps, or complete private journals.

## The executable or helper does not start

For a source checkout, run from its root and check the required toolchain:

```sh
elixir --version
rustc --version
./scripts/build.sh
./bin/ipse demo
```

The build requires Elixir 1.18+, OTP 27+, Rust 1.85+, a C linker, and dependency
network access. The demo needs no account. For an extracted release, use its
`./ipse` launcher and an archive matching your OS, architecture, and Linux libc.
A bundled release does not need the development toolchain to run.

If Mix reports `:eperm` or fixture sockets cannot bind, check the execution
sandbox. Mix locks and local HTTP fixtures need loopback sockets. Run the check
in an appropriately permitted terminal. Keep TLS verification enabled and retain
test assertions. Dependency fetch failures need access to the sources locked in
`mix.lock`; they do not establish an Ipse runtime defect.

## Browser callback refused

Keep the login terminal open. The callback listener expires after five minutes.
Run `ipse login` again and use the new URL; old authorization/callback URLs cannot
be reused. The browser must reach the login process's `127.0.0.1` listener.
Remote hosts, containers, and proxies may need explicit loopback routing.

A completed refresh/logout/other login can invalidate an older waiting browser
attempt. Start a fresh attempt rather than resubmitting its callback. Browser
waiting does not hold the credential lock; token exchanges and writes do.

Auth, inference, and HTTP MCP share proxy policy. `HTTPS_PROXY` selects the proxy
for HTTPS destinations, but the proxy URL must use supported `http://` syntax.
Encoded proxy credentials are allowed. Unsupported schemes or failed selected
proxies do not fall back to a direct connection. Check `NO_PROXY` and browser
loopback bypass separately. Never disable certificate verification.

## Account, model, and provider errors

Run `ipse status` to inspect local subscription status. For missing or unusable
renewable credentials, run `ipse login` and authorize again.

| Symptom | What to do |
| --- | --- |
| Terminal refresh-token rejection | Sign in again. Ipse clears unusable tokens but retains registration. |
| Registration rejected | Inspect the selected registration/configuration. Repeating inference does not repair it. |
| Account/workspace ineligible | Check account and workspace policy. Repeated OAuth does not change eligibility. |
| Subscription usage limit | Check ChatGPT Settings usage and app limits. The error alone gives no reset time. |
| Plan usage disabled | Authorize Ipse's plan permission, then sign in again. |
| Temporary routing/usage-check error | Review service/network state and explicitly retry later. Credentials remain. |
| Credentials busy | Let another login/refresh/logout finish. Keep lock files intact. |
| Model rejected | Explicitly select an eligible model or profile. Keep billing choice deliberate. |
| HTTP clients busy | Wait for another request to finish. One application permits 64 simultaneous clients. |

Subscription failures never authorize a move to API billing. API keys must be
supplied privately through the matching provider variable. Ipse does not load
`.env` automatically. Provider error displays omit raw prose and retain bounded
status/code/request ID information. Include that sanitized information in a bug
report.

If refreshed credentials await identity validation after a network failure,
Ipse retains them privately and retries validation on a later request. It does
not use an unverified identity or reuse the consumed refresh token. If identity
expires first, sign in again. If logout clears local tokens but cannot confirm
remote revocation, disconnect Ipse in ChatGPT Settings.

A stream/body/output-limit error stops incomplete response admission and starts
none of that response's tools. Previously displayed text or prior effects can
remain. Inspect recorded accounting and effects before a fresh task. There is
no automatic retry or provider change.

## Native shell policy refuses a command

Check `/session` for the selected platform's visibility rules. Native enforcement
is requested separately from approval; `--yes` does not broaden the OS profile.
An unavailable backend fails closed.

On Linux, confirm Landlock ABI 6+ and permitted unprivileged user, mount, network,
and PID namespaces. On both platforms, keep the active application and helper
outside the workspace. Use a prebuilt helper owned by your user, with one link
and no group/other write permission. Do not rebuild it within the writable target
to bypass the overlap refusal.

On macOS, use an installed bundle outside the candidate workspace. Existing
`IPSE_HOME` must have mode `0700`. Invalid signatures, unsafe cache entries, or
a full 32-generation cache under `IPSE_HOME/sandbox/macos` refuse setup. Do not
remove cache data while commands or detached children may use it.

Native commands do not inherit your host environment. A script expecting `USER`
can fail with an unbound-variable error. Use an explicit synthetic value only
for a reviewed fixture that requires one. Home toolchains, caches, sibling source
checkouts, and network package fetching may be outside the allowed policy. A
path lookup failure does not prove the file is absent on the host. Report skipped
checks accurately; do not silently rerun them unsandboxed.

See [shell policy](usage.md#shell-policy) and the
[full native contract](../developer/sandbox.md) before changing an explicit policy.

## Session locks and interrupted work

A session-already-open error means another owner or its cleanup still holds the
lock. Close/cancel that owner normally. The visible process can disappear before
slow storage or tracked work finishes. Never delete a lock file to create another
writer.

For missing results or unconfirmed cleanup, inspect files, external services,
and running processes. Task/VM exit alone is insufficient. Detached children
can survive cancellation. Follow [Recovery](recovery.md) before repeating effects.

## Context, configuration, or journal refusal

For an Ollama answer that ends before producing the required result, compare
input plus output token counts with the loaded model's context window. Reasoning
also consumes output space. A larger output cap alone cannot enlarge that window.
Check the selected server's loaded `context_length` and follow
[context configuration](configuration.md#allow-a-longer-extension-answer).
Preserve the failed result before trying a separately authorized request.

`/diagnostics` distinguishes context bytes from token accounting. Compaction can
retain too much necessary content to fit, especially within one long turn.
`--no-compact` disables both reduction paths. Choose a suitable explicit
`--context-bytes` value or create a reviewed fresh-session handoff. Repeating a
completed effect is not a compaction strategy.

Changed configuration, model destination, extension selection, or runtime pins
can refuse resume. Restore the original configuration/runner or export a
[handoff](recovery.md#continue-in-a-fresh-session). `/context refresh` reloads
instructions/skills only. It cannot make changed configuration compatible.

A sealed journal remains sealed after limits increase. Corrupt committed
checkpoints refuse recovery. Preserve original files; do not remove records to
force a successful load. Oversized legacy files may require developer-assisted
bounded inspection.

## MCP or extension failures

MCP requires explicit `--mcp-config PATH`. Check the exact tool/resource/prompt
allowlists, executable or URL, protocol version, and supported schema subset.
Discovery does not install a server. Descriptor changes prevent dispatch. For
HTTP, check system CA trust and the selected bearer environment variable; token
rotation requires restart. OAuth negotiation, redirects, automatic reconnect,
and replay are unsupported. See [MCP servers](mcp.md).

A server's native sandbox setting is independent of shell `--sandbox`. Remote
MCP cannot be confined or stopped by the local sandbox. A post-dispatch error
can leave an unknown effect even when the connection closed cleanly.

For extensions, inspect the artifact digest, trust ceiling, selected instance,
options, compatibility, and `/ext` catalog. Import alone enables nothing.
Changed code/options/configuration can require a fresh session. State writes,
questions, and model calls retain separate approval semantics. See
[extension recovery](extensions.md#recovery-and-execution-boundaries).

If persistent memory refuses activation with `extension_admission_refused`,
compare `options.scope` with the selected instance's operator `state_bindings`
entry. For example, `scope: "operator"` cannot use a binding limited to
`["project"]`. Select project scope or deliberately review an operator-scope
grant in your private configuration. See the [memory configuration example](memory.md#configure-project-notes).

## Collect a useful bug report

Record the command with secrets removed, Ipse version from `/info` or launcher
output, OS/architecture, provider and requested model, selected sandbox, sanitized
error/request ID, and the smallest reproducible sequence. Distinguish executed,
failed, denied, and skipped actions. Prefer synthetic files over private examples.

For diagnostic sinks, include `/diagnostics` readiness, drops, closure reason,
and cleanup status. A corrupt or incomplete trace catalog requires a fresh
private directory and new session; do not rewrite the old ring. Trace samples
are separate from journals and usage. Stopping capture does not delete either.
See [Diagnostic capture](observability.md).
