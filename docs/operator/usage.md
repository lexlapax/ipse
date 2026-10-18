# Using Ipse

For installation, see the [Arch setup guide](arch-linux.md). For errors, see
[troubleshooting](troubleshooting.md). Commands below run from a source checkout;
with a bundled release, replace `./bin/ipse` with `./ipse`.

## 1. ChatGPT subscription

```sh
./bin/ipse login
./bin/ipse chat --cwd /path/to/your/repository
```

For a disposable coding check, create a scratch workspace:

```sh
IPSE_TRY_DIR=$(mktemp -d)
./bin/ipse chat --provider chatgpt --cwd "$IPSE_TRY_DIR"
```

Ask Ipse to create `hello.exs` that prints `hello`, run it, and summarize the
result. Review each proposed file and shell call before approving it.

One provider response may propose at most 32 tool calls and 2 MiB of arguments;
one operator turn may admit 128 calls and 8 MiB of arguments. Invalid arguments
and denied/preflight calls still count. An excess response starts none of its
calls and ends the turn with a budget error. Review prior outcomes before a new
prompt; continuation of a saved question retains that turn's count.

Provider responses also have finite byte, fragment, event and item limits. A
`Provider stream limit exceeded` error refuses the incomplete answer and executes
none of its tools. Review any text already shown and prior effects before sending
a fresh prompt. This does not trigger a retry or provider/billing change; see the
[response limits](../developer/provider-limits.md#host-response-admission).

Open the printed **Continue with ChatGPT** URL in a browser on the same machine.
Authorize Ipse and ChatGPT plan usage. The app listens on a temporary
`127.0.0.1` callback port. On a remote machine, use a browser/port-forward arrangement
that reaches that loopback listener, or run Ipse locally.

This uses OpenAI's documented [Sign in with ChatGPT for open-source apps](https://developers.openai.com/siwc/token-sharing-open-source),
with dynamic registration, PKCE, state/nonce checking, signed ID-token validation,
and refresh tokens. Inference uses the public Responses API with `store: false`
and `stream: true`. It does not read another application's credentials or call
private ChatGPT backend endpoints.

The default OpenAI model is `gpt-6.1-sol`; use `--model NAME` for a model available
to your account. Plan eligibility, model access, and usage limits apply. Provider
failures never silently switch to paid API billing. This preview retains one
selected account registration. `ipse status` shows it; `ipse logout`
revokes the renewable session where possible and clears local tokens.

Successful reauthorization replaces the locally saved credentials after identity
validation; it does not establish that an older remote grant has been revoked.
The public [profiles and sessions contract](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
specifies revocation on sign-out, without promising older-grant invalidation on
reauthorization. To disconnect a suspected compromised grant, use ChatGPT Settings.

Live browser sign-in, subscription inference, approved coding tools, resume, and
logout passed on Arch with one account; see [verification results](../developer/testing.md).
Live natural-expiry refresh and token rotation also passed on 2026-10-15.
An approved temporary permission-off check returned the live usage-limit error;
Ipse's permission was restored. Exhausted allowance and ineligible accounts remain
unverified; see the [P0 evidence](../developer/testing.md#p0-closure-on-serenity-2026-10-15). Automated
tests cover OAuth validation/refresh and streaming using local fixtures.

Subscription requests follow the current preview format: developer instructions
and an `additional_tools` input item describe local functions. API-provider
requests retain their own wire format. Eligibility and usage-limit failures stop
the turn without retries or a billing change. Errors show bounded status, code,
parameter, body shape, and request ID where available, while provider prose is
omitted to avoid exposing secrets. See [recovery](troubleshooting.md#account-model-and-provider-errors).

## 2. OpenAI API

Set `OPENAI_API_KEY` through your normal secret-management method, then:

```sh
./bin/ipse chat --provider openai --cwd /path/to/repo
./bin/ipse run --provider openai --yes 'Fix the failing test and run it'
```

API requests use API billing, separately from your ChatGPT subscription.
For supported API/Ollama providers, an explicit `--max-output-tokens N` caps each
request; the [configuration guide](configuration.md) defines ranges and lower
adapter limits. Subscription requests reject that unsupported setting instead of
dropping it or switching billing. This is separate from aggregate cost budgets.

## 3. Local Ollama

Start Ollama and pull a model that supports tool calls, for example:

```sh
ollama pull qwen3:8b
./bin/ipse chat --provider ollama --model qwen3:8b
```

Uses `http://localhost:11434/api/chat`. Override its root with
`--base-url http://localhost:11434`. Coding reliability depends on the selected
model and local hardware.

Recorded live checks used the installed `qwen3.5:9b` model for basic tool/stream
acceptance, identity/resume, compaction, native local MCP, and serial/parallel delegation; see
[provider verification status](../developer/testing.md#provider-verification-status).

## 4. Anthropic API

Set `ANTHROPIC_API_KEY`, then:

```sh
./bin/ipse chat --provider anthropic --model claude-sonnet-4-5
```

This explicitly selects Anthropic API billing. Live acceptance with
`claude-haiku-4-5` passed streamed text, an approved tool round trip, continuation,
resume, a provider error, compaction, native local MCP, and serial/parallel delegation on
Arch. Other models/hosts remain separate checks. See
[provider verification status](../developer/testing.md#provider-verification-status).

## Working with the agent

For a project assessment, start with `--cwd` and ask:

```text
Use $project-orientation to explain what this project does and what its next
steps are. Keep the assessment read-only.
```

The bundled skill gathers instructions, implementation, current Git changes, and
available validation before recommending operator provisioning. It distinguishes
local remote-tracking refs from freshly verified external state, preserves
existing edits, and reports failed/skipped/blocked checks. Relevant Git guidance
loads explicitly as a bounded resource. The model can also select this skill
from its catalog; explicit invocation makes the requested workflow clear.
Shell checks still require full approvals. A read-only request does not change
the OS profile into a read-only filesystem sandbox. No GitHub adapter or extra
repository access is introduced by this skill.


The [live project assessment](../developer/testing.md#p11-live-project-assessment-2026-10-15)
used this workflow without changing its target repository. Linux native mode
supports Bash process substitution, while sibling dependency checkouts remain
hidden and host environment variables are not inherited; see
[diagnosis](troubleshooting.md#bash-descriptor-paths-and-sibling-repositories).

Interactive chat asks before `write`, `edit`, and every `shell` call. `--yes`
allows them for the session. Headless `run` denies mutations unless `--yes` is
present. Approvals display the full proposed arguments.

Ipse can request [structured operator clarification](#operator-questions) using
single-choice, multiple-choice or free-text questions. Answers are validated and
journaled separately from action approvals. Ordinary conversational questions
still accept normal user turns; MCP elicitation remains unsupported.

With the default `--sandbox off`, shell execution is trusted local execution. Commands have
your user permissions. The helper clears common provider credential environment
variables, but it cannot prevent authorized commands from reading your files,
credentials on disk, or other ambient secrets. Use a disposable workspace/container
when appropriate. File tools reject symlinks and workspace escapes. Write/edit
reserve `.git` path components across Unicode case and canonical normalization,
also ignoring format controls, combining grapheme joiners and variation selectors.
This conservatively rejects spellings such as `.GIT` even on case-sensitive
filesystems. It does not change shell permissions. These checks do not defend
against a hostile process concurrently replacing filesystem entries.

### Shell policy

To request the fixed native workspace sandbox explicitly:

```sh
./bin/ipse chat --cwd /path/to/project --sandbox native
```

Linux permits workspace/private-temp writes and system tool reads, denies network
access, and clears the command environment. macOS runs the shell through a signed
App Sandbox worker: it permits workspace and sandbox data writes, selected system
reads, and denies network access. Approvals still apply; `--yes` changes approval
policy only. Unsupported OS/kernel policy or failed setup stops the shell call
without retrying outside the sandbox. Linux needs Landlock ABI 6+ and permitted
unprivileged user, mount, network, and PID namespaces. A configured mode is not proof
a command started.

Startup, `/session`, and model context share allowlisted platform-specific
visibility facts. Linux describes the selected workspace, private HOME/TMPDIR,
system roots, job-private descriptor paths, and hidden siblings; macOS describes
its signed App Sandbox and Homebrew read exceptions separately. These are policy
facts, not a claim that a particular command activated enforcement. A failed
lookup means a path is not visible or accessible to that tool; it does not prove
host absence. USER and host environment values are not supplied to native shells.

Root, home directories, protected credential directories, and broad system
workspaces are refused. On both platforms, the workspace must also be separate
from the active application and native helper. For self-development, run an
installed bundle outside the candidate checkout. Native mode requires a prebuilt
helper and refuses hardlinked or group/other-writable helper files.
Secrets already inside the selected workspace remain
accessible. User toolchains/home caches, `/proc`, and network package fetching
may be unavailable. Resource ceilings are per process or real UID, not aggregate
memory/disk quotas. See [native policy and limits](../developer/sandbox.md).
The saved mode is restored on CLI resume; a conflicting mode is refused. Start
a new session to choose a different shell policy.

On macOS, the signed worker and its exact entitlements are validated for each
invocation. Its protected cache is under `IPSE_HOME/sandbox/macos` (or the default
Ipse home), and the selected workspace must not contain the active helper,
application, or cache. Use an installed bundle outside the workspace; a source
checkout whose application files are inside the workspace is refused. Existing
`IPSE_HOME` must be owned by your user with mode `0700`. The cache stops at 32
generations; it does not evict data while detached processes may still use it. Detached
`setsid`/`setpgid` children may survive cancellation or timeout and retain access
to that workspace. The sandbox still confines their filesystem and network
access, but process cleanup is best effort. Sandbox data and its container are
shared by commands for the same workspace; there is no per-command data isolation
or aggregate memory/disk quota. See [native policy and limits](../developer/sandbox.md).
Core/source and fresh-bundle CI passed on Linux x86_64 and macOS arm64. Native
macOS enforcement passed locally on macOS 26.7.2 arm64 and in macOS 14 arm64 CI; see
[native results](../developer/testing.md#macos-native-backend-2026-10-15). Live
subscription checks were on Arch. See [evidence](../developer/testing.md#p4-release-verification-and-protocol-proposal-2026-10-15).
Windows is future work.

### Local delegation

Local child delegation is disabled by default. Enable it explicitly with
`--subagents`; the parent asks before starting a child and forwards each child
mutation proposal for a separate approval. A child uses the configured routine/
review role or explicit profile, otherwise the parent's provider/model. It shares
the workspace and saved workspace-instruction snapshot, but has a
separate private journal and does not receive the parent's conversation or MCP
servers. It cannot delegate recursively. A stopped or interrupted child is
recorded as unknown and is never replayed on resume. Child model calls have
their own bounded budgets, additional to the parent's `--max-steps`. See the
[local subagent guide](subagents.md) for limits, examples, and recovery.

### Chat commands

Chat commands:

| Command | Behavior |
| --- | --- |
| `/skills` | Show available skill metadata |
| `/session` | Show the current session ID and state |
| `/info` | Show local application/provider/model facts without inference |
| `/diagnostics` | Show content-free phase/budget and exact effective-context byte categories |
| `/events off` | Stop selected live feeds and report cleanup uncertainty; no in-session re-enable |
| `/context` | Show saved workspace instruction sources, digests, and diagnostics |
| `/context refresh` | Reload workspace instructions while idle, without inference |
| `/cancel` | Stop current work and clear queued input; started effects may already have happened |
| `/help` | Show commands and options |
| `/exit` | Cancel active work and leave |

The CLI reports running, waiting for approval, finished, failed, and cancelled
states. New messages entered during a turn are queued for the next turn, up to
16 tasks and 1 MiB total queued UTF-8 input; overflow is visibly refused. Each
prompt must be valid UTF-8 and at most 1 MiB both before and after explicit skill
expansion. Admission refusal leaves Session history unchanged. These are accepted
input bounds, not a process-memory quota: trusted operator stdin can allocate a
line or read-ahead messages before admission.
Terminal rendering shows control and invisible format characters as literal
escapes, including in model/tool output and full approval arguments. Ordinary
Unicode, newlines and tabs remain readable; ANSI styling and cursor/clipboard
commands from returned content do not execute. This is a display transformation:
saved messages, tool arguments and provider-native content retain their originals.
JSON commands remain valid JSON and decode to the original field values.
While an action is waiting for approval, the CLI defers model/tool/sibling display
output in a bounded queue (64 events/64 KiB), preserving the actual proposal as
the last approval block. Local commands can reprint that proposal. Deferred events
drain in order before newer display messages after the decision; overflow is
reported. Review the full arguments, then enter the exact `allow CODE` line printed
at the end of that proposal, or `n` to deny. Every proposal gets a fresh random
code; bare `y`/`yes`, incorrect codes and codes from earlier proposals leave it
pending. This keeps input buffered before the real proposal from authorizing it.
Returned text can imitate prompts but cannot select the host's fresh code.
MCP target details remain part of the proposal. EOF still denies pending effects,
and `--yes` retains its explicit session-wide meaning. Programmatic approvals
continue to use their exact Session reference.
An error clears queued input with a visible message, preventing further queued
requests after an account or usage-limit failure. Review the error and send a
fresh task when ready.
`/cancel` also releases cleanly stopped extension-owned text enrollments; a new
task must enroll the selected required consumers again. It does not release
separate embedding handles or confirm uncertain worker cleanup.
`/cancel` clears that queue; input received while cancellation is pending is
explicitly discarded. Send a fresh task after cancellation finishes. Repeated
cancellation requests do not start more work. Inspect the workspace before
retrying an interrupted mutation, because started effects may already have happened.

EOF exits immediately while idle. During work it finishes accepted turns,
including queued input, then exits. Pending and subsequent approvals are denied
after EOF. An error stops further queued work and exits with a failure status;
EOF never authorizes a mutation. `/exit` cancels and leaves immediately.
The UI is a line-oriented terminal client, not a full-screen TUI.


## Saved session listings

```sh
./bin/ipse sessions
./bin/ipse sessions --json
./bin/ipse sessions --json --state-dir /path/to/isolated/sessions
./bin/ipse chat --resume SESSION_ID
./bin/ipse run --resume SESSION_ID --yes 'Continue and check the result'
```

The default listing remains human-readable. `sessions --json` prints one JSON
array sorted by session ID, with exactly `id`, `provider`, `model` and `cwd` on
each entry. Missing metadata fields are `null`; an empty or missing store prints
`[]`. It uses the existing journal listing rules: invalid journals are skipped,
and a truncated final record can be ignored without repairing the file. There
is no authentication, inference, network request or journal mutation. By default
it reads `IPSE_HOME/sessions` (normally `~/.ipse/sessions`); `--state-dir` selects
another store. `--json` applies only to `sessions`, not other commands. It does
not export conversations or other metadata, but the allowed fields can still
contain private workspace paths or model names; review output before sharing.

Resume keeps the original workspace, provider, and model. It reconstructs history
without replaying tools. Saved not-started results retain their status and reason;
unmatched calls without a recorded result are conservatively reconstructed as
unknown. A partially written final journal record can be repaired under the
session lock. Full transcripts remain on disk, including tool output.

For a fresh conversation after a retained-context refusal, explicitly import an
operator-reviewed recovery artifact instead of resuming the old history:

```sh
./bin/ipse chat --handoff /private/path/handoff.json --cwd /path/to/repo
```

This is fresh interactive chat only: do not combine `--handoff` with `--resume`,
`run`, `demo` or another command. The closed version-1 artifact is validated before
authentication/session creation (16 KiB total, 8192-byte verbatim note). Import
adds attributed untrusted historical context and stays idle until you type a
fresh prompt. It transfers no provider, approval, tool or native continuation
state and never replays source calls. The new journal retains the validated
artifact, so later normal resume does not need its original file. Inspect unknown
effects before retrying; see [recovery and artifact limits](recovery.md).

## Context compaction

Ipse automatically attempts context reduction above 80% of its default
400,000-byte ceiling. It reports compaction and before/after sizes. The preferred
older-turn summary adds a request to the selected provider/model and consumes
its normal usage. If that cannot be planned, a deterministic older-tool-output
reduction makes no model request. Neither switches provider or billing mode. Original transcripts stay in the journal.
The summary path retains the latest two user turns in full. The output fallback
can operate within one turn: it keeps all user requests, provider continuation
fields, exact calls, approval/outcome metadata, and the newest two tool-call
batches. Older settled outputs over 4 KiB become marked beginning/end excerpts
with original byte counts and hashes. Full results remain in the journal. Model summaries can be incomplete or incorrect, so inspect files
and original results before repeating effects.

Use `--context-bytes N` to adjust the conservative ceiling (minimum 8192), or
`--no-compact` to stop at the ceiling without either reduction path. `/cancel` also stops
an active compaction. These settings can be supplied again when resuming.
If retained history or a valid summary cannot fit, Ipse stops with a specific
planning/validation diagnosis; provider-summary failures show a safe generic
message. User text, native payloads, arguments, or newest results can still
prevent reduction, even during a long single turn.
Inspect the journal and actual tool effects first. A short continuation may make
an older completed turn eligible, as in the
[task-tracker trial](../developer/testing.md#p12-task-tracker-coding-trial-2026-10-15);
it does not authorize or require repeating completed effects. If retained
history still cannot fit, supply necessary context to a new session or explicitly
choose a suitable `--context-bytes` ceiling. Compaction is not unlimited memory
or a provider token-count guarantee.


## Request accounting

`/diagnostics`, `/session` and saved `ipse diagnose` show durable normalized
[usage facts](usage-accounting.md), request/parent identities and unknown
outcomes. They do not calculate an invoice or enforce a spend budget. Optional
operator [shared budgets](budgets.md) reserve covered main/summary/child requests;
inspect that separate ledger with `ipse budget --resume ID` and the matching
`--state-dir` when customized. Unknown liability is retained across resume.

## Runtime identity


In chat, `/info` reports the running Ipse application version, configured
provider, requested model, last provider-reported model in this run, and the
saved session's last reported model when resuming. It is available during work
and approval, sends no model request, and exposes no credential configuration.
These allowlisted facts also enter the model's host instructions on every turn.

The requested model comes from `--model`, `IPSE_MODEL`, or the provider default.
A provider-reported identifier may differ from that request or be absent. It
identifies a response, not a guarantee about the next response or an exact
backend revision. Aliases remain aliases. Saved response metadata is historical;
current-run metadata begins unavailable on resume. Older journals without this
metadata remain resumable and show unavailable. The application version always
comes from the running application, not an old journal. `/info` is authoritative
for these host facts; a natural-language self-description can still be wrong.

## Skills


Skills are discovered in place (no copying or installation), in this same-name
precedence order:

1. Project `.agents/skills/<name>/SKILL.md`
2. Ipse user `IPSE_HOME/skills/<name>/SKILL.md` (default `~/.ipse/skills`)
3. Shared operator `~/.agents/skills/<name>/SKILL.md`
4. Bundled skills

The shared operator home comes from `HOME` (VM user home fallback), independently
of `IPSE_HOME`. Redirecting Ipse data/auth with `IPSE_HOME` does not relocate the
CLI's shared skill root. Discovery never changes authentication or writes shared
installations. `ipse skills` and `/skills` report the selected source, SHA-256,
and shadowed paths. Canonical-file aliases are deduplicated rather than reported
as separate shadows. Selection is deterministic; malformed/oversized/invalid
UTF-8 documents are skipped. `review` and `project-orientation` are bundled.
Use the latter for [project assessment](#working-with-the-agent).

`$self-development` supplies a reusable supervised change/review/evidence procedure
with explicitly loaded supporting resources; see [self-development](self-development.md).
It grants no publication, installation or action permission.

For embedding and isolated fixtures, see the explicit root inputs and session
isolation rules in the [developer contract](../developer/architecture.md#skill-discovery).
[Scoped configuration](configuration.md) loads operator/project/directory JSON
separately from skill discovery, with explicit project trust and no effect grants.

```markdown
---
name: review
description: Review changes for correctness and missing tests.
---

Read the diff and surrounding code. Report actionable findings with file locations.
```

Version 0.1 accepts simple single-line frontmatter values for name and description,
not full YAML or arbitrary skill metadata. Skill documents are bounded to 64 KiB.
Metadata discovery and skill loads can follow filesystem symlinks; canonical
identity deduplicates aliases, but is not an installation trust check or a
race-proof filesystem boundary. Resource loading remains stricter: the selected
skill directory and resource entries cannot be symlinks (root-path aliases such
as macOS `/var` are canonicalized). Discovery does not establish compatibility
with every shared skill format or authorize referenced scripts.
Only metadata enters the initial context. The model can call `load_skill`; `$review`
explicitly loads a skill into the next user turn. Loaded content includes its path
and SHA-256. No script is executed by loading a skill, and skills grant no permissions.
Repository instructions use a saved, bounded workspace snapshot. See
[workspace instructions](#workspace-instructions) below.
Supporting text loads explicitly through `load_skill_resource` with a discovered
skill name and a skill-relative path, including user/bundled skills outside the
workspace. Each read is limited to 32 KiB and eight path components. Absolute,
escaping, symlink, credential-path, invalid UTF-8, and oversized targets are
rejected with a diagnostic. Resource links do not load recursively and script
text never executes. The bundled review skill uses `references/checklist.md`.
Results include source and SHA-256 and stay in the journal; resume retains the
saved contents instead of silently rereading changed resources. Ordinary context
compaction still applies. See [the developer contract](../developer/architecture.md#skill-resources).

## Workspace instructions

Run Ipse from the directory where you want it to work, or choose `--cwd PATH`.
Ipse-wide state and skills stay under `~/.ipse` (or `IPSE_HOME`). Optional
`~/.ipse/AGENTS.md` supplies instruction defaults; it cannot change provider,
billing, or approval settings.

Within a Git repository, applicable `AGENTS.md` files load from the nearest
repository boundary to the selected directory. Outside a repository, discovery
stops at the selected directory. Nearer project instructions override broader
guidance, and explicit user requests take precedence. The workspace's README
and one level of local text references also supply bounded context. Sources are
limited to 32 KiB each, 16 sources, and 128 KiB total; omitted invalid or oversized
sources produce diagnostics. Symlink and sensitive-path sources are excluded.

`/context` shows instruction and selected skill paths, scopes, SHA-256 digests,
and diagnostics. `/skills` lists the session's saved catalog; standalone `ipse skills`
discovers the current filesystem. Resume keeps saved instruction contents and
skill selection and reports detected drift. Changed skill bodies refuse loading
until refresh. To adopt changed files or newly shadowing skills, finish or cancel
active work and use `/context refresh`, which reloads instructions and skills. Refresh neither
executes tools nor changes approval settings. Journals retain instruction text;
treat them as private session data.

Instructions, skill metadata and extension contributions are labelled reference
context in a user-role message. Only core-owned rules occupy the system message.
Reference text grants no tool permission and is not a new operator request.

For deeper file-tool targets, Ipse checks the path and discovers applicable
nested instructions before starting the call or requesting approval. A refused
path/context check returns the specific reason on that call and asks the model to
check its target path and workspace guidance. Later queued calls receive only a
generic stopped-before-start result, not the first path's failure. These results
mean `not_started` and approval `not_decided`, not that a read ran or an effect
has an unknown outcome.

Newly discovered guidance is saved before reconsideration. The next model request
includes that context and an explicit review-before-retry reason for the affected
call; the old proposals remain unexecuted. Any revised mutation still needs its
own approval under the current policy. Better diagnostic text does not guarantee
that the model will successfully replan. Saved results retain the reasons on
restoration, and idle resume never retries the calls. By contrast, an actually
started effect interrupted without a result remains unknown; inspect its effects
before explicitly retrying.

Arbitrary shell commands can target directories indirectly; the host cannot infer
every applicable scope. Review deeper guidance and full shell arguments before
approving. See the [context contract](../developer/workspace-context.md) for
discovery, persistence, and boundary details.

## Runtime and limits

Ipse's harness is implemented in Elixir/OTP with Rust OS helpers. Projects and
tasks handled by it may use other languages and installed tools, including
TypeScript/Node or Python; the harness's implementation restrictions are not a
project-language policy. A neutral forms/SQLite trial selected Python/Flask and
passed independent app checks; see [coding evidence](../developer/testing.md#p13-neutral-stack-coding-trial-2026-10-16).
The CLI help and host role describe general-purpose tasks; the current
bundled tools mainly serve local file/project work. A bounded synthetic
document-planning trial passed, including source reconciliation and an approved
artifact write; this does not establish arbitrary task coverage.

For document tasks, supply explicit workspace-relative source filenames and the
expected artifact/scope. The read tool requires a file path; directory discovery
needs a separately reviewed shell call. Ask for source citations and separate
confirmed facts from pending items. Reading or loading instructions does not
authorize messaging, purchases, or other effects. See [trial evidence](../developer/testing.md#p13-non-coding-document-trial-2026-10-16).

One GenServer owns a session. Monitored tasks perform provider and tool work;
session death stops them. The Rust helper kills command process groups on timeout
or lost parent connection and provides cross-process session locks. Each shell or
stdio invocation owns an extra inert helper that retains the group identity
through cleanup; abrupt supervisor loss closes its private lease and stops
ordinary children. This does not capture deliberately detached descendants.
Independent
sessions can run concurrently; tools within a turn execute sequentially.

Credentials are stored separately from journals in owner-only files. Default
application data is under `~/.ipse`; override with `IPSE_HOME`.
Use `--state-dir` to override journal storage and its associated budget-ledger
location; it does not relocate credentials or extension artifacts/state.
Mandatory finite journal limits are separate from the active context window;
operator configuration can lower them. Exhaustion seals the file, preserving
read-only diagnosis/handoff without allowing ordinary resume or automatic retry.
See [journal configuration](configuration.md) and [recovery](recovery.md).
Session events contain no
injected provider credentials, but user prompts and tool output may contain secrets
and are retained locally. Native continuation/reasoning data is preserved when
required by the provider; raw hidden reasoning is not exposed in the UI.

Current limits: 30 model calls per turn by default (`--max-steps`), bounded file and
shell output, and a conservative conversation byte ceiling with bounded
[automatic compaction](#context-compaction). Explicit stdio and Streamable HTTP MCP can expose
allowlisted tools, exact-URI text resources, and named prompts. Local MCP servers
have their own `off` or `native` sandbox setting, separate from shell `--sandbox`.
HTTP endpoints use verified TLS and optional server-specific bearer credentials;
remote effects cannot be confined or cancelled by the local sandbox;
see the [MCP guide](mcp.md) for allowlist, schema, and platform limits. **Full-screen
TUI, remote agents, and Windows are not implemented.** Local
delegation is opt-in and serial by default; two-child parallel mode uses
`--subagents --subagent-concurrency 2`. Children do not inherit MCP servers. See
[local subagents](subagents.md). Uncompactable
context stops with an actionable message rather than silently dropping history. Skills with scripts requiring Node/Python do not
make those runtimes dependencies of Ipse.

Authentication and provider requests share a bounded limit of 64 simultaneous
HTTP clients per running Ipse application. If clients are busy, retry after
another request finishes. Each request's connection and proxy state is isolated.

## Configuration and model routing

Version-1 JSON settings are supported in `IPSE_HOME/config.json` and scoped
project/directory `.ipse/config.json`. Project files require current-run
`--trust-project-config`; `--no-project-config` ignores them. `ipse config` reports
effective non-secret settings and provenance locally, without authentication or
inference. See [configuration](configuration.md) for fields, precedence, examples
and resume behavior. Skills and configuration grant no effect permissions.
Named main/routine/review profiles and documented reasoning effort are available;
see [model profiles](model-profiles.md).

## Operator questions

Interactive chat supports the native `ask_operator` tool with up to three
questions per call. The terminal shows stable option IDs, descriptions and optional
recommendations. Reply using the displayed `answer CODE VALUE` prefix: the value
is one number/ID for a single choice, comma-separated numbers/IDs for multiple
choices, or free text. Each question gets a fresh code; buffered input or an older
code cannot answer the current question. Invalid values keep the current code;
recommendations are never selected or submitted automatically.
For literal slash-command text, the value may keep the `=` escape (for example
`answer CODE =/exit`). `/info` and
`/context` remain local; `/cancel` stops the turn and `/exit` exits.

A complete answer bundle is synced to the private journal before the next model
request. Partial entries in the terminal's multi-question form are not submitted
until all questions are answered. If the session/VM is interrupted while waiting,
resume presents the saved question bundle without restarting inference or tools.
A recorded answer survives interruption; idle resume does not continue inference
automatically. Explicit cancellation/EOF closes the question without an answer.
Neither clarification nor a recommended choice authorizes a file/shell/MCP action.

Headless `run` cannot wait for answers, including with `--yes`: a required question
fails explicitly. A headless attempt to resume a pending question refuses without
changing its checkpoint; resume with interactive chat instead. Local children
currently cannot ask operator questions and must return needed clarification to
the parent; parent question forwarding is not implemented. This capability is
separate from MCP elicitation and from a full-screen or graphical form UI.

Embedded clients receive `{:question, id, arguments}` inside the usual Ipse event
envelope and answer with `Ipse.Session.answer(pid, id, answers)`, where `answers`
maps each question ID to an option ID, a list of IDs, or text. See the
[developer contract](../developer/operator-questions.md) for schema and recovery.

When launched from a bundled release, trusted shell tools use the operator's
remaining PATH after Ipse removes its own bundled ERTS directory and release
launcher variables. This prevents system Mix/Elixir commands from selecting
Ipse's release boot files. It is environment cleanup, not a sandbox guarantee.

## Research

Use `$research` with an explicitly selected compatible MCP search/fetch service.
Native source/claim tools retain auditable evidence in the private session journal
outside compacted model context; `ipse research --resume ID` exports it locally.
No endpoint, credential or fallback search service is embedded. See
[research configuration and limits](research.md); recorded support kinds are
model assessments, not automatic truth or freshness guarantees.

## Extension and debugging roadmap

Use the [extension guide](extensions.md) to import/inspect a reviewed local
artifact, grant its operator capability ceiling and select an instance for a
new session. Two bundled hooks are disabled by default. Independent artifacts
use owned Elixir workers without rebuilding Ipse; project configuration can
select only an operator-approved subset. Import, skills and generated code
grant no trust or action permission.

`/ext` lists active tools/commands/services; `/ext NAME JSON_OBJECT` invokes a
declared operator command while idle, without a model request. Explicitly
negotiated host operations support scoped state, structured questions,
file/shell workflows, operator-bound value services and contextual evidence.
Selected artifacts can also receive separately granted
[read-only prompt and completed-answer events](extensions.md#event-subscribers);
notification replies cannot request effects. Separately admitted
[event jobs](extensions.md#event-jobs) can use normal approved actions for
before-request recall or after-turn maintenance. After-turn work leaves the saved
answer intact and keeps the session busy until that serial lane settles.
Normal mutation approval applies. For selection flags, limits and recovery,
use the [capability procedures](extensions.md#configure-selections).

Temporary selection affects the durable session, not global defaults. Promote
it through an explicit persistent configuration edit after review. Resume pins
exact code/options/configuration identity; changing the catalog requires a
fresh session or reviewed handoff. Separate workers and deadlines are not OS
sandboxing. No live activation, automatic download or build assistant exists.

Local `/diagnostics`, `ipse diagnose --resume ID` and
`ipse handoff --resume ID --note TEXT` support content diagnosis and reviewed
recovery. See [context recovery](recovery.md). Visible text streams in chat;
embedded clients and selected `stream.text` workers use the
[private bounded channel](../developer/text-streams.md).
Default-off [diagnostic capture](observability.md) separately selects metadata sink
workers with `--observability off|local|export`; `/observability off` revokes new
samples immediately. Journals and usage remain active.
Selected [live event feeds](extensions.md#live-event-feeds) enroll on explicit
work with separate bounded queues and durable receipts. `/events off` stops them;
idle resume starts no feed, and incomplete coverage needs explicit catch-up.
Current delivery and remaining work follow this sequence:

| Milestone | Scope | Status and boundary |
| --- | --- | --- |
| P23 | Complete within selected scope | Own-session/child reports, optional [shared reservations](budgets.md) and explicit [extension text calls](extensions.md#accounted-model-calls); source/package/platform gates passed. Context bytes are not tokens or an invoice |
| P24 | Independent architecture validation and baseline security | See the [review checkpoint](architecture-review.md) and [dispositions](../developer/architecture-review-dispositions.md) for current evidence and remaining gates |
| P25 | Larger supervised comparative research/self-development trial | Supervised trial and repair work in progress; patches require independent supervisor review before acceptance |
| P26/P27 | Optional working/long-term memory, research engine, graph and RAG | Production packages deferred pending P25 selection; independently configurable and default-off |
| P28 | STT/text-agent/TTS and realtime media | Deferred former-P24 scope, with explicit device/provider/billing selection; text authentication does not imply audio access |

The [plan](../plan.md) owns milestone acceptance. The
[observability design](../developer/observability.md) separates optional
sanitized diagnostics from mandatory journals/accounting and private content;
no exporter starts automatically. The [knowledge design](../developer/knowledge-extensions.md)
treats Zero-Mem as inspiration, not an installed backend. P22's SDK/proof gates
are complete within their [documented coverage](../developer/lifecycle-events.md#supported-lifecycle-coverage).
Existing skills, configured MCP tools and the research ledger remain available.
Optional memory will not replace ordinary history or make RAG persist personal
records silently.
