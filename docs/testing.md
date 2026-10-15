# Verification and local handoff

## Checks that require no account

```sh
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
RUNESPELL_HOME=$(mktemp -d) ./bin/runespell demo
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
Use its printed ID with `./bin/runespell chat --resume SESSION_ID` under the
same `RUNESPELL_HOME`; `/session` should show the session without replaying tools.

## Release check

```sh
./scripts/package.sh
```

Extract the printed archive into an empty directory. Run `./runespell --help`
and `RUNESPELL_HOME=$(mktemp -d) ./runespell demo` there. Do not rely on a source
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

Live
subscription login and inference, paid API calls, local Ollama, current Arch
packages, and macOS remain unverified until explicitly recorded. Implemented
adapters and successful fixture tests do not establish live-service compatibility.

Priorities and completion criteria are in [plan.md](plan.md). When reporting a
failure, include the command, toolchain, sanitized error, and whether it ran in
a sandbox. Avoid calling permission failures application regressions until
the same command has been checked with the required access.
