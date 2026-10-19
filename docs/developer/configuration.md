# Resolving and pinning configuration

Configuration is the first trust boundary a contributor encounters. A repository
may suggest a model or a smaller limit, but it cannot appoint its own credential
endpoint, authorize executable extensions, or replace operator policy. Follow a
configuration value through `Ipse.Config.resolve/4` before changing its behavior.
The [operator guide](../operator/configuration.md) explains how users supply it.

## Follow one setting into a session

`lib/ipse/config.ex` canonicalizes the workspace, finds the nearest Git boundary,
and loads version-1 JSON sources from operator scope through project scopes.
Outside a repository, only the launch directory contributes project settings.
Project files require explicit current-run trust. Missing default files are
optional; an explicitly selected operator file must exist.

Resolution proceeds in this order: built-in defaults, operator file, project
files from root to launch directory, selected main profile, allowlisted
environment settings, and explicit CLI options. Nearer profiles replace whole
profile definitions; role assignments merge by key. `runtime_settings/1` converts
only known field names to atoms. Do not create atoms from arbitrary JSON keys.

The result keeps effective settings, field provenance, source descriptors, and a
canonical fingerprint. Source descriptors include paths, scope, and SHA-256.
Whitespace changes alter a source digest and therefore invalidate resume even
when decoded settings are equal. Equivalent CLI overrides do not change identity
merely because their provenance differs. Raw file contents never become model
context or journal metadata.

For a concrete exercise, read the precedence fixture in
`test/config_test.exs` and follow `max_steps` through its operator, project,
environment, and CLI assignments. Then inspect `overlay/3` and `manifest/1`.
The winning value and its provenance answer different questions.

```sh
mix test test/config_test.exs test/config_session_test.exs
```

The first suite checks source resolution and closed validation. The second checks
that saved sessions reject configuration drift before work or journal repair.
These fixtures do not require a provider account.

## Keep authority separate from precedence

Several fields need stricter rules than ordinary last-writer precedence:

| Input | Authority rule |
| --- | --- |
| Project `sandbox` | Can tighten to `native`; cannot replace an earlier `native` with `off` |
| Operator environment or CLI sandbox | May explicitly select either supported mode |
| Profile `base_url` and operator profile IDs | Project scopes cannot introduce endpoints or replace operator IDs |
| `embedding_profiles` | Operator-only separate registry; text profile roles never select it |
| `budget`, `journal`, extension trust, capture policy | Operator-only policy; project declarations refuse |
| Extension selection/options | Require independent artifact/trust admission before callbacks |

Generic project trust does not waive these checks. Discovery validates data; it
never opens an extension artifact, invokes code, or installs a dependency.
Extension options are represented by digest in inspected manifests. Do not place
credentials in options; hashing inspection output does not protect the file.

## Read the closed settings contract

Files are at most 16 KiB, with at most 17 sources. Duplicate keys, unknown fields,
unsupported versions, malformed UTF-8/JSON, and escaping project aliases refuse.
Errors do not include file contents. Environment input uses a fixed allowlist,
not a dump of the operator's process environment.

| Setting | Default | Accepted range or values |
| --- | --- | --- |
| `provider` | `chatgpt` | `chatgpt`, `openai`, `ollama`, `anthropic`, `demo` |
| `sandbox` | `off` | `off`, `native` |
| `max_steps` | 30 | 1–100,000 |
| `context_bytes` | 400,000 | 8,192–16,000,000 |
| `compact` | true | Boolean |
| `subagents` | false | Boolean |
| `subagent_concurrency` | 1 | 1–2; 2 requires subagents |
| `timeout_ms` | 120,000 | 1,000–600,000 |
| `max_output_tokens` | absent | Provider-specific validation in [provider limits](provider-limits.md) |

`model` is a nonempty string of at most 200 characters. When omitted, resolution
selects the configured provider's default in `@models`; consult that table when
updating defaults. [Profiles](model-profiles.md), [budgets](budgets.md), and
[persistence](persistence.md) own their nested schemas.

`EmbeddingProfiles` owns its separate registry and selected execution snapshot.
The CLI explicitly carries that registry into host runtime; delegation and routed
child allowlists preserve the private operator reference. Worker SDK values get
only the bounded selected facts. Follow `test/embedding_config_test.exs` to check
project refusal and fingerprint inclusion, then the
[embedding walkthrough](extension-embedding-actions.md) for destination pinning.

## Preserve resume identity when adding a field

Session metadata pins the manifest. Resume compares it before requesting
inference or repairing a torn tail. Legacy metadata without a manifest accepts
only a configuration with no loaded files, alongside existing execution checks.
Instruction refresh reloads workspace text and skills, not execution policy.

The actual main route is also pinned by origin and target digest, including direct
CLI or embedded base URLs. Invalid routes refuse before journal creation. Explicit
and implicit forms of the same default route compare equally. Legacy recovery
checks recorded request endpoint hashes; request-free legacy sessions cannot prove
an old custom route and accept only an implicit default or exactly pinned profile.
Use a fresh session when the old destination is unknown.

To add a setting, update the schema, fixed runtime-key map, environment parser,
manifest/fingerprint policy, CLI conversion, and resume checks together. Decide
whether absence must preserve legacy fingerprints. Add a precedence fixture and
a changed-saved-value fixture. A field that works only on fresh CLI launches is
an incomplete configuration change.
