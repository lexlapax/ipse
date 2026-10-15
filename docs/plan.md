# Development plan

Ipse is an MIT-licensed local coding agent. Keep its core in Elixir/OTP,
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

Automatic context compaction is available with a retained original journal.
Full-screen TUI, MCP, subagents, remote execution, and Windows are not implemented.
The optional Linux native shell profile is separate from trusted execution.
Uncompactable context stops with recovery guidance.

## P0: verify the current release path

Live subscription renewal after natural access-token expiry passed on 2026-10-15,
including rotating refresh tokens, subsequent streamed inference, and logout.
The focused P0 lifecycle and host release checks are complete; broader account
eligibility and usage-limit error cases remain open. Arch release packaging and the
installed local Ollama tool round trip passed; see [testing and evidence](developer/testing.md)
for procedures and outstanding checks.

### Local build and demo

Initial Debian Linux validation passed: build, formatting, 49 tests, source demo,
interactive resume, and extracted release demo. On 2026-10-14 the local Arch
source build, formatting, warnings-as-errors compilation, 51 tests, source demo,
and scripted interactive resume passed after fixing Elixir 1.20 bitstring-size
pin warnings. See [verification results](developer/testing.md) for the toolchain and outstanding checks.

Acceptance: on a clean checkout, formatting, warnings-as-errors compilation,
and `mix test` pass; `./scripts/build.sh` works without Node or Python;
`./bin/ipse demo` runs without credentials, creates and reads its fixture,
and executes the sample command. Resuming its session restores history without
replaying tools.

### Live ChatGPT subscription sign-in

Fixture tests do not verify live account use. With an eligible test account,
confirm loopback browser authorization, owner-only token storage, streamed
Responses API inference with storage disabled, status, refresh, and logout.
Record plan eligibility, model access, and usage-limit behavior. Provider
failures must never switch silently to API billing.

On 2026-10-14, live browser sign-in, protected storage, streamed inference with
`gpt-6.1-sol`, individually approved write/edit/shell calls in a scratch workspace,
resume with retained context and no tool replay, and logout passed on Arch.
Fixed a real auth transport nil check and retention of streamed items when the
terminal response has empty output. Requests used the public Responses endpoint
with `store: false`, `stream: true`, and explicit subscription provider selection.
Official authentication and inference documentation was reviewed.

On 2026-10-15, natural-expiry refresh, token rotation, subsequent streamed
inference, and logout passed with the same account registration on Arch.
Broader eligibility/usage-limit error behavior remains unverified; fixture
coverage is separate.

### Arch Linux validation

Use the Arch setup notes on a clean local installation. Acceptance: build from
source and run the demo; confirm timeout cleanup and lock release on process
exit; smoke-test the matching release archive and bundled helper/runtime. Try
one Ollama tool-call round trip when compatible hardware/model is available and
record it as model-dependent.

On 2026-10-14, the Arch archive built and passed help, demo, and bundled helper
timeout/owner-death/lock checks from a fresh extraction with no development
toolchain on `PATH`. Supplied version-matched upstream runtime notices were
verified in the archive. Fixed stale docs/notices surviving repeated packaging.
The installed Ollama-compatible service passed a `qwen3.5:9b` read-tool round
trip without installing or downloading a model. Cross-machine portability and
other hardware/model combinations remain unverified.

## P1: make everyday use clearer

Polish the line-oriented CLI before considering a full-screen interface.
Acceptance: users can distinguish running, waiting for approval, cancelled,
and finished states; `/cancel` returns promptly; tests cover EOF during idle,
work, and approval, plus queued input around cancellation and resume. Recovery
must record unknown outcomes and never rerun started tools.

On 2026-10-15, the CLI state/EOF/cancellation/resume acceptance checks passed
with controlled loopback fixtures, including queued input discarded during
cancellation and a fresh successful turn afterward. The full 61-test suite,
source build, formatting, warnings-as-errors compilation, and demo passed.
These CLI checks are fixture evidence, separate from the live P0 provider checks.

