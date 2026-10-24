# Configure a workspace, model and session

Keep repeatable settings in a private version-1 JSON file. Inspect the selected
provider, model and endpoint before submitting work. Configuration inspection
needs no model account or running service. Starting a conversation requires the
selected service and model to be available.

The commands below use an installed `ipse`. In a source checkout, use
`./bin/ipse`; in an extracted release, use `./ipse`.

## Choose and save a provider

Run `ipse setup` from a terminal. Choose a provider explicitly: there is no menu
default. The menu labels subscription, API billing and local service routes.
Choose a model and optional shell policy, then review the exact JSON and type
`write` to save it. API credentials come from your private environment; setup
never asks for or stores a key. ChatGPT setup can offer the existing `ipse login`
browser flow after validating the proposal. Extensions are selected separately
through the [extensions manual](extensions.md).

OpenRouter, Gemini and compatible local servers have no model default: an empty
answer asks again. OpenRouter also asks for a pinned upstream and a data-collection
policy, defaulting to `deny`. A compatible server requires a loopback base URL.
Review those fields in the preview before saving.

For scripts, supply both provider and model. Preview first:

```sh
ipse setup --provider demo --model scripted
ipse setup --provider demo --model scripted --write
ipse doctor
ipse demo
```

For a new API/local route, these commands preview complete configuration without
making a model request. Replace models and endpoints with ones you can access;
provide keys privately before the saved configuration's doctor check:

```sh
ipse setup --provider openrouter --model openai/gpt-4.1-mini --upstream openai --data-collection deny
ipse setup --provider gemini --model gemini-3.8-flash
ipse setup --provider openai_compatible --model YOUR_LOCAL_MODEL --base-url http://127.0.0.1:8080/v1
```

Repeat the chosen command with `--write` only after reviewing it. Routing fields
or an explicit endpoint are saved in a new `setup_PROVIDER` profile selected for
the main role. Setup refuses a name collision and preserves existing profiles and
roles. To change an existing profile's endpoint, upstream or collection policy,
edit and review the operator file explicitly. `--upstream` and `--data-collection`
apply only to OpenRouter setup; inference selects the saved profile.

Preview commands write nothing, including directories. `--write` authorizes the
non-interactive save. The target is `--config PATH`, then `IPSE_CONFIG`, then
`IPSE_HOME/config.json`. New directories are mode `0700` and the file is `0600`;
existing parent directory permissions are retained. Setup refuses symlink targets
and invalid or oversized existing files. It never changes project configuration.

An existing target requires `--replace`. The preview preserves unrelated settings,
profiles, roles, extension selections and trust. Saving first retains the exact
old bytes in a private `config.json.bak-YYYYMMDDTHHMMSSZ` beside the target. A
backup collision refuses rather than overwriting it. A main profile or environment
override that conflicts with your choice refuses before any backup or write;
inspect `ipse config` and resolve that conflict explicitly. Incompatible preserved
settings, such as an unsupported output cap, also refuse before writing.

