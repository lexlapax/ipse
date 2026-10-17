# Development plan

Ipse is an MIT-licensed general-purpose local AI harness, currently focused on
coding/project workflows. Keep its core in Elixir/OTP,
with Rust limited to OS helpers. There is no JavaScript or Python runtime and
no mandatory workflow framework. Validate changes with focused tests and the
credential-free demo.

## Current sequence and provider verification

P0–P7 are complete within their documented scopes. The developer selected
the next feature sequence on 2026-10-15:

| Milestone | Scope | Status |
| --- | --- | --- |
| [P8](#p8-bounded-skill-resources) | Bounded explicit skill resources | Complete within documented scope |
| [P9](#p9-parallel-local-subagents) | Parallel local subagents | Complete within documented scope |
| [P10](#p10-network-mcp) | Explicit network MCP | Complete within documented scope |
| [P11](#p11-live-dotsetup-trial) | Read-only assessment in `~/projects/lexlapax/dotsetup` | Read-only comparison and selected follow-ups complete |
| [P12](#p12-task-tracker-coding-trial) | New forms/SQLite task tracker | Specified-stack coding trial complete |
| [P13](#p13-long-turn-compaction-and-general-purpose-trials) | Long-turn context recovery and neutral coding/non-coding trials | Complete within documented scope |
| [P14](#p14-bounded-deep-research) | Research method, explicit search/retrieval, evidence and validation | Complete within documented scope |
| [P15](#p15-scoped-configuration-and-shared-operator-skills) | Operator/project/directory configuration and shared skills | Complete within documented scope |
| [P16](#p16-explicit-model-profiles-and-task-routing) | Main/subtask model profiles and provider-specific settings | Complete within documented scope |
| [P17](#p17-structured-operator-questions) | Validated operator questions and resumable answers | Complete within documented scope |
| [P18](#p18-supervised-self-development-on-the-operators-mac) | Second supervised trial using the combined harness on macOS | Complete within documented supervised scope; local and hosted checks passed |
| [P19](#p19-long-session-diagnosis-and-recovery) | Diagnose retained-context limits and improve explicit recovery | Complete within documented scope; Linux and hosted Mac checks passed |
| [P20](#p20-repeatable-supervised-self-development) | Reusable supervised development/review skill and evidence | Complete: fixtures, hosted checks and supervised live use; limitations recorded |
| [P21](#p21-larger-self-development-trial-on-serenity) | Larger supervised trial with independent Mac verification | Complete within supervised scope; bounded review and Linux/hosted Mac checks passed |
| [P22](#p22-extension-scaffold-and-lifecycle-hooks) | Typed extension scaffold, lifecycle hooks and runtime observability | Complete: lifecycle audit, independent installed proof, supervised trial and hosted Linux/macOS checks |
| [P23](#p23-usage-cost-reporting-and-budget-controls) | Usage/cost extensions and host budget admission | In progress: explicit rate-card calculator; report/accounting-read and budget integration remain |
| [P24](#p24-voice-and-realtime-media) | Voice extensions and owned realtime/media capabilities | Authorized; follows owned stream/provider foundation |
| [P25](#p25-optional-knowledge-extensions) | Default-off working/long-term memory, research, graph and RAG | Authorized; research gates precede implementation selection |

After P22–P25 are complete, the operator requested changing Ipse's repository
license from MIT to Apache-2.0. This is the final authorized follow-up, not an
early change to the active extension work. Replace the project license and
bundled copies, update current documentation and packaging notices, and verify
artifact identity/package checks. Preserve third-party licenses and historical
provenance. Commit and push the verified license transition separately.

Feature completion does not close every live provider acceptance check. On
2026-10-15, installed Ollama `qwen3.5:9b`, Anthropic `claude-haiku-4-5`, and
OpenAI API `gpt-4.1-mini` passed basic live acceptance, compaction, native local
MCP, HTTP MCP, serial/parallel delegation, and idle resume. Paid API checks used
privately loaded keys from the ignored repository `.env` under explicit developer authorization.
See the authoritative
[provider status and outstanding checks](developer/testing.md#provider-verification-status).

The live checks repaired two compaction-format failures without replacing
history or changing billing/provider selection. Broader model/host eligibility
and negative account cases remain separate from these scoped passes. No model
download or new runtime dependency was required.

## Authorized execution order, 2026-10-16

The developer explicitly authorized completing all five proposed stages, with
continued execution until done and a pause only for required operator action/input.
This supersedes the earlier planning-only status of the selected work. Provider,
billing, credentials and external-effect invariants still apply.

| Order | Work | Status |
| --- | --- | --- |
| 1 | Supervised self-development using stable Ipse to add P15 shared operator skills | Complete; stable trial, independent review and combined checks passed |
| 2 | P17 structured operator questions | Complete; fixture/live and combined checks passed |
| 3 | Remaining P15 scoped configuration | Complete; source, package and hosted checks passed |
| 4 | P16 explicit model profiles/routing | Complete; mixed-provider live trial and combined checks passed |
| 5 | P14 bounded deep research | Complete; configured retrieval, durable ledger, independent live review and combined checks passed |

Update each row and its implementation/evidence record as focused increments pass.
Use independent review, required source/package checks and explicit live evidence;
commit/push completed increments without declaring unverified integrations done.

All five authorized stages are complete within the stated boundaries. Final
[combined evidence](developer/testing.md#five-stage-integrated-verification-2026-10-16)
records 324 native Linux tests, extracted-package checks and hosted Linux/macOS
verification, alongside the independently reviewed live trials. Optional summary
routing, child questions/MCP and unattended self-development remain outside this
completed scope.

## Proposed next sequence after P18

P18 exposed retained-context stops and a review exceeding its bounded child budget.
The proposed order is P19 diagnosis/recovery, P20 a reusable supervised-development
skill, P21 a larger trial, and P22 the extension scaffold. P19–P21 implementation
was subsequently authorized on 2026-10-16. Following the extension/runtime/knowledge
review, the operator authorized implementation of P22–P25 on the same date.
On 2026-10-16 the operator requested extension/debugging research, including
OpenCode, Codex and Pi; that research is recorded under P22. Bring minimal
content-free context/timing diagnostics forward into P19 so recovery work is
measurable; extend the same contracts in P22 rather than waiting for a plugin
system to diagnose a core failure. Services and exporters remain configurable.

## Prototype 0.1: available now


- CLI and supervised OTP sessions; resumable JSONL conversations and demo.
- Streaming ChatGPT/OpenAI, Ollama, and Anthropic adapters.
- Workspace read/write/edit/shell tools; interactive approvals and
  deny-by-default headless mutations.
- Bounded skill instructions with project > Ipse user > shared operator > bundled
  precedence;
  loading a skill never executes scripts or grants permissions.
- Rust process-group cleanup and advisory locks. These are lifecycle controls,
  not an OS sandbox.
- Cancellation and restart recovery mark interrupted effects unknown rather
  than replaying them.

Automatic context compaction is available with a retained original journal.
Explicit stdio/Streamable HTTP MCP tools and opt-in serial/parallel local delegation
are available. Full-screen TUI, remote agents, and Windows are not implemented.
Local parallel groups are explicitly enabled with `--subagent-concurrency 2`.
The optional Linux and macOS native shell profiles are separate from trusted
execution. macOS detached-descendant cleanup is best effort.
Uncompactable context stops with recovery guidance.

## P0: verify the current release path

Live subscription renewal after natural access-token expiry passed on 2026-10-15,
including rotating refresh tokens, subsequent streamed inference, and logout.
P0 is complete for the available Arch host and account, with explicitly bounded
live coverage: a permission-off request returned the usage-limit error, while
allowance exhaustion and ineligible accounts remain unverified. Arch packaging and the
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
The Serenity return check also passed the current documented subscription request
shape, streaming, and approved scratch write/shell execution. A temporarily
disabled Ipse plan permission returned `subscription_sharing_usage_limit_exceeded`;
the permission was restored, with credits still disabled. This verifies the live
error code, not exhausted allowance. No ineligible account was available.
Terminal renewal errors, reduced scopes, eligibility failures, and usage failures
have fixture coverage; see the [P0 closure record](developer/testing.md#p0-closure-on-serenity-2026-10-15)
for exact evidence and remaining live checks.

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
and separate implementation gates. P5 adds the local MCP client; P6 adds serial
local delegation. Remote execution remains unimplemented. Linux/macOS CI includes source checks and fresh-home bundled
release verification. The macOS App Sandbox probe signs an isolated helper with
approved built-in `codesign`; its file/network enforcement passed on the macOS
14 arm64 runner. Fresh-home checks do not substitute for every target OS,
architecture, signing/notarization, or account-eligibility check.

Hosted matrix runs passed Linux x86_64 and macOS arm64 core/source/package checks.
The corrected experimental macOS probe also passed its actual file/network and
child-inheritance checks; network assertions require connect permission denial.
P4's packaging verification and protocol-design scope is complete; see
[actual results](developer/testing.md#p4-release-verification-and-protocol-proposal-2026-10-15).
On 2026-10-15, public-native research and bounded tests established that
`setsid`/`setpgid` descendants can escape process-group cleanup on macOS.
The developer then selected native Mac execution with this documented lifetime
limit. The optional signed App Sandbox backend now enforces file/network
restrictions, applies per-process resource ceilings, and validates immutable
per-workspace signed workers through a bounded protected cache. Ordinary child
cleanup remains active; detached children may survive and keep workspace access.
See [the exact boundary](developer/sandbox.md#macos-production-boundary) and
[current verification](developer/testing.md#macos-native-backend-2026-10-15).

The final implementation CI passed Linux and macOS 14 source/package checks,
including actual Mac enforcement. Local Mac checks passed 122 tests with seven
Linux enforcement tests excluded. Development then returned to Serenity;
[Linux return verification is complete](developer/testing.md#p0-closure-on-serenity-2026-10-15).

Windows, broader MCP features, parallel/remote agents, broader account
eligibility, and other architectures remain future work. Reliable adversarial
descendant termination on macOS also remains unimplemented. No private API,
deprecated sandbox utility, privileged service, or VM was adopted.

## P5: local MCP tools

Implement an explicitly selected local stdio client and small tool allowlist,
using existing Elixir packages for protocol and schema evaluation. Every external
call enters the host's full-argument approval and durable intent boundary.
Server descriptions/annotations/results cannot grant permission. The session
owns transport lifetime; unknown outcomes stop the batch and are never replayed.
No network transport, resource/prompt loading, sampling, delegation, or remote
execution is implied by this milestone.

Acceptance: bounded explicit configuration; credential isolation and redaction;
schema validation with unsupported features rejected; duplicate/changed
discovery handling; exact descriptor binding; interactive approval and headless
denial; owner-death and cancellation cleanup; serial calls and bounded queues;
intent-before-dispatch journaling; unknown-outcome resume without retries;
and a credential-free demo. Verify source and package checks on supported hosts,
review developer/operator guidance, and commit/push the focused result.

The implementation reuses MCP Elixir SDK 1.1.0 and JSONSchex 0.10.0, with a
bounded SDK transport around Ipse's Rust OS helper. The developer approved
Telemetry and Rebar3 as BEAM dependencies on 2026-10-15. The source SDK-to-SDK
demo passed one exact approved scratch write without a model service.
Source and fresh-package verification passed on Arch: 182 ordinary tests and
189 with Linux enforcement included. The extracted runtime passed an actual
SDK-to-SDK MCP round trip without the development toolchain. The initial local
MCP scope is complete. A live ChatGPT subscription session subsequently passed
one exact approved MCP write, streamed completion, and resume without replay on
Arch. This verifies the example SDK server path; arbitrary third-party servers,
other live providers, and broader protocol capabilities remain separate checks.
The corrected implementation also passed
[Linux and macOS source/package CI](https://github.com/lexlapax/ipse/actions/runs/38773218000),
including bundled MCP verification and existing Mac native enforcement.
See [operator setup](operator/mcp.md), [developer contract](developer/mcp.md),
and [actual verification](developer/testing.md#p5-local-mcp-2026-10-15).

## P6: local subagent delegation

Selected by the developer after P5: explicitly enabled local child sessions with
parent-controlled approvals. Reuse ordinary OTP sessions, tasks, monitors, and
private journals. Define context transfer, provider/billing identity, exact tool
approval forwarding, ownership/cancellation, bounded results and model budgets,
and unknown-outcome recovery before exposing the tool. Children must not approve
themselves, spawn recursive children, or inherit MCP by default.

Acceptance: the [delegation contract](developer/delegation.md), focused fixtures
for policy/lifetime/recovery, a bounded live subscription scratch check, supported
Linux/macOS source/package checks, reviewed operator/developer guidance, and a
focused commit/push. The local implementation, focused fixtures, source baseline,
and live subscription scratch check passed on Arch. Final package verification
also passed, and [Linux/macOS source/package CI](https://github.com/lexlapax/ipse/actions/runs/38795554992) passed. P6 is complete
within this scope; see [actual results](developer/testing.md#p6-local-delegation-2026-10-15).

## P7: expanded MCP capability

Selected by the developer to follow P6. Start with independently implemented
local servers and concrete compatibility gaps, then bounded explicit local MCP
resources/prompts. Preserve exact host approvals, configuration allowlists,
credential isolation, descriptor binding, cancellation, and unknown outcomes.
Reuse the existing SDK/schema packages rather than adding a framework. Network
transports and their endpoint/authentication/privacy policies need a separate
design; they are not enabled by this planning entry.

Acceptance: pinned independent interoperability evidence, focused compatibility
and resource/prompt fixtures, truthful source/live verification, updated trust and
operator guidance, supported-host checks, and focused commits/pushes.

Local implementation, Arch source/enforcement checks, SDK resource/prompt demo,
and pinned independent Rust server interoperability passed. A separate live
ChatGPT session passed three individually approved MCP requests and idle resume
without replay. Added canonical schema metadata/nullable/default compatibility
and per-server native enforcement without new runtime dependencies. Final bundled
verification and [Linux/macOS source/package CI](https://github.com/lexlapax/ipse/actions/runs/38799753085)
passed, including actual Mac native stdio enforcement. P7 is complete within
this local scope. An initial Mac cleanup completion failure was not reproduced
by forty stricter CI repetitions. Subsequent [local Mac load checks](developer/testing.md#macos-stdio-cleanup-load-2026-10-15)
reproduced a drain failure with an ordinary pipe-holding descendant still alive
after the first group signal. Bounded cleanup retries and strict regressions
address that local reproduction without changing sandbox policy or the detached-
descendant limit. The fix at `b3db345` also passed
[Linux and macOS source/package CI](https://github.com/lexlapax/ipse/actions/runs/38822941399),
including actual Mac native enforcement. The initial CI failure's cause remains unconfirmed.
The subsequent [Serenity return verification](developer/testing.md#linux-return-after-macos-cleanup-2026-10-15)
passed source build, formatting, warnings-as-errors compilation, 236 tests with
Linux native enforcement included (14 Mac tests excluded), isolated demo, and
fresh Linux package verification. No runtime fix or live provider check was
needed on return.
Broader independent-server coverage remains recommended before designing
authenticated network transports. See
[actual P7 results and limits](developer/testing.md#p7-expanded-local-mcp-2026-10-15).

Following the Linux return check, a second pinned independent local server,
`mcp-memory` 2.0.0, passed native stdio discovery, denied-write non-dispatch,
exact approved create/get/search calls, persistence across fresh processes,
ordinary tool-error journaling, and idle resume without replay. Its published
source needed one documented prefetch pointer cast to build on Rust 1.99/x86_64;
no Ipse runtime or protocol policy changed. The optional verifier installs
nothing and adds no default/CI server dependency. This is scripted-model Linux
evidence, not current-release, live-provider, Mac, or network-transport coverage;
see [the second-server record](developer/testing.md#second-independent-local-mcp-server-2026-10-15).

## P8: bounded skill resources

Selected to follow P7. Start with a concrete repository skill that needs
supporting text files. Define explicit resource selection, paths relative to
the skill, permitted roots, precedence, size/depth bounds, and provenance before
extending the existing skill loader. Referenced content remains instructions or
data; loading it never runs scripts, installs dependencies, or grants permission.

Acceptance: demonstrate the real skill/resource use case; test missing,
malformed, oversized, sensitive, symlink, and escaping targets; preserve exact
loaded content/digests in bounded session context and deterministic resume;
show omissions clearly. Review operator/developer guidance, run appropriate
source and supported-host checks, and commit/push the focused implementation.
Implemented `load_skill_resource` using the existing bounded source reader.
The bundled review checklist, explicit provenance, rejection boundaries, and
changed-file resume fixtures passed. Arch build, format, warnings-as-errors,
239 tests with Linux enforcement (14 Mac tests excluded), and resource-enabled
demo passed. Hosted Linux/macOS source/package verification also passed at
`4a19bb3`; P8 is complete within this scope. Provider checks remain separate.
See [P8 evidence](developer/testing.md#p8-skill-resources-2026-10-15).

## P9: parallel local subagents

Selected by the developer to follow P8. Extend the existing opt-in local
delegation contract using Elixir/OTP sessions, tasks, monitors, and messages.
Keep serial behavior as the default. Define bounded concurrent children,
aggregate model/work budgets, approval routing by child/call identity, and a
shared-workspace conflict policy before permitting overlapping mutations.
Preserve separate child journals, explicit context transfer, same selected
provider/model, and the current prohibition on recursive delegation and child MCP.

Acceptance: overlapping read-only work; individually routed approvals with
interleaved children; deterministic result collection; conflict handling;
bounded scheduling and budgets; parent cancellation/death stopping all owned
children and ordinary process groups; partial failure and unknown recovery
without replay. Update the delegation contract and operator guide, distinguish
fixture from live provider evidence, verify supported hosts, and commit/push.
Implemented opt-in two-child groups using existing OTP ownership and separate
sessions. Source fixtures and live Ollama/Anthropic/OpenAI API checks passed;
hosted Linux/macOS source/package checks passed. Remote agents remain outside this
milestone. See [P9 evidence](developer/testing.md#p9-parallel-local-delegation-2026-10-15).

## P10: network MCP

Selected by the developer to follow P9. Start with a separate endpoint,
authentication, privacy, and recovery design behind the existing MCP adapter.
Select and pin the first transport/protocol combination and evaluate the
maintained SDK's support before implementing protocol machinery. Network MCP
stays disabled without explicit trusted configuration; model or repository text
cannot choose endpoints, credentials, or expanded capabilities.

Acceptance: verified TLS; explicit endpoint and redirect/credential-forwarding
policy; server-specific credentials and redaction; bounded discovery, messages,
connections, deadlines, and queues; exact allowlists, descriptor binding, full
approval arguments, and durable intent before dispatch. Test authentication
failures, descriptor drift, cancellation, disconnects, and incomplete results
as potentially unknown remote effects, never automatic replay. Verify against a
pinned independent server, update developer/operator guidance and dependency
inventory, and commit/push the supported result. Local approvals and sandboxing
cannot establish a remote server's isolation or guarantee remote cancellation.
Implemented MCP 2025-11-25 Streamable HTTP POST with JSON/finite SSE responses,
verified HTTPS, optional per-server bearer credentials, bounded private HTTP/1
clients, and best-effort session DELETE. Literal loopback HTTP requires an explicit
exception. Redirects, retries, OAuth negotiation, GET streams/subscriptions, and
reconnection/replay are excluded. Fixture and pinned independent-server checks
passed; hosted Linux/macOS source/package verification passed, including the
final abnormal-worker cleanup regression. See the
[contract](developer/mcp.md#streamable-http-boundary) and
[P10 evidence](developer/testing.md#p10-streamable-http-mcp-2026-10-15).
Remote subagents and arbitrary remote command execution remain outside this scope.

## P11: live dotsetup trial

Selected by the developer after P10: use Ipse in the live repository
`~/projects/lexlapax/dotsetup`. Inspect its instructions, branch, and worktree
first and preserve unrelated edits. Select a concrete bounded task from its
current needs; retain explicit provider selection, full tool approvals, and
unknown-outcome recovery. Record the actual task, provider/model, checks, and
limitations without credentials or private transcripts. Do not infer successful
live use from Ipse fixtures or earlier scratch-workspace checks.
Status: the developer-selected read-only project/next-steps assessment completed
with the real CLI, ChatGPT subscription, and Linux native shell profile on
Serenity. The existing worktree change was preserved. A follow-up health check
exposed native Bash process-substitution incompatibility and a model claim that
a sandbox-hidden sibling checkout was absent from the host. See the
[comparison and actual checks](developer/testing.md#p11-live-project-assessment-2026-10-15).
No project edits, live deployment, or coding-change acceptance are claimed.

The developer selected the first two repairs on 2026-10-15. Implementation and
local/bundled verification are complete; hosted Linux/macOS checks passed. See
[repair evidence](developer/testing.md#native-bash-and-visibility-repair-2026-10-15).
The developer continued with bundled project-orientation guidance, now verified
with a synthetic live project; see [skill evidence](developer/testing.md#project-orientation-skill-2026-10-15).
The three selected follow-ups are complete; multi-repository read roots remain
a separate proposal without implementation authorization:

1. Implemented and locally verified: Bash descriptor-path compatibility without
   exposing host processes or weakening the native filesystem/network boundary.
   Ordinary Bash/project-script regressions cover compatibility alongside
   adversarial enforcement.
2. Implemented and locally verified: bounded, platform-specific sandbox visibility
   facts for the model and operator. Distinguish hidden paths from host absence;
   do not silently expand roots or retry in trusted mode. Evaluate explicit read-only dependency roots
   separately if multi-repository verification is selected.
3. Implemented and verified: reusable project-orientation/Git workflow guidance:
   inspect existing changes and validation status before operator provisioning; preserve edits,
   identify owners, and distinguish source, staged deployment, and live proof.
   Existing read/approved shell tools handled this after a neutral follow-up.

GitHub was not exercised, so this trial does not establish a need for a new
GitHub adapter. The developer chose a new task tracker for the coding trial
instead of modifying dotsetup; see [P12](#p12-task-tracker-coding-trial).

## P12: task tracker coding trial

The developer selected a new app instead of a dotsetup coding change: a local
website with forms and a SQLite database, then chose a task tracker. Use a
separate project. Ipse implements the app; independently review its output and
verify create/edit/complete/delete forms, input validation, and persistent data.
Keep provider selection and individual tool approvals explicit. Record actual
checks and any Ipse changes indicated by this trial. Elixir was explicitly
imposed for this first
app by the test operator; the developer chose to finish it while clarifying that
Ipse's implementation language must not constrain its workloads. This trial
therefore does not validate autonomous stack selection or general non-coding
work. Future trials should preserve user choice or allow task-appropriate stack
selection, including TypeScript/Node or Python. Dotsetup's selected
read-only comparison is complete and its existing edits remain untouched.

Completed in `~/projects/lexlapax/ipse-task-tracker` through Ipse's embedded OTP
session API, ChatGPT subscription, and individually approved trusted local tools.
The app and independent review passed 16 tests, real HTTP CRUD/validation/security
checks, SQLite persistence after restart, and desktop/narrow Chromium layout
inspection. Source is committed locally; no new GitHub repository or deployment
was created. See [P12 evidence](developer/testing.md#p12-task-tracker-coding-trial-2026-10-15).

The long session exposed an existing compaction limitation: one or two retained
user turns can exceed the trigger without an eligible older prefix. A short
continuation made the completed first turn eligible; live compaction and local
commit then succeeded without replay. Improving long-turn compaction and its
cause-specific recovery diagnostics became the selected [P13 follow-up](#p13-long-turn-compaction-and-general-purpose-trials).
Neutral stack-selection/non-coding trials remain separate from this historical pass.

## P13: long-turn compaction and general-purpose trials

Selected by the developer on 2026-10-16 to complete the P12 follow-ups. Status:
long-turn output checkpoints and specific failure diagnostics implemented; source
build, formatting, warnings-as-errors compilation, 277 Linux tests, native demo,
P12 transcript replay, and a live eight-read single-turn check passed. Packaging
passed, and hosted Linux/macOS CI [38867833020](https://github.com/lexlapax/ipse/actions/runs/38867833020) passed. The core fix is committed/pushed at `57c9b67`.
Neutral coding trial passed in a separate workspace: Ipse chose Python/Flask;
independent review found a NUL validation crash, the same session repaired it, and
44 tests plus actual HTTP/restart/validation checks and desktop/narrow renders
passed. The synthetic non-coding trial passed after one source-path clarification:
source-backed plan, exact schedule/budget, pending owners and unchanged source
hashes. P13 is complete within these bounded checks; see [coding](developer/testing.md#p13-neutral-stack-coding-trial-2026-10-16),
[non-coding](developer/testing.md#p13-non-coding-document-trial-2026-10-16), and
[compaction](developer/testing.md#p13-long-turn-compaction-2026-10-16) evidence.
No unrestricted task coverage or unattended self-development is claimed.

1. Improve safe context reduction during long action turns and provide specific
   recovery causes. Preserve user requests, provider continuation payloads, exact
   tool-call identities/arguments, approval/outcome metadata, and the original
   journal. Retain recent tool results; checkpoint reductions durably before
   continuation and validate them on resume. Prove no automatic replay, failure
   integrity, cancellation/owner-death behavior, and compatibility with existing
   checkpoints. Reproduce the P12 long-turn failure and verify source/package
   checks, operator/developer documentation, and commit/push.
2. Run a fresh task-tracker/forms/SQLite coding trial with neutral requirements
   and let Ipse choose an appropriate installed stack. Do not inherit Ipse's
   Elixir implementation constraint into the workload. Independently review
   implementation, validation, persistence, and the actual selection rationale.
3. Run a bounded non-coding task over synthetic local documents, independently
   verify its factual result and artifact, and preserve task scope/permissions.
   Record actual provider, tools, checks, limitations, and any needed harness
   fixes. No deployment, new public repository, private project transfer, or
   external messaging is required by these trials.

### First supervised self-development trial

The developer asked what is needed for Ipse to develop itself. Existing file/shell
and Git/Mix tooling, scoped instructions, approvals, persistence, providers and
optional delegation/MCP can support a supervised trial now; a dedicated GitHub
adapter or workflow engine is not a prerequisite. The developer subsequently selected this as the first authorized stage on
2026-10-16, using shared operator skill discovery as the bounded first change.
That trial is now complete: stable bundled Ipse prepared the isolated change,
independent review/tests/package checks passed, interruption and idle resume
preserved journal/workspace bytes, and the reviewed feature was integrated.
The trial exposed bundled launcher environment contamination of system Mix;
the integrated harness now removes its own release variables/ERTS PATH entry.
See [actual evidence](developer/testing.md#shared-skills-questions-configuration-and-profiles-integration-2026-10-16).
The next trial is [P18](#p18-supervised-self-development-on-the-operators-mac).

Use an isolated checkout/worktree and the stable installed harness to make one
small Ipse change, review its diff independently, run the required source and
package checks, exercise interruption/resume, then review the exact commit before
merging/pushing. Keep the running harness separate from the code under change.
A reusable repository-development skill, clearer review/test evidence, and real
task regressions may improve this loop after demonstrated needs. Unattended
self-development would require stronger isolation and acceptance controls; current
supervised trials do not establish that capability.

## P14: bounded deep research

Added to the plan at the developer's request on 2026-10-16 and subsequently
authorized for implementation. Complete within documented scope on main with
an inert research skill, provider-agnostic configured MCP retrieval, durable
source/claim ledger and local export. A bounded live primary-source trial passed
with three captured sources, supported/inference/open claims and unchanged idle
resume after repairing missing host call attribution. Combined source checks passed
324 native Linux tests; extracted release and hosted Linux/macOS checks passed.
External dependencies/endpoints must be configurable, with no embedded search
service or hidden fallback, as explicitly required by the operator. External
setup, credentials and provider/billing choices remain explicit within the
authorized research scope. This milestone does not impose a mandatory workflow.

Ipse already supplies local file analysis, skills, bounded context, journals and
explicit MCP/delegation. Open-web deep research needs retrieval capabilities and
independently verified evidence handling; selecting a model alone supplies neither.

Acceptance:

1. Add a bounded research skill for question/scope clarification, search planning,
   source evaluation, primary-source preference, conflicting evidence, uncertainty
   and a cited final report. Use ordinary modules, tools and local artifacts;
   loading the skill grants no permission and enables no external service.
2. Evaluate compatible, explicitly configured search and page-retrieval MCP tools
   before adding custom retrieval machinery. Review server/schema/credential needs,
   output bounds and dependencies/licenses. Preserve provider/billing selection,
   individual external-call approvals and honest failed/unknown outcomes. Public
   retrieval must use an explicitly network-capable configuration; no silent
   fallback from a network-denying native shell/server profile.
3. Retain a durable, bounded source ledger outside the model's transient context:
   URL, retrieval date, publication/author data when available, content digest,
   relevant captured excerpts and claim-to-source links. Distinguish observed
   evidence from inference. Context reduction must not silently turn an excerpt
   into proof of a whole source; original evidence and report references must
   remain inspectable after resume. Do not automatically replay unknown calls.
4. Exercise optional parallel analysis without changing existing child boundaries:
   the parent retrieves MCP sources, children analyze collected local evidence,
   and the parent verifies the synthesis and citations. Children currently cannot
   use MCP or delegate recursively. A successful serial research trial suffices
   before expanding parallel coverage.
5. Verify controlled fixtures for missing/stale/conflicting sources, misleading
   retrieved instructions, unsupported claims, output limits and interrupted
   sessions. Then run a bounded live public-source question with explicit provider
   and retrieval configuration. Independently inspect cited source contents,
   claim support, uncertainty, completeness relative to scope, and resume behavior;
   URL availability alone is insufficient. Keep a credential-free fixture path.
6. Record actual tools/provider, source dates, checks and limitations in developer
   evidence; document operator setup, approvals, source/artifact locations and
   recovery. Update the documentation map if new guides are added. Commit/push
   focused changes only after their relevant completion checks pass.

### Related gap: structured operator questions

The original gap was free-text-only clarification, separate from yes/no action
approvals. P17 now implements native single/multiple/text questions with validated
explicit answers and durable waiting on main; see the operator/developer contracts.
MCP elicitation is also unsupported. Skills can guide wording but cannot supply
this runtime capability. Research scoping can initially use ordinary chat.

The selected native `ask_operator` tool supports bounded single-choice,
multiple-choice and free-text questions, explicit responses (no auto-submitted
recommendations/defaults), typed session/client events, journaling/resume,
cancellation/EOF and defined headless behavior. Waiting for clarification must
not confer approval, execute an action or leave a model request running. Keep
questions separate from permission prompts, validate stale/duplicate answers,
and define how child questions reach the parent operator before enabling them.
This is implemented under [P17](#p17-structured-operator-questions); child-to-parent
question forwarding and MCP elicitation remain unavailable.

## P15: scoped configuration and shared operator skills

Added at the developer's request and authorized on 2026-10-16. Status: shared
operator skills and scoped JSON settings are implemented and independently
verified on main. Combined source checks passed 324 native Linux tests; extracted
release and hosted Linux/macOS checks passed. Shared discovery uses project >
Ipse user > shared operator > bundled precedence and does not copy installations.
See [skill discovery](developer/architecture.md#skill-discovery),
[configuration](operator/configuration.md) and [verification](developer/testing.md).

Acceptance:

1. Define one bounded, versioned, data-only configuration schema for operator
   defaults and project/directory `.ipse/` settings. Evaluate existing Elixir/OTP
   and maintained Mix packages before choosing format/parsing machinery; reuse
   current Jason if JSON is suitable. Document exact filenames and supported
   fields before implementation examples are presented as usable commands.
2. Define deterministic setting precedence: built-in defaults, operator config,
   trusted project config, nearer trusted directory config, environment, then
   explicit CLI overrides. Keep directory discovery within the selected workspace/
   repository boundary; do not silently inherit unrelated parent-project policy.
   Preserve explicit user overrides and show effective values with their sources.
3. Treat discovered repository configuration as untrusted until applicable
   operator authorization is established. Configuration files must not silently
   change billing/provider, enable MCP/delegation, weaken approvals/sandbox, run
   scripts, or expand filesystem roots. Keep credentials in protected auth storage
   or explicit secret references, not committed project config or model context.
   The dedicated config loader must not remove `.ipse` sensitive-path exclusions
   from general instruction/resource loading or expose auth/session contents.
4. Discover shared **`~/.agents/skills/<name>/SKILL.md`** in addition to current
   project `.agents/skills/`, Ipse-specific user skills and bundled skills.
   Implemented same-name precedence: project `.agents/skills` > Ipse-specific
   `IPSE_HOME/skills` (default `~/.ipse/skills`) > operator `~/.agents/skills` >
   bundled. Shared operator discovery follows the operator home, independently of
   the Ipse state directory. Report selected/shadowed paths and retain provenance;
   avoid duplicate discovery of the same canonical source. Honor supported skills
   without copying or modifying their installation directories.
5. Verify supported frontmatter/resource compatibility with isolated skill trees;
   report unsupported metadata rather than claiming universal format support.
   Document and test path-alias/symlink handling without weakening existing
   resource restrictions. Loading any skill remains bounded, explicit and inert:
   no script execution, dependency installation or permission grants. Shared
   resources stay bound to their selected skill source and normal journal rules.
6. Fixture checks cover missing/malformed/oversized config, unknown fields,
   precedence and nested boundaries, duplicate/shared skills, secret exclusion,
   CLI/environment overrides and resume/refresh behavior. Persist the effective
   non-secret configuration/provenance needed for reproducibility; changed
   execution policy must not silently alter a resumed session. Isolate operator
   HOME and `IPSE_HOME` in tests so installed personal skills/auth are never read.
   Review operator/developer docs, map and links; run appropriate source/package
   checks, then commit/push the completed focused increments.

## P16: explicit model profiles and task routing

Added at the developer's request and authorized on 2026-10-16. Implemented on
main: bounded named profiles, main/routine/review
roles, conservative Responses effort mapping and selected-profile child isolation.
The native Linux suite passed 309 tests (14 macOS excluded); a live subscription
`gpt-6.1-sol`/high parent and installed Ollama `qwen3.5:9b` child passed routing,
arithmetic verification and unchanged idle resume. The combined main suite passed
324 native Linux tests; extracted package and hosted Linux/macOS checks passed. See
[profile setup](operator/model-profiles.md) and [contract](developer/model-profiles.md).
The intended use is a stronger main model with an explicitly chosen smaller local
model for suitable routine subtasks. P15 supplies persistent configuration; this
milestone supplies host-enforced profiles/routing, not a mandatory task pipeline.

Acceptance:

1. Add named, validated execution profiles with provider, model, supported
   provider-specific reasoning settings, context/step/timeout limits and credential
   references. Separate ChatGPT subscription and OpenAI API billing identities.
   Validate reasoning settings against documented provider/model capabilities;
   reject unsupported settings instead of silently ignoring them or inventing
   model-name suffixes. Review current public provider documentation when wiring
   these settings into each adapter.
2. Support explicit role assignments such as `main`, `routine` and `review`, with
   optional separately configured summary routing. Preserve the existing single-
   provider behavior when routing is absent. A model may propose only operator-
   configured profile IDs; it may not invent endpoints, credentials, billing modes
   or arbitrary provider overrides. Skills may recommend a task/profile but the
   harness validates and enforces the configured choice.
3. Permit a selected main profile and a different bounded child profile, including
   ChatGPT subscription parent plus local Ollama child. Keep child conversations,
   credentials and journals separate, pass only approved task/context, and never
   replay one provider's opaque continuation fields into another provider. Keep
   independent parent/child approvals, ownership/cancellation, step budgets and
   current no-recursive-delegation/no-child-MCP boundaries. Treat child output as
   untrusted evidence for the parent to check before acting on it.
4. Display and journal the actual role/profile/provider/requested model/settings
   and available usage metadata for each execution, preserving reported-model
   identity separately. Make routing and credential/data-transfer boundaries
   visible before execution. Default to reporting unavailable/failed profiles;
   any fallback must be explicitly configured/authorized, bounded and visible.
   Never silently escalate a local task to paid inference or change billing mode.
5. Fixture tests cover precedence, role/profile validation, every adapter's request
   mapping, unsupported reasoning options, missing credentials, failure without
   unapproved fallback, native-payload isolation, cancellation, resume and unknown
   effect outcomes. Run a bounded live stronger-parent/local-child trial under
   explicit account/provider authorization and independently verify actual routing
   and results. Verify `high` reasoning separately only where the public interface
   and selected account/model support it. Keep credential-free fixtures/demo and
   record untested providers/settings honestly.
6. Update operator configuration/examples and developer trust/provider/delegation
   contracts before declaring an increment complete. Document any added dependency
   in the inventory. Complete relevant source/package checks and commit/push;
   profile configuration and skills must never become implicit permission grants.

## P17: structured operator questions

Selected and authorized on 2026-10-16. Implemented on main. The feature passed
25 focused tests, 293 native Linux tests, live subscription single/multiple/text
answers, extracted runtime checks and hosted Linux/macOS checks. Combined main
source passed 324 native Linux tests (14 macOS excluded locally); extracted
release and hosted Linux/macOS checks passed. See [contract](developer/operator-questions.md).

Acceptance:

1. A bounded `ask_operator` tool supports single-choice, multiple-choice and free
   text with stable question/option identifiers, descriptions and optional
   recommendations. Recommended options are never automatically submitted.
2. Expose typed session/client question and answer events with explicit answer
   validation. Reject stale/duplicate/invalid responses without executing tools;
   keep clarifications separate from approval and permission grants.
3. Journal questions and explicit answers and restore pending questions on idle
   resume without repeating prior effects or inference. Cancellation, EOF, owner
   death and headless invocation have defined bounded behavior; no hanging model
   task or implicit default answer. Child questions use parent-mediated routing
   or fail explicitly until that routing is supported.
4. Verify CLI/API behavior, malformed and over-limit payloads, waiting/cancellation,
   resume, owner death and no replay with fixtures and a bounded live choice task.
   Review developer/operator documentation and map/links; run required source/
   package checks and commit/push completed increments.

## P18: supervised self-development on the operator's Mac

The local supervised Mac trial ran on 2026-10-16. Ipse authored the
`sessions --json` implementation, eight isolated regressions, CLI help and
operator/developer guidance from a frozen `ee50392` runner. Independent source,
Mac native and extracted-package checks passed, as did a bounded read-only review.
The full suite passed 315 tests with 31 excluded; the separate Mac native/stdio
run passed 27 with six Linux-native tests excluded.

Structured clarification and idle resume were exercised. The initial pre-exit
journal checksum failed because `/exit` appended one `cancelled` event. The
post-exit/pre-resume comparison passed without inference or tool replay; the
runbook now uses that timing. An initial review exhausted its six-step budget
and returned unknown; a narrower explicit review completed without findings.
Context compaction later stopped safely, so the supervisor finished the evidence
updates without changing Ipse's source or tests. See the
[Mac runbook](operator/self-development.md) and
[local evidence](developer/testing.md#p18-macos-supervised-self-development-evidence).

The operator delegated final review and publication to the supervisor after the
local results were presented. PR [#1](https://github.com/lexlapax/ipse/pull/1)
merged after the exact candidate passed hosted Linux and macOS checks for both
push and pull-request runs. P18 is complete within this supervised trial's
documented scope. The context, child-budget and live-account limitations above
and in the evidence record remain.

Acceptance:

1. Freeze a known baseline in a separate stable runner checkout and create a
   candidate branch/worktree. Preserve existing Mac edits and validate the local
   baseline before model work. Record exact OS/toolchain/commit evidence.
2. Select explicit subscription/provider profiles and private trial state. Use
   individually reviewed effects, native structured clarification and one bounded
   read-only review. Local routine delegation is optional and uses only a model
   actually installed/configured on the Mac. No mandatory external service.
3. Complete one small behavior change with meaningful isolated regression tests,
   relevant operator/developer documentation and no new dependency. The proposed
   JSON listing contract is specified in the runbook; do not export raw metadata
   or private conversation contents.
4. Verify idle interruption/resume without automatic inference/effect replay.
   Inspect unknown effects before explicit continuation. Keep the stable running
   harness separate from the code under change.
5. Independently review code and actual focused/full Mac source, native and
   extracted-package results. Record skipped/failed checks honestly; hosted CI
   cannot substitute for the operator's local Mac trial.
6. After review, the operator commits/pushes the exact candidate, waits for
   Linux/macOS CI and approves merge. Update this plan and the developer evidence
   record before completion. The trial model must not commit/push/merge itself.

## P19: long-session diagnosis and recovery

Implemented after the Mac trial: exact content-free live/saved context accounting,
model/summary request duration records and explicit bounded handoff export. Existing
compaction rules stay intact; original/native data is never silently trimmed.
Synthetic fixtures reproduce the retained-native-data failure shape, not the
unavailable original private Mac transcript. Local source/package checks are
recorded in [P19 evidence](developer/testing.md#p19-diagnosis-and-explicit-recovery);
hosted Linux/Mac completion checks passed after fixture timing synchronization.
Reproduce the retained-context stop with synthetic fixtures and identify exact
byte contributions before choosing a repair. Do not assume the safe refusal is
itself a bug or solve it by silently dropping native continuation or operator intent.

Acceptance direction:

1. Add a local content-free diagnostic snapshot and correlated timing/context
   measurements, including pinned requests, arguments/provenance, native data,
   recent results and instructions. Preserve credential/hidden-reasoning exclusion.
2. Reproduce P18's failure shape and independently verify the diagnosis. Real Mac
   transcripts remain private; use sanitized structural measurements/synthetic
   content rather than committing them or assuming they exist on Serenity.
3. Improve validated compaction where supported, or an explicit operator-reviewed
   handoff into a new session with provenance and unresolved effects clearly
   represented. Preserve original journals, configuration identity and no replay.
4. Verify cancellation, refusal/corruption paths, idle resume and source/package
   behavior; update operator/developer docs and actual evidence, then commit/push.

See the [diagnostic capture and tracing contract](developer/observability.md).

## P20: repeatable supervised self-development

Implemented as the bundled `self-development` skill with evidence/review resources
and a credential-free real Session fixture. Source/package fixtures, 340 native
Linux tests and hosted Linux/Mac checks passed. Supervised live P21 use completed
authoring and recovery, with repeated orientation requiring supervisor narrowing;
this is not evidence of unattended development. The resources reuse existing
questions, configuration, profiles, approvals and journals without P22 or a
workflow engine. Child reviews retain their real six-step/time limits. See
[skill evidence](developer/testing.md#p20-reusable-self-development-skill) and
[live limitations](developer/testing.md#p21-supervised-serenity-trial-and-independent-checks).

Acceptance direction: frozen runner/candidate separation; explicit task and
acceptance checks; bounded review and independent validation; interruption/handoff;
accurate test/package/platform evidence; operator-reviewed publication; inert
skill loading and no hidden installs/provider changes. Validate the skill in a
credential-free fixture and supervised use, review both documentation audiences,
then commit/push.

## P21: larger self-development trial on Serenity

Live supervised authoring completed from frozen P20 runtime `b7c0ed6` in a
separate candidate worktree. The fresh-chat import passed 31 focused fixtures,
independent build/format/compile/demo, 351 native Linux tests (14 Mac-only
exclusions), and integrated extracted-package recovery checks. The supervisor
exercised byte-identical idle resume, inspected an unstarted proposal before
explicit continuation, and manually supplied a reviewed P19 handoff note to a
fresh session after a safe retained-context stop. Repeated orientation required
supervisor phase narrowing; this is not unattended development evidence.
Implementation and independent package/evidence additions were committed and
pushed. After explicit operator approval, the separate live child review completed
using the configured review role (`gpt-6.1-sol`/high): two targeted reads, three
model requests, no mutations or shell calls, and no findings within the permission/
replay/resume scope. The supervisor checked its claims against source and fixtures.
The [full hosted Linux/Mac matrix](https://github.com/lexlapax/ipse/actions/runs/38961827683)
passed, including native Mac and extracted packages. P21 is complete within this
supervised scope, with intervention and retained-context limitations preserved. See
[actual trial evidence](developer/testing.md#p21-supervised-serenity-trial-and-independent-checks).

The selected workload was explicit validated import of P19 handoff artifacts into
a fresh session, with source identity, unknown-effect review and no permission/
provider/native-history transfer. It used a frozen stable runner, separate
candidate worktree, explicit profiles, independent review, interruption/recovery
and source/native/package checks. Separate approval, provider and OS boundaries
remain intact. This is separate from the P22 extension scaffold.

## P22: extension scaffold and lifecycle hooks

**Complete within the documented SDK contract at `de073ba`.** The operator
authorized P22–P25 on 2026-10-16. P22 establishes
the generic extension APIs and verifies that domain features can use them
without feature-specific core dispatch. New domain behavior, memory,
presentation and optional workflows should use these APIs; core retains
lifecycle, trust, approvals, persistence, provider and OS correctness.
Unknown future capabilities and core bugs may still require reviewed core work.

The [architecture and framework comparison](developer/extensions.md) explains
the design and [core/SDK boundary](developer/extensions.md#core-boundary-and-sdk-coverage).
The [adoption scenarios](developer/extension-scenarios.md) cover bundled,
third-party and operator-generated extensions, including temporary and
persistent use. They are design walkthroughs, not execution proofs.

### Implemented foundation

| Area | Current behavior | Contract |
| --- | --- | --- |
| Artifacts and activation (A1–A3) | Inert immutable import/inspection, independent worker SDK, scoped operator trust/configuration and session leases | [Artifacts](developer/extension-artifacts.md), [operator selection](operator/extensions.md) |
| Prompt and presentation (A4) | Two default-off examples; source-bound projections retain original/native data and restore without callbacks | [Hooks](developer/extension-hooks.md) |
| Request facts (A5) | Durable identities, normalized final/partial/unknown usage, rejected-summary retention and child attribution | [Usage](developer/usage-accounting.md) |
| Visible text (A6/A13) | Embedded and selected worker consumers, serializable handles, acknowledgments, bounded pressure and incomplete shutdown | [Text channel](developer/text-streams.md) |
| Catalogs and invocations (A7) | Inert typed tools/commands/services, full tool approval, owned workers and committed receipts | [Invocations](developer/extension-invocations.md) |
| Host state (A8) | Finite continuations, scoped CAS storage, retained tombstones and separate write approval | [Host calls](developer/extension-host-calls.md) |
| Operator questions (A9) | Durable checkpoints; only explicit validated answers start new continuations | [Questions](developer/extension-questions.md) |
| Workflow actions (A10) | Existing file/shell tools behind instruction preflight, full mutation approval and bounded owned execution | [Tool actions](developer/extension-tool-actions.md) |
| Service composition (A11) | Operator-bound typed value services with acyclic dependency pins and durable provenance | [Services](developer/extension-services.md) |
| Context and evidence (A12) | Caller-scoped bounded publications, assertion/receipt distinctions and exact cached request snapshots | [Context](developer/extension-context.md) |
| Lifecycle source/views (A14) | Internal stable journal occurrence IDs, bounded read-only source pages and distinct metadata/private prompt projections; no subscriber activation | [Lifecycle events](developer/lifecycle-events.md#internal-journal-source-and-prompt-views) |
| Prompt subscriptions (A15) | Inert declarations, scoped metadata/private views, final-effective user-text marker and finite owned notifications with required/optional no-replay receipts | [Subscriptions](developer/extension-events.md) |
| Prompt jobs and recall (A16) | Source-bound typed handlers use finite approved actions; before-request context, after-turn maintenance, host-derived failures and explicit question continuation | [Event jobs](developer/extension-event-jobs.md) |
| Shared committed metadata (A17) | Allowlisted model/tool/context/question/child/extension/turn projections retain stable source IDs and existing host causal links; no broader delivery or exporter activation | [Lifecycle events](developer/lifecycle-events.md#internal-journal-source-and-prompt-views) |
| Diagnostic capture (A18) | Operator-only off/local/export policy, default-off local sink, bounded owned worker queues, visible drops/failures, rotation, immediate stop and independent recovery receipts | [Controls](operator/observability.md), [contract](developer/observability.md) |
| Local trace retention (A19) | Bundled sink backend bounds slots/files/bytes across sessions, protects active writers with native locks and refuses corrupt/mismatched policy without changing host APIs | [Ring contract](developer/observability.md#local-ring-retention) |
| SDK conformance (A20) | Explicit synthetic CLI checks reuse Sessions, trust/approval and recovery schemas; support prompt/tool/command/service scenarios, structured answers, scratch state and content-free assertions | [Author runner](developer/extension-conformance.md) |
| Developer tracing (A21) | Opt-in synthetic dispatcher samples use isolated OTP sessions, one-in-flight VM admission, fixed arities, bounded reports and independent cleanup/deadline monitors | [Trace and source-debugging boundaries](developer/observability.md#synthetic-dispatcher-tracing) |
| Completed-answer events (A22) | Original/presented private views, shared metadata/source identity and after-turn notify/job delivery bind final presentation to native history and effective prompt; normal approvals and question/no-replay recovery remain separate | [Subscriptions](developer/extension-events.md), [jobs](developer/extension-event-jobs.md) |
| Explicit history (A23) | Own-session fixed-range reads share source/view identities, separate private history grants, bounded pages and skipped/gap outcomes; SDK catch-up uses normal actions, questions and no-replay recovery | [History contract](developer/extension-history.md) |
| Runtime epochs/waits (A24) | Opt-in durable session start/resume/logical close and approval/question waits, bounded recording, process-local duration, actual host links and incomplete restart semantics; no broader subscriber activation | [Runtime facts](developer/lifecycle-events.md#runtime-epochs-and-operator-waits) |
| Live metadata feeds (A25) | Selected committed activity after explicit enrollment, source-bound intents/acknowledgments, bounded serial queues, visible incomplete closure, independent diagnostic policy and inert idle resume | [Feed contract](developer/extension-feeds.md) |
| Admitted-tool views (A26) | Host tool IDs and source-bound input/outcome facts, separately granted structured live/history views, metadata privacy, bounded recording and explicit question/cancellation recovery | [Tool event contract](developer/tool-events.md) |
| Child outcomes (A27) | Parent-owned start/result binding, authenticated worker completion, bounded metadata feed/history projection and distinct cleanup acknowledgment, with unknown/incomplete recovery | [Child event contract](developer/lifecycle-events.md#delegated-child-outcomes) |
| Ephemeral text sources (A28) | Negotiated v2 text delivery, broker epochs, fresh stream/range identity, distinct consumer sequence, bounded metadata/private projections and unchanged v1 admission/recovery | [Stream event contract](developer/stream-events.md) |
| Independent domain proof (A29) | Seven separately compiled artifacts exercise scoped memory/graph extraction, recall, questions/workflows, history/deduplication/forget and private tool/text observers against candidate core `3b0ef78`; unchanged installed Linux archive, temporary CLI selection and persistent configuration verified | [Proof scope](developer/extension-proof.md), [operator lab](operator/extension-lab.md) |
| Lifecycle audit and supervised extension change (A30) | Supported/unsupported boundaries audited; frozen release authored an operator-only read-only stats command under three separately approved edits, followed by a fresh scoped review, 41 source/installed assertions and unchanged idle resume | [Coverage audit](developer/lifecycle-events.md#supported-lifecycle-coverage), [live trial](developer/testing.md#supervised-extension-only-trial-2026-10-17) |

The [verification guide](developer/testing.md#current-evidence-and-next-checks)
distinguishes source fixtures, extracted-package baselines, hosted platform
checks and live trials. The combined evidence below completes P22; it does not
establish production knowledge quality or implement P23–P25 capabilities.

### Completion evidence and future capabilities

The [shared lifecycle audit](developer/lifecycle-events.md#supported-lifecycle-coverage)
records exact private views, actual causal links, legacy absences and unsupported
stages at each stable boundary. It found no additional core seam needed by the
specified P22 scenarios. Notifications, transforms, feeds and effectful jobs share
vocabulary without sharing authority; remote bridges still require negotiated
egress, acknowledgment, disconnect and catch-up contracts.

The independent lab freezes candidate core at `3b0ef78` and passes 41 synthetic
assertions in source and an unchanged installed Linux release. A frozen release
also authored a two-file extension change in a separate worktree under individual
edit approval, followed by a separate read-only review and supervisor verification.
Both shipped hooks ran in both live sessions; idle resume changed neither journals
nor source. [Hosted run `39037702166`](https://github.com/lexlapax/ipse/actions/runs/39037702166)
passed every applicable Linux/macOS build, format, compile, test, demo, ordinary
package and installed-lab step, plus macOS native/default experimental enforcement.
It verifies the canonical bundle-path correction after `2874da0` mistook macOS's
`/private/var` alias for a different runtime. System tools remain rejected.
Any future core change requires a new candidate freeze and compatibility evidence;
do not extend this historical proof by assertion. See the
[delivery sequence and coverage gate](developer/extensions.md#delivery-sequence-and-extension-only-proof)
and [actual evidence](developer/testing.md#current-evidence-and-next-checks).

Remote catalogs/download assistants, turnkey builders, idle hot activation and
nested interactive/effectful service contracts remain explicit future
enhancements. Current value-service replies cannot acquire those capabilities.
Optional cost/budget policy is P23; voice/realtime is P24; researched default-off
knowledge extensions are P25. P25 can proceed independently of voice.

| Acceptance | Completion evidence |
| --- | --- |
| 1 — typed lifecycle and delivery | Supported-boundary audit, exact declaration refusals, private/metadata separation, physical source validation, bounded feeds and durable/ephemeral identity fixtures |
| 2 — SDK, artifacts, trust and usage | Inert import, immutable registry/runtime/config pins, worker ownership, child subset/expiry/missing-artifact fixtures, canonical request accounting and acknowledged text channel |
| 3 — two shipped hooks | Credential-free source/package examples and both hooks in the live author/reviewer sessions; original/native integrity and inert resume checked |
| 4 — extension-only memory/workflow proof | Seven separately compiled artifacts, 41 source/installed assertions, temporary CLI and persistent selection, deduplication/catch-up/forget/conflict; no core/native change or archive rebuild |
| 5 — observability/developer controls | Off/local/export policy, bounded owned sinks and aggregate ring, immediate stop, synthetic tracing/conformance and documented source-debugger limits; no mandatory broker/exporter |
| 6 — failure/recovery/platform/trial | Full Linux native suite (632 passed, 14 macOS exclusions), both hosted platforms including installed lab, version/import/lease/approval/failure fixtures and separately reviewed supervised trial |
| 7 — documentation/dependencies/publication | Integrated operator/developer guides, public coverage/evidence records, dependency reuse inventory and checked links; verified increments committed and pushed through `de073ba` |

Acceptance:

1. Define the event taxonomy and payload/version/ordering/failure contract for
   session start/resume/close, prompt admission, context, model/stream, tool
   validation/approval/intent/outcome, operator questions, children, compaction,
   turn completion/error/cancellation and owner death. Implement only documented
   stable seams, with observation distinct from permission to transform or act.
   Treat hooks as typed subscriptions to shared lifecycle boundaries: distinguish
   metadata notifications, private content feeds, ordered hooks and triggered jobs.
   Pin original/effective prompt views, durable source IDs, causal origin and
   generation; bound delivery/queues and report gaps. Acknowledgment never implies
   action completion. Preserve existing v1 contracts; unsupported subscriptions
   refuse until negotiated and implemented.
   Keep transport separate from occurrence identity: local SDK consumers need no
   broker; future external bridges must explicitly negotiate private-view/egress
   authority, remote acknowledgments, bounded disconnect handling and catch-up.
   A read-only feed acknowledgment must never acquire storage/publish effects.
2. Add a backend-independent Elixir SDK/registry and owned workers: bundled
   trusted modules may run in-VM, while independent packages use a versioned
   serializable worker bridge. Define immutable artifacts, installed/trusted
   records and activation instances with distinct identities. Support local
   artifact import without rebuilding Ipse, generic config/flag selection and
   scoped options/lifetimes. Pin artifact/runtime/config/API/generation for resume,
   separately validate project/child policy, and verify disabled adapters never
   initialize. No implicit evaluation, downloads, host code-path injection or
   arbitrary host atoms. Process separation is not an OS sandbox claim.
   Establish request/attempt/parent identity, durable normalized usage facts and
   a private bounded visible-text subscription, distinct from droppable diagnostics.
   Define typed service composition, evidence/context/state/job contracts for the
   knowledge extension family; negotiate unsupported future capabilities explicitly.
3. Ship two bounded, opt-in examples: an attributed operator prompt-context
   template and a completed-answer presentation formatter. Preserve original
   input/output, provider continuation and tool provenance; validate and journal
   derived projections. Resume restores them without rerunning callbacks/effects.
   Define streamed-versus-completed output behavior explicitly.
4. Specify long-term memory recall/remember/forget/export and workflow adapter
   contracts: scope, provenance, budgets, explicit approved/journaled effects,
   stale/conflicting data, deletion and bounded continuation. Prove the generic
   SDK with a separate synthetic local memory/workflow package after core is
   frozen: no edits under core/native and no feature-name dispatch branches.
   Prove a private prompt subscriber can perform deterministic entity extraction
   and separately approved scoped storage, with provenance/deduplication, no
   self-trigger loop and no resurrection after forget. Compare background indexing
   with awaited recall; an admitted request cannot change with background timing.
   Exercise queue saturation, interruption/idle resume and explicit bounded catch-up
   without automatic effect replay. See the [event acceptance cases](developer/lifecycle-events.md#knowledge-graph-acceptance-proof).
   Production memory backends and elaborate workflows remain follow-on extensions.
   No mandatory memory store, embedding service, workflow framework or exporter.
   Exercise a separately built worker artifact in temporary-session use and
   explicit persistent configuration, with no Ipse rebuild or core changes.
5. Reuse P19's sanitized event foundation for lifecycle/extension timing, context
   contributions and failure diagnosis. Evaluate Telemetry as a direct declared
   dependency; do not run transform callbacks inside Telemetry handlers. Add a
   bounded local diagnostic sink and explicit local developer tracing procedures.
   External OpenTelemetry export remains optional and separately configured.
   Define off/local/export host gates and generic sink configuration/flags,
   default-off local capture, effective-config inspection and immediate sink-stop.
   Add synthetic extension-debugging/conformance inputs; evaluate existing source
   debuggers rather than creating an IDE/runtime debugger or mandatory service.
6. Verify ordering, bounds, timeouts/crashes, cancellation/owner death, overload,
   no approval bypass, synthetic-secret exclusion, original/derived integrity,
   child isolation policy and durable no-replay resume. Include both example
   adapters in credential-free source/package verification and an independently
   reviewed supervised trial, with Linux/Mac evidence distinguished. Cover pinned
   concurrent versions, malformed artifacts, interrupted imports, scope/promotion,
   expiry/revocation and resume after missing/changed artifacts. Deferred installers,
   builders and live activation must refuse unsupported capabilities explicitly.
7. Review operator/developer usage, installation/trust/recovery limitations and
   dependency inventory; check file links/anchors, update actual status/evidence,
   then commit/push completed focused increments. Research/design completion
   alone must not mark the extension milestone implemented.

## P23: usage, cost reporting and budget controls

**In progress.** P23A implements the pure extension-side
[rate-card estimator](developer/costs.md): exact model/billing/endpoint/date/token-band
selection, configured decimal rates, fixed-point arithmetic, cache partitions,
explicit unknown/partial values and provenance. Fifteen synthetic fixtures cover
its contract. It does not yet expose a report extension or enforce budgets.

P22 supplies durable
canonical usage facts and identities independently of tracing. Build an optional
bundled report/cost extension using configurable versioned pricing, explicit
provider/billing/model/unit attribution, unknown/incomplete estimates and dated
rate provenance. Do not label ChatGPT subscription usage API spend or local
inference free hardware/electricity. No mandatory rate service or hardcoded prices.

Budget enforcement is a foreseen host capability, not an observational callback:
gate covered main/summary/child/extension requests, reserve liability atomically
across parallel work and reconcile actual/partial/unknown usage. Document the
provider's enforceable limits and avoid promising an exact invoice ceiling for
in-flight requests. Reports, budget displays and policies use the SDK; approval,
provider selection, cancellation and durable accounting stay core-owned.

Next deliver a bounded granted accounting-read SDK operation and default-off
report extension with request-revision and parent/child aggregation; then atomic
host reservation/reconciliation and generic accounted extension model requests.

Require fixtures for rate/version changes, unknown counts/rates, retry/revision
deduplication, parent/child aggregation, rejected summaries, parallel reservations,
cancellation/resume and tracing disabled. Review both documentation audiences,
dependency/rate provenance and links, then commit/push completed increments.
See [usage contract](developer/runtime-capabilities.md#usage-facts-and-costs).

## P24: voice and realtime media

Implementation is authorized after P22/P23 foundations. Additional dependencies
still follow the dependency approval policy. Start with a chained STT → admitted text agent → TTS
extension/client. Use separately selected explicit provider profiles and bounded
owned input/output resources. Then add a versioned realtime provider/session
capability for bidirectional transport, interruption, turn control, playback
acknowledgment and generated-versus-played history reconciliation.

Voice choice, STT/TTS/provider/device adapters and UI stay in extensions/clients;
resource ownership, admission, approvals, cancellation, flow control and provider
continuation integrity stay host-owned. Use a separate media data plane, ephemeral
raw audio by default, canonical transcripts/usage and explicit endpoint/device/
billing choices. Never infer audio API eligibility from text subscription auth.

Require synthetic split/slow/disconnected media, interim-transcript revision,
barge-in, stale frames, unplayed output, owner death, approval waits and no-replay
recovery before optional live provider/device checks. Evaluate maintained Elixir/
Rust/OS facilities and inventory/approve external dependencies before adoption;
no bundled codec, frontend runtime or service is selected by this plan. Review
operator/developer guidance and links, then commit/push completed increments.
See [stream/media boundaries](developer/runtime-capabilities.md#text-and-media-are-distinct-from-diagnostics).

## P25: optional knowledge extensions

Research the operator-requested shipped capability family, all disabled by default:
short-term working memory, long-term memory, a robust research engine with
pluggable providers, graph augmentation of memory and RAG. Select skill, tool/MCP,
extension or backend implementation per use case; automatic policies may need
hooks while explicit retrieval may need only tools. Configuration selects
independent instances and providers; no store, worker, indexing job,
network request or inference starts merely because the code ships with Ipse.
Implementation is authorized, with research gates before backend selection.

Zero-Mem is the operator's inspiration candidate. Require thorough primary-source,
implementation/license/dependency and alternative research for each capability
before selection, followed by matched-budget prototypes and failure/quality/cost
evaluation. Distinguish the paper, authors' repository and independent implementations;
do not reproduce their performance claims as Ipse evidence. Compare deterministic
raw-turn/lexical memory with relational/temporal retrieval; account for encoder,
storage and final-answer costs separately. See the
[research and selection gate](developer/knowledge-extensions.md#research-before-implementation-selection).

P22 supplies scoped state/context contributions, typed service composition,
evidence identity, owned jobs and approved effects. P23 adds optional cost reports
and budget admission. The packages implement recall/write policies, store/retrieval
adapters and research workflows; they do not replace core conversation recovery,
permissions or provider integrity. Graph/RAG/research remain independently useful;
none requires a mandatory database, embedding model, search service or framework.

Deliver selected memory tools/adapters first, then research/RAG and graph capabilities
as independently useful increments; this work need not wait for voice or cost UI.
The operator approved the implementation sequence on 2026-10-16. Ask for input
only when a material selection requires it. Require default-off parity,
scope/provenance/retention, deletion propagation, source-supported citations,
partial-failure/cancellation/budget handling and unchanged no-replay resume.
Evaluate dependencies, run source/package fixtures and separate live checks,
review operator/developer configuration/recovery guidance, check links, then
commit/push completed increments. See [package/hook map and acceptance](developer/knowledge-extensions.md).
