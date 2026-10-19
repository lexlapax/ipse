> Historical reference only. Snapshot of `docs/developer/architecture.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../developer/architecture.md).

# Architecture

Ipse is an Apache-2.0-licensed, general-purpose local AI harness built around Elixir
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
cross-process lock policy. A separate `Session.Lock` guardian owns the native
lock Port so untrappable Session death cannot release it before tracked work
stops. Provider and tool work runs in monitored tasks, with events
sent back to the owning session and its CLI subscriber.

Each owned task also has a private `TaskResources` process. Shell helpers,
task-owned advisory locks, independent extension workers and MCP transports register
before dispatch and report their actual native-helper exit. Known pre-spawn
refusals settle their tickets without an OS-cleanup failure; once a helper has
started, only its actual receipt can confirm cleanup. Commands, working directories
and lock paths reject invalid UTF-8 and embedded NUL bytes before launch.
Task completion retains a
single cleanup receipt until Session consumes it. Cancellation closes registered
resources before killing the task, within a shared four-second resource deadline;
missing acknowledgments, resource-owner death and failed closure remain
unconfirmed. Losing the Session stops the scope and its dependent work. These
receipts establish ordinary helper/group cleanup, not containment of detached
descendants or a guarantee against uninterruptible kernel IO.
Nested workflow tool, helper-model and history tasks inherit the outer cleanup
scope through `TaskResources.async/1` and wait at a tracking barrier before their
function runs. The lock guardian monitors the writer, root/nested workers, scopes,
registered resource actors, admitted filesystem completion owners and delegated
child guards. `FileEffect` lets core filesystem critical sections finish without
killing their IO owner; BEAM `DOWN` alone does not fence dirty IO. Budget and state
locks remain owned by that completion process through their critical section.
On Session death the guardian kills
workers promptly, asks scopes to drain and waits for actual process exits before
unlocking. Normal cancellation first obtains OS-helper receipts, then terminates
nested task processes; reversing that order loses the receipt. Ordinary
`Task.async/1` does not carry this binding or tracking contract.
Before attachment, the new task monitors both Session and scope while waiting
at its dispatch barrier. If either disappears, it exits without dispatch; after
readiness, the attached scope owns cleanup. This covers creation as well as
already-running work.

The CLI registers itself as the root Session's owner; loss stops the Session and
dependent work through the existing owner monitor. Request-call exits are caught
without displaying private reasons. The client stops its reader, reports an
unconfirmed acknowledgment, attempts bounded close and exits nonzero without
retrying an approval/cancel/prompt. A timeout cannot establish that a request had
no effect. Sequential cleanup and durable IO can still outlast the caller's
deadline, so cleanup confirmation remains a separate result; see
[operator recovery](../operator/recovery.md).

`Ipse.CLI.Terminal` escapes terminal controls and invisible format characters at
every CLI-owned output write, preserving ordinary Unicode/newline/tab display.
Its visible escapes also retain JSON round-trip values, including supplementary
format characters. Encoding-aware writes preserve UTF-8 values on Unicode and
latin1 IO devices, including the installed verifier's restricted locale. Source
messages, arguments and native/provider data are not rewritten. The client retains
the actual pending approval's reference, name, full arguments and any MCP target
manifest. While it is pending, sibling display events wait in a bounded queue
(64 events/64 KiB); overflow is visibly counted after the decision. Local commands
can redraw the complete proposal. This keeps the real approval last without
per-chunk amplification of its full arguments.
After the decision, the client drains saved display events in arrival order
before receiving newer mailbox output, without sending them back to its mailbox.
Returned prose remains untrusted; the renderer does not authenticate its contents.

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
                                      └── durable append writer ──> private JSONL journal
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
cleanup, including registered task-owned OS resources. Child PID death alone cannot manufacture completion; idle resume
starts no child and replays no effect.

`Ipse.Provider` selects a provider adapter. Adapters stream text and
normalized tool calls into the session; provider-specific continuation data is
kept where needed to resume a provider exchange. The session enforces a
per-turn model-call limit and runs tools sequentially. It does not use a fixed
plan/execute workflow or require a graph framework.

Separately trusted extensions can request bounded one-shot text inference through
`host.model` using a named profile. Session owns the additional egress approval,
model step and canonical admission; a linked task resolves the selected provider's
credentials and performs IO. Only bounded text and normalized usage return to the
worker. Private native responses remain separate from the main conversation, and
these helper requests share any configured tree budget. See
[accounted extension model calls](extension-model-calls.md) for routing, cancellation
and source-bound recovery.

Before dispatch, Session journals a correlated request admission. Normalized
usage observations and final/partial/unknown outcomes remain durable even when
a summary is rejected or a request fails. [Request accounting](usage-accounting.md)
is mandatory and independent of optional tracing; pricing/budget policy remains
separate. The [private text channel](text-streams.md) carries only visible output
with bounded acknowledgments/pressure. Session fragments large valid provider
deltas into sequential bounded UTF-8 pushes before forwarding the original UI
delta; direct broker limits and saved responses do not change.
Its chunks/subscriptions are ephemeral,
while completed assistant/native data and accounting stay in the journal.
Optional [v2 event sources](stream-events.md) identify broker epochs and accepted
stream byte ranges independently of consumer-local delivery sequence. V1 remains
unchanged; neither channel supplies history replay or playback confirmation.

`Ipse.HTTPProfile` owns per-request HTTP lifetimes for authentication, providers,
and network MCP. Authentication and inference use existing Finch streaming callbacks for every
HTTP status; MCP uses Req with Finch. Authentication caps responses at 1 MiB
before accumulation, inference at 8 MiB, with verified TLS and one shared proxy
selection policy. Literal 127/8 addresses bypass the proxy; similarly prefixed
hostnames do not. Explicit operator NO_PROXY rules still apply.
A monitored guardian retains the private client lease through borrower and pool
shutdown. Before a Finch client is disclosed, its guardian also monitors the
direct supervised children. Abrupt top-supervisor death does not establish that
its named registries/pools have exited; those children must stop before the slot
is released. Pool-supervisor loss still kills the borrower and stops a provider
Session conservatively. Explicit idle resume is the recovery path, without replay.
Guardians in an owned task also join its cleanup scope, so cancellation
waits for the borrower and pool before confirming local cleanup. MCP allocates
the guardian lease before starting its request task; close never depends on a
later registry lookup succeeding. Another request cannot reuse the name during
shutdown. A fixed pool of 64 names
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
Project trust cannot set profile endpoints or replace operator-declared profile
IDs; endpoint authority remains with the operator. Helper egress approvals derive
their visible origin/target digest from the actual adapter route. Main Session
metadata also pins that non-secret destination before the first request, including
a CLI `--base-url`; changing or dropping the endpoint refuses resume. Legacy
compatibility and recovery are specified in [configuration](configuration.md).
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

Identity-token parsing bounds token/segment sizes and JWKS cardinality before
verification. RSA public moduli are limited to 2048–8192 bits, with minimally
encoded positive components, an odd exponent ≥3 that fits in 32 bits, and a signature matching
the modulus length. These are local resource limits, not live account coverage.

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
Credential contention retries the native lock refusal within its existing
deadline. Failed helper cleanup uses idempotent Port closure so a helper exiting
after its error frame cannot replace that retryable refusal with a cleanup
exception. No credential exchange or record mutation runs without the OS lock.
Browser login waiting releases it; callback processing reacquires it and compares
the complete saved record before exchanging a code. Successful login and logout
advance a protected authorization epoch, including logout before the first token
exists. Refresh/logout during a pending login invalidate that old callback.

Reauthorization replaces local protected credentials only after validation. The
public [profiles and sessions contract](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
requires revocation on sign-out but does not define invalidation of older remote
grants on replacement. Ipse does not assume that property or revoke an older token
after activating new credentials; the effect on the new grant is unspecified.
Remote disconnection remains an explicit operator action in ChatGPT Settings.

`Provider.Error` formats bounded machine metadata and fixed recovery guidance,
without echoing server prose. The subscription adapter uses developer messages
and an `additional_tools` item, preserving native continuation data; the API route
keeps its existing wire shape. Subscription endpoints are pinned below the CLI;
only test-compiled code permits loopback fixtures. Provider errors redact the
active credential and stop the turn; the CLI clears queued requests visibly.
All HTTP provider adapters enforce an 8 MiB response-consumption ceiling across
success, error and redirect statuses, including chunked responses, before
adapter parsing or error-body accumulation. A larger declared Content-Length is
refused at the headers; otherwise received chunks count toward the same ceiling.
Internal callers can select a smaller positive `max_response_bytes`
ceiling; extension helper calls retain their 64 KiB limit. Oversized responses
stop without admitting an assistant response or tools, and are not retried.
Error formatting retains only a bounded prefix. Requests disable automatic
redirects and retries and request identity encoding. This bounds accumulated
adapter/parser data, not the HTTP client's instantaneous
network buffers or OS memory. It is separate from model token caps and cost budgets.

## Trust and side effects

The system message contains core-owned rules and runtime facts. A separate
labelled user-role reference message contains workspace instructions, selected
skill metadata and extension contributions, encoded as untrusted data rather
than a new operator request. Both messages count toward the context ceiling.
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
workspace escapes, and writes under reserved `.git` components. `Tools.path_key/1`
compares canonical Unicode normalization and case-folded names after removing
format controls, combining grapheme joiners and variation selectors; the same key
protects parallel child mutation claims. These comparisons conservatively reject
aliases even on case-sensitive volumes and never rewrite execution/approval paths.
They address case/normalization aliases, not arbitrary filesystem equivalence or
concurrent path replacement. See [delegation](delegation.md) for the shared-workspace
boundary. Interactive chat asks
before writes and shell execution. Headless mode denies mutations unless
`--yes` is supplied. Approval controls agent-directed calls only. Shell
commands default to the user's OS permissions. Explicit `--sandbox native`
requests the fixed Linux or macOS workspace profile and fails closed when unavailable;
see the [native boundary](sandbox.md).

In default trusted mode, the Rust helper launches `/bin/sh -c` in a process group, streams bounded
output, and kills the group on timeout or loss of its parent pipe. A separate
inert helper anchors that group's identity until cleanup clears every signaling
slot and reaps it; shell, stdio and native Mac signature checks share the
[group lifetime contract](../../../../../native/README.md#process-group-identity-and-lifetime).
The supervisor's private lease also stops ordinary children after abrupt helper
death. This adds one owned OS process per invocation, with no package or daemon.
It removes
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
hardlink deduplication. Sessions checkpoint selected metadata and retain it on
resume. `load/2` verifies the canonical path and discovery-time digest before
returning bytes; changed sources require explicit `/context refresh`. Skill-resource
loads recheck that same selected entrypoint. See [snapshot/refresh bounds](workspace-context.md#persistence-and-refresh).

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
| One-shot text inference | Named profile, full egress approval, owned provider IO, private native receipts, canonical usage and source-bound recovery | [Model calls](extension-model-calls.md) |
| Value-service composition | Operator routes, acyclic dependency identities, target lease/schema/cleanup checks and host provenance | [Services](extension-services.md) |
| Session context | Bounded caller-owned sets, assertion/receipt provenance and exact main-request snapshots | [Context](extension-context.md) |
| Accounting reads | Caller/session-bound pages and separately granted registered-child prefixes; owned IO/locks, exact origin, content exclusion and cached/source validation | [Usage read SDK](usage-accounting.md#extension-accounting-reads) |
| Shared model admission | Operator policy, durable atomic main/summary/child/helper reservations, retained unknown liability and pre-repair source checks; independent of extension reports | [Budget contract](budgets.md) |
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

Each JSONL journal has one Session owner and an owned append process. The Rust
helper's persistent advisory lock excludes other sessions; its inode remains in
place. The lock guardian outlives an abruptly killed Session and retains the Port
until its tracked writer/workers, cleanup scopes and resource/child guards exit.
This is local process quiescence, not confirmation of remote effects or detached
descendant containment. Uninterruptible IO can keep the lock held past caller
deadlines. Loss of the lock helper or guardian stops Session without further
journal appends. The writer validates history when opening, then encodes and fsyncs new
records without decoding all prior events. Session waits for durable acknowledgment
before effects or source publication. File changes and writer loss fail closed;
normal or abrupt owner loss closes the writer. The
[persistence contract](persistence.md) specifies guards, ownership, stateless
read/append APIs and remaining storage/growth limits.

Resume reconstructs history without replaying tool calls. Started interrupted
calls are marked with an unknown outcome because their external effects may
already have happened. Calls cancelled before launch
are recorded as not started; older unresolved history remains conservative.
Malformed or duplicate tool-call identities refuse the entire new response
before approval or dispatch. A private `provider_response_refused` record retains
the original response/native evidence without placing invalid calls in effective
context or pretending to settle them. Historical duplicate IDs consume recorded
results once, in order; an unresolved duplicate cannot inherit another call's result.

Tool admission also caps each provider response at 32 calls and 2 MiB of argument
bytes, and each operator turn at 128 calls and 8 MiB of argument bytes. Admission
charges all proposed calls before any dispatch, including malformed arguments,
denials and context preflights. An excess response is refused whole; earlier
effects retain their recorded outcomes. The current turn's budget is reconstructed
from restored conversation, including question continuation. A new operator
prompt resets it. These bounds supplement model steps, individual tool/result
limits and cancellation; result amplification is bounded by the admitted count.

Lost shell supervision, malformed/incomplete helper frames and unexpected tool
worker exceptions have an unknown machine-readable outcome. Explicit validation
and pre-dispatch setup refusals remain known errors; a failed file write is
conservatively unknown because truncation or partial writes may have occurred.
The [native protocol](../../../../../native/README.md) distinguishes those boundaries.
A final partial journal record may be repaired while holding the session lock.
The full transcript remains on disk.

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
