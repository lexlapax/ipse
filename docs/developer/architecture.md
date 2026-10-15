# Architecture

Ipse is an MIT-licensed, local coding agent built around Elixir and OTP.
The core agent loop, provider adapters, tool policy, skills, authentication, and
session journal are Elixir. A small Rust standard-library helper owns shell
process groups and advisory session locks. There is no JavaScript or Python
runtime dependency, and no required workflow framework.

The project's name reflects continuity and feedback; its philosophical origin
and limits are explained in [naming.md](../naming.md).

## Current shape

The OTP application starts a unique `Registry`, a `Task.Supervisor`, and a
`DynamicSupervisor` for independent sessions. The CLI is a thin terminal client
and can also start the deterministic, credential-free demo. A session is one
`GenServer`; it owns the conversation, active job, approval state, usage, and
cross-process lock. Provider and tool work runs in monitored tasks, with events
sent back to the owning session and its CLI subscriber.

```text
CLI ──prompt / approval / cancel──> Session GenServer
                                      │
                                      ├── supervised turn task ──> Provider adapter
                                      │                              ├─ ChatGPT/OpenAI
                                      │                              ├─ Ollama
                                      │                              └─ Anthropic
                                      ├── sequential tool calls ──> read/write/edit
                                      │                          └─ shell ──> Rust helper
                                      └── append events ──> private JSONL journal
```

When explicitly enabled, `Ipse.Delegation.Worker` starts one child `Session`
at a time. Each child has a separate journal and receives only the selected task,
context, and saved workspace snapshot. Required child mutation approvals return
through the parent session. The child uses the same provider/model and shared
workspace; it does not inherit MCP servers or parent conversation history. See
the [delegation contract](delegation.md).

`Ipse.Provider` selects a provider adapter. Adapters stream text and
normalized tool calls into the session; provider-specific continuation data is
kept where needed to resume a provider exchange. The session enforces a
per-turn model-call limit and runs tools sequentially. It does not use a fixed
plan/execute workflow or require a graph framework.

`Ipse.HTTPProfile` owns per-request HTTP lifetimes for authentication and
providers. A monitored guardian starts each standalone OTP profile and retains
its lease until the profile exits. Borrower death closes its profile and sockets;
another request cannot reuse the name during shutdown. A fixed pool of 64 names
bounds atom usage and keeps proxy settings and connection state isolated between
concurrent requests. Exhaustion returns a retryable error instead of creating
unbounded profile names.

## Context compaction

`Ipse.Compaction` builds bounded summary requests and validates checkpoints;
Session owns the extra provider task and journal commit. It preserves verbatim
older user intent, host-written action/approval provenance, and the latest two
user turns including native continuation data. Summaries remain untrusted data.
A synced checkpoint changes only the effective projection; original transcript
events stay intact. Resume validates the covered prefix and restores without
automatically restarting inference or tools. Cancellation saves no partial
checkpoint. See [the compaction contract](context-compaction.md) for thresholds,
schema, recovery, and fidelity limits.

## Runtime identity


`Ipse.RuntimeInfo` is a small shared formatter and allowlisted snapshot builder.
`Session.info/1` exposes it under `runtime`; `/info` formats that snapshot locally.
The context builder formats the same facts for every model call. Application
version is read from OTP application metadata. Configured provider/requested
model come from the session configuration; configuration maps and credentials
are never interpolated wholesale.

Adapters retain optional validated `reported_model` in existing assistant
`provider_data`, without changing their result tuples or continuation formats.
Identifiers are bounded to 200 ASCII bytes and exclude whitespace/control text.
The session tracks the last successful response in the active run separately
from the last saved assistant response on resume. Missing metadata remains
unavailable; it does not fall back to an older reported model or overwrite the
requested model. Original journals without this optional field still work.
A reported identifier is provider data, not evidence of an exact backend revision.
No plugins, answer rewriting, extra model requests, or dependencies are needed.

## Trust and side effects


The system message describes the workspace and available skill metadata.
Project skills override user and bundled skills. A skill is plain instruction
text: loading it never executes scripts and does not grant tool permission.
`AGENTS.md` is also included when present. Explicit `$skill-name` references
load the matching skill into the user turn.
`WorkspaceContext` builds bounded, provenance-bearing snapshots from global
defaults, applicable repository instructions, README, and local references.
Sessions journal snapshots, retain saved contents on resume, and explicitly
refresh while idle. New nested file scopes force pending proposals to return
without execution so the model can reconsider them. See the
[workspace context contract](workspace-context.md), including shell-scope limits.

