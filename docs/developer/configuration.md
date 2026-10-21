# Resolve configuration and route model requests

A configuration value crosses three boundaries: source admission, runtime
admission and request dispatch. Trace those boundaries before adding a setting
or changing model routing. Repository data can suggest a model or a tighter
limit; it cannot select its own credential endpoint or authorize an effect.
The [operator procedure](../operator/configuration.md) supplies complete files
and commands for users.

## Follow a value through its owners

| Owner | Input and result | Authority retained elsewhere |
| --- | --- | --- |
| `Config.resolve/4` | Scoped JSON, selected profile, allowlisted environment and CLI settings become effective values, provenance and fingerprint | No credential lookup, executable artifact launch or inference |
| `Config.runtime/2` | Effective settings and explicit client facts become admitted Session policy | CLI retains interaction policy and credential preflight |
| `Profiles` | Closed profile data and role IDs become exact main/child execution facts | No task classification, workflow scheduler or automatic provider fallback |
| `Provider.Request` | An admitted request resolves fresh credentials in its owned task | Session retains admission, accounting and history |
| `Session` | Selected runtime and saved evidence become one owned conversation | Journal/source validation precedes recovery and effects |

Start in `lib/ipse/config.ex`, then read `Profiles.validate_profile/1`,
`select/3`, `validate_route/2` and `child_config/3`. Finish with
`lib/ipse/provider/request.ex` and Session's initialization checks.

`Config.resolve/4` canonicalizes the workspace and finds the nearest Git
boundary, including a worktree's `.git` file. Outside Git, only the launch
directory contributes project settings. Missing default files are optional;
an explicitly selected operator file must exist. Project files require explicit
current-run trust.

Resolution overlays built-in defaults, operator JSON, project scopes from root
to launch directory, the selected main profile, allowlisted environment values
and explicit CLI fields. Nearer profile records replace whole project-defined
profiles; role assignments merge by key. The selected main route cannot be
silently replaced by conflicting provider/model settings or a direct endpoint.
Config's closed `@providers` table owns supported provider atoms and defaults.
`@fields`, `@option_keys` and `@env_keys` admit only named settings. Arbitrary
JSON keys never create atoms.

## Reproduce precedence and identity drift

Run `iex -S mix` from the repository root. Build a synthetic operator source and
choose the same setting in the environment and CLI layers:

```elixir
scratch = Path.join(System.tmp_dir!(), "ipse-config-exercise-" <> Ipse.Usage.id())
workspace = Path.join(scratch, "project")
home = Path.join(scratch, "operator")
File.mkdir_p!(Path.join(workspace, ".git"))
File.mkdir_p!(home)
path = Path.join(home, "config.json")
File.write!(path, Jason.encode!(%{version: 1, settings: %{provider: "demo", max_steps: 4}}))
{:ok, first} = Ipse.Config.resolve(workspace, home, [max_steps: 7], %{"IPSE_MAX_STEPS" => "6"})
7 = first.settings["max_steps"]
"CLI" = first.provenance["max_steps"]
File.write!(path, Jason.encode!(%{version: 1, settings: %{provider: "demo", max_steps: 5}}))
{:ok, second} = Ipse.Config.resolve(workspace, home, [max_steps: 7], %{"IPSE_MAX_STEPS" => "6"})
true = first.settings == second.settings
true = first.fingerprint != second.fingerprint
File.rm_rf!(scratch)
```

Both effective limits are seven, but the source bytes changed. Source descriptors
include path, scope and SHA-256, so that drift changes resume identity. Whitespace
changes have the same consequence. Equivalent CLI provenance alone does not
change identity. Raw source bodies do not enter model context or journal metadata.

Extend the existing precedence fixture in `test/config_test.exs` when adding a
field. Check both the winning value and its provenance. Use
`test/config_session_test.exs` to verify changed-source refusal before work or
permitted journal repair, rather than testing only decoded JSON.

## Distinguish authority from precedence

These rules apply even after a project is trusted:

| Input | Admission rule |
| --- | --- |
| Project `sandbox` | May tighten to `native`; cannot weaken an earlier `native` to `off` |
| Explicit operator environment or CLI sandbox | May select either supported mode |
| Profile endpoints and operator profile IDs | Project scopes cannot introduce endpoints or replace operator IDs |
| `embedding_profiles` | Operator-only, separate from text profiles and roles |
| Budget, journal policy, extension trust and diagnostic capture | Operator-only policy; project declarations refuse |
| Extension options and selection | Still require independent artifact/trust admission before callbacks |

