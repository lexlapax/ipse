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
Broader eligibility and usage-limit behavior remain unverified. Automated
tests cover OAuth validation/refresh and streaming using local fixtures.

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

## 4. Anthropic API

Set `ANTHROPIC_API_KEY`, then:

```sh
./bin/ipse chat --provider anthropic --model claude-sonnet-4-5
```

## Working with the agent

Interactive chat asks before `write`, `edit`, and every `shell` call. `--yes`
allows them for the session. Headless `run` denies mutations unless `--yes` is
present. Approvals display the full proposed arguments.

**Shell execution is trusted local execution, not an OS sandbox.** Commands have
your user permissions. The helper clears common provider credential environment
variables, but it cannot prevent authorized commands from reading your files,
credentials on disk, or other ambient secrets. Use a disposable workspace/container
when appropriate. File tools reject symlinks and workspace escapes; writes to
`.git` are rejected. These path checks are not a defense against a hostile process
concurrently replacing filesystem entries.

Chat commands:

| Command | Behavior |
| --- | --- |
| `/skills` | Show available skill metadata |
| `/session` | Show the current session ID and state |
| `/info` | Show local application/provider/model facts without inference |
| `/cancel` | Stop current work and clear queued input; started effects may already have happened |
| `/help` | Show commands and options |
| `/exit` | Cancel active work and leave |

The CLI reports running, waiting for approval, finished, failed, and cancelled
states. New messages entered during a turn are queued for the next turn.
`/cancel` clears that queue; input received while cancellation is pending is
explicitly discarded. Send a fresh task after cancellation finishes. Repeated
cancellation requests do not start more work. Inspect the workspace before
retrying an interrupted mutation, because started effects may already have happened.

EOF exits immediately while idle. During work it finishes accepted turns,
including queued input, then exits. Pending and subsequent approvals are denied
after EOF; EOF never authorizes a mutation. `/exit` cancels and leaves immediately.
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
Repository root `AGENTS.md` is also loaded (up to 32 KiB).
Currently this means the `AGENTS.md` directly in the selected workspace. Launching
from a subdirectory does not automatically load ancestor or nested instruction
files. Read applicable guidance explicitly for now; broader discovery and global
configuration precedence are planned in the
[workspace-context milestone](../plan.md#p3-workspace-context-from-any-directory).
Version 0.1 loads `SKILL.md` text only. Referenced resources do not load
automatically; the model can read workspace files through ordinary file tools.
Resources outside the workspace and broader skill packaging need further support.

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
[automatic compaction](#context-compaction). **Full-screen TUI, MCP, subagents,
OS sandboxing, Windows, and remote execution are not implemented.** Uncompactable
context stops with an actionable message rather than silently dropping history. Skills with scripts requiring Node/Python do not
make those runtimes dependencies of Ipse.

Authentication and provider requests share a bounded limit of 64 simultaneous
HTTP clients per running Ipse application. If clients are busy, retry after
another request finishes. Each request's connection and proxy state is isolated.
