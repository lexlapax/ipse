Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../../developer/configuration.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Routing requests with execution profiles

An execution profile chooses provider behavior without giving model text access
to credentials or routing policy. `Ipse.Profiles` owns validation, selection, and
child configuration. `Ipse.Config` owns source authority and precedence; Session
owns the selected execution identity throughout recovery.

Start in `lib/ipse/profiles.ex`. Read `validate_profile/1`, `select/3`,
`validate_route/2`, and `child_config/3` in that order. The progression mirrors a
profile's lifetime: accepted data, main selection, proposed child route, then a
new child's runtime configuration.

## Trace a routed child

A parent can propose a configured profile ID or a `routine`/`review` role in a
delegation request. The host resolves the role to an exact profile before
approval and child creation. Unknown routes refuse at this point, including
inside a parallel group. The model cannot choose an arbitrary provider URL.

The child starts with an allowlist of inherited host policy: workspace, sandbox,
instruction and skill inputs, approval policy, origin, journal/budget constraints,
and the parallel-child hardlink restriction. The selected profile supplies its
execution fields. Parent API keys, provider module, direct endpoint, conversations,
native continuation, profile catalog, and MCP state are dropped. Credential
lookup happens later in the child's owned request task for its selected provider.
Only a ChatGPT child receives the protected ChatGPT auth-directory reference.

Read the fixture named "child profile isolates credentials and parent payloads
while preserving host policy" in `test/profiles_test.exs`. It constructs a parent
containing synthetic secrets and native data, then inspects the child config.
Repeat that exercise for any newly inherited field. An allowlist is intentional:
a broad `Map.merge` can turn a convenience field into leaked authority.

## Understand profile identity

At most eight named profiles are accepted. `main`, `routine`, and `review` roles
refer to configured IDs. IDs begin with an ASCII letter and contain at most 64
letters, digits, underscores, or hyphens. Profiles are closed data; they do not
schedule workflows or classify tasks.

Operator IDs and every `base_url` are operator authority. Even trusted project
configuration cannot replace an operator profile or introduce an endpoint.
Nearer project scopes can replace project-defined profiles as whole records.
The selected main profile overlays file settings before environment/CLI limits,
but conflicting provider/model/endpoint overrides refuse.

All profile definitions, role assignments, and selected execution facts enter the
configuration fingerprint. Resume restores that identity before work and never
falls back to another profile, provider, or billing mode. Host routing facts in
child results precede the explicitly untrusted child answer; self-description in
an answer is not routing evidence.

Reasoning effort is separate from the model name. The dispatcher accepts `low`,
`medium`, `high`, `xhigh`, and `max` for exact model `gpt-6.1-sol` on the
OpenAI/ChatGPT paths. It maps effort into Responses `reasoning.effort` and
retains native continuation. Ollama accepts the explicit value `none`, mapped
to native `think: false`. An omitted value leaves the model's default unchanged.
Other combinations, including Anthropic thinking settings, remain unsupported.

Trace the Ollama selection through profile validation, execution manifests,
`ModelCall.prepare/2` and `Provider.Ollama.complete/4`. The existing execution
field carries the selection into approval and saved-request validation; no new
worker-controlled provider override is introduced. The Session fixture named
"explicit Ollama none is approved, sent on the wire and retained through idle
resume" checks the actual HTTP body, execution fact and saved journal. The
standalone model proof runs with both omitted and explicit `none` selections.
Its default run sends no `think` field; its `none` run sends native `false` and
restores that selection from the journal. Keep both controls when editing this path.

The operator must check the selected model's advertised `/api/show` thinking
values. Ipse requests a supported backend control; its execution record is not
proof of the model's internal computation. See the
[native API contract](https://docs.ollama.com/capabilities/thinking).

## Preserve inherited ceilings

A selected child's output cap can narrow its parent's cap, but cannot widen or
omit it. Combined provider capability checks precede delegation approval. A route
to a provider that cannot honor the inherited cap refuses. Child limits also
retain at most six model/helper calls, 120 seconds of active work, and the
parent's context ceiling. See [delegation](../../../../../developer/delegation.md) for scheduling and
[provider limits](../../../../../developer/provider-limits.md) for wire fields.

Separately granted `host.model` extensions keep a private helper-profile catalog
and protected credential reference. Those are host runtime values, never SDK
payloads or inherited API keys. Approval displays the actual egress origin and a
full-target SHA-256 derived from the adapter's `endpoint/1`. See
[extension model calls](extension-model-calls.md) before changing helper routing.

```sh
mix test test/profiles_test.exs test/profile_session_test.exs
```

Use these suites when changing selection or inheritance. They check role/ID
routing, unsupported settings, endpoint policy, secret isolation, native integrity,
output ceilings, and inert saved-session recovery. Add a fixture to the appropriate
layer rather than testing only the JSON schema.