Broaden skill/resource support only for demonstrated repository needs. Keep
resources bounded, explicit, data-only, and provenance-bearing. Tests cover
malformed metadata, precedence, size limits, changed files, and explicit loads.
Executable-looking content stays inert unless a separately approved tool runs
it.

### Runtime identity and extension boundaries

Observed on 2026-10-15: the CLI displayed `chatgpt/gpt-6.1-sol`, but a
natural-language version question produced a claim that the model name was
unavailable. The previous context builder omitted application/provider/model
facts and adapters discarded reported model metadata. Model self-description
is not an authoritative version source.

Implemented on 2026-10-15: `Ipse.RuntimeInfo` builds an allowlisted runtime
description from application/session state for `/info` and every model turn.
Distinguish Ipse's application version, configured provider and requested model,
and any provider-reported model identifier. An alias is not proof of an exact
backend revision; unknown revision stays unknown. Feed these facts into the
host-owned instruction section on every turn and offer a deterministic `/info`
command using the same source. Do not intercept natural-language questions with
keyword matching or rewrite model answers after streaming them. Keep credentials,
authorization headers, account identity, and private configuration out of this
surface. Resume describes the active application version and separates the
saved session's last reported model from current-run responses.

Acceptance: fixture tests cover application version, provider/model overrides,
resume, missing or differing provider-reported identifiers, and secret exclusion;
request fixtures prove the facts reach each adapter. Live natural-language checks
are recorded separately and do not replace deterministic `/info` checks. Operator
docs explain configured versus reported identity and unresolved aliases.
The full 66-test fixture suite and source baseline passed; a live local Ollama
identity response also passed. Live ChatGPT identity and saved reported-model
metadata after resume subsequently passed with explicit subscription selection. See [verification evidence](developer/testing.md).

