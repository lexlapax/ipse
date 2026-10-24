# Resolve configuration and bound a model request

A setting crosses source resolution, Session admission, and dispatch. Trace all
three before changing it. A trusted project can suggest a route or tighter limit;
it cannot select its own credential endpoint or authorize effects. The
[operator manual](../operator/configuration.md) supplies complete configuration files.

## Follow a value through the current owners

| Owner | Responsibility |
| --- | --- |
| [`Config.resolve/4`](../../lib/ipse/config.ex) | Scoped JSON, selected profile, allowlisted environment, and explicit CLI become values/provenance/fingerprint, without credentials or execution |
| `Config.runtime/2` | Values plus explicit client facts become admitted Session policy |
| [`Provider.Registry`](../../lib/ipse/provider/registry.ex) | Closed string/atom specs, credential sources, defaults, capabilities, usage extraction and operator labels/probes |
| [`Config.Profiles`](../../lib/ipse/config/profiles.ex) | Validated text/embedding profiles and selected execution facts, without scheduling/fallback |
| [`Provider`](../../lib/ipse/provider.ex) | Fresh credential resolution, output-cap validation/narrowing, and adapter dispatch in owned work |
| [`Provider.Transport` and `Stream`](../../lib/ipse/provider/) | Bounded HTTP/error handling and incremental response assembly |
| [`Session`](../../lib/ipse/session.ex) | Pin runtime identity and validate saved evidence before recovery/effects |

Start at `Provider.Registry.fetch/1`: a trusted Spec binds a string ID to an
existing atom and adapter. Config retains fixed field/CLI/environment tables;
arbitrary JSON keys never create atoms. Then trace `Profiles.validate_profile/1`, `select/3`,
`validate_route/2`, and `child_config/3`, finishing at Provider's request functions.

The registry owns provider differences rather than registering untrusted code.
Its ordered views preserve operator and rate-card presentation; callbacks validate
reasoning and extract counters using fixed native paths. Usage owns consistency,
derivation and persisted validation. Adapters own wire shapes and opaque replay.
ChatGPT and OpenAI retain the same `openai` replay key with distinct billing and
endpoint policy. Transport retains bounded error parsing/redaction; subscription
diagnostic hints belong to its spec. A spec never authorizes a request or changes
credential source silently.

In `iex -S mix`, inspect a route without calling it:

```elixir
{:ok, spec} = Ipse.Provider.Registry.fetch("openai")
:openai = spec.atom
{:env, "OPENAI_API_KEY"} = spec.credential
"api" = spec.billing_mode
:error = Ipse.Provider.Registry.fetch("unknown-provider")
```

Before changing existing metadata, run `mix test test/ipse/provider/registry_test.exs`.
Pre-refactor fixtures compare full Config manifests, destinations, canonical usage
and cost, then restore old journals and request-free legacy sessions without
mutation. Updating goldens to match a refactor removes that protection; investigate
differences before changing evidence.

Resolution canonicalizes the workspace and nearest Git boundary, including
worktree `.git` files. Outside Git, only the launch directory contributes project
settings. Missing default files are optional; explicit operator files must exist.
Project files need current-run trust.

Precedence is defaults, operator JSON, project scopes from root to launch directory,
selected main profile, allowlisted environment, then explicit CLI fields. Nearer
project profile definitions replace entire records; role keys merge. Conflicting
provider/model settings or a direct endpoint cannot silently replace a selected
main route. Source bytes, path, and scope contribute to fingerprinting.

## Reproduce precedence and source drift

Guided setup uses `Config.preview/5` to substitute proposed operator bytes into
the same resolution path without creating a temporary configuration or directory.
Schema, profiles, caps, provenance and fingerprint therefore agree with a later
file-based resolve. Setup compares the admitted provider/model/sandbox with the
proposal to catch environment or profile conflicts before saving. The pure
preview seam belongs in Config because copying resolution into a CLI writer
would create a second admission policy.

