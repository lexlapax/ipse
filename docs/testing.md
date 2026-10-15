# Verification and local handoff

## Checks that require no account

```sh
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
IPSE_HOME=$(mktemp -d) ./bin/ipse demo
```

Use focused tests during changes, then run the suite for a runtime handoff.
The suite exercises real filesystem and process behavior, local HTTP streaming,
OAuth validation with generated test keys, refresh serialization, skills,
journal recovery, approvals, and cancellation. HTTP fixtures bind to loopback;
Mix can also need local sockets. Initial dependency fetching needs network.
No real API keys or subscription are required. Auth transport injection is
compiled only for the test environment.

The demo is deterministic and does not call a model. It checks that the CLI,
session loop, skill loading, file tools, and native command helper work together.
Use its printed ID with `./bin/ipse chat --resume SESSION_ID` under the
same `IPSE_HOME`; `/session` should show the session without replaying tools.

## Release check

```sh
./scripts/package.sh
```

Extract the printed archive into an empty directory. Run `./ipse --help`
and `IPSE_HOME=$(mktemp -d) ./ipse demo` there. Do not rely on a source
checkout's `priv/` directory or build artifacts. Record OS, architecture, libc,
Elixir/OTP, and Rust versions with results. A release includes ERTS and the
native helper, but needs compatible system libraries.

## Live provider acceptance

These checks are manual and use the account owner's authorization. Use a scratch
workspace and a small prompt. Record success/failure without credentials,
authorization URLs, tokens, private prompts, or full transcripts.

1. ChatGPT: browser login, status, streamed answer, tool-call round trip, resume,
   token refresh after expiry, and logout. Confirm account/model eligibility and
   that no API billing fallback occurs. Expiry/refresh must be tested with the
   live service before claiming the complete subscription lifecycle works.
2. OpenAI API: set the key securely; test streamed text and a tool round trip
   with `--provider openai`. This uses separate API billing.
3. Ollama: start the service and a tool-capable model; test text and a tool round
   trip with `--provider ollama`. Record the model/version and relevant hardware.
4. Anthropic API: test text, tool use, continuation, and a surfaced provider error
   with `--provider anthropic` and a key supplied securely.

## Current evidence and next checks

Initial handoff checks passed on Debian 13 Linux x86_64 (glibc 2.41),
Elixir 1.18.3 / OTP 27, Rust 1.85.1:

- Source build and compilation with warnings as errors.
- Elixir formatting and **49 tests, 0 failures**.
- Source CLI demo and interactive session resume without tool replay.
- Bundled release build; extracted CLI help and demo from a separate directory,
  without the development toolchain's library-path setting.
- No occurrences of the old project spelling in repository source or filenames.

### Arch source check, 2026-10-14

On Arch Linux x86_64, glibc 2.44, Elixir 1.20.4 / OTP 29 (ERTS 17.0.6),
Rust 1.99.0:

- Fixed Elixir 1.20 bitstring-size pin warnings in the native frame parser,
  SSE parser, and SSE fixture helper.
- Source build, formatting check, warnings-as-errors compilation, and all
  **51 tests passed** after the live fixes below. Tests use fixtures, not live
  model services.
- Source demo passed with isolated state under `/tmp`; interactive resume
  restored the idle session without replaying tools.
- The first sandboxed build failed because Mix's TCP lock returned `:eperm`.
  Build and checks passed with the required socket access outside that sandbox.
- Reviewed the implementation against official OpenAI
  [registration](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
  [session lifecycle](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions),
  and [inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
  documentation. This is a source review, not live protocol verification.
- An initial browser callback connection refusal involved a stale callback
  port; a running login listened on a different port. A fresh matching attempt
  reached the listener. The precise cause of the initial stale URL is unknown.
- Fixed the real auth transport's strict `not uri.userinfo` check: normal URLs
  have `nil` userinfo, which raised before HTTP exchange. Public OpenID discovery
  then succeeded with TLS verification enabled. Added a real-transport URL
  credential rejection test; OAuth protocol fixtures still inject transport.
- Fixed the Responses adapter discarding streamed output items when the live
  `response.completed` event contained `output: []`. A regression fixture now
  covers text, tool calls, and opaque continuation retention in this case.

### Live ChatGPT subscription check, 2026-10-14

Verified with the account owner authorizing in Chrome on the same Arch machine:

- Fresh browser authorization, loopback callback, token exchange and signed
  identity validation completed. Status confirmed plan-usage permission; the
  credential file mode was `0600`.
- Explicit `chatgpt` provider with `gpt-6.1-sol` returned streamed text using the
  public Responses API with `store: false` and `stream: true`. No API provider
  or API key was selected.
- In a scratch workspace, individually approved `write`, `edit`, and `shell`
  calls created a small file, changed its contents, and read it through a shell
  command with exit code 0. Full proposed arguments appeared before approval.
- After closing and resuming the live session, the model recalled the file,
  final contents, and command result without tools. Journal tool-start counts
  remained three, confirming no replay.
- Logout returned success (remote revocation confirmed by the auth transport).
  Status then reported no session. Checked that access, refresh, and ID token
  fields were removed while client registration and host ID remained.

Live refresh after expiry remains **unverified**; it was not forced or observed.
Plan-tier eligibility beyond this account, unavailable models, usage limits,
and revoked-session recovery remain unverified against the live service.
Arch release packaging, paid API calls, local Ollama, and macOS also remain
unverified. Successful fixture tests do not establish live-service compatibility.

Priorities and completion criteria are in [plan.md](plan.md). When reporting a
failure, include the command, toolchain, sanitized error, and whether it ran in
a sandbox. Avoid calling permission failures application regressions until
the same command has been checked with the required access.
