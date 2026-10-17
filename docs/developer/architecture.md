# Architecture

Ipse is an MIT-licensed, general-purpose local AI harness built around Elixir
and OTP. Session owns conversation, permissions, active work and durable
recovery. Providers, skills, tools and extensions supply capabilities through
that boundary. A small Rust standard-library helper owns OS process groups,
pipes, advisory locks and the explicitly selected native sandbox facilities.

There is no JavaScript/Python runtime dependency or mandatory workflow
framework. These implementation choices do not restrict the languages or
runtimes of target projects. The current bundled tools focus on file/project
work; broader coverage is bounded by the [actual trials](testing.md).

This guide explains ownership and interactions. Topic contracts below own the
detailed schemas and limits; the [documentation map](../index.md) routes
operator procedures, proposals and verification evidence.

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
                                      ├── opt-in owned workers ──> MCP / extensions
                                      ├── opt-in child sessions ──> separate jobs/journals
                                      └── append events ──> private JSONL journal
```

When explicitly enabled, `Ipse.Delegation.Worker` starts serial child sessions by
default. `Ipse.Delegation.Group` coordinates two workers when parallel mode is
explicitly selected. Each child has a separate journal and receives only the
selected task,
context, and saved workspace snapshot. Required child mutation approvals return
through the parent session. The child uses a configured profile/role or inherited
provider/model and shares the workspace; it does not inherit MCP servers or parent conversation history. See
the [delegation contract](delegation.md). Parent-side result receipts bind actual
start sources and distinguish bounded results, unknown work and acknowledged
logical cleanup. Child PID death alone cannot manufacture completion; idle resume
starts no child and replays no effect.

`Ipse.Provider` selects a provider adapter. Adapters stream text and
normalized tool calls into the session; provider-specific continuation data is
kept where needed to resume a provider exchange. The session enforces a
per-turn model-call limit and runs tools sequentially. It does not use a fixed
plan/execute workflow or require a graph framework.

Before dispatch, Session journals a correlated request admission. Normalized
usage observations and final/partial/unknown outcomes remain durable even when
a summary is rejected or a request fails. [Request accounting](usage-accounting.md)
is mandatory and independent of optional tracing; pricing/budget policy remains
separate. The [private text channel](text-streams.md) carries only visible output
with bounded acknowledgments/pressure. Its chunks/subscriptions are ephemeral,
while completed assistant/native data and accounting stay in the journal.
Optional [v2 event sources](stream-events.md) identify broker epochs and accepted
stream byte ranges independently of consumer-local delivery sequence. V1 remains
unchanged; neither channel supplies history replay or playback confirmation.

`Ipse.HTTPProfile` owns per-request HTTP lifetimes for authentication, providers,
and network MCP. A monitored guardian starts a standalone OTP HTTP profile or
private Finch HTTP/1 pool and retains its lease until the client exits. Borrower
death closes its profile and sockets;
another request cannot reuse the name during shutdown. A fixed pool of 64 names
bounds atom usage and keeps proxy settings and connection state isolated between
concurrent requests. Exhaustion returns a retryable error instead of creating
unbounded profile names.

## Configuration and profile boundaries

CLI configuration resolves bounded operator/project/directory JSON through
`Ipse.Config`, requiring current-run project trust. Effective non-secret settings,
source digests, configured profiles/roles and selected execution are persisted and
checked on resume before inference. See [configuration](configuration.md) and
[model profiles](model-profiles.md). `Ipse.Profiles` enforces configured IDs/roles,
documented reasoning capabilities and credential/native-history isolation for
mixed-provider children. Configuration and skills grant no effect permissions.
Shared operator skills use explicit isolation inputs; see
[skill discovery](#skill-discovery).

Bundled trusted shell launches strip the active release's injected ERTS PATH entry
and launcher variables before executing operator tools. This avoids contaminating
an independent installed Erlang/Elixir toolchain. Native execution keeps its own
fixed environment policy. This adds no filesystem or network enforcement claim.

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

`Ipse.Sandbox.visibility/2` supplies fixed platform-specific policy facts;
`describe/2` is shared by CLI startup and model context, and `Session.info/1`
exposes the same list. Facts distinguish requested policy from activation,
hidden paths from host absence, private HOME/TMPDIR from the operator's home,
and minimal shell environment from inherited host state. They contain no
credential/environment dumps and do not grant extra roots. See
[Linux descriptor support and visibility](sandbox.md#observed-bash-and-dependency-visibility-limits).

## Authentication and provider errors

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

## Trust and side effects

The system message describes the workspace and available skill metadata.
Project skills override Ipse user, shared operator, and bundled skills, in that
order. A skill is plain instruction
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

## Skill discovery

`Skills.discover(cwd)` scans project `.agents/skills`, Ipse user skills
(`IPSE_HOME/skills`, default `~/.ipse/skills`), shared operator
`HOME/.agents/skills` (VM user home fallback), then bundled skills. Shared home
is independent of Ipse's data/auth home. Existing `discover(cwd, user_dir)`
callers remain compatible and isolated: this form does not scan a personal
shared root. `discover(cwd, user_dir, operator_home: path)` enables that home's
`.agents/skills`; `shared_root: path` overrides the derived root, and
`shared_root: nil` explicitly disables it. No directories are installed/copied.

Sessions accept `:operator_home` and `:shared_root` in their config. An explicit
`:home` or `IPSE_HOME` without a separate shared-root/operator-home input disables
implicit shared discovery for embedding/fixtures. The CLI explicitly supplies
`Skills.operator_home/0`, so CLI users retain shared discovery when redirecting
`IPSE_HOME`. Delegated children inherit these inputs with their parent config;
this does not redirect auth or add configuration-file loading.

Candidates within a root use wildcard path order; the first valid document for a
metadata name wins in root-priority order, and the result list sorts by name.
Each selected descriptor retains its expanded source `path`, `canonical_path`,
SHA-256 and lower-priority distinct `shadowed_paths`. Catalogs show source,
digest and shadows. Canonical-file identity deduplicates aliases before name
selection; aliases to the same file are not distinct shadows. This is not inode
hardlink deduplication. `load/2` reads current bytes with a fresh digest rather
than pinning the catalog's discovery-time bytes.

Only single-line name/description frontmatter is supported, not full YAML or
arbitrary shared skill metadata. Discovery skips malformed, unreadable, invalid
UTF-8 and over-64-KiB documents. Metadata and skill-body reads retain their
existing symlink-following behavior; canonicalization is not a trust/race-proof
boundary. Resource reads keep their stricter directory/entry symlink exclusions
and 32-KiB bounds below. Skill bodies/resources remain inert until explicitly
loaded; even loading grants no execution, installation or tool permissions.
Tests isolate HOME and IPSE_HOME before default CLI/session discovery.

## Skill resources

`Skills.load_resource/3` resolves one explicit name/path against the selected
discovered skill, preserving project > Ipse user > shared operator > bundled precedence. It reuses
`WorkspaceContext`'s bounded source reader and canonical root checks. Resources
are UTF-8 files of at most 32 KiB, with at most eight relative path components
and a 1024-byte path. Parent traversal, absolute paths, resource symlinks,
credential directories, `.env*`, and private-key extensions are refused. The
selected skill directory itself must be a directory rather than a symlink;
trusted application path aliases are canonicalized before reading beneath it.
These checks do not resist hostile concurrent filesystem replacement.

The `load_skill_resource` tool performs no automatic link traversal, dependency
installation, or execution. It returns exact content, canonical source, and a
SHA-256 digest through ordinary tool journaling. Repeated explicit loads read
current bytes and report the current digest. Idle resume uses saved messages,
including the old resource result, without rereading disk. Normal bounded
context/checkpoint rules apply; full original results stay in the journal.
The bundled review skill's checklist and project-orientation skill's conditional
Git assessment guide use this mechanism. Project orientation is instruction text,
not a project registry or Git/GitHub adapter. It directs the selected provider to
gather relevant implementation, current changes, and validation before operator
steps, while preserving read-only scope when requested. It uses existing read,
approved shell, and skill-resource tools. No automatic execution, additional
roots, dependencies, or mandatory workflow framework is introduced. See
[operator invocation](../operator/usage.md#working-with-the-agent).

## MCP integration

Explicit stdio and Streamable HTTP MCP use an existing SDK behind the session's
approval/journal boundary. Servers are explicitly configured and allowlisted for exact tools,
resource URIs, and prompt names. Discovery and results grant no permissions;
every external call requires approval. Resource text and role-tagged prompt
messages remain untrusted data. A session-owned transport uses the Rust helper
for bounded pipes and ordinary process-group cleanup, or guarded private Finch
pools for network IO. Local per-server MCP sandboxing
is independently selected and fails closed; shell `--sandbox` does not change
the server policy. Loss or RPC failure after dispatch stops the batch with an
unknown outcome, never an automatic retry. See the [MCP contract](mcp.md) for
catalog/schema limits, protocol scope, and platform boundaries.

## Extension guidance

Extensions add explicitly selected behavior through inert declarations and
owned workers. The registry pins artifact, options, source/scope, runtime,
host API and lifetime identity before executable activation. Session owns
capability/schema/lease admission, journals intent before initialization and
commits validated results before continuation. Disabled code never initializes.
Separate VMs and process groups are ownership boundaries, not OS sandboxing.

| Interface | Host responsibility | Contract |
| --- | --- | --- |
| Prompt/presentation transforms | Preserve original input, assistant/native data and source-bound derived projections | [Hooks](extension-hooks.md) |
| Tools/commands/services | Inert namespaced catalogs, argument/result validation, full tool approval and owned invocation receipts | [Invocations](extension-invocations.md) |
| Finite host actions | Separate mutation approval, scoped CAS state and ordered no-replay action receipts | [Host calls](extension-host-calls.md) |
| Questions | Close workers before publication; commit explicit answers and continuation intent before new initialization | [Questions](extension-questions.md) |
| Workflow tools | Existing file/Runner policy, instruction preflight, linked owned tasks and output-completeness facts | [Tool actions](extension-tool-actions.md) |
| Value-service composition | Operator routes, acyclic dependency identities, target lease/schema/cleanup checks and host provenance | [Services](extension-services.md) |
| Session context | Bounded caller-owned sets, assertion/receipt provenance and exact main-request snapshots | [Context](extension-context.md) |
| Accounting reads | Caller/session-bound pages and separately granted registered-child prefixes; owned IO/locks, exact origin, content exclusion and cached/source validation | [Usage read SDK](usage-accounting.md#extension-accounting-reads) |
| Private text consumers | Owned independent workers, opaque resource handles, acknowledged frames and explicit incomplete cleanup | [Text delivery](text-streams.md) |
| Prompt event subscribers | Inert declarations, separate private-view grants, ordered owned notification and source-bound no-replay receipts | [Event delivery](extension-events.md) |

Ordinary returned JSON is data; it never implies another host action. Unknown
outcomes stop without replay. Idle resume validates committed projections and
receipts without loading callbacks or retrieving again. Mandatory instructions,
messages and native continuation remain intact. Domain algorithms belong in
extensions where the supported SDK permits; missing host capabilities require
reviewed general contracts. The [lifecycle foundation](lifecycle-events.md)
uses shared source/event identity across allowlisted committed-fact metadata,
private prompt views and separate delivery
contracts for notifications, ordered hooks and triggered jobs. Event delivery
does not grant effects, and background work cannot change an admitted request.
[Prompt jobs](extension-event-jobs.md) use this contract for finite approved
actions, before-request recall and after-turn maintenance in one serial lane.
Optional [diagnostic capture](observability.md) wraps shared metadata in bounded
owned sink channels, with separate off/local/export policy and immediate stop.
The local sink uses a bounded ring with active-writer locks; backend retention
does not change host event/action APIs. Synthetic developer tracing, selected
private subscriptions/feeds and the [independent installed lab](extension-proof.md)
complete their documented [P22 gates](../plan.md#p22-extension-scaffold-and-lifecycle-hooks).

The internal lifecycle Source/Event adapter now binds committed journal facts to
stable occurrence IDs and projects explicit metadata/private prompt views.
Bounded source pages neither repair tails nor execute/replay callbacks. They
contain private journal records and are not a diagnostic export or worker API;
selected private views are delivered only through separately admitted subscription,
feed or job contracts. Finite effectful prompt/answer jobs use normal approvals;
unsupported views, causal links and concurrent effectful jobs remain explicit
enhancements in the [coverage audit](lifecycle-events.md#supported-lifecycle-coverage).

Keep provider-specific wire formats inside provider adapters and keep session
state transitions in `Ipse.Session`. Put ordinary filesystem and shell
operations behind the tool boundary. Add new capabilities only with clear
permission and recovery behavior; do not imply that process supervision is an
OS security boundary. Keep Rust limited to OS facilities that OTP cannot
provide directly. Preserve a credential-free demo and tests that do not require
paid model access.

## Operator clarification

`Ipse.Questions` reuses the existing bounded JSON Schema adapter for shapes and
adds question/option identity and explicit-answer checks. Session owns pending
questions, emits typed client events and commits answers before continuation.
No model task remains active while waiting. Other proposed batch calls are
settled as not started so the answer can change the plan. Questions are separate
from boolean action approvals and grant no permission. Headless/child requests
fail explicitly. See the [question contract](operator-questions.md) for bounds,
durable restore and terminal behavior. MCP elicitation remains unavailable.

## Research ledger

`Ipse.Research` binds bounded literal source excerpts and claim references to
successful original MCP results. Native bookkeeping stays in private durable
journal events, is revalidated on resume and survives context compaction without
retrieval replay. Call IDs/time are explicit host provenance, while source content
and semantic support assessments remain untrusted. Search services are operator
MCP configuration, never embedded endpoints. See [research contract](research.md).

## Supervised development skill

P20's bundled `self-development` skill and two inert resources compose existing
orientation, questions, profiles, review, diagnostics and approvals. No workflow
engine or executable hook is loaded by the skill. A deterministic provider fixture
loads it and both resources through the real Session/journal with effect policy
denied; the source and extracted-package checks run that fixture explicitly.
Live application is separately verified in P21. See the
[operator procedure](../operator/self-development.md).

## Context compaction

`Ipse.Compaction` builds bounded summary requests and validates checkpoints;
Session owns the extra provider task and journal commit. Summaries preserve older
user intent/action provenance and the latest two user turns including native data.
When summary planning fails, deterministic older settled tool-output excerpts can
reduce a single long turn, preserving all user/native/call/provenance fields and
the newest two call batches. Both paths retain the original journal and validate
durable projections on resume. Summaries and excerpts remain untrusted data.
A synced checkpoint changes only the effective projection; original transcript
events stay intact. Resume validates the covered prefix and restores without
automatically restarting inference or tools. Cancellation saves no partial
checkpoint. See [the compaction contract](context-compaction.md) for thresholds,
schema, recovery, and fidelity limits.

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

Optional [runtime facts](lifecycle-events.md#runtime-epochs-and-operator-waits)
distinguish recorded session epochs and operator waits. Diagnostic capture or a
reviewed extension's `lifecycle.record` capability enrolls them independently of
effect admission. Unclosed epochs/waits remain incomplete after abrupt loss;
resume never synthesizes a successful finish or replays a handler. Logical close
is recorded before process exit and carries only the cleanup confirmation actually
available. No termination callback writes after the lock helper is lost.

Live [scoped feeds](extension-feeds.md) enroll on explicit work and own separate
serial workers. Session syncs source-bound delivery intent before enqueueing and
an exact acknowledgment receipt before releasing capacity. Queue pressure ends
coverage visibly. Feed control records cannot trigger themselves; acknowledgment
grants no effect authority. Source validation preserves question-checkpoint
adjacency, resolves anchors and bounds the source-to-intent scan. Idle resume
restores receipts without starting callbacks or reconstructing a queue.
Opt-in [tool recording](tool-events.md) adds host occurrence IDs for admitted
model-selected executions. Bounded private input/result projections share source
identity with metadata, retain actual request/turn/epoch and intent/result bindings,
and preserve native history. Resumed tool questions retain their original IDs;
duration is unavailable across restart. Unknown/interrupted effects are not replayed.

`ipse sessions` reads listings directly through `Journal.list/1`, without starting
or resuming sessions or authenticating. The default text output is unchanged;
`--json` projects only `id`, `provider`, `model` and `cwd` into one ID-sorted array,
with missing fields encoded as null. It does not export arbitrary metadata or
messages. Empty/missing stores and skipped invalid journals retain the existing
listing behavior, and truncated tails are read without repair. This is a local
read, not a configuration/provider request or journal mutation. See
[operator listing usage](../operator/usage.md#saved-session-listings) and
[local verification](testing.md#p18-macos-supervised-self-development-evidence).

## Boundaries and current limits

The line-oriented terminal client is not a full-screen TUI. Explicit opt-in
serial local delegation is implemented with bounded child sessions and an
explicit two-child parallel mode. Recursive and remote agents are not implemented.
Network MCP supports explicitly configured Streamable HTTP endpoints; see the
[transport contract](mcp.md#streamable-http-boundary). Windows is unsupported.
Native Linux and macOS sandbox profiles are optional. macOS
does not provide reliable cleanup for descendants that detach from the process
group; its filesystem and network enforcement do not make those descendants
short-lived. See [native policy](sandbox.md).
Automatic compaction attempts to retain useful history within the context byte
ceiling. If no safe checkpoint fits, the session stops with recovery guidance
and keeps the original journal.