Reads and mutations use workspace-relative tools. Path checks reject symlinks,
workspace escapes, and writes under `.git`; these checks are not race-proof
against a hostile process changing paths concurrently. Interactive chat asks
before writes and shell execution. Headless mode denies mutations unless
`--yes` is supplied. Approval controls agent-directed calls only. Shell
commands default to the user's OS permissions. Explicit `--sandbox native`
requests the fixed Linux or macOS workspace profile and fails closed when unavailable;
see the [native boundary](sandbox.md).

In default trusted mode, the Rust helper launches `/bin/sh -c` in a process group, streams bounded
output, and kills the group on timeout or loss of its parent pipe. It removes
common provider-token environment variables, but other inherited environment
values and files remain accessible. A deliberately adversarial process can
escape the process group. On macOS, the signed App Sandbox worker enforces file
and network boundaries, while cleanup of detached descendants is best effort;
they may survive cancellation or timeout with workspace access. See
[native policy](sandbox.md) and [actual checks](testing.md#macos-native-backend-2026-10-15).

## Persistence and recovery

The default application home is `~/.ipse` and can be changed with
`IPSE_HOME`. Owner-only credential files are kept separately from session
journals; journals contain prompts, tool arguments, and results, so those may
include user secrets. A state directory can be overridden with `--state-dir`.

Each session journal is JSONL. The Rust helper provides a persistent advisory
lock whose lifetime follows its Port owner; lock files are kept to preserve
inode identity. Resume loads events into conversation history without replaying
tool calls. Started interrupted calls are marked with an unknown outcome because
their external effects may already have happened. Calls cancelled before launch
are recorded as not started; older unresolved history remains conservative. A final partial record may be
repaired while holding the session lock. The full transcript remains on disk.

## Boundaries and current limits

The line-oriented terminal client is not a full-screen TUI. Explicit opt-in
serial local delegation is implemented with bounded child sessions; parallel,
recursive, and remote agents are not implemented. Network MCP and Windows are
also unsupported. Native Linux and macOS sandbox profiles are optional. macOS
does not provide reliable cleanup for descendants that detach from the process
group; its filesystem and network enforcement do not make those descendants
short-lived. See [native policy](sandbox.md).
Automatic compaction attempts to retain useful history within the context byte
ceiling. If no safe checkpoint fits, the session stops with recovery guidance
and keeps the original journal.

ChatGPT subscription sign-in follows the documented open-source app flow.
Browser sign-in, inference, coding tools, resume, and logout passed with one
account on Arch; natural-expiry refresh and rotation also passed on 2026-10-15.
See [testing.md](testing.md#p0-closure-on-serenity-2026-10-15). A permission-off
request returned the live usage-limit error. Exhausted allowance and broader
account/model eligibility remain unverified; fixtures do not establish those
live-service properties.

Subscription recovery follows the official
[error contract](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery).
`Auth.HTTP` recognizes a fixed allowlist of terminal OAuth errors on client-error
responses. Under the credential lock, `Auth` clears the unusable token fields
and retains the host/client/account mapping for reauthorization. Rate limits,
service errors, malformed errors, and invalid-client configuration do not erase
credentials. Successful rotation is saved as owner-only pending renewal before
identity discovery/key fetching. Retry validates that saved response without
reusing the consumed refresh token; unverified identities never become active.
Activation preserves the original receipt-time expiry. Reduced scopes are
committed before permission denial. Fresh login replaces pending renewal, and
logout revokes its newest refresh token. Loss before durable storage still
requires fresh login; an expired unvalidated identity also requires fresh login.

`Provider.Error` formats bounded machine metadata and fixed recovery guidance,
without echoing server prose. The subscription adapter uses developer messages
and an `additional_tools` item, preserving native continuation data; the API route
keeps its existing wire shape. Subscription endpoints are pinned below the CLI;
only test-compiled code permits loopback fixtures. Provider errors redact the
active credential and stop the turn; the CLI clears queued requests visibly.

## Extension guidance

Local stdio MCP uses an existing SDK behind the session's approval/journal
boundary. Servers are explicitly configured and allowlisted; discovery and
results grant no permissions. Every external call requires approval. A
registered, session-owned transport uses the Rust helper for bounded pipes and
ordinary process-group cleanup; it is unsandboxed even when the shell uses native
mode. Loss after dispatch stops the batch with an unknown outcome, never an
automatic retry. See the [MCP contract](mcp.md) for ownership, package decisions,
schema limits, and detached-descendant limitations.

Keep provider-specific wire formats inside provider adapters and keep session
state transitions in `Ipse.Session`. Put ordinary filesystem and shell
operations behind the tool boundary. Add new capabilities only with clear
permission and recovery behavior; do not imply that process supervision is an
OS security boundary. Keep Rust limited to OS facilities that OTP cannot
provide directly. Preserve a credential-free demo and tests that do not require
paid model access.
