# Work in a local workspace

Ipse runs a conversation over a directory you choose. Start in a disposable
workspace, review the proposed actions, and inspect their results. The examples
use an installed `ipse`. Use `./bin/ipse` from a checkout or `./ipse` inside an
extracted release. [Installation](install.md) covers bundles on Linux/macOS;
[Arch Linux setup](arch-linux.md) covers a source build and native prerequisites.

## Check the application without a model

```sh
ipse demo
```

Expect a temporary workspace, a file write and read-back, a shell result, and a
session ID. This scripted demonstration needs no account or model service.
It exercises the application; it does not establish your provider access.
Use `ipse doctor --provider demo` for offline configuration/storage diagnostics
without an account. Omit the provider override to inspect your configured route
and its credential requirements. [Diagnosis](recovery.md#diagnose-your-setup)
explains warnings, failures and the explicit network-probe option.

## Select a provider

Choose your route explicitly. Ipse never changes provider or billing mode to
recover from a failed request. Supply API secrets through your private environment;
Ipse does not load `.env` files automatically.
Use `ipse setup` to save a reviewed private choice, then `ipse doctor` before your
first conversation. [Configuration](configuration.md#choose-and-save-a-provider)
explains preview, replacement and backup. Without any explicit choice, chat and
run announce the built-in ChatGPT subscription default before checking access.

| Route | Prerequisite | Start a conversation |
| --- | --- | --- |
| ChatGPT subscription | Run `ipse login`, complete the printed browser authorization, then check `ipse status` | `ipse chat --provider chatgpt --cwd /path/to/project` |
| OpenAI API | Set `OPENAI_API_KEY` privately; API billing is separate from a subscription | `ipse chat --provider openai --cwd /path/to/project` |
| Local Ollama | Start your service and install a tool-capable model yourself | `ipse chat --provider ollama --model YOUR_INSTALLED_MODEL --cwd /path/to/project` |
| Anthropic API | Set `ANTHROPIC_API_KEY` privately and choose an available model | `ipse chat --provider anthropic --model YOUR_MODEL --cwd /path/to/project` |
| Gemini API | Set `GEMINI_API_KEY` privately; choose an explicit model and review project billing | `ipse chat --config /private/path/gemini.json --profile gemini --cwd /path/to/project` |
| OpenRouter API | Set `OPENROUTER_API_KEY` privately; save a model/upstream profile | `ipse chat --config /private/path/router.json --profile router --cwd /path/to/project` |
| Local compatible server | Start a Chat Completions service on explicit loopback; no credential is sent | `ipse chat --provider openai_compatible --model YOUR_LOCAL_MODEL --base-url http://127.0.0.1:8080/v1 --cwd /path/to/project` |

ChatGPT login uses Ipse's public sign-in flow. The browser must reach the temporary
`127.0.0.1` callback on the machine running Ipse. On a remote host, arrange access
to that listener or run locally. Another application's login does not sign Ipse in.
`ipse status` reads local sign-in state without refreshing tokens or making a
network request. It prints JSON with `email`, `client_id`, `label`, `expires_at`
and `plan_usage`; it prints no tokens. An expired timestamp means a later real
session may need refresh or a new login, rather than proving the account usable.
`ipse logout` clears local credentials and attempts supported revocation. Review
account-side connected grants if an older grant may be compromised.

Ollama defaults to `http://localhost:11434`. Select another permitted endpoint with
`--base-url URL`, or use an operator-owned [named profile](configuration.md#reuse-a-named-model-profile).
Profiles also select exact provider/model routes for children and extensions.
Selecting a model does not download it or guarantee that your account can use it.
For OpenRouter, follow [upstream pinning](configuration.md#pin-an-openrouter-upstream)
before starting; both model and upstream are required. API credits and usage stay
separate from ChatGPT subscription access. Compatible local services use the
Chat Completions protocol; remote compatible endpoints are refused.

## Approve a small task

With a configured provider, create a scratch directory and start chat:

```sh
IPSE_TRY_DIR=$(mktemp -d)
ipse chat --provider chatgpt --cwd "$IPSE_TRY_DIR"
```

Enter this task. It makes real subscription requests:

```text
Create hello.exs that prints hello. Run it and report the exact output.
Ask before changing files or running shell commands.
```

Read the full arguments of each proposal. To approve, enter its printed
`allow CODE`; to deny, enter `n`. Each proposal has its own code. Bare `y` or
`yes`, stale codes, and input buffered before a proposal do not approve it.
A task or skill is an instruction, not permission for an effect. Check the file
and command output before relying on the final explanation.

A question uses a different prefix, `answer CODE VALUE`. Choose an option number
or ID, comma-separated choices, or free text as requested. Recommendations are
not submitted automatically. To submit literal slash-command text, use the
`=` escape, for example `answer CODE =/exit`. Answering a question approves no action.

## Run once or keep chatting

Interactive chat lets you approve each action. Headless `run` performs one task:

```sh
ipse run --provider chatgpt --cwd /path/to/project \
  'Read README.md and summarize its setup instructions without changes'
ipse run --provider chatgpt --cwd /path/to/scratch --yes \
  'Create hello.exs that prints hello, run it, and report the output'
```

Both commands use a real model. Headless effects are denied without `--yes`.
`--yes` permits mutations, shell commands, configured MCP calls, and enabled
local delegation for the session. A required question fails in headless mode,
including with `--yes`.

During a turn, additional tasks queue for later. The queue holds 16 tasks and
1 MiB of UTF-8 input; each prompt is at most 1 MiB before and after expansion.
Errors clear the queue. `/cancel` stops active work and clears queued input.
Wait for cancellation to finish before submitting another task. `/exit` cancels
and leaves. EOF lets accepted work finish but denies pending and later approvals.
A started effect may already have happened.

## Choose shell confinement

The default `--sandbox off` gives approved shell commands your user permissions.
File tools reject workspace escapes, symlinks, and protected `.git` mutation
paths. Those file-tool checks do not restrict arbitrary shell commands.

```sh
ipse chat --provider chatgpt --cwd /path/to/project --sandbox native
```

Native mode fails closed when its backend or prerequisites are unavailable.
Linux requires Landlock ABI 6+ and permitted user, mount, network, and PID
namespaces. macOS uses a signed App Sandbox worker. Both profiles permit selected
system reads and workspace/private writes, and deny external network access.
Toolchains, caches, and package fetching may be unavailable. `/session` reports
platform visibility. See [sandbox behavior](../developer/sandbox.md) for its exact limits.

Choose a narrow workspace outside the running application and helper cache.
Root, home, protected credential directories, and broad system workspaces are
refused. On macOS, an existing `IPSE_HOME` must be owned by you with mode `0700`.
Its helper cache holds 32 generations and does not evict them automatically.
Secrets inside the workspace remain readable. Cancellation stops ordinary owned
process groups, but deliberately detached processes can survive. Confinement is
not an aggregate memory or disk quota.

## Inspect local state and instructions

These chat commands make no model requests:

| Command | Result |
| --- | --- |
| `/session`, `/info` | Session/configuration facts and recorded model identity |
| `/diagnostics` | Phase, usage, budget, and context size |
| `/context`, `/skills` | Saved instruction sources and skill catalog |
| `/context refresh` | Reload instructions and skills while idle |
| `/ext` | Active extension names and schemas |
| `/observability off`, `/events off` | Stop selected diagnostics or live feeds |
| `/help` | Available commands |

Invoke a selected skill with `$name`. List available skills before a session with
`ipse skills --cwd /path/to/project`. Same-name precedence is project
`.agents/skills`, `IPSE_HOME/skills`, shared `~/.agents/skills`, then bundled skills.
`IPSE_HOME` defaults to `~/.ipse`. A skill supplies text; it does not execute its
support files. Skill documents must be regular files; FIFOs, devices, directories
and leaf symlinks are skipped. A selected file that changes or becomes unavailable
refuses the prompt; inspect it and use `/context refresh` before trying again.
These regular-file and path checks do not prevent hostile concurrent replacement
between validation and reading. Use reviewed workspaces; skill text grants no
execution or installation permission. An internal preflight failure reports a
failed operation separately from a changed skill catalog.
Skill documents are limited to 64 KiB; explicit resource reads
are limited to 32 KiB and eight path components, without recursive loading.

Ipse snapshots applicable `AGENTS.md` files from the nearest repository boundary
to the workspace, plus optional `IPSE_HOME/AGENTS.md`. Outside Git, discovery
starts at the selected directory. README and one level of text references can
contribute context. The total is bounded to 16 sources, 32 KiB each, and 128 KiB.
`/context` reports omissions and invalid sources. Newly discovered guidance for
a deeper file target can stop an unstarted call for reconsideration. Indirect
shell targets cannot always be inferred.

Resume keeps saved instructions. `/context refresh` adopts changed instructions
and skills while idle, without reloading configuration or extension code.
Terminal output escapes control characters; retained values keep original bytes.
Reported model names are response metadata, not proof of the next response's identity.

## Delegate a bounded review

Enable children explicitly, then ask for a small task with inspectable evidence:

```sh
ipse chat --provider chatgpt --subagents --cwd /path/to/project
```

```text
Delegate a read-only review of the changed error handling. Supply only the
necessary context. Check the child's findings against source and tests, and
report actionable problems with file locations. Do not edit.
```

Review the proposed task and context before approving delegation. Children share
the workspace but have separate conversations, journals, approvals, and accounting.
They receive selected context and the saved instruction snapshot, not the full
parent transcript. A completed child result still needs review. Children cannot
use MCP, delegate again, or ask structured questions. They can use explicitly
allowed extensions under separate grants and the tree budget.

To allow a pair of independent reviews, add `--subagent-concurrency 2` and request
two bounded tasks. A `delegate_parallel` proposal has exactly two task/context
objects and one group approval. Results return in task order. Only one child
mutation executes at a time. File claims conflict across equivalent case/Unicode
paths; hardlinked targets are refused. Shell mutation claims the whole workspace.
Reads can still observe changes, so this is not a filesystem snapshot.

A parent turn admits two children, serially by default. Each child has six admitted
main/helper model calls and two minutes of active work, excluding approval waits.
Task and context are each 8 KiB; final output is 16 KiB and displayed approval
arguments are 32 KiB. Failure, timeout, oversized output, or unknown cleanup
stops remaining delegation, including a parallel sibling. Inspect effects before
another attempt. [Resource controls](resources.md) explain shared reservations.

## Resume or hand off long work

```sh
ipse sessions
ipse sessions --json
ipse chat --resume SESSION_ID
```

Use the original `--state-dir` if customized. Listing is local and returns bounded
session metadata; it does not validate the full journal. Resume restores the
workspace, provider/model, pinned configuration, and instruction snapshot. Idle
resume makes no inference or tool calls. Interrupted effects remain unknown.
[Recovery](recovery.md) explains refusals and fresh-session handoffs.

By default, a turn allows 30 model calls and context holds 400,000 bytes.
Compaction begins above 80%, retaining original journal evidence. A summary makes
another same-provider request; the older-output fallback does not. Set
`--context-bytes N` within 8192..16000000, or use `--no-compact` to stop at the
ceiling. Required retained content can still prevent compaction.

One response admits 32 tools and 2 MiB of arguments; a turn admits 128 tools and
8 MiB. Invalid/denied proposals count. Excess or incomplete responses execute none
of their proposed tools. Prior effects can remain. Journals have separate finite
limits and may seal even when context is small.

Journals default to `IPSE_HOME/sessions`. `--state-dir` relocates journals and
budget ledgers, not authentication, artifacts, or extension state. Journals retain
private prompts, results, instruction snapshots, and provider continuation. Keep
them outside Git. Hidden reasoning is not displayed. Continue with
[configuration](configuration.md), [extensions](extensions.md), or [recovery](recovery.md).
