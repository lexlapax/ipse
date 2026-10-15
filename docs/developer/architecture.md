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

`Ipse.Provider` selects a provider adapter. Adapters stream text and
normalized tool calls into the session; provider-specific continuation data is
kept where needed to resume a provider exchange. The session enforces a
per-turn model-call limit and runs tools sequentially. It does not use a fixed
plan/execute workflow or require a graph framework.

## Trust and side effects

The system message describes the workspace and available skill metadata.
Project skills override user and bundled skills. A skill is plain instruction
text: loading it never executes scripts and does not grant tool permission.
`AGENTS.md` is also included when present. Explicit `$skill-name` references
load the matching skill into the user turn.

Reads and mutations use workspace-relative tools. Path checks reject symlinks,
workspace escapes, and writes under `.git`; these checks are not race-proof
against a hostile process changing paths concurrently. Interactive chat asks
before writes and shell execution. Headless mode denies mutations unless
`--yes` is supplied. Approval controls agent-directed calls only. Shell
commands run with the user's OS permissions and are **not sandboxed**.

The Rust helper launches `/bin/sh -c` in a process group, streams bounded
output, and kills the group on timeout or loss of its parent pipe. It removes
common provider-token environment variables, but other inherited environment
values and files remain accessible. A deliberately adversarial process can
escape the process group. Use a separate OS sandbox or disposable environment
when that isolation is required.

## Persistence and recovery

The default application home is `~/.ipse` and can be changed with
`IPSE_HOME`. Owner-only credential files are kept separately from session
journals; journals contain prompts, tool arguments, and results, so those may
include user secrets. A state directory can be overridden with `--state-dir`.

Each session journal is JSONL. The Rust helper provides a persistent advisory
lock whose lifetime follows its Port owner; lock files are kept to preserve
inode identity. Resume loads events into conversation history without replaying
tool calls. Interrupted calls are marked with an unknown outcome because their
external effects may already have happened. A final partial record may be
repaired while holding the session lock. The full transcript remains on disk.

## Boundaries and current limits

The line-oriented terminal client is not a full-screen TUI. There is no
automatic context compaction, MCP support, subagent execution, remote execution,
Windows support, or OS sandbox integration. When the context byte ceiling is
reached, the current version stops with an actionable error rather than
silently dropping conversation history.

ChatGPT subscription sign-in follows the documented open-source app flow.
Browser sign-in, inference, coding tools, resume, and logout passed with one
account on Arch; see [testing.md](testing.md). Live refresh, broader account/model
eligibility, and usage-limit behavior remain unverified. Fixture tests do not
establish those live-service properties.

## Extension guidance

Keep provider-specific wire formats inside provider adapters and keep session
state transitions in `Ipse.Session`. Put ordinary filesystem and shell
operations behind the tool boundary. Add new capabilities only with clear
permission and recovery behavior; do not imply that process supervision is an
OS security boundary. Keep Rust limited to OS facilities that OTP cannot
provide directly. Preserve a credential-free demo and tests that do not require
paid model access.
