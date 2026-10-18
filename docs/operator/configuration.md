# Scoped configuration

Ipse reads data-only JSON from `IPSE_HOME/config.json` (default
`~/.ipse/config.json`) and `.ipse/config.json` in the nearest Git repository,
from its root through the selected `--cwd` directory. A Git worktree `.git`
file is a boundary too. Outside a repository, only the selected directory is
searched. It never inherits configuration outside that boundary.

```json
{
  "version": 1,
  "settings": {
    "provider": "ollama",
    "model": "qwen3.5:9b",
    "max_steps": 30,
    "max_output_tokens": 1024,
    "context_bytes": 400000,
    "timeout_ms": 120000,
    "compact": true,
    "sandbox": "native",
    "subagents": false,
    "subagent_concurrency": 1
  }
}
```

Provider values are `chatgpt`, `openai`, `ollama`, `anthropic`, and `demo`;
subscription and API billing stay separate. Supported settings are exactly those
shown. Unknown fields, inline credentials, approval policies, scripts, MCP
servers and filesystem-root changes are rejected. JSON endpoint settings belong only
to operator-defined [model profiles](model-profiles.md), not project settings or
profiles. Authentication remains in
protected auth storage or the existing explicit provider environment variables.
This loader does not expose private `.ipse` files through general tools.

