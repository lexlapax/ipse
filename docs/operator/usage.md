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
| Grok API | Set `XAI_API_KEY` privately and choose API billing explicitly | `ipse chat --provider xai --model grok-4.7 --cwd /path/to/project` |
| Grok subscription | Obtain an approved Ipse registration from xAI and follow [device sign-in](configuration.md#use-grok-through-xai); live access is unverified | `ipse chat --provider xai_oauth --model grok-4.7 --cwd /path/to/project` |
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

Login prints a machine label such as `ipse@serenity`, using the short local
hostname. New registrations send that label as the browser's suggested name so
you can recognize the machine in ChatGPT. Review or edit it before approving.
Returning login keeps the existing registration name and sends no new name hint.
The display label does not replace the
stored opaque host ID. If the hostname is unavailable or unsuitable for display,
the label is `ipse@unknown-host`.

Ollama defaults to `http://127.0.0.1:11434`. Select another permitted endpoint with
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
ipse chat --cwd "$IPSE_TRY_DIR"
```

This uses your saved provider/profile. Enter this task; a real model route makes
service requests and can incur its configured charges:

```text
Create greeting.txt containing hello followed by a newline. Read it back, then
use the shell builtin printf to print hello. Report both exact outputs.
Ask before changing files or running shell commands.
```

Read the full arguments of each proposal. To approve, enter its printed
`allow CODE`; to deny, enter `n`. Each proposal has its own code. Bare `y` or
`yes`, stale codes, and input buffered before a proposal do not approve it.
A task or skill is an instruction, not permission for an effect. Check the file
and command output before relying on the final explanation.

For repeated work, choose the smallest permission that fits:

| Choice | Authority and duration |
| --- | --- |
| `allow CODE` | Only the displayed proposal |
| `edits CODE` on a native write/edit proposal | Native workspace file edits until this session closes |
| `session CODE` on a native shell proposal | That exact shell call, including all arguments, cwd and requested sandbox policy, until this session closes |
| `n` | Deny this proposal |

These choices use the fresh code displayed with the pending proposal. To start
interactive chat with native edits already enabled, use:

```sh
ipse chat --accept-edits --cwd /path/to/project
```

Protected-note-derived model proposals have a separate Linux native display
path with one-use `allow CODE` or denial only. Wait for its `approval>` prompt;
its source and policy owners release before input, and execution rechecks them.
Unsupported dependencies or an oversized complete display refuse. Follow
[knowledge permission](knowledge-permissions.md#review-the-project-and-exact-permission)
for its prerequisites and remaining limits.

Shell, MCP, extension effects and child actions still require their own approvals.
Native file checks continue to reject workspace escapes, symlinks and `.git`
mutations; session edit grants also refuse hardlinked targets. These checks are
not protection against hostile concurrent filesystem replacement. Use a reviewed
workspace. Shell consent permits the complete command, including any compound
operations it contains; it is not a safe-command classification or a prefix rule.
It does not freeze the files or environment used by that command.
An edit grant combined with `session CODE` for `sh script.sh` permits the model
to rewrite `script.sh` and run that same command again without another prompt.
Use `allow CODE` for a single execution when the script's reviewed contents
matter, or use `/permissions clear` before editing or rerunning it.
With confinement off, an approved shell command has your user permissions.

Use `/permissions` to inspect grants and `/permissions clear` to revoke all edit
and command grants. Clearing affects later dispatches; an already dispatched
effect may finish. `/cancel` stops work but retains session grants. Closing and
resuming discards grants, unless you explicitly select `--accept-edits` again.
Children and extensions never inherit these native-tool grants. Shell grants are
limited to 32 entries of at most 16 KiB of arguments each. If a grant is refused,
you can still approve the proposal once. `--accept-edits` is restricted to chat
and cannot combine with `--yes`; headless behavior is unchanged.

A native knowledge decision card uses its own fresh `accept CODE`. With the
reviewed knowledge selection, the model can nominate an exact recommendation
from its completed reply. The host captures it as pending, closes the original
conversation for protected review, then resumes the same conversation after a
confirmed result. This closure ends native edit and shell grants; the configured
ordinary approval policy, including an explicit `--yes`, still applies. Follow
[review a proposed decision during chat](knowledge-permissions.md#review-a-proposed-decision-during-chat)
for prerequisites, bounded source support and recovery. An explicit interactive
resume without an initial task can check a known pending decision before the
first chat prompt and offer a fresh code. It never repeats its capture or an
uncertain review. Accepting a decision
grants no file, shell or service permission.

A question uses a different prefix, `answer CODE VALUE`. Choose an option number
or ID, comma-separated choices, or free text as requested. Recommendations are
not submitted automatically. To submit literal slash-command text, use the
`=` escape, for example `answer CODE =/exit`. Answering a question approves no action.
If a batch repeats the same prompt, question kind and ordered option labels and
descriptions, Ipse asks the model to revise it before showing a question. It also
returns a previously answered matching question to the model within the same
visible turn, even if IDs or a recommendation changed. It does not detect
reworded questions or search across earlier turns.

## Plan before acting

To start a conversation with the planning ceiling, use:

```sh
ipse chat --provider demo --planning
```

In an existing interactive chat with a verified native terminal, enter `/plan`
at an idle prompt to apply the ceiling to that session. The command is refused
while work or cleanup remains active, and pending queued input is discarded on
entry; submit any still-wanted input again. Finish or cancel an active draft
before changing modes. `/plan` does not start or submit a model turn.
To leave a locally selected ceiling entered with `/plan` or a recorded
`--planning` flag, enter `/plan exit` at an idle native prompt. The transition
preserves enclosing restrictions and approval settings; it discards queued input
and does not save plan decisions. An inherited ceiling or a legacy selection
without recorded local provenance cannot be exited this way.

Planning allows local reads and questions while denying workspace writes, shell,
delegation and knowledge publication. An operator-declared planning MCP read
may run with its ordinary approval; see [MCP planning reads](mcp.md#review-a-tool-for-request-refinement).
`--yes` does not override the ceiling. `--planning` also works with `run`, and
cannot be combined with `--accept-edits`. The ceiling remains in force when the
session is resumed, even if the flag is omitted. Start a new ordinary session
when an inherited or ambiguous ceiling cannot be exited and review its context.
For a session resumed with an earlier development build that did not record a
later planning selection, pass `--planning` again: the saved history cannot
establish that earlier selection. A changed resume policy is saved in a newer
checkpoint format; an older build that cannot read it refuses the session. Keep
the current runner available if you need to resume that history.

To retain a decision you write yourself while locally planning, enter:

```text
/plan decide Use a local fixture for this check.
```

The text must be nonblank valid UTF-8 and at most 1,024 bytes. Review the exact
text and enter the displayed `accept CODE`. This records a
deferred decision in the Session journal; it does not publish a note. Bare `yes`,
a stale code, or cancelling the review does not accept it. Use `/plan decisions`
to inspect retained IDs and status, including after resuming the same Session.
Up to sixteen decisions can be retained per Session.

To retain the assistant's proposal, first ask for it while planning and wait for
the reply. Copy a unique, exact, contiguous quote from the latest reply:

```text
/plan decide-assistant Use the local fixture for this check.
```

Review the displayed assistant proposal and enter its fresh `accept CODE`.
The quote must be nonblank valid UTF-8, at most 1,024 bytes, and occur exactly
once in the original reply. This path requires the latest committed planning
reply, no presentation transform or after-turn extension, and no protected
managed note content in the conversation. Authenticated observations of the
collection root alone are permitted. A new user turn makes the old reply
ineligible. Acceptance retains the assistant source and does not save a note.

Ordinary-chat [decision cards](knowledge-permissions.md#review-a-proposed-decision-during-chat)
require normal execution ceilings and remain unavailable while planning.

For the save journey, start in the admitted project with the saved provider and
configuration used for its native knowledge selection. The earlier `--provider
demo` example is for planning alone and can fail that pinned route. After
`/plan exit`, explicitly select an accepted ID to review a save:

```text
/plan save COPY_THE_32_LOWERCASE_HEX_CHARACTER_ID
```

Saving needs both active and enclosing ceilings to be `normal`, the Session's
active [native knowledge permission](knowledge-permissions.md), current source
and supported protected storage. For your own words, review the exact statement
again and enter its fresh `remember CODE`; cancelling saves nothing.
A successful capture of your own words stores an ordinary operator-authored
literal with its source receipt linked to the earlier planning acceptance. For
an assistant proposal, the separate save review shows the exact quote and
destination and requires `stage CODE`. This creates a pending proposal, not an
accepted note. Keep the returned `pending.` key, exit the Session, then complete
the independent native review in the same project and home:

```sh
ipse knowledge review pending.COPY_THE_64_CHARACTER_ID --cwd /path/to/project
```

Include the same `--config` and `--no-project-config` options when needed to
select the original permission. If the original Session used a custom sessions
directory, also pass `--state-dir /path/to/original/sessions`. The independent
review rechecks the proposal, its source and current permission; it may refuse
stale or unavailable evidence.
See [review a pending proposal](knowledge-permissions.md#review-a-pending-proposal).
Exiting planning alone never saves a decision. A cancelled save review leaves the decision available for a new
explicit review. `/plan decisions` distinguishes a known refusal before the
extension starts from a save intent that needs journal inspection. The intent
alone does not establish that the extension started. Neither is automatically
repeated; an attempted save cannot be retried with the same ID. The displayed
statuses are `waiting_for_planning_exit`, `ready_for_save_review`,
`source_unavailable_for_save`, `save_refused_before_publication` and
`save_started_inspect_journal`. The source-unavailable status means the assistant
reply is no longer eligible for this save, for example after a later user turn.
Ready status reflects the retained Session evidence; it does not check the
current collection root or saved permission. The protected capture checks those
again and can refuse if they changed.
If an attempted save's
outcome is unavailable, inspect the Session journal and stored state. The ID is
bound to this Session. If an enclosing ceiling prevents saving, keep its journal;
a fresh ordinary Session can review the text as a new assertion, but does not
transfer the old decision or its provenance.
This development-source path
has not yet been qualified for installed or independent human use.

## Refine a request before submitting it

This experimental development-source feature needs interactive chat and a
verified native terminal. Ask the current assistant for a clearer request:

```text
/enhance Create a small task tracker with editable due dates and local storage.
```

This uses the conversation's selected provider, model, billing and budget. Wait
for the draft to finish. Drafting permits bounded native reads and questions.
The drafting instruction asks the model to check relevant available context
before asking about unanswered material choices, and to state low-impact
assumptions. Review the proposal and any unanswered requirements yourself;
the model may still miss information or ask unnecessary questions.
A specifically declared planning-read MCP tool can also run with ordinary MCP
approval; see [review and declare a planning read](mcp.md#review-a-tool-for-request-refinement).
Workspace writes, shell, delegation, undeclared external calls and extension
callbacks are denied even when ordinary session permissions allow them. The
ordered tool catalog remains present. Configured MCP discovery can still start
its configured command or contact its endpoint; no draft text is sent in
discovery requests.

Review the proposal, then choose an action:

| Command | Result |
| --- | --- |
| `/enhance show` | Show the draft ID, revision and exact proposed request |
| `/enhance replace TEXT` | Replace the proposal with the text on the command line |
| `/enhance replace` | Read a replacement from the next terminal line |
| `/enhance replace multi` | Collect up to sixteen lines; `/end` saves them and `/cancel` discards the replacement |
| `/enhance accept ID` | Render that draft and a fresh `accept CODE` confirmation |
| `/enhance cancel` | Abandon the draft before returning to ordinary input |

Replace `ID` with the displayed draft ID. `/enhance accept` also selects the
current completed draft. Acceptance submits exactly the displayed proposal as a
new ordinary turn. Its file, shell and service effects still require their normal
permissions. A pre-existing planning or read-only ceiling remains in force.
Bare `yes`, a stale ID/code, a different terminal, or piped input cannot accept it.
`/cancel` stops pending request/replacement entry; at an acceptance display it
abandons the draft. `/enhance cancel` abandons the current draft explicitly.
To enter text beginning with a command word such as `show`, enter `/enhance`
alone, then supply the request on the next line.
Inline replacement removes surrounding whitespace. To use the literal text
`multi` as a replacement, enter `/enhance replace` and then `multi` on the next
line; the inline form selects multiline entry.

Keep the request and accepted proposal within 32 KiB. Drafting allows at most
three model requests and three question rounds, narrowed by existing limits.
Provider responses retain the selected route's transport limit: ordinarily
8 MiB, or a tighter configured limit. That limit includes stream framing and
provider continuation, separately from the proposal's 32-KiB UTF-8 limit.
A transport failure can occur after partial text appears; that text is not a
completed draft. An empty or oversized final proposal reports an error. Cancel
that pending draft before starting a new request; replacement requires a completed
proposal. These bounds do not add an output-token
cap to a route that does not support one or establish that remote work stopped.
If clarification cannot continue within the draft's question bounds, cancel the
draft and include the missing information in a new request.
At most sixteen accepted drafts can retain provenance in one Session. The active
projection also bounds unrebased draft intervals to sixteen; use an explicit fresh
session when this capacity or required compaction prevents another draft.
Explicit `$skill` expansion is unavailable in this workflow; use an ordinary
request when you need to invoke a skill.

Cancelled draft text and clarification answers remain in the private journal,
but are withheld from later model input and eligible Session sources. Accepted
text is admitted as fresh intent with links to its original input, answers and
read evidence. ChatGPT and OpenAI API sessions can withhold a complete Responses
draft interval when its native items and tool exchanges are safely isolated;
the selected provider and billing route remain unchanged. With Ollama, the
complete no-tool draft interval can be withheld even when its native assistant
messages contain thinking. That draft-only thinking remains in the private
journal and is not sent on later turns. Anthropic supports
withholding a no-tool draft whose native content contains matching plain-text
blocks, bounded thinking blocks with a nonempty signature, and bounded opaque
redacted-thinking blocks. The complete draft-only native content stays in the
private journal and is withheld from later model input. Anthropic tool exchanges
and unrecognized native fields remain unsupported for draft withdrawal.
A draft can still complete or be cancelled if it contains unsupported
continuation, but acceptance or later work can refuse when the draft cannot be
safely withheld. Follow the
recovery procedure below; earlier and later ordinary history remains available,
subject to complete tool-call boundaries.
Unsupported provider continuation, required compaction, or active
extension delivery can refuse drafting or later continuation. Use the explicit
[draft recovery procedure](recovery.md#recover-a-request-draft); no alternate
provider or fresh conversation is selected automatically. Knowledge retrieval,
document-based clarification and live model quality remain unqualified.

## Run once or keep chatting

Interactive chat uses individual approvals or your explicit session grants.
Headless `run` performs one task:

```sh
ipse run --cwd /path/to/project \
  'Read README.md and summarize its setup instructions without changes'
ipse run --cwd /path/to/scratch --yes \
  'Create greeting.txt containing hello and a newline, read it back, then use the shell builtin printf to print hello. Report both outputs.'
```

Both commands use the saved provider/profile. Headless ordinary mutations are
denied without `--yes`. A separately reviewed [knowledge permission](knowledge-permissions.md)
records only its declared collection scope for `run`. Saved consent can cover
the narrow native capture path and attributed pending proposals from argv or
standard input without `--yes`. These development-source paths remain experimental;
installed behavior and capture quality are not qualified. Correction and
supersession require the separate
[interactive two-review procedure](knowledge-permissions.md#correct-or-supersede-a-native-note);
headless correction, supersession and managed document mutations still refuse.
Follow that manual's current source,
category and publication limits; `--yes` cannot widen the knowledge permission.
Existing read/inspection routes remain separate.
To forget an existing native note, use the separate interactive
[`knowledge forget` review](knowledge-permissions.md#forget-a-selected-native-note)
on a supported Linux protected-storage profile; it is not a headless `run` effect.
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
ipse chat --cwd /path/to/project --sandbox native
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
| `/permissions`, `/permissions clear` | Inspect or revoke native edit/command grants; makes no change to broad `--yes` authority |
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
New sessions keep their admitted model header and tool catalog fixed between
explicit refreshes and compaction boundaries. Updated scoped instructions,
response metadata and extension excerpts enter as labelled reference data after
conversation history. Older resumed sessions retain their saved layout.
Terminal output escapes control characters; retained values keep original bytes.
Reported model names are response metadata, not proof of the next response's identity.

## Delegate a bounded review

Enable children explicitly, then ask for a small task with inspectable evidence:

```sh
ipse chat --subagents --cwd /path/to/project
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
