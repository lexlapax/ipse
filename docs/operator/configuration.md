# Configure a workspace and session

Use a version-1 JSON file to keep repeatable settings out of command lines.
Inspect the effective configuration before making model requests, especially
when a project proposes a provider or endpoint change. This guide uses `ipse`;
see the [manual entry point](index.md) for source/release command substitutions.

## Create an operator configuration

Create a private file outside the workspace, such as `~/.ipse/config.json`.
This complete example selects a local service; it does not install that service
or download the named model:

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

`IPSE_HOME/config.json` is the default operator file. `IPSE_HOME` defaults to
`~/.ipse`. Select another existing file with `--config PATH` or `IPSE_CONFIG`.
An explicitly selected file must exist; an absent default file is allowed.

Inspect without authentication, network calls, or inference:

```sh
ipse config --config /path/to/operator.json --no-project-config
```

Expect effective non-secret values, provenance, source paths/digests, and a
fingerprint. Keep credentials out of JSON. Use Ipse's protected subscription
login or the selected provider's supported environment variable. Unknown fields,
duplicate keys, inline credentials, scripts, approval policies, MCP definitions,
and filesystem-root changes are rejected.

Start a real conversation only after reviewing the output:

```sh
ipse chat --config /path/to/operator.json --no-project-config --cwd /path/to/project
```

The selected model/service must already be available. This command uses that
service when you submit a task. Configuration inspection grants no action
permissions; interactive approvals still apply.

## Decide whether to trust project settings

Project files live at `.ipse/config.json`. Inside Git, Ipse searches from the
nearest repository boundary through `--cwd`; a worktree `.git` file also defines
a boundary. Outside Git, it searches only the selected directory.

Review those files, then compare the untrusted and explicitly trusted views:

```sh
ipse config --cwd /path/to/project --no-project-config
ipse config --cwd /path/to/project --trust-project-config
ipse chat --cwd /path/to/project --trust-project-config
```

Project trust is required on each invocation. It allows those settings to affect
this run, including provider/billing selection. It does not authorize writes,
shell, MCP, or delegation. Automatically discovered aliases must resolve within
the repository. An explicitly selected operator file may itself be a symlink.

Ordinary precedence, lowest first, is defaults, operator file, project root,
nearer directory, environment, then CLI. Environment names use uppercase setting
names, such as `IPSE_MAX_STEPS`; boolean values are `true` or `false`.

Project sandbox settings can tighten to `native` but cannot weaken an existing
`native` selection to `off`. Explicit operator `IPSE_SANDBOX` or `--sandbox` can
select either value. This exception retains the stricter value's provenance.

## Set execution limits

| Setting | Default or behavior | Accepted range |
| --- | --- | --- |
| `provider` | `chatgpt` | `chatgpt`, `openai`, `ollama`, `anthropic`, `demo` |
| `model` | Provider default | At most 200 characters |
| `max_steps` | 30 model calls per turn | 1..100000 |
| `context_bytes` | 400000 | 8192..16000000 bytes |
| `timeout_ms` | 120000 ms provider request deadline | 1000..600000 ms |
| `compact` | `true` | Boolean |
| `sandbox` | `off` | `off` or `native` |
| `subagents` | `false` | Boolean |
| `subagent_concurrency` | 1 | 1 or 2; 2 requires subagents |
| `max_output_tokens` | Omitted | OpenAI API 16..1000000; Ollama/Anthropic 1..1000000 |

A file is at most 16 KiB; at most 17 candidate scopes are examined.
`max_output_tokens` caps each supported request, including summaries. ChatGPT
subscription and demo reject it. Adapter/model limits can be tighter;
Anthropic's default is 8192 and Ollama summaries retain a 4096 cap. A per-request
cap is separate from [aggregate admission budgets](budgets.md) and does not limit
input tokens or promise an invoice ceiling.

Provider response bodies have an independent 8 MiB accumulation ceiling and
sign-in responses a 1 MiB ceiling. Exceeding these stops the attempt. Redirects
and automatic retries are disabled. Keep TLS verification enabled.

## Bound journal growth

To lower the mandatory per-journal limits, add operator-only `journal` alongside
`settings` in the same version-1 file:

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

| Field | Default and host ceiling | Minimum |
| --- | --- | --- |
| `max_bytes` | 134217728 bytes, 128 MiB | 1024 |
| `max_events` | 100000 records | 2 |
| `max_record_bytes` | 16777216 JSON bytes, excluding newline | 512 |

Omitted fields keep their ceiling. Values must be integers; unlimited settings
and project declarations are refused. Very small limits can refuse startup if
metadata and a terminal receipt cannot fit. Children have separate journals with
the inherited policy. These limits do not bound the whole state directory.

When a limit is exhausted, Ipse preserves and seals the journal. Raising limits
does not reopen it. Inspect with `ipse diagnose --resume SESSION_ID`, check
uncertain effects, and use a [fresh-session handoff](recovery.md). Oversized legacy
files may need developer-assisted bounded inspection because whole-history
commands can also refuse them.

## Add profiles and optional features

The operator file can also contain these documented top-level objects:

- `profiles` and `roles` select [named models](model-profiles.md). Projects can
  add default-endpoint profiles but cannot replace operator IDs or set endpoints.
- `budget` reserves covered work for [one session tree](budgets.md).
- `extensions` selects instances; operator-only `extension_trust` grants their
  reviewed ceilings and optional storage/service bindings. See [Extensions](extensions.md).
- Operator-only `observability` controls [diagnostic capture](observability.md).

Project trust does not grant any operator-only object. Keep endpoint changes in
operator profiles. Config inspection prints extension option digests rather
than contents, but configuration is not a secret store.

## Change configuration without losing recovery

Files are fixed for a session. `/context refresh` reloads instructions and skills,
not settings. Start a new session to adopt a file edit.

Resume checks saved fingerprints and source digests, as well as execution-policy
pins. Changed files can refuse resume even if a value appears equivalent. Old
sessions without manifests accept no newly introduced configuration. Restore the
original file/profile/endpoint for ordinary resume. If the policy must change,
inspect the old session and export a reviewed handoff into a fresh session.
Never edit a journal to make incompatible configuration appear unchanged.
