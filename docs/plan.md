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
| [P14](#p14-bounded-deep-research) | Research method, explicit search/retrieval, evidence and validation | Authorized; queued after P16 |
| [P15](#p15-scoped-configuration-and-shared-operator-skills) | Operator/project/directory configuration and shared skills | Authorized; shared skills/self-development in progress |
| [P16](#p16-explicit-model-profiles-and-task-routing) | Main/subtask model profiles and provider-specific settings | Authorized; queued after scoped configuration |
| [P17](#p17-structured-operator-questions) | Validated operator questions and resumable answers | Implemented and verified in isolated feature worktree; integration pending shared-skills review |

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
| 1 | Supervised self-development using stable Ipse to add P15 shared operator skills | In progress in isolated worktree; independent review pending |
| 2 | P17 structured operator questions | Isolated implementation, fixture/live and package verification passed; integration pending |
| 3 | Remaining P15 scoped configuration | JSON loader/CLI/resume verified on feature branch; integration pending |
| 4 | P16 explicit model profiles/routing | Implemented/verified in feature branch; main integration pending |
| 5 | P14 bounded deep research | Implemented generic configured MCP/ledger; fixture/live checks passed, main/release integration pending |

Update each row and its implementation/evidence record as focused increments pass.
Use independent review, required source/package checks and explicit live evidence;
commit/push completed increments without declaring unverified integrations done.

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

### Candidate next step: supervised self-development

The developer asked what is needed for Ipse to develop itself. Existing file/shell
and Git/Mix tooling, scoped instructions, approvals, persistence, providers and
optional delegation/MCP can support a supervised trial now; a dedicated GitHub
adapter or workflow engine is not a prerequisite. The developer subsequently selected this as the first authorized stage on
2026-10-16, using shared operator skill discovery as the bounded first change.

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
authorized for implementation. Implemented on the research feature branch with
an inert research skill, provider-agnostic configured MCP retrieval, durable
source/claim ledger and local export. A bounded live primary-source trial passed
with three captured sources, supported/inference/open claims and unchanged idle
resume after repairing missing host call attribution. Main/release/hosted checks
remain pending. External dependencies/endpoints must be configurable, with no
embedded search service or hidden fallback, as explicitly required by the operator. External setup, credentials and provider/billing choices
remain explicit within the authorized research scope. The separate
[supervised self-development candidate](#candidate-next-step-supervised-self-development)
remains available; adding this milestone does not impose a mandatory workflow.

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
explicit answers and durable waiting in its feature worktree; main-branch
integration remains pending the current execution sequence.
MCP elicitation is also unsupported. Skills can guide wording but cannot supply
this runtime capability. Research scoping can initially use ordinary chat.

The selected native `ask_operator` tool supports bounded single-choice,
multiple-choice and free-text questions, explicit responses (no auto-submitted
recommendations/defaults), typed session/client events, journaling/resume,
cancellation/EOF and defined headless behavior. Waiting for clarification must
not confer approval, execute an action or leave a model request running. Keep
questions separate from permission prompts, validate stale/duplicate answers,
and define how child questions reach the parent operator before enabling them.
This is now selected for implementation in [P17](#p17-structured-operator-questions);
it remains unavailable until that stage passes its checks.

## P15: scoped configuration and shared operator skills

Added at the developer's request and authorized on 2026-10-16. Status: shared
operator skill implementation/self-development trial in progress; scoped config
queued after P17.
The scoped configuration feature branch implements bounded version-1 JSON in
`IPSE_HOME/config.json` and repository/directory `.ipse/config.json`, with explicit
project trust, local inspection, field/source provenance and resume fingerprints.
It passed 302 native Linux tests, source build, format, warnings-as-errors compile,
native demo and documentation target/anchor checks. Main integration follows the
shared-skills trial and P17; packaged/hosted checks remain separate. See
[operator configuration](operator/configuration.md).

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
   Proposed same-name precedence: project `.agents/skills` > Ipse-specific
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
the model-profile feature branch: bounded named profiles, main/routine/review
roles, conservative Responses effort mapping and selected-profile child isolation.
The native Linux suite passed 309 tests (14 macOS excluded); a live subscription
`gpt-6.1-sol`/high parent and installed Ollama `qwen3.5:9b` child passed routing,
arithmetic verification and unchanged idle resume. Main/package/hosted integration
checks follow the first self-development increment. See
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

Selected and authorized on 2026-10-16. Native questions are implemented in the
isolated operator-question worktree while the stable shared-skills self-development
trial continues. Fixture/live and bundled checks passed; integration review follows
the first stage. See [contract](developer/operator-questions.md) and
[actual evidence](developer/testing.md#p17-structured-operator-questions-2026-10-16).

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
