> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/operator/usage.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Use Ipse for a local task

This guide takes you from a credential-free demonstration to a conversation in
your own workspace. Use an installed `ipse`, `./ipse` inside an extracted release,
or `./bin/ipse` from the source checkout. For an Arch source installation, follow
[Install on Arch Linux](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/arch-linux.md).

## Try the demonstration

```sh
ipse demo
```

The demo uses a scripted provider. It creates a temporary workspace, writes
`ipse-demo.txt`, reads the file back, and runs a short shell command. It needs no
credentials, network model service, or paid inference. The output includes the
workspace and session ID so you can inspect what happened.

## Choose your provider

Ipse defaults to ChatGPT subscription use. It never silently changes provider or
billing mode after a failure. Select one of the following routes explicitly.
Account eligibility and model access come from the selected service.

### ChatGPT subscription

```sh
ipse login
ipse status
ipse chat --provider chatgpt --cwd /path/to/project
```

Open the printed **Continue with ChatGPT** URL in a browser that can reach the
same machine's temporary `127.0.0.1` callback listener. Complete authorization,
then return to the terminal. On a remote host, arrange access to that loopback
listener or run Ipse locally. Ipse uses its own public sign-in flow and protected
auth storage. Another application's login does not sign Ipse in.

The default requested model is `gpt-6.1-sol`. Set `--model NAME` only for a model
your account can use. Run `ipse logout` to revoke renewable credentials where
possible and clear local tokens. Reauthorization replaces local credentials; use
ChatGPT Settings to disconnect a suspected compromised older grant.

### OpenAI API

Supply `OPENAI_API_KEY` through your usual private secret-management method.
Ipse does not automatically read `.env` files.

```sh
ipse chat --provider openai --cwd /path/to/project
```

This route uses API billing separately from ChatGPT subscription usage. Its
default requested model is `gpt-6.1-sol`.

### Local Ollama

Start your separately installed Ollama service and make a tool-capable model
available before starting Ipse. Use its exact installed model name:

```sh
ipse chat --provider ollama --model qwen3:8b --cwd /path/to/project
```