`CLI.Setup` owns prompts, exact preview and explicit write consent. It preserves
unowned fields, compares the current file before mutation, and creates an exclusive
timestamped backup on replacement. `PrivateFile.write_atomic/3` creates missing
directories privately, writes an exclusive mode-0600 temporary file, syncs it and
publishes by rename. Exclusive backup publication uses a hard link instead of
replacement. Existing parent modes stay unchanged. Auth reuses that helper with
its original credential error and locking behavior. These checks do not protect
against hostile concurrent directory replacement; setup is for reviewed local
paths. Offline doctor follows a successful save; its failure does not roll back
the reviewed configuration.

Run this complete exercise in `iex -S mix`:

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

Both effective limits are seven. Different source bytes still change resume
identity; whitespace can do the same. Equivalent CLI provenance alone does not.
Raw configuration bodies enter neither model context nor journal metadata.
Extend the precedence fixture in `test/ipse/config_test.exs` with both value and
provenance assertions. Its integration suite checks drift refusal before work
or permissible tail repair, beyond successful JSON decoding.

## Separate authority from precedence

| Source | Rule even after project trust |
| --- | --- |
| Project sandbox | May tighten to native, never weaken an earlier native selection |
| Explicit operator environment/CLI sandbox | May choose either supported mode |
| Profile endpoints/deadlines/IDs | Projects cannot introduce `base_url` or `model_call_timeout_ms`, or replace operator IDs |
| Embedding profiles | Operator-only, separate from text profiles/roles |
| Budget/journal/trust/diagnostics | Operator-only policies; project declarations refuse |
| Extension options/selection | Still require artifact/trust admission before callbacks |

Files allow 16 KiB and at most seventeen sources. Unknown fields, duplicate keys,
unsupported versions, invalid UTF-8/JSON, and escaping automatic project aliases
refuse without displaying file contents. Environment reads use a fixed allowlist,
not a dump. Nested owners validate profiles, `Usage.Budget`, Journal limits,
`Extension.Config`, and Observability policy. A digest is not secret protection;
keep credentials out of extension options.

`Config.runtime/2` consumes validated values without a second CLI defaults pass.
Client facts include workspace/home/auth/operator paths, explicit MCP/direct
endpoint, approval mode, and question permission. Admission checks the direct
endpoint, prepares extension metadata, loads MCP configuration, then verifies
sandbox setup. Selected profile runtime facts merge last. CLI credential preflight
discards the key; Config neither loads nor caches credentials. Provider resolves
them again in the owned task. Explicit embedded fixture keys keep their supported
behavior. `ipse config` calls only resolve/manifest, without sign-in/runtime launch.

## Trace main and child profile selection

At most eight text profiles use IDs starting with an ASCII letter and up to 64
letters/digits/underscores/hyphens. `main`, `routine`, and `review` reference IDs.
Every definition, role, and selected execution fact contributes to identity.
Profiles describe routes, without classifying tasks or scheduling work.

Main selection follows explicit profile ID, `IPSE_PROFILE`, then `main` role.
The profile overlays file settings before environment/CLI limits. Conflicting
provider/model/direct endpoint refuses. Main compaction stays on that route.
A delegate proposes only a configured ID/role; resolve it before approval/creation.
The model cannot introduce URLs or choose credentials.

Read the child-isolation fixture in `test/ipse/config/profiles_test.exs`:

- Workspace, confinement, instructions/skills, approvals, origin, journal/budget,
  and parallel-child hardlink policy are inherited through a fixed allowlist.
- The route supplies execution fields. Parent key, provider module, direct endpoint,
  transcript, continuation, profile catalog, and MCP state are dropped. Only a
  ChatGPT child receives its protected auth-directory reference.
- Owned child requests resolve their own credentials. Host routing facts precede
  the untrusted answer, whose prose cannot establish which route ran.

