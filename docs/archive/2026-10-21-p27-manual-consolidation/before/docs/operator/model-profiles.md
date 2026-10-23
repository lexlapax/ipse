Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../../operator/configuration.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Select models with named profiles

Use profiles when you repeatedly choose the same provider, model, and limits, or
want a child review to use a separately chosen model. A profile names an existing
service. It does not install a model, sign you in, or permit effects.

These profiles route text generation. Configure vector generation through the
separate operator [embedding profiles](../../../../2026-10-22-before-structural-consolidation/docs/operator/embeddings.md); text roles never select
an embedding model automatically.

## Configure a main model and a local routine model

Save this complete version-1 example in an operator file such as
`/private/path/models.json`. The subscription model needs `ipse login`. The local
model must already be installed and served by Ollama.

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
      "reasoning_effort": "none",
      "timeout_ms": 120000
    }
  },
  "roles": {"main": "strong", "routine": "local", "review": "strong"}
}
```

Inspect the route locally, then launch:

```sh
ipse config --config /private/path/models.json --no-project-config --profile strong
ipse chat --config /private/path/models.json --no-project-config --profile strong --cwd /path/to/project
```

The first command makes no inference. In chat, `/info` shows the active profile,
requested model, reasoning effort, and any provider-reported model identity.
Submitting work uses the selected service and billing mode. A failed local
service or inaccessible subscription model does not trigger fallback.

Explicit `--profile ID` overrides `IPSE_PROFILE`, then the configured `main` role.
A selected profile owns provider/model/endpoint. Conflicting `--provider`,
`--model`, or `--base-url` flags are rejected. Step, context, timeout, and supported
output-cap flags can still narrow or override their respective settings.

## Choose endpoints and credentials deliberately

Up to eight profiles are allowed. An ID starts with an ASCII letter and contains
at most 64 letters, digits, underscores, or hyphens. Every profile needs
`provider` and `model`. Optional execution fields use the
[configuration bounds](configuration.md#set-execution-limits).

Only operator profiles can set `base_url`. Use HTTPS, or HTTP with literal
loopback/localhost, and a port in 1..65535. Userinfo, query strings, and fragments
are refused. Keep secrets out of paths because configuration is inspectable.
Your API key and selected context go to that endpoint. Subscription endpoints
remain restricted to the public OpenAI endpoint. CLI endpoints follow the same
transport policy.

Credential references are fixed for each provider:

| Provider | Reference |
| --- | --- |
| `chatgpt` | `ipse-auth` |
| `openai` | `OPENAI_API_KEY` |
| `anthropic` | `ANTHROPIC_API_KEY` |
| `ollama`, `demo` | `none` |

References are lookups, never inline secrets or arbitrary environment names.
Profiles may omit the reference to use their provider's fixed behavior.
`reasoning_effort` accepts `low`, `medium`, `high`, `xhigh`, and `max` for exact
`gpt-6.1-sol` ChatGPT/OpenAI profiles. For Ollama, the explicit value `none` sends
`think: false`. Use it only when your selected server/model advertises `false`
in its `/api/show` thinking controls. The local example selects that setting
deliberately; omit it to retain the model's default behavior. See
[Ollama's thinking controls](https://docs.ollama.com/capabilities/thinking).

Inspect the effective profile before submitting work:

```sh
ipse config --config /private/path/models.json --no-project-config --profile local
ipse chat --config /private/path/models.json --no-project-config --profile local --cwd /path/to/project
```

Thinking selection appears in execution facts and helper approvals. It requests
backend behavior; it does not establish that the model did no internal work or
that requests cost nothing. Unsupported settings for other provider/model
combinations reject. Anthropic extended-thinking controls remain unavailable.

Trusted project files may add profiles using default endpoints and assign roles.
They cannot replace operator-owned IDs or set `base_url`. Review project files
and pass `--trust-project-config` for each run that uses them.

## Ask for a routed child task

With subagents enabled, enter a bounded request:

```text
Review the error handling in lib/example.ex. Delegate a read-only check to the
configured review role. Include only the relevant files and question. Compare
its evidence with the source before reporting findings.
```

Inspect the proposed task, selected context, profile/role, provider, model, and
billing mode before approving delegation. A child can select one configured
profile or one configured role, not both. If neither is provided, it uses
`routine`, or inherits the parent when that role is absent. No model may invent
a new endpoint through delegation arguments.

A routed child gets fresh history and credential lookup, selected context, and
workspace instructions. It does not receive the parent's full conversation,
credentials, or native provider payloads. Additional requests consume additional
resources. Each child has at most six admitted main/helper calls and 120 seconds
of active work. Its effects need separate approvals. See [Subagents](../../../../2026-10-22-before-structural-consolidation/docs/operator/subagents.md).

Inherited output caps remain or narrow for selected children. Routing to a
provider that cannot support the inherited cap refuses before work starts.
Main-model compaction stays on the main profile. Extensions can separately request
approved one-shot inference through named profiles; roles do not route those
calls automatically. See [accounted model calls](../../../../2026-10-22-before-structural-consolidation/docs/operator/extensions.md#accounted-model-calls).

## Recover after a profile change

Changing profile definitions or roles can invalidate resume. Keep the original
configuration for an existing session, or use [Recovery](../../../../../operator/recovery.md) to inspect
it and create a reviewed fresh-session handoff. Missing credentials, unavailable
models, and refused endpoints require an explicit operator decision. Do not solve
one of these errors by silently selecting another billing route.