The default endpoint root is `http://localhost:11434`. To use another permitted
endpoint, pass `--base-url URL` or configure an operator-owned
[model profile](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/configuration.md#reuse-a-named-model-profile). Ipse does not download models for you.

### Anthropic API

Supply `ANTHROPIC_API_KEY` privately, then select API use explicitly:

```sh
ipse chat --provider anthropic --model claude-sonnet-4-5 --cwd /path/to/project
```

The model name is an example and the provider default. Verify access with your
account. An unavailable model or service stops the request without fallback.

## Complete your first task

Create a disposable directory, then start interactive chat with your chosen
provider. This example makes real subscription model requests after you submit
a task:

```sh
IPSE_TRY_DIR=$(mktemp -d)
ipse chat --provider chatgpt --cwd "$IPSE_TRY_DIR"
```

At the chat prompt, enter:

```text
Create hello.exs that prints hello. Run it, then report the exact output.
Ask before changing files or running shell commands.
```

Ipse displays each proposed write, edit, shell, MCP, or delegation action with its
complete arguments. Check the path, content, command, and destination. To approve,
enter the exact `allow CODE` line printed with that proposal. The code changes
for each proposal. Enter `n` to deny. Bare `y` or `yes`, stale codes, and text
buffered before the proposal do not approve it.

Expect a file proposal followed by a shell proposal if the model chooses that
route. Approval of one does not approve the next. Inspect the created file and
reported command result before relying on the final explanation.

To assess an existing repository first, ask:

```text
Use $project-orientation to explain this project's purpose, current changes,
and available checks. Keep the assessment read-only. Do not fix anything yet.
```

A read-only request guides the agent. Shell commands still require approval and
have the permissions described below.

## Work interactively or run one task

Interactive chat lets you inspect individual actions. `--yes` permits mutations,
shell, configured MCP, and enabled delegation for the session. Choose it only
when you intend that broader allowance.

Headless `run` performs one task and cannot wait for clarification. It denies
effects without `--yes`, even when the task requests them:

```sh
ipse run --provider chatgpt --cwd /path/to/project \
  'Read README.md and summarize the setup instructions without changes'
ipse run --provider chatgpt --cwd /path/to/scratch --yes \
  'Create hello.exs that prints hello, run it, and report the output'
```

Both commands use a real model. The second authorizes session-wide effects. A
required operator question fails in headless mode, including with `--yes`.

While work runs, another entered task queues for the next turn. The queue holds
at most 16 tasks and 1 MiB of UTF-8 input. Each prompt is at most 1 MiB before and
after skill expansion. Errors clear queued tasks. `/cancel` stops active work and
clears the queue; send fresh input after cancellation finishes. A started effect
may already have happened. `/exit` cancels and leaves. EOF finishes accepted work
but denies pending and later approvals.

## Shell policy

The default `--sandbox off` runs approved shell commands with your user
permissions. Credential-environment cleanup does not prevent reads of files or
secrets on disk. File tools reject symlinks, workspace escapes, and protected
`.git` mutation targets; arbitrary shell commands have a separate boundary.

To request OS enforcement for shell commands:

```sh
ipse chat --provider chatgpt --cwd /path/to/project --sandbox native
```

Native mode fails closed if the backend or setup is unavailable. Approval still
applies. Linux requires Landlock ABI 6+ and permitted unprivileged user, mount,
network, and PID namespaces. Its fixed profile allows workspace/private-temp
writes and selected system reads, while denying external network access. macOS
uses a signed App Sandbox worker with workspace and sandbox-data writes, selected
system/Homebrew reads, and no network access.

Choose a workspace separate from the active application and native helper. Root,
home, protected credential directories, and broad system workspaces are refused.
On macOS, keep the application and protected helper cache outside the workspace;
use an installed bundle for changing Ipse itself. Existing `IPSE_HOME` must be
owned by your user with mode `0700`. The cache holds at most 32 generations and
does not automatically evict them. Secrets within the workspace remain readable.
Home toolchains, sibling repositories, caches, and package fetching may be hidden.
`/session` shows the selected platform's visibility facts.

Cancellation stops owned work and ordinary process groups. Deliberately detached
children can survive and retain workspace access, including on macOS. Native
confinement is separate from cleanup and is not an aggregate memory or disk
quota. See [sandbox details](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/sandbox.md) when deciding whether the
fixed profile suits your task.

## Ask questions and inspect the conversation

Ipse can ask up to three structured questions at once. Reply using the printed
`answer CODE VALUE` prefix. Use an option number/ID, comma-separated choices,
or free text as requested. Recommendations are never submitted automatically.
To answer with literal slash-command text, use the `=` escape, such as
`answer CODE =/exit`. A question answer does not approve an action.

Use these local chat commands without making model requests:

| Command | Use |
| --- | --- |
| `/session` | Read the session ID, state, configuration, and accounting |
| `/info` | Check running application version and configured/reported model identity |
| `/diagnostics` | Inspect current phase, usage, budgets, and context bytes |
| `/context` | Inspect instruction sources, digests, and omissions |
| `/context refresh` | Reload instructions and skills while idle |
| `/skills` | List the saved skill catalog |
| `/ext` | List active extension exports |
| `/observability off` | Stop new diagnostic sink samples |
| `/events off` | Stop selected live event feeds |
| `/help` | Read available commands |

Reported model identifiers are historical response metadata, not a promise about
the next backend response. Prefer `/info` to a model's natural-language identity
claim. Terminal output escapes control/invisible format characters so returned
ANSI commands cannot operate your terminal. Saved values keep their originals.

## Skills and workspace instructions

Invoke a selected skill with `$name`, for example `$review`. Loading it adds
instructions; it does not execute referenced scripts or authorize actions.
Discover available skills before a session with:

```sh
ipse skills --cwd /path/to/project
```

Same-name precedence is project `.agents/skills`, `IPSE_HOME/skills`, shared
`~/.agents/skills`, then bundled skills. `IPSE_HOME` defaults to `~/.ipse`; changing
it does not relocate the shared skill root. The catalog shows selected sources
and shadowed paths. Skill documents accept simple single-line name/description
frontmatter and are limited to 64 KiB. Explicit supporting-resource reads are
limited to 32 KiB and eight path components. They do not load recursively.

Ipse snapshots applicable `AGENTS.md` files from the nearest repository boundary
to `--cwd`, or just the selected directory outside Git. Optional
`IPSE_HOME/AGENTS.md` supplies user defaults. README and one level of text references
can contribute bounded context. Limits are 16 sources, 32 KiB each, and 128 KiB
total. Invalid, sensitive, symlink, or oversized sources produce diagnostics.
For deeper file targets, newly found guidance can stop an unstarted call for
reconsideration. Review `/context` before requesting another attempt. Shell
arguments can refer indirectly to directories whose guidance Ipse cannot infer.

Resume keeps saved instructions and skills. To adopt changes, finish/cancel
active work and use `/context refresh`. This reloads neither configuration nor
extension code. Instructions remain reference text and never grant permissions.

## Save, resume, and manage long work

```sh
ipse sessions
ipse sessions --json
ipse chat --resume SESSION_ID
```

Replace `SESSION_ID` with an ID from the listing. Add the original `--state-dir`
if you used a custom store. JSON listing returns only `id`, `provider`, `model`,
and `cwd`, sorted by ID. Listing is local and does not validate an entire history.

Resume restores the original workspace, provider, model, instruction snapshot,
and compatible execution configuration. It does not replay tools or start new
inference while idle. Interrupted actions without results remain unknown. Keep
the original endpoint and pinned configuration; see [Recovery](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/recovery.md) if
compatibility checks refuse resume.

The default turn allows 30 model calls. The context ceiling is 400,000 bytes;
automatic compaction begins above 80%. Summarizing older turns makes an additional
request to the same provider. The local older-output fallback makes none. Both
retain original evidence in the journal. `--context-bytes N` changes the ceiling
within 8192..16000000 bytes; `--no-compact` stops at the ceiling. Compaction can
still refuse when necessary retained content cannot fit. Use a reviewed
[fresh-session handoff](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/recovery.md#continue-in-a-fresh-session) for such work.

One response can propose at most 32 tools/2 MiB of arguments; one turn admits
128 tools/8 MiB. Invalid and denied proposals count. Excess or incomplete provider
responses execute none of their proposed tools. Prior effects can remain.
Journals separately have finite limits and can seal even when context is small.

Default journals live under `IPSE_HOME/sessions`. `--state-dir` changes journal
and associated budget-ledger storage, not authentication, artifacts, or extension
state. Journals retain private prompts, tool output, instruction snapshots, and
provider continuation. Protect them and keep them outside Git. Hidden reasoning
is not displayed. Diagnostic captures and exports have separate privacy scopes.

Continue with [configuration](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/configuration.md), [optional subagents](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/subagents.md),
[external tools](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/mcp.md), or [troubleshooting](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/troubleshooting.md) as needed.