After saving, setup runs offline doctor and prints the next command. A failed
doctor check returns exit code 1 while keeping the saved configuration; follow
[diagnosis](recovery.md#diagnose-your-setup) before starting real work. Native
shell policy is offered interactively only when availability checks pass on Linux;
the check does not establish kernel enforcement. macOS native policy remains
experimental and requires explicit selection.

## Edit and inspect operator settings

For settings beyond guided setup, edit `~/.ipse/config.json`, or another private
file outside your workspace. For example:

```json
{
  "version": 1,
  "settings": {
    "provider": "ollama",
    "model": "qwen3:8b",
    "max_steps": 12,
    "max_output_tokens": 1024,
    "context_bytes": 400000,
    "timeout_ms": 120000,
    "compact": true,
    "sandbox": "off",
    "subagents": false,
    "subagent_concurrency": 1
  }
}
```

This example selects an existing local Ollama service. It installs no service
and downloads no model. Replace `/path/to/operator.json` with the file you saved:

```sh
ipse config --config /path/to/operator.json --no-project-config
```

Expect non-secret effective settings, each setting's provenance, source paths
and digests, and a configuration fingerprint. No inference occurs. Keep tokens
out of this file: subscription access uses `ipse login`, and API providers use
their supported credential environment variables.
An explicit `--mcp-config PATH` is also validated by `ipse config`, including
endpoint and allowlist rules. It does not launch servers or discover remote
tools. Use the [MCP manual](mcp.md) to review those capabilities before a session.

The default file is `IPSE_HOME/config.json`; `IPSE_HOME` defaults to `~/.ipse`.
`--config PATH` overrides `IPSE_CONFIG`. An explicitly selected file must exist;
an absent default file is allowed. Files allow at most 16 KiB. Unknown fields,
duplicate keys and inline credentials refuse with a configuration error.

After reviewing the output, start a session:

```sh
ipse chat --config /path/to/operator.json --no-project-config --cwd /path/to/project
```

Submitting a task uses the selected model. The file grants no write, shell,
MCP or delegation permission. Interactive approvals still apply.

## Reuse a named model profile

Use `profiles` to name routes you repeatedly choose. This complete operator file
uses a subscription model for main work and a local model for routine children:

```json
{
  "version": 1,
  "settings": {"subagents": true},
  "profiles": {
    "strong": {
      "provider": "chatgpt",
      "model": "gpt-6.1-sol",
      "reasoning_effort": "high",
      "credential": "ipse-auth"
    },
    "local": {
      "provider": "ollama",
      "model": "qwen3:8b",
      "max_steps": 4,
      "max_output_tokens": 4096,
      "timeout_ms": 120000
    }
  },
  "roles": {"main": "strong", "routine": "local", "review": "strong"}
}
```

Save it as `/private/path/models.json`. Sign in with `ipse login` before using
`strong`. Serve the named local model before using `local`.

```sh
ipse config --config /private/path/models.json --no-project-config --profile strong
ipse config --config /private/path/models.json --no-project-config --profile local
ipse chat --config /private/path/models.json --no-project-config --profile strong --cwd /path/to/project
```

Both inspection commands stay local. In chat, `/info` shows the selected profile,
requested model, reasoning policy and any provider-reported model identity.
An unavailable model or failed service produces an error; Ipse does not select
another provider or billing route.

Selection follows `--profile ID`, then `IPSE_PROFILE`, then the `main` role.
The selected profile fixes provider and model. Conflicting `--provider` or
`--model` values refuse; `--base-url` cannot accompany a selected profile.
Supported step, context, timeout and output-cap settings can still be overridden.
Up to eight profiles are allowed. IDs begin with an ASCII letter and contain
at most 64 letters, digits, underscores or hyphens.

### Choose credentials and endpoints

Credential references are fixed lookups, not token values:

| Provider | Credential reference |
| --- | --- |
| `chatgpt` | `ipse-auth` |
| `openai` | `OPENAI_API_KEY` |
| `anthropic` | `ANTHROPIC_API_KEY` |
| `gemini` | `GEMINI_API_KEY` |
| `openrouter` | `OPENROUTER_API_KEY` |
| `ollama`, `openai_compatible`, `demo` | `none` |

Omit `credential` to use the provider's fixed lookup. Text roles never select
vector generation; configure that separately through [embeddings](extensions.md).

Only operator profiles may set `base_url`. Endpoints require HTTPS, or HTTP to
literal loopback or `localhost`, with a port in 1..65535. Credentials in URLs,
query strings and fragments refuse. Keep secrets out of paths: configuration
is inspectable. The selected API endpoint receives the provider credential and
request context. Subscription access stays on the public OpenAI endpoint.

`reasoning_effort` accepts `low`, `medium`, `high`, `xhigh` and `max` for exact
`gpt-6.1-sol` ChatGPT or OpenAI profiles. For Ollama, explicit `none` sends
`think: false`; choose it only for a server/model supporting that control.
Omitting it retains the model's default behavior. Other unsupported combinations
refuse. Anthropic extended-thinking configuration is unavailable.
OpenRouter accepts `none`, `low`, `medium`, `high`, `xhigh` and `max`; the pinned
upstream decides support. Compatible local profiles omit reasoning controls.
Gemini accepts `low`, `medium` and `high`; `none` omits its thinking control.
The selected model decides which thinking levels it supports.

### Use a Gemini API key

Create a Gemini API key in Google AI Studio and provide it privately through
`GEMINI_API_KEY`. `GOOGLE_API_KEY` is not selected implicitly. Both variables are
removed from tool and extension child environments. The key goes only in the
`x-goog-api-key` header, never in a URL. Vertex AI endpoints and OAuth/service
account authentication are unsupported.

Choose an available model explicitly; there is no Gemini default. Save this
complete example as `/private/path/gemini.json`, adjusting the model to one your
project can access:

```json
{
  "version": 1,
  "profiles": {
    "gemini": {
      "provider": "gemini",
      "model": "gemini-3.8-flash",
      "reasoning_effort": "low",
      "max_output_tokens": 1024
    }
  },
  "roles": {"main": "gemini"}
}
```

```sh
ipse config --config /private/path/gemini.json --no-project-config
ipse doctor --config /private/path/gemini.json --no-project-config
ipse chat --config /private/path/gemini.json --no-project-config --cwd /path/to/project
```

Use lowercase model IDs containing letters, digits, dots and hyphens, optionally
prefixed with `models/`. Query characters, fragments, other slashes and uppercase
IDs refuse before a request. Ipse uses the native stateless GenerateContent API.
Original response parts and signatures remain private continuation data in the
journal, in their original order. Thoughts never become displayed answer text.
Tool results retain the API's call IDs when supplied; synthetic host IDs do not
alter signed parts. Compaction retains the recent native history and replaces
older history with an explicitly historical user checkpoint.

Imported history has no invented signature. If Gemini refuses it, start a fresh
session or export a handoff. A `400` can also mean the model rejected a thinking
level; inspect the selected model before retrying. Free and paid tiers use the
same API-key interface. Ipse records API billing and cannot observe the tier;
configure a reviewed [rate card and budget](resources.md) for spend controls.
Missing usage counters stay partial rather than becoming zero.

### Pin an OpenRouter upstream

Choose an available model and its upstream slug from OpenRouter's
[routing documentation](https://openrouter.ai/docs/guides/routing/provider-selection).
Set `OPENROUTER_API_KEY` privately. Save this complete operator file as
`/private/path/router.json`, replacing `openai/YOUR_MODEL` and `openai` with your
matching model and upstream. No model is selected by default:

```json
{
  "version": 1,
  "profiles": {
    "router": {
      "provider": "openrouter",
      "model": "openai/YOUR_MODEL",
      "upstream": "openai",
      "data_collection": "deny",
      "max_output_tokens": 4096
    }
  },
  "roles": {"main": "router"}
}
```

```sh
ipse config --config /private/path/router.json --no-project-config
ipse doctor --config /private/path/router.json --no-project-config
ipse chat --config /private/path/router.json --no-project-config --profile router --cwd /path/to/project
```

The request restricts both upstream lists to your slug, disables fallbacks and
requires support for its parameters. `deny` excludes collecting endpoints;
`allow` requires an explicit profile change. This is separate from a zero-retention
guarantee. Only base slugs with 1..64 lowercase letters, digits, dots, underscores
or hyphens are supported; region/variant slash selectors are unavailable.
`openrouter/auto`, comma-separated models and `:nitro`/`:floor` routing shortcuts
refuse. An unsupported model/upstream/data-policy combination returns a refusal;
Ipse does not broaden the route.

The first stream chunk must report the requested model and upstream before
content is admitted. Later reported changes also refuse. A request may still be
charged; observed usage remains recorded. No undocumented alias conversion is
performed. The verified OpenRouter catalog pair `openai`/`OpenAI` is recognized;
all other upstream names require exact equality with the configured slug. Native
reasoning details remain private and preserve their order on
tool continuation. Changing the upstream or data policy requires a fresh session
or restoration of the original profile for resume.

### Connect a loopback compatible server

Start and configure the model service yourself. Save `/private/path/local.json`
with your actual installed model and loopback address:

```json
{
  "version": 1,
  "profiles": {
    "local": {
      "provider": "openai_compatible",
      "model": "YOUR_LOCAL_MODEL",
      "base_url": "http://127.0.0.1:8080/v1",
      "max_output_tokens": 1024
    }
  },
  "roles": {"main": "local"}
}
```

```sh
ipse config --config /private/path/local.json --no-project-config
ipse doctor --config /private/path/local.json --no-project-config
ipse chat --config /private/path/local.json --no-project-config --cwd /path/to/project
```

An explicit `base_url` and model are required. Only literal loopback or `localhost`
is accepted, including with HTTPS; credentials, queries and fragments in URLs
refuse. No API credential, provider-routing object or reasoning request is sent.
The local service supplies model behavior and standard Chat Completions usage.
Missing counters remain unavailable. This route is recorded as local billing;
remote compatible services require a separately defined billing policy.

### Route a child review

With subagents enabled, ask for a bounded task in the configured role:

```text
Review the error handling in lib/example.ex. Delegate a read-only check to the
configured review role. Include only the relevant files and question. Compare
its evidence with the source before reporting findings.
```

Before approving, inspect the task, selected context, profile or role, provider,
model and billing mode. A child selects one profile or one role. Without either,
it uses `routine`, or inherits the parent if `routine` is absent. Children get
fresh history and credential lookup, selected context and workspace instructions.
They do not receive the parent's transcript, tokens or native provider payloads.

Each child has at most six admitted main/helper calls and 120 seconds of active
work. Effects need separate approvals. An inherited output cap remains or narrows;
an incompatible route refuses before work. Main-model compaction stays on the
main profile. See [delegated work](usage.md) for a complete operating procedure.
Extensions request one-shot text inference separately through named profiles;
roles do not route those calls automatically.

### Allow a longer extension answer

For an extension that explicitly sends a version-three `model.complete` request,
save an operator file such as `/private/path/slow-answer.json`:

```json
{
  "version": 1,
  "settings": {"provider": "ollama", "model": "qwen3.5:9b", "timeout_ms": 480000},
  "profiles": {
    "answer": {
      "provider": "ollama",
      "model": "qwen3.5:9b",
      "credential": "none",
      "max_output_tokens": 8192,
      "model_call_timeout_ms": 480000
    }
  }
}
```

Inspect it before starting the separately configured extension:

```sh
ipse config --config /private/path/slow-answer.json --no-project-config
```

Expect the `answer` profile and root request limit to permit 480000 milliseconds.
This file neither installs an extension nor starts inference. The extension must
request profile `answer`, version three and its desired deadline. Its egress
approval shows the effective limit. This Ollama profile omits `reasoning_effort`,
so the model retains its default thinking policy; check the selected backend's
metadata before relying on that default.

The output allowance and the model's context window are separate limits. Context
must fit the prompt and all generated tokens, including reasoning. Increasing
`max_output_tokens` does not increase an Ollama server's context window. For a
server you manage, select its context through Ollama's
[context configuration](https://github.com/ollama/ollama/blob/main/docs/faq.mdx),
then check the loaded model's `context_length` in `/api/ps` after a request.
Ipse's ordinary provider profile does not configure that server setting.
For the optional measured comparison, use the explicit service context in the
[evaluation procedure](../developer/knowledge-evaluation.md#bind-a-fresh-service-and-local-output-paths).

`model_call_timeout_ms` accepts integers in 1000..600000. It replaces that
profile's ordinary `timeout_ms` for extension model calls only. The root request
limit and the extension's requested deadline still narrow it. Without the new
field, extension inference remains capped at 120000 milliseconds, even with a
larger ordinary timeout. Versions one and two still accept at most 120000.
Selecting the profile for main work or a child does not apply this override.

An SDK-2 invocation still has its original two-minute aggregate deadline. A
longer model allowance cannot extend that enclosing invocation. Use a worker
whose invocation contract supports the requested duration, such as the SDK-1
answer helper. On timeout, inspect the retained outcome and accounting before
starting new work. The remote request may have happened; Ipse does not replay it.

## Review project settings before trusting them

Project settings live at `.ipse/config.json`. Within Git, discovery runs from
the nearest repository boundary through `--cwd`; a worktree's `.git` file counts
as a boundary. Outside Git, only the selected directory contributes settings.
At most 17 scopes are examined.

Read the files, then compare these views:

```sh
ipse config --cwd /path/to/project --no-project-config
ipse config --cwd /path/to/project --trust-project-config
```

If the trusted view is acceptable, launch with the same explicit trust:

```sh
ipse chat --cwd /path/to/project --trust-project-config
```

Trust applies to that invocation and can change provider or billing selection.
It does not approve effects. Project profiles may use default endpoints and
assign roles, but cannot replace operator profile IDs, set endpoints or define
`model_call_timeout_ms`.
Automatically discovered aliases must resolve within the repository. An
explicit operator file may be a symlink.

Settings resolve from defaults, operator file, project scopes, selected profile,
allowlisted environment settings, then explicit CLI values. Nearer project
settings take precedence. Environment names include `IPSE_MAX_STEPS` and
`IPSE_TIMEOUT_MS`; booleans use `true` or `false`.

A project can tighten an existing sandbox policy to `native`, but cannot weaken
`native` to `off`. An explicit operator `IPSE_SANDBOX` or `--sandbox` can select
either supported mode.

## Set request and journal limits

| Setting | Default | Accepted values |
| --- | --- | --- |
| `provider` | `chatgpt` | `chatgpt`, `openai`, `ollama`, `anthropic`, `gemini`, `openrouter`, `openai_compatible`, `demo` |
| `model` | Provider default | Nonempty, at most 200 characters |
| `max_steps` | 30 calls per turn | 1..100000 |
| `context_bytes` | 400000 | 8192..16000000 bytes |
| `timeout_ms` | 120000 | 1000..600000 ms |
| `compact` | `true` | Boolean |
| `sandbox` | `off` | `off`, `native` |
| `subagents` | `false` | Boolean |
| `subagent_concurrency` | 1 | 1 or 2; 2 requires subagents |
| `max_output_tokens` | Absent | OpenAI API 16..1000000; Ollama/Anthropic/Gemini/OpenRouter/compatible 1..1000000 |

Output caps apply per supported request, including summaries. Subscription and
demo reject them. Model limits may be tighter; Anthropic defaults to 8192 and
Ollama summaries retain a 4096 cap. A per-request cap does not bound input tokens
or an invoice. Use [budgets](resources.md) for covered aggregate admission.
Provider responses have a separate 8 MiB accumulation ceiling; sign-in responses
allow 1 MiB. Redirects and automatic retries are disabled.

To lower mandatory journal bounds, add operator-only `journal` alongside
`settings`, or use this complete journal-only file:

```json
{
  "version": 1,
  "journal": {
    "max_bytes": 67108864,
    "max_events": 50000,
    "max_record_bytes": 8388608
  }
}
```

The host ceilings are 134217728 bytes, 100000 records and 16777216 JSON bytes per
record, excluding its newline. Minimums are 1024 bytes, two records and 512 bytes
per record. Omitted fields retain their ceiling. Values must be integers.
Project journal declarations refuse. Very small limits can refuse startup before
metadata fits. Children inherit the policy but have separate journals; the whole
state directory has no aggregate size limit.

Exhaustion preserves and seals the journal. Raising limits does not reopen it.
Run `ipse diagnose --resume SESSION_ID`, inspect uncertain effects and create a
[fresh-session handoff](recovery.md). Whole-history commands can also refuse
oversized legacy files; preserve those files for bounded inspection.

## Add optional behavior or recover a changed configuration

Use [Extensions](extensions.md) for `extensions` and operator-only
`extension_trust`, [Embeddings](extensions.md) for `embedding_profiles`,
[Budgets](resources.md) for `budget`, and [Diagnostic capture](observability.md)
for `observability`. Generic project trust grants none of these operator-only
authorities. Inspection shows extension option digests, not their contents;
the file itself remains a private configuration file, not a secret store.

Settings stay fixed for a session. `/context refresh` reloads instructions and
skills only. File/profile/role edits can refuse resume even if effective values
look equivalent, because source digests and execution pins are checked too.
Restore the original configuration for ordinary resume, or inspect the old
session and export a reviewed handoff into a fresh one. Never edit a journal to
make an incompatible route appear unchanged.