Ordinary setting precedence is built-in defaults, operator file, project root, nearer directory,
`IPSE_*` environment settings, then CLI flags. Environment keys match the setting
names in uppercase, such as `IPSE_MAX_STEPS`; booleans accept `true` or `false`.
Sandbox policy is an exception within project scopes: projects may select
`native` but cannot replace an already selected `native` with `off`, including
one selected by the operator file or an ancestor project. The stricter value's
provenance remains visible. Explicit operator `IPSE_SANDBOX` or `--sandbox` still
overrides those files; `--sandbox off` is an intentional operator choice.
`--config PATH` or `IPSE_CONFIG` replaces the operator file and must exist.
Default files may be absent. Each file is at most 16 KiB; at most 17 candidate
scopes are examined. JSON must use version 1. Model names are bounded to 200
characters; steps 1..100000, context 8192..16000000 bytes, timeout 1000..600000 ms.
Concurrency is 1 or 2, with 2 requiring enabled subagents. `max_output_tokens` is
optional: 16..1000000 for OpenAI API, 1..1000000 for Ollama/Anthropic. ChatGPT
subscription and demo reject it. Omit it to keep the previous provider behavior.
Use `IPSE_MAX_OUTPUT_TOKENS` or `--max-output-tokens N` for explicit overrides.
This is a per-request generation cap, including summary requests, not an aggregate
budget or invoice limit. Optional operator-only [shared budgets](budgets.md)
configure aggregate admission separately. Existing lower adapter limits still apply: Anthropic
defaults to 8192 and Ollama summaries to 4096. Model/account limits may be tighter.
Independently of token settings, provider HTTP response consumption has an 8 MiB
ceiling for all success/error statuses and chunked bodies; internal helper
requests can set smaller limits. Exceeding it stops the
attempt without executing returned tools or retrying inference. This is a host
transport accumulation bound, not an OS memory cap, token estimate or billing
guarantee. Automatic redirects and retries remain disabled.
Authentication separately caps every response status at 1 MiB before accumulation.
Both clients use verified TLS and the shared operator proxy policy.
See [usage and budget boundaries](usage-accounting.md#unknowns-and-recovery).

Repository settings require **`--trust-project-config` on each invocation**.
Review them before trusting, since they can select a provider/billing mode or
tighten sandbox policy. `--no-project-config` ignores them. These flags grant no
mutation, shell, MCP or delegation permission; ordinary approvals still apply.
Automatically discovered project aliases must resolve inside the repository.
An explicitly selected operator file can be a symlink alias.

```sh
./bin/ipse config --cwd /path/to/project --no-project-config
./bin/ipse config --cwd /path/to/project --trust-project-config
./bin/ipse chat --cwd /path/to/project --trust-project-config --max-steps 20
```

`ipse config` is local: it prints effective non-secret settings, field provenance,
source paths/digests and a fingerprint without authentication or inference.
Sessions using files print that manifest before accepting work and retain it in
their private journal. Files are fixed for the session; `/context refresh` reloads
instructions only. Restart to load configuration changes.

Resume retains saved execution settings unless explicitly overridden and checks
the effective fingerprint and source digests. Changed files or execution policy
refuse resume without replay. Restore the original configuration or start a new
session. Old sessions without a manifest can resume only when no config file is
newly introduced. Current action approvals are always separate from saved data.
Named model profiles and main/routine/review routing are available; see
[model profiles](model-profiles.md). Top-level `profiles` and `roles` extend this
version-1 schema. Profile IDs declared in the operator file cannot be replaced by
project/directory files, even with current-run trust. Projects may add profiles
using provider defaults and assign roles to configured IDs. Any project profile
with `base_url` refuses before session creation or credential-bearing HTTP dispatch;
configure custom endpoints in the operator file. Nearer project files can still
replace a project-defined same-ID profile as a whole. Roles retain ordinary scoped
precedence; neither roles nor project trust grant action permissions.

After moving an old project endpoint into operator configuration, inspect the
effective configuration and start a new session. Existing source/fingerprint and
runtime pins are not rewritten to make old sessions resume; use a reviewed
[handoff](recovery.md) if recovery context is needed.
Operator-only top-level `budget` pins a per-session-tree policy with explicit
reservations; project files cannot set or replace it. Omission leaves it disabled.
It shares the ordinary 16 KiB file limit and source/fingerprint resume checks.

Operator-only top-level `journal` may lower the mandatory per-journal limits:

```json
{
  "version": 1,
  "journal": {"max_bytes": 67108864, "max_events": 50000}
}
```

| Field | Default/host ceiling | Minimum |
| --- | --- | --- |
| `max_bytes` | 134217728 bytes (128 MiB) | 1024 |
| `max_events` | 100000 records | 2 |
| `max_record_bytes` | 16777216 encoded JSON bytes, excluding newline | 512 |

Omitted fields keep their ceilings. Values must be integers; unlimited values and
project declarations are refused, including trusted projects. A small policy can
refuse startup if it cannot fit metadata and the reserved terminal receipt.
Routed/inherited children keep the policy for their separate journals. These are
not whole-directory disk, process-memory or invoice guarantees. No CLI/environment
override disables the guard. Config inspection displays the effective limits;
file/source fingerprint rules remain unchanged.

Exhaustion preserves history and seals the journal; ordinary resume cannot reopen
it. Saved diagnosis reports the reason/limits. Review uncertain effects, then use
an explicit [fresh-session handoff](recovery.md); increasing limits does not unseal
the old file. Oversized legacy files are refused unchanged; automatic diagnosis
and export can also refuse. Developer-assisted bounded inspection and reviewed
notes for a fresh session may be needed. Source-page inspection has its own
1 MiB record bound and cannot export every legacy record.

Extension import/inspection and data-only selections are also available through
`extensions` and operator-only `extension_trust`; see
[extensions](extensions.md#configure-selections) for schemas, scope, temporary
selection, `--no-extensions` and current activation limits. Config inspection
shows option digests rather than contents. Duplicate JSON keys, including nested
ones, are rejected. Existing configurations without extension data keep their
previous resume fingerprint.

Operator-only top-level `observability` controls optional metadata capture.
`IPSE_OBSERVABILITY` and `--observability off|local|export` override its mode;
project files cannot set it. Sink selection still uses separate extension trust
and instances. See [capture and stop procedures](observability.md) for the closed
policy schema, privacy/retention limits and `/observability off`. Capture mode
overrides do not change the tool fingerprint; changing the file still changes its
source identity.
