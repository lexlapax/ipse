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
acceptance, identity/resume, compaction, native local MCP, and serial delegation; see
[provider verification status](../developer/testing.md#provider-verification-status).

## 4. Anthropic API

Set `ANTHROPIC_API_KEY`, then:

```sh
./bin/ipse chat --provider anthropic --model claude-sonnet-4-5
```

This explicitly selects Anthropic API billing. Live acceptance with
`claude-haiku-4-5` passed streamed text, an approved tool round trip, continuation,
resume, a provider error, compaction, native local MCP, and serial delegation on
Arch. Other models/hosts remain separate checks. See
[provider verification status](../developer/testing.md#provider-verification-status).

## Working with the agent

Interactive chat asks before `write`, `edit`, and every `shell` call. `--yes`
allows them for the session. Headless `run` denies mutations unless `--yes` is
present. Approvals display the full proposed arguments.

With the default `--sandbox off`, shell execution is trusted local execution. Commands have
your user permissions. The helper clears common provider credential environment
variables, but it cannot prevent authorized commands from reading your files,
credentials on disk, or other ambient secrets. Use a disposable workspace/container
when appropriate. File tools reject symlinks and workspace escapes; writes to
`.git` are rejected. These path checks are not a defense against a hostile process
concurrently replacing filesystem entries.

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
unprivileged user, mount, and network namespaces. A configured mode is not proof
a command started.

Root, home directories, protected credential directories, and broad system
workspaces are refused. Secrets already inside the selected workspace remain
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
mutation proposal for a separate approval. A child uses the same provider,
requested model, workspace, and saved workspace-instruction snapshot, but has a
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
| `/context` | Show saved workspace instruction sources, digests, and diagnostics |
| `/context refresh` | Reload workspace instructions while idle, without inference |
| `/cancel` | Stop current work and clear queued input; started effects may already have happened |
| `/help` | Show commands and options |
| `/exit` | Cancel active work and leave |

The CLI reports running, waiting for approval, finished, failed, and cancelled
states. New messages entered during a turn are queued for the next turn.
An error clears queued input with a visible message, preventing further queued
requests after an account or usage-limit failure. Review the error and send a
fresh task when ready.
`/cancel` clears that queue; input received while cancellation is pending is
explicitly discarded. Send a fresh task after cancellation finishes. Repeated
cancellation requests do not start more work. Inspect the workspace before
retrying an interrupted mutation, because started effects may already have happened.

EOF exits immediately while idle. During work it finishes accepted turns,
including queued input, then exits. Pending and subsequent approvals are denied
after EOF. An error stops further queued work and exits with a failure status;
EOF never authorizes a mutation. `/exit` cancels and leaves immediately.
The UI is a line-oriented terminal client, not a full-screen TUI.


```sh
./bin/ipse sessions
./bin/ipse chat --resume SESSION_ID
./bin/ipse run --resume SESSION_ID --yes 'Continue and check the result'
```

Resume keeps the original workspace, provider, and model. It reconstructs history
without replaying tools. Interrupted tool calls receive an explicit unknown
outcome, and a partially written final journal record can be repaired under the
session lock. Full transcripts remain on disk, including tool output.

## Context compaction

Ipse automatically attempts to summarize older context above 80% of its default
400,000-byte ceiling. It reports compaction and the before/after sizes. This adds
a request to the selected provider/model and consumes its normal usage; it never
switches providers or billing modes. Original transcripts stay in the journal.
Recent exchanges and user requests are preserved; older results have excerpts
and summaries. Model summaries can be incomplete or incorrect, so inspect files
and original results before repeating effects.

Use `--context-bytes N` to adjust the conservative ceiling (minimum 8192), or
`--no-compact` to stop at the ceiling without summarizing. `/cancel` also stops
an active compaction. These settings can be supplied again when resuming.
If pinned user history, recent exchanges, or the summary cannot fit, Ipse stops
with recovery guidance. Review the journal and supply necessary context to a new
session. Compaction is not unlimited memory or a provider token-count guarantee.

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


Put local skills under `.agents/skills/<name>/SKILL.md` or
`~/.ipse/skills/<name>/SKILL.md`. Project definitions override user and bundled
definitions with the same name. `review` is bundled as an example.

```markdown
---
name: review
description: Review changes for correctness and missing tests.
---

Read the diff and surrounding code. Report actionable findings with file locations.
```

Version 0.1 accepts simple single-line frontmatter values for name and description.
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

`/context` shows source paths, scopes, SHA-256 digests, and diagnostics. Resume
keeps the saved instruction contents and reports detected drift. To adopt changed
files, finish or cancel active work and use `/context refresh`. Refresh neither
executes tools nor changes approval settings. Journals retain instruction text;
treat them as private session data.

For deeper file-tool targets, newly discovered nested instructions return the
pending proposals as not started so the model can reconsider them before approval.
Arbitrary shell commands can target directories indirectly; the host cannot infer
every applicable scope. Review deeper guidance and full shell arguments before
approving. See the [context contract](../developer/workspace-context.md) for
discovery, persistence, and boundary details.

## Runtime and limits

One GenServer owns a session. Monitored tasks perform provider and tool work;
session death stops them. The Rust helper kills command process groups on timeout
or lost parent connection and provides cross-process session locks. Independent
sessions can run concurrently; tools within a turn execute sequentially.

Credentials are stored separately from journals in owner-only files. Default
application data is under `~/.ipse`; override with `IPSE_HOME`.
Use `--state-dir` to override only journal storage. Session events contain no
injected provider credentials, but user prompts and tool output may contain secrets
and are retained locally. Native continuation/reasoning data is preserved when
required by the provider; raw hidden reasoning is not exposed in the UI.

Current limits: 30 model calls per turn by default (`--max-steps`), bounded file and
shell output, and a conservative conversation byte ceiling with bounded
[automatic compaction](#context-compaction). Explicit local stdio MCP can expose
allowlisted tools, exact-URI text resources, and named prompts. Each MCP server
has its own `off` or `native` sandbox setting, separate from shell `--sandbox`;
see the [MCP guide](mcp.md) for allowlist, schema, and platform limits. **Full-screen
TUI, network MCP, remote agents, and Windows are not implemented.** Local
delegation is opt-in and serial by default; two-child parallel mode uses
`--subagents --subagent-concurrency 2`. Children do not inherit MCP servers. See
[local subagents](subagents.md). Uncompactable
context stops with an actionable message rather than silently dropping history. Skills with scripts requiring Node/Python do not
make those runtimes dependencies of Ipse.

Authentication and provider requests share a bounded limit of 64 simultaneous
HTTP clients per running Ipse application. If clients are busy, retry after
another request finishes. Each request's connection and proxy state is isolated.