Child profiles can narrow an inherited output cap, never widen/omit it. Check
provider support before approval. Children retain six admitted main/helper calls,
120 seconds active time, and the parent's context ceiling. [Architecture](architecture.md)
teaches child ownership. Extension inference uses its separately granted private
profile catalog; main/routine/review roles do not select it.

Extended helper deadlines require `model_call_timeout_ms`. Profiles validates it
without projecting it into main/child settings. `Extension.ModelCall.snapshot/1`
captures its minimum with root timeout and 600000. Without the field, historical
snapshots retain the minimum with 120000 even if ordinary timeout was larger.
This preserves saved equality. Request execution narrows again; v1/v2 requests
retain their 120000 ceiling. Exercise these distinctions in
`test/ipse/extension/model_call_test.exs` before changing a projection.

## Preserve reasoning and destination facts

Reasoning effort is separate from model identity. Exact `gpt-6.1-sol`
OpenAI/ChatGPT profiles accept `low`, `medium`, `high`, `xhigh`, and `max`, mapping
to Responses `reasoning.effort`. Ollama `none` means native `think: false`;
omission preserves backend default. Other combinations, including Anthropic
thinking settings, refuse. Operators still need a supporting service/model.

Trace profile validation, saved execution, ModelCall preparation, and Ollama wire
construction. The profile integration fixture checks the synthetic HTTP body,
saved facts, and idle resume for `none`; the model proof also checks omission.
A recorded setting proves the request, not internal model behavior.

Actual adapter `endpoint/1` supplies a non-secret origin and full-target digest.
Session pins main destinations; helper approvals display them. Invalid endpoints
refuse before journal creation. Equivalent implicit/explicit defaults compare
equally. Legacy request-free sessions allow only implicit defaults or exactly
pinned profiles. Never weaken destination identity to make a changed route resume.

## Follow an output ceiling to the wire

Provider owns `validate_output_limit/1`, `output_tokens/1`, and
`narrow_output_tokens/2`. Absence adds no wire field. OpenAI API permits
16..1000000; Anthropic/Ollama permit 1..1000000. ChatGPT subscription/demo refuse
explicit caps without dropping them or switching billing.

| Adapter | Effective field |
| --- | --- |
| OpenAI API Responses | `max_output_tokens` |
| Anthropic Messages | `max_tokens`, narrowed by existing adapter value |
| Ollama Chat | `options.num_predict`, narrowed by existing summary options |
| ChatGPT subscription | Unsupported; refusal before dispatch |

In IEx:

```elixir
100 = Ipse.Provider.narrow_output_tokens(100, 4096)
{:error, _} = Ipse.Provider.validate_output_limit(%{provider: :chatgpt, max_output_tokens: 100})
```

Config and Session validate/pin the effective cap, including embedded callers
and resume before repair. Summaries narrow rather than widen their own limit.
Read actual ordinary/summary request-body fixtures in `test/ipse/provider_test.exs`;
a configuration-only assertion cannot establish wire behavior.

Explicit length/incomplete completion is response failure. Retain usage, admit
none of that response's tools, and preserve earlier visible text/effects. Do not
execute partial arguments or label truncation successful because HTTP ended.
[Accounting](accounting.md) explains liability after response refusal.

## Bound response assembly separately

Transport accepts 8 MiB or a smaller selected `max_response_bytes`, with at most
131072 data chunks. Error bodies retain only a bounded diagnostic prefix.
Stream scans new line bytes, retains fragments, and joins once at a delimiter.
Field accumulators materialize completed text/arguments/native data once. Avoid
repeated whole-prefix joining or scanning.

| Resource | Hard ceiling |
| --- | --- |
| Partial line, joined SSE data, accumulated field | 8 MiB |
| Nonempty fragments per line/field | 32768 |
| Data lines per SSE event | 32768 |
| Parsed lines per response | 131072 |
| SSE events and decoded provider events | 65536 each |
| Output items/Anthropic blocks | 256, indices 0..255 |
| Tool calls including incremental Ollama batches | 32 |