Research favors code-managed prompt builders with explicit identity/context,
not a plugin framework for this example; see official OpenAI
[prompt engineering](https://developers.openai.com/api/docs/guides/prompt-engineering).
Keep the design provider-neutral and use ordinary Elixir modules.
If concrete independent extensions later justify hooks, first specify typed
input/context, tool-intent/result, and final-output boundaries; ordering, timeouts,
cancellation, failure behavior, provenance, and journal/resume semantics. Validate
side effects at the tool boundary, preserving host approvals. Final-output checks
cannot retract text already streamed: choose and document buffering or a visibly
limited validation contract before enabling them. Never silently alter user
intent, provider, billing, approval policy, or tool arguments. Repository text
must not load executable plugins automatically. The official
[guardrail boundary guidance](https://developers.openai.com/api/docs/guides/agents/guardrails-approvals)
distinguishes input/output validation from checks around individual tools; it is
design evidence, not a proposal to add its SDK or runtime dependencies.

## P2: automatic context compaction

Define preserved intent, decisions, recent exchanges, tool results, approvals,
and provider continuation data before implementation. Save summaries as
journal events and retain the original transcript. Acceptance: deterministic
threshold tests verify useful history survives; resume uses the saved summary
without replaying side effects; compaction is reported to the user; failure to
produce a safe summary stops with recovery guidance.

Implemented on 2026-10-15 with verbatim user intent, host action/approval metadata,
two intact recent user turns, bounded provider-neutral summaries, and durable
validated checkpoints. Original transcripts remain intact. All 78 tests and the
source baseline passed. A live ChatGPT scratch check compacted 29,490 to 3,358
bytes, retained its project name/license, and resumed without recompression or
tool execution. See [design and limits](developer/context-compaction.md) and
[verification evidence](developer/testing.md#p2-context-compaction-2026-10-15).

## P2: define an OS sandbox boundary

Approval does not constrain a command after launch. Design OS-enforced
filesystem, network, process, and resource limits separately from the Rust
process helper. Acceptance: adversarial tests prove denied access is blocked by
the OS, including access to credential files by default. Until then, describe
shell execution as trusted local execution, not a sandbox.

On 2026-10-15, the optional fixed Linux native profile passed actual filesystem,
network, process, environment, and resource-control adversarial checks on Arch.
All 104 tests passed with native enforcement explicitly included; fresh-bundle
enforcement and a live approved ChatGPT coding command also passed. The default
remains trusted local execution; requested native enforcement fails closed.
See [profile and limitations](developer/sandbox.md) and
[actual evidence](developer/testing.md#p2-native-linux-sandbox-2026-10-15).
Native OS backends were selected for portability; macOS App Sandbox probing and
eventual Windows AppContainer/Job Object support are separate from Linux evidence.

## P3: workspace context from any directory

Ipse should run as a coding agent or another action agent from any directory or
subdirectory, using the launch directory as its working context while retaining
Ipse-wide preferences, skills, and state under `~/.ipse` (or `IPSE_HOME`).
The source launcher preserves the launch directory, and `--cwd` chooses
a workspace explicitly. Bounded global, ancestor, workspace, and nested
instruction snapshots are implemented; see the
[context contract](developer/workspace-context.md).

Define workspace boundaries and instruction precedence before extending loading.
Discover applicable ancestor `AGENTS.md` files within the chosen boundary and
apply nested instructions to the files/actions they govern, with nearer scopes
overriding broader project guidance. Separate these from Ipse-wide defaults and
explicit user requests. Load relevant README/context files and explicit resource
references through bounded, provenance-bearing reads, rather than importing every
file recursively. Never load unrelated parent directories or secrets implicitly;
report missing, invalid, or oversized instruction sources clearly. Instructions
and configurations remain separate from permission to execute tools.

Acceptance: source and bundled launchers work from arbitrary directories and
repository subdirectories without using the install/source directory as context.
Tests cover default launch directory and `--cwd`, ancestor/nested precedence,
non-repository workspaces, conflicting global/project guidance, relevant resource
loads, UTF-8/size/symlink boundaries, and deterministic resume after instruction
files change. Show which instruction sources apply and preserve their provenance.
Demonstrate both a coding task and a non-coding file/action task in scratch
workspaces, retaining approvals and unknown-outcome recovery. Any new global
configuration schema must be documented without silently changing provider,
billing, or approval policy.

On 2026-10-15, P3 source and bundled launch-directory checks, bounded instruction
scope/provenance, deterministic resume/refresh, and pending-batch replan fixtures
passed on Arch. All 95 tests and both supported formatter checks passed. Separate
live ChatGPT coding and non-coding file tasks honored nested/saved instructions
with individual approvals. See [actual evidence](developer/testing.md#p3-workspace-context-2026-10-15).
Arbitrary shell target scopes remain explicitly unknown; these path checks are
not an OS sandbox or protection against concurrent hostile filesystem changes.

## P4: packaging and protocols

Make Arch and supported Linux release builds repeatable before broadening
packaging. Acceptance: archives identify OS/architecture/libc, include license
notices, and install/demo from a clean account.

Consider MCP after session, approval, and recovery behavior stabilizes. An MCP
proposal must define schemas, approvals, cancellation, journal events, and
in-flight recovery. Subagents and remote execution need separate trust and
unknown-outcome designs plus focused tests before implementation.

The [protocol proposal](developer/protocol-proposal.md) defines these contracts
and separate implementation gates; MCP, subagents, and remote execution remain
unimplemented. Linux/macOS CI now includes source checks and fresh-home bundled
release verification. The macOS App Sandbox probe signs an isolated helper with
approved built-in `codesign`; its enforcement result must be recorded after the
actual macOS CI run. Fresh-home checks do not substitute for every target OS,
architecture, signing/notarization, or account-eligibility check.
