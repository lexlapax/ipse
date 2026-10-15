# Development plan

Runespell is an MIT-licensed local coding agent. Keep its core in Elixir/OTP,
with Rust limited to OS helpers. There is no JavaScript or Python runtime and
no mandatory workflow framework. Validate changes with focused tests and the
credential-free demo.

## Prototype 0.1: available now

- CLI and supervised OTP sessions; resumable JSONL conversations and demo.
- Streaming ChatGPT/OpenAI, Ollama, and Anthropic adapters.
- Workspace read/write/edit/shell tools; interactive approvals and
  deny-by-default headless mutations.
- Bounded skill instructions with project > user > bundled precedence;
  loading a skill never executes scripts or grants permissions.
- Rust process-group cleanup and advisory locks. These are lifecycle controls,
  not an OS sandbox.
- Cancellation and restart recovery mark interrupted effects unknown rather
  than replaying them.

Automatic compaction, full-screen TUI, MCP, subagents, remote execution,
Windows, and OS sandboxing are not implemented. The context limit stops with
an actionable error instead of silently dropping history.

## P0: verify the current release path

### Local build and demo

Initial Debian Linux validation passed: build, formatting, 49 tests, source demo,
interactive resume, and extracted release demo. Repeat on the local Arch checkout;
see [testing.md](testing.md) for the recorded toolchain and outstanding checks.

Acceptance: on a clean checkout, formatting, warnings-as-errors compilation,
and `mix test` pass; `./scripts/build.sh` works without Node or Python;
`./bin/runespell demo` runs without credentials, creates and reads its fixture,
and executes the sample command. Resuming its session restores history without
replaying tools.

### Live ChatGPT subscription sign-in

Fixture tests do not verify live account use. With an eligible test account,
confirm loopback browser authorization, owner-only token storage, streamed
Responses API inference with storage disabled, status, refresh, and logout.
Record plan eligibility, model access, and usage-limit behavior. Provider
failures must never switch silently to API billing. Until then, live sign-in
and inference remain unverified.

### Arch Linux validation

Use the Arch setup notes on a clean local installation. Acceptance: build from
source and run the demo; confirm timeout cleanup and lock release on process
exit; smoke-test the matching release archive and bundled helper/runtime. Try
one Ollama tool-call round trip when compatible hardware/model is available and
record it as model-dependent.

## P1: make everyday use clearer

Polish the line-oriented CLI before considering a full-screen interface.
Acceptance: users can distinguish running, waiting for approval, cancelled,
and finished states; `/cancel` returns promptly; tests cover EOF during idle,
work, and approval, plus queued input around cancellation and resume. Recovery
must record unknown outcomes and never rerun started tools.

Broaden skill/resource support only for demonstrated repository needs. Keep
resources bounded, explicit, data-only, and provenance-bearing. Tests cover
malformed metadata, precedence, size limits, changed files, and explicit loads.
Executable-looking content stays inert unless a separately approved tool runs
it.

## P2: automatic context compaction

Define preserved intent, decisions, recent exchanges, tool results, approvals,
and provider continuation data before implementation. Save summaries as
journal events and retain the original transcript. Acceptance: deterministic
threshold tests verify useful history survives; resume uses the saved summary
without replaying side effects; compaction is reported to the user; failure to
produce a safe summary stops with recovery guidance.

## P2: define an OS sandbox boundary

Approval does not constrain a command after launch. Design OS-enforced
filesystem, network, process, and resource limits separately from the Rust
process helper. Acceptance: adversarial tests prove denied access is blocked by
the OS, including access to credential files by default. Until then, describe
shell execution as trusted local execution, not a sandbox.

## P3: packaging and protocols

Make Arch and supported Linux release builds repeatable before broadening
packaging. Acceptance: archives identify OS/architecture/libc, include license
notices, and install/demo from a clean account.

Consider MCP after session, approval, and recovery behavior stabilizes. An MCP
proposal must define schemas, approvals, cancellation, journal events, and
in-flight recovery. Subagents and remote execution need separate trust and
unknown-outcome designs plus focused tests before implementation.