The first bound refuses the response. Ollama's nonempty EOF tail counts as a line;
SSE EOF invents no event. CR/LF/split CRLF, split UTF-8, and multiline data retain
protocol meaning. Production reducers process each completed line/event before
later suffixes, so earlier usage survives suffix overflow and earlier errors keep
precedence. Collecting feed helpers return no successful prefix after failure;
use reducers for observable accounting callbacks.

Deadline checks occur during framing, around callbacks, and before materialization.
They are cooperative and cannot forcibly interrupt a decoder/callback. Cleanup
can outlast inference. A late success refuses admission. Native signatures and
private reasoning remain only in continuation where required, never visible text.

## Make a refusal useful without exposing values

Validation owners describe their own failures. Profiles reports a validated
profile ID and a known field name; it never echoes the failing value. MCP tags
its existing checks with field classes, reports a validated server ID or its
one-based position, and withholds identifiers that overlap any configured secret.
Neither path launches a worker or model request to diagnose configuration.

Trace a refused credential reference in IEx:

```elixir
{:error, message} = Ipse.Config.Profiles.validate(
  %{"local" => %{"provider" => "ollama", "model" => "fixture", "credential" => "OPENAI_API_KEY"}},
  %{}
)
true = String.contains?(message, "Profile local: Invalid profile field credential.")
false = String.contains?(message, "OPENAI_API_KEY")
```

The CLI renders those sanitized strings through `Ipse.CLI.Errors`. Known host
reasons have a cause, effect-state guidance and a recovery anchor. Unexpected
terms and exceptions produce only a stable code, never `inspect(reason)` or an
exception message. Terminal question refusals and Session error events use the
same renderer. `ipse status` serializes only `Auth.status/1`'s public keys as JSON.

Add the causal CLI fixture in `test/ipse/cli/errors_test.exs` when extending this
boundary. Assert the exact distinct refusal, unchanged journal bytes, absent
dispatch/state creation, and absence of a synthetic private value. Do not replace
a detailed expectation with a substring that the old generic refusal also met.

## Verify a complete setting change

For an operator-facing readiness check, follow `CLI.Doctor.run/3` before changing
Session startup. It reuses Config resolution, artifact preparation, MCP parsing,
Auth status and bounded journal headers without creating a conversation, testing
locks, refreshing tokens or launching workers. Current UID comes from the
existing Rust helper's `--uid` facility through a bounded Runner invocation;
no platform command or dependency is added. Native diagnosis reports helper and
workspace policy, without executing the kernel confinement path.

Only the explicit probe branch borrows a private Finch client. It sends metadata
GETs, stops after status, retains no response body, and uses the existing proxy/TLS
policy with finite deadlines. Subscription reachability stays skipped. Preserve
the no-network positive control in `test/ipse/cli/doctor_test.exs`: an offline run
must leave the listener untouched, and the explicit probe must send exactly one
GET. Expired-credential bytes and held session locks must survive inspection.

```sh
mix test test/ipse/config_test.exs test/ipse/config/integration_test.exs test/ipse/config/profiles_test.exs
mix test test/ipse/config/profile_integration_test.exs test/ipse/config/embedding_test.exs
mix test test/ipse/provider_test.exs test/ipse/provider/stream_test.exs
mix test test/ipse/cli/doctor_test.exs
mix test test/ipse/cli/setup_test.exs test/ipse/private_file_test.exs test/ipse/auth_test.exs
```

For a new field, update schema, fixed CLI/environment maps, runtime projection,
and identity together. Decide whether absence must preserve legacy equality.
Test precedence, changed saved source, actual wire fields, fragmented boundaries,
overflow after usage, and native continuation. A larger bound also needs transport,
materialization, and journal review. Instruction refresh changes no execution
policy. Preserve old evidence and use [recovery](../operator/recovery.md) for an
incompatible route, without silent provider fallback.
