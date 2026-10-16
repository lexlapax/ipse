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
shown. Unknown fields, credentials, approval policies, scripts, endpoints, MCP
servers and filesystem-root changes are rejected. Authentication remains in
protected auth storage or the existing explicit provider environment variables.
This loader does not expose private `.ipse` files through general tools.

Precedence is built-in defaults, operator file, project root, nearer directory,
`IPSE_*` environment settings, then CLI flags. Environment keys match the setting
names in uppercase, such as `IPSE_MAX_STEPS`; booleans accept `true` or `false`.
`--config PATH` or `IPSE_CONFIG` replaces the operator file and must exist.
Default files may be absent. Each file is at most 16 KiB; at most 17 candidate
scopes are examined. JSON must use version 1. Model names are bounded to 200
characters; steps 1..100000, context 8192..16000000 bytes, timeout 1000..600000 ms.
Concurrency is 1 or 2, with 2 requiring enabled subagents.

Repository settings require **`--trust-project-config` on each invocation**.
Review them before trusting, since they can select a provider/billing mode or
execution policy. `--no-project-config` ignores them. These flags grant no
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
version-1 schema. A later same-ID profile replaces the whole earlier definition.
