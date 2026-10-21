# Configure a workspace, model and session

Keep repeatable settings in a private version-1 JSON file. Inspect the selected
provider, model and endpoint before submitting work. Configuration inspection
needs no model account or running service. Starting a conversation requires the
selected service and model to be available.

The commands below use an installed `ipse`. In a source checkout, use
`./bin/ipse`; in an extracted release, use `./ipse`.

## Save and inspect operator settings

Create `~/.ipse/config.json`, or another private file outside your workspace:

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
| `ollama`, `demo` | `none` |

Omit `credential` to use the provider's fixed lookup. Text roles never select
vector generation; configure that separately through [embeddings](embeddings.md).

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
main profile. See [delegated work](subagents.md) for a complete operating procedure.
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
| `provider` | `chatgpt` | `chatgpt`, `openai`, `ollama`, `anthropic`, `demo` |
| `model` | Provider default | Nonempty, at most 200 characters |
| `max_steps` | 30 calls per turn | 1..100000 |
| `context_bytes` | 400000 | 8192..16000000 bytes |
| `timeout_ms` | 120000 | 1000..600000 ms |
| `compact` | `true` | Boolean |
| `sandbox` | `off` | `off`, `native` |
| `subagents` | `false` | Boolean |
| `subagent_concurrency` | 1 | 1 or 2; 2 requires subagents |
| `max_output_tokens` | Absent | OpenAI API 16..1000000; Ollama/Anthropic 1..1000000 |

Output caps apply per supported request, including summaries. Subscription and
demo reject them. Model limits may be tighter; Anthropic defaults to 8192 and
Ollama summaries retain a 4096 cap. A per-request cap does not bound input tokens
or an invoice. Use [budgets](budgets.md) for covered aggregate admission.
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
`extension_trust`, [Embeddings](embeddings.md) for `embedding_profiles`,
[Budgets](budgets.md) for `budget`, and [Diagnostic capture](observability.md)
for `observability`. Generic project trust grants none of these operator-only
authorities. Inspection shows extension option digests, not their contents;
the file itself remains a private configuration file, not a secret store.

Settings stay fixed for a session. `/context refresh` reloads instructions and
skills only. File/profile/role edits can refuse resume even if effective values
look equivalent, because source digests and execution pins are checked too.
Restore the original configuration for ordinary resume, or inspect the old
session and export a reviewed handoff into a fresh one. Never edit a journal to
make an incompatible route appear unchanged.
