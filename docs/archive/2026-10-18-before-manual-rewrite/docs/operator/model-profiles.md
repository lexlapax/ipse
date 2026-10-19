> Historical reference only. Snapshot of `docs/operator/model-profiles.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../operator/model-profiles.md).

# Model profiles and task roles

Named profiles select provider, model, bounded execution limits and a fixed
credential reference in the [scoped JSON configuration](configuration.md).
Operator files own their declared profile identities and all custom endpoints;
trusted project files may add profiles using provider defaults or assign roles,
but cannot replace an operator profile or set `base_url`.
Explicit `--profile ID` overrides `IPSE_PROFILE`, then the configured `main`
role. Without profiles, existing provider/model selection remains available.

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
      "model": "qwen3.5:9b",
      "max_steps": 4,
      "max_output_tokens": 1024,
      "timeout_ms": 120000
    }
  },
  "roles": {"main": "strong", "routine": "local", "review": "strong"}
}
```

Install/configure the chosen model service separately; profiles never download
models or sign in for you. Up to eight profiles are allowed. IDs begin with an
ASCII letter and use at most 64 letters/digits/underscore/hyphen characters.
Every profile requires provider/model. Optional limits are `max_steps`,
`context_bytes`, `timeout_ms` and supported `max_output_tokens`, using
configuration bounds. Subscription profiles reject output caps; the public
subscription interface does not support that field. Operator-only `base_url`
selects an explicit HTTPS endpoint, or HTTP on literal loopback/localhost, with
a valid URI and port in 1..65535. URLs cannot contain userinfo, queries or fragments;
keep secrets out of paths too, since configuration is nonsecret inspection data.
API keys and supplied context go to the configured endpoint: review it as an
egress/credential decision. Subscription endpoints
are restricted to the public OpenAI endpoint. An omitted endpoint uses the
provider default. Models cannot change endpoints through delegation arguments.
The same HTTPS/loopback and URL-shape policy applies to `--base-url` and embedded
adapter dispatch; a CLI override cannot send API credentials over remote cleartext.

Credential references are fixed by provider: `ipse-auth` for ChatGPT,
`OPENAI_API_KEY` for OpenAI API, `ANTHROPIC_API_KEY` for Anthropic, and `none` for
Ollama/demo. These refer to existing protected auth or environment lookup, never
inline secrets or arbitrary environment-variable names. Profiles do not change
billing modes silently. Missing credentials/service/model fail without fallback.

`reasoning_effort` currently supports `low`, `medium`, `high`, `xhigh` and `max`
only for exact `gpt-6.1-sol` ChatGPT/OpenAI profiles. Other models/providers reject
this field rather than ignore it. This conservative allowlist follows the
[public model documentation](https://developers.openai.com/api/docs/models/gpt-6.1-sol).
Ollama uses its model default thinking controls; configurable Ollama thinking and
Anthropic extended thinking are not implemented. Their APIs differ, so the OpenAI
setting is not translated to them.

```sh
./bin/ipse config --cwd /path/to/project --trust-project-config --profile strong
./bin/ipse chat --cwd /path/to/project --trust-project-config --profile strong --subagents
```

A selected profile owns provider/model/endpoint. Conflicting `--provider`,
`--model` or `--base-url` overrides are rejected; choose another profile. CLI
step/context/timeout/output-cap overrides still take precedence. Project files require
current-run trust. Neither profiles nor roles grant effect permissions.

The parent can propose `delegate` with a configured `profile` ID or a configured
`routine`/`review` role, with bounded task/context. Omit both to use `routine`, or
inherit the parent if no routine role exists. Both routing fields together are
invalid. Parallel children can choose independently within the same allowlist.
Delegation still requires approval; child effects receive separate parent-mediated
approvals. Children cannot use MCP, delegate again or ask operator questions.
Profiles allow a remote parent/local child or another explicitly configured
provider; selected context and applicable workspace instructions go to that
provider. Review the visible configuration and full delegation arguments first.

Children receive fresh conversations and their own credential lookup. Parent
history, credentials, endpoint and opaque provider payloads do not cross to a
selected child profile. Child journals record profile/role/provider/model/effort;
host routing facts accompany the untrusted child result. `/info` shows the active
profile and effort, separately from provider-reported model identity.
Child limits remain at most six admitted main/helper calls and 120 seconds, with bounded
context/results; this is additional to parent work. A configured
[session-tree budget](budgets.md) shares host reservations across parent and
children, retaining uncertain liability. An inherited child keeps the parent's output cap;
a selected child can narrow that cap and cannot remove
or widen it. Routing an inherited cap to an unsupported provider refuses before
delegation starts. No automatic fallback or separate summary routing is provided.
Main-model compaction stays on the main
profile. Changing profile definitions/roles invalidates resume conservatively;
start a new session after policy changes.

Reviewed extensions with `host.model` can separately name a profile for one-shot
inference. Their own egress approval shows the actual scheme/host/port origin and
a digest of the full wire target; URL paths and credentials are not included in
that destination display. They supply explicit input and do
not inherit the main conversation, API key or native continuation. A permitted
child extension can use the same host-managed profile catalog, while its requests
retain the child's origin and share tree admission. Profile roles do not select
these calls implicitly. See [model-call operation](extensions.md#accounted-model-calls).