Files allow at most 16 KiB, with at most 17 sources. Unknown fields, duplicate
keys, unsupported versions, invalid UTF-8/JSON and escaping automatic project
aliases refuse. Errors omit file contents. Environment parsing uses a fixed
allowlist, never an environment dump. `settings_schema/0` owns settings bounds;
the [operator limits](../operator/configuration.md#set-request-and-journal-limits)
describe their effect on a run.

Nested owners validate their own contracts: `Profiles`, `EmbeddingProfiles`,
`Budget.Policy`, `Journal.Limits`, `Extensions.Config` and
`Observability.Config`. Extension manifests expose option digests, not a safe
place to store credentials. Hashing inspection output does not protect the file.

## Assemble runtime policy once

`Config.runtime/2` reads validated effective settings directly. Its client map
contains workspace, home/auth/operator paths, the explicit MCP file and direct
endpoint, approval mode and permission to ask operator questions. The CLI does
not apply another default table or precedence pass.

Admission checks the direct endpoint, prepares extension metadata, loads the
selected MCP configuration and verifies the sandbox, in that order. Selected
profile runtime facts merge last, retaining the profile endpoint and reasoning
selection. The CLI then performs credential preflight. It discards that key;
Config neither reads credentials nor caches one in the runtime map.
`Provider.Request` resolves credentials again in the owned request task.
Explicit embedded fixture keys retain their supported behavior.

The local `ipse config` command calls only `resolve/4` and `manifest/1`.
Inspection performs no runtime admission or sign-in. Preserve that distinction
when adding a new optional integration.

## Trace main and child profile selection

At most eight profiles are admitted. IDs begin with an ASCII letter and contain
at most 64 letters, digits, underscores or hyphens. `main`, `routine` and `review`
roles refer to configured IDs. Every definition, role and selected execution fact
enters the configuration fingerprint. A profile names an existing route; it
does not schedule work or infer which task deserves that route.

For main work, selection follows explicit profile ID, `IPSE_PROFILE`, then the
`main` role. The selected profile overlays file settings before environment and
CLI limits. Conflicting provider/model choices and a direct endpoint refuse.
No unavailable model triggers another provider or billing mode.

For delegation, the parent proposes a configured ID or role. The host resolves
that route before approval and child creation, including within parallel groups.
The model cannot supply an arbitrary provider URL. Read the fixture named
"child profile isolates credentials and parent payloads while preserving host
policy" in `test/profiles_test.exs`:

- The child inherits allowlisted workspace, sandbox, instruction/skill, approval,
  origin, journal/budget and parallel-child hardlink policy.
- The selected profile supplies execution fields. Parent keys, provider module,
  direct endpoint, transcript, native continuation, profile catalog and MCP state
  are dropped. Only a ChatGPT child receives the protected auth-directory reference.
- The child's owned request resolves its own credentials. Its answer cannot
  establish routing: host routing facts precede the explicitly untrusted answer.

A selected child can narrow an inherited output cap, but cannot widen or omit it.
Provider capability checks precede approval. Children retain at most six admitted
model/helper calls, 120 seconds of active work and the parent's context ceiling.
See [delegation](delegation.md) for scheduling and [provider limits](provider-limits.md)
for wire fields. Main compaction stays on the main route. Separately granted
extension inference uses a private helper-profile catalog; roles do not select it.
Its SDK payload contains no provider key or routing authority.

## Preserve reasoning and destination facts

Reasoning effort is distinct from the model name. Ipse supports `low`, `medium`,
`high`, `xhigh` and `max` for exact `gpt-6.1-sol` OpenAI/ChatGPT profiles, mapping
the selection into Responses `reasoning.effort`. Ollama's explicit `none` maps
to native `think: false`; omission leaves the backend default unchanged. Other
combinations, including Anthropic thinking settings, refuse. The operator remains
responsible for choosing a backend that supports the requested control.

Trace the Ollama selection through profile validation, execution manifests,
`ModelCall.prepare/2` and `Provider.Ollama.complete/4`. The profile Session fixture
checks the actual synthetic HTTP body, saved execution facts and idle resume for
explicit `none`. The standalone model proof also checks omission. Keep both
controls: a recorded setting is evidence of a request, not of internal model work.

Destination identity comes from the actual adapter's `endpoint/1`: a non-secret
egress origin plus full-target SHA-256. Session pins main destinations and
approvals display helper destinations. Invalid routes refuse before journal
creation. Equivalent implicit/explicit default routes compare equally. Legacy
recovery uses recorded endpoint hashes; request-free legacy sessions accept only
an implicit default or an exactly pinned profile. Do not weaken these checks to
make a changed endpoint resume.

## Verify a configuration change across recovery

```sh
mix test test/config_test.exs test/config_session_test.exs test/profiles_test.exs test/profile_session_test.exs test/embedding_config_test.exs
```

These fixtures need no account. They cover source authority, provenance, schema
refusals, routing, secret isolation, native continuation, inherited ceilings and
inert resume. For a new setting, update the schema, fixed CLI/environment maps,
runtime projection and fingerprint policy together. Decide whether absence must
retain legacy identity. Add precedence and saved-value-drift cases to the
existing suites. A field working only on fresh CLI launches is incomplete.

Instruction refresh changes workspace text and skills, not execution policy.
To adopt a new route after a refusal, preserve the original journal and use the
[recovery procedure](../operator/recovery.md). Never resolve a missing credential
or incompatible endpoint by silently changing providers.
