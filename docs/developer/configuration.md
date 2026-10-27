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
| [`Config.Activation`](../../lib/ipse/config/activation.ex) | Apply an already reviewed protected selection after base fingerprinting, or reconstruct its exact saved selection |
| [`Provider.Registry`](../../lib/ipse/provider/registry.ex) | Closed string/atom specs, credential sources, defaults, capabilities, usage extraction and operator labels/probes |
| [`Config.Profiles`](../../lib/ipse/config/profiles.ex) | Validated text/embedding profiles and selected execution facts, without scheduling/fallback |
| [`Config.Decisions`](../../lib/ipse/config/decisions.ex) | Operator-only advisory profiles, service/expected-model identity, nullable disclosures and child selection |
| [`Provider`](../../lib/ipse/provider.ex) | Fresh credential resolution, output-cap validation/narrowing, and adapter dispatch in owned work |
| [`Provider.Transport` and `Stream`](../../lib/ipse/provider/) | Bounded HTTP/error handling and incremental response assembly |
| [`Session`](../../lib/ipse/session.ex) | Pin runtime identity and validate saved evidence before recovery/effects |

Start at `Provider.Registry.fetch/1`: a trusted Spec binds a string ID to an
existing atom and adapter. Config retains fixed field/CLI/environment tables;
arbitrary JSON keys never create atoms. Then trace `Profiles.validate_profile/1`, `select/3`,
`validate_route/2`, and `child_config/3`, finishing at Provider's request functions.

The registry owns provider differences rather than registering untrusted code.
Decision-only providers are closed in `Config.Decisions` and their transport;
they do not become conversation providers in the Registry. Trace
`Decisions.resolve/1`, `snapshot/1` and `prepare/2` with
[the decision exercise](decisions.md#trace-a-request-through-the-session).
`decision_profiles` are operator-only, and enabling `host.decision` pins their
snapshot with usage metadata version 3. Sessions without that capability retain
their earlier usage version, and absent legacy decision snapshots compare as
null during resume. Child profiles exist only when the child inherits
an explicitly allowed decision artifact. The `TYPESAFE_API_KEY` lookup joins the
shared secret scrub/denial inventory without becoming a text credential choice.
Its ordered views preserve operator and rate-card presentation; callbacks validate
reasoning and extract counters using fixed native paths. Usage owns consistency,
derivation and persisted validation. Adapters own wire shapes and opaque replay.
ChatGPT and OpenAI retain the same `openai` replay key with distinct billing and
endpoint policy. Transport retains bounded error parsing/redaction; subscription
diagnostic hints belong to its spec. A spec never authorizes a request or changes
credential source silently.

Native trusted shells and measurement launchers share `native/ipse-secrets.rs`.
The runner suite checks every `Registry.secret_env/0` name against that policy and
the real shell boundary. A provider addition must update that native policy or
the conformance check fails. Rate-card order intentionally differs from setup
order, with exact registry coverage checked by the registry suite.

In `iex -S mix`, inspect a route without calling it:

```elixir
{:ok, spec} = Ipse.Provider.Registry.fetch("openai")
:openai = spec.atom
{:env, "OPENAI_API_KEY"} = spec.credential
"api" = spec.billing_mode
:error = Ipse.Provider.Registry.fetch("unknown-provider")
```

Before changing existing metadata, run `mix test test/ipse/provider/registry_test.exs`.

For the selected Grok increment, begin with the
[source research and acceptance map](../archive/2026-10-24-xai-provider-research/index.md).
It distinguishes xAI API-key billing from subscription OAuth and records the
missing Ipse registration prerequisite. Reuse bounded protocol owners while
keeping native replay and credentials provider-specific; an OpenAI-compatible
wire format does not make opaque continuation transferable between providers.
The xAI entries use separate credentials/billing with a shared xAI replay
namespace. The stateless Responses owner in `provider/openai.ex` selects its
endpoint/replay key from the registry; the existing OpenAI/ChatGPT manifests stay
unchanged. xAI permits its trailing `[DONE]` only after `response.completed`.
An early marker or EOF still refuses tool execution. Foreign native output
cannot be flattened into another provider's request.

Modern xAI input/output counters use the Responses contract. Legacy documentation
contains an example where reasoning is separate from completion, alongside a
schema description of inclusive totals. The normalizer requires the reported
total to disambiguate: use completion directly when input+completion agrees, or
add reasoning when input+completion+reasoning agrees. Missing evidence stays
partial; contradictory totals and mixed dialects refuse instead of guessing. The visible-only output limit is
declared in the Spec; Budget refuses using it for a total-output reservation.
Private native metadata retains a bounded reported USD-tick cost separately
from configured aggregate estimates. That value is not an invoice reconciliation.
Exercise these boundaries with `mix test test/ipse/provider/xai_test.exs` and
the shared conformance set before changing them.

`Auth.XAI` owns registered-client RFC 8628 login and RFC 7009 revocation, independently
of ChatGPT's registration/JWT identity contract. It uses only fixed issuer
endpoints, an explicitly supplied public client ID and minimal API/offline scopes.
It does not perform dynamic registration or borrow another app's identity. Shared
private-file and retained OS-lock helpers admit closed `:chatgpt`/`:xai`
namespaces, preserving the existing ChatGPT paths. Mark refresh pending durably
before dispatch: a transport interruption or owner death cannot justify replaying
a rotating refresh token. A successful response must be saved before returning
its access token. Refresh explicitly requests only the saved granted scopes. If
its response omits scope, retain that request; reject expansion rather than
replacing a narrower grant with the initial request's broader scope list.
Status/doctor never refresh. Device polling fixtures check pending, slow-down,
expiry and denial; rotation fixtures check concurrent callers
and unknown outcome recovery. Run `mix test test/ipse/auth/xai_test.exs test/ipse/auth_test.exs`.
Fixture success does not establish xAI's approval of an Ipse registration or a
subscription entitlement.

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

Setup's provider menu, labels, defaults and credential source come from the
registry. Route prompts collect OpenRouter's upstream/data policy or a compatible
server's loopback URL. `Profiles.validate_profile/1` admits that complete route
before preview. Settings-only choices keep the ordinary settings shape; route
fields or an endpoint require a new selected `setup_PROVIDER` profile. An existing
main profile is reused only when its requested fields agree. Name collisions and
route changes refuse without modifying old profiles, roles or backup bytes.

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

## Apply a protected selection without changing base configuration

Protected activation is a separate Session admission step. `Config.resolve/4`
and `manifest/1` keep ordinary source bytes, provenance and fingerprint unchanged.
`Config.runtime/2` privately retains the admitted base extension catalog; it does
not rewrite a configuration file. Fresh `Session.open` then calls
`Config.Activation.fresh/2`, before capturing its actual execution mode and semantic
pin. A protected policy may select a reviewed installed artifact and narrower
Main timeout. It cannot introduce provider endpoints or profile definitions.

`Config.Activation.current/2` reads existing project identity and Consent state
without selecting code. Absent identity/control state returns nil and creates no
new roots. It uses `ProjectIdentity.with_existing_binding/4` and
`Consent.existing_snapshot/2`: retained native locked reads that neither join nor
reclaim pending files, even when selected control bytes are malformed. These
existing-only reads require `.lock` and ancillary `.writer.lock` to exist as safe
owner-only, single-link, empty regular files. Missing/unsafe lock files refuse
before quota acquisition; the reader does not create them. Exact retained writer
identity is checked around quota and after the callback. These cooperative-host
prechecks do not make the existing create-capable native protocol atomic against
arbitrary same-UID concurrent deletion. Ordinary mutation/recovery owners keep
their separate `with_binding`/`snapshot` paths and
intentional reclamation. A read cannot enter those paths merely to validate a
binding. Present malformed state refuses. An already admitted linked worktree
retains the bounded native metadata-copy/cleanup checks needed to preserve exact
nanosecond witnesses; this transient IO is not a new identity admission. Existing
primary and folder lookups do not need that metadata capture.

Use `Config.Activation.readiness/2` for an advisory status preview, rather than
calling fresh admission. Its result adds `ready: true | false` to the same
`binding`/`snapshot` data. It never joins or returns a prepared runtime. A true
result requires the exact current policy under `Consent.with_existing_policy/6`,
all ordinary overlay artifact/sidecar/route/base/timeout checks and a nonquarantined
ledger. The actual prepared Registry identity digest must equal the protected
policy's saved identity digest. Child/explicitly disabled, absent, expired and
out-of-scope activation is
not ready; selected invalid bytes or changed routes refuse. This is an
instantaneous review result, not a reusable permission or Collection absence
witness. Admission and every effect still perform their own live checks.

A fresh reciprocal worktree can join an already admitted repository through
`ProjectIdentity.join_existing/3`. Under the retained index lock, it checks the
native metadata and backlink against that exact known repository before the host
callback checks a current project-scoped activation, actual bundle and routes.
Only then may the checked index publication occur. A clone, folder, unknown
repository, revoked policy or worktree-only grant cannot authorize this join.
Candidate inspection uses bounded transient native metadata snapshots, including
when a join is refused; it does not admit a new project. After joining, fresh
Session admission rechecks the current policy epoch/hash. Membership alone never
permits an extension effect.

Before a grant exists, `SemanticRoutes.review/2` derives review data from actual
admitted Main/named-profile destinations. It reuses an exact operator service
alias, or proposes `origin-` followed by the first 56 hexadecimal characters of
the canonical origin's SHA256. The protected policy binds those full routes and
service references. Applying the overlay requires exact equality with the actual
base routes; a worker or policy JSON cannot supply a new endpoint. Registrations
remain bounded by the ordinary eight-service limit.

Fresh selection requires the current packaged bundle inventory digest, verified
installed bytes, matching `operator.json`, actual Registry identity and exact
capability ceiling. Resume instead reconstructs the artifact/options/selection
from the saved version-2 semantic policy, even if the current policy was disabled
or the packaged inventory upgraded. The exact installed saved artifact must still
exist; startup never imports or rebuilds it. Historical metadata without activation
stays unselected. Current Consent still gates every later effect, so retaining a
saved catalog does not revive a revoked grant.

An optional saved `main_timeout_ms` can only narrow the admitted base timeout;
90 seconds against a 30-second base refuses instead of clamping or widening.
Explicit `--no-extensions` keeps fresh sessions unselected and refuses removal of
a saved activated catalog on resume. Children restore base entries, timeout and
operator service registry before independent child filtering; the derived overlay
is not inherited. Idle resume writes no new activation event or configuration.

Run the configuration exercise above, then run:

```sh
mix test test/ipse/extension/semantic_routes_test.exs test/ipse/extension/project_identity_existing_test.exs
mix test test/ipse/extension/consent_existing_test.exs test/ipse/extension/consent_test.exs
mix test test/ipse/config/activation_session_test.exs
```

The final command creates a private packaged catalog and independently compiled
SDK worker in a child VM. It checks real fresh/resumed Session selection, exact
route registration, revocation, child policy and reciprocal worktree admission.
Its local provider is configured for route validation only; it makes no model
request. Do not replace the private application directory with the checkout's
`priv` path when extending this fixture.

## Trace standalone native knowledge review

The [operator permission procedure](../operator/knowledge-permissions.md) selects
the shipped native bundle without changing provider/configuration bytes or
creating a conversation. `CLI.Knowledge.prepare/4` builds review data from the
actual installed `operator.json` through `Artifact.read_declared/4`. It checks
the declared schemas/recipes, drafts the activation, prepares the actual Registry
identity, derives actual Main routes with `SemanticRoutes.review/2`, then builds
the exact settings-v2 policy with `SemanticConsent.prepare/3`. No worker/model is
used to interpret the sidecar or choose authority.

The terminal displays the complete escaped review plus a fresh challenge. The
native v2 operator observation must bind both the exact displayed-byte SHA256 and
original returned-text SHA256 before the exact `enable CODE` or `disable CODE`
is accepted. Piped input, copied old codes, `--yes` and generic project trust
cannot replace that observation. Project admission and artifact import can have
already happened when a later review is cancelled; cancellation saves no grant.

After confirmation, the host revalidates the exact ProjectIdentity and reloads
configuration through the same original options, home and workspace. Its ordinary
fingerprint, including source-file digests, must still match the reviewed snapshot;
a malformed or changed source refuses even if effective settings would look
equivalent. The host repeats preparation byte-for-byte with that current runtime,
then applies Consent CAS against the reviewed epoch. A concurrent policy change
refuses instead of being overwritten. Successful
selection affects the next new Session; saved Sessions keep their original
activation and later effects still check current permission. Status uses
`readiness/2`; permissions uses `current/2` so a changed route can refuse readiness
while the original saved policy remains inspectable. Neither read joins or repairs.

Run `mix test test/ipse/cli/knowledge_test.exs` in the coordinated serial native
terminal test window. Follow its real native save/revoke, stale challenge,
cancel/pipe, concurrent epoch, paused-review configuration changes and
read-preservation controls. Keep these synthetic
PTY checks separate from human terminal attestation, live model behavior and
automatic capture/current-note recall acceptance.

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
endpoint, approval mode, explicit chat-only native edit consent, and question permission.
Edit consent is a client flag, never a project configuration permission grant.
Admission checks the direct
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
  transcript, continuation, profile catalog, and MCP state are dropped. Subscription
  children (`chatgpt` or `xai_oauth`) receive the protected auth-directory reference
  for their selected provider; API/local children do not.
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
OpenRouter's declared efforts pass through to its pinned upstream; compatible
local profiles support no explicit effort. The profile route fields `upstream`
and `data_collection` propagate through main/child manifests and extension
snapshots only for their declared provider. Ordinary providers gain no extra
saved keys. Session validates the route before opening or repairing a journal.

ChatCompletions checks first-frame model/upstream identity before text, observes
usage before refusals, and requires a successful finish plus `[DONE]`. A repeated
finish on a content-free final usage frame is accounting. Indexed call fields use
Stream buffers; native reasoning-detail arrays retain order without text emission.
Fixtures cover actual approved extension requests and unchanged idle resume.

Gemini's adapter retains up to 4096 original native parts, without merging signed
parts. It buffers only visible text separately, translates whole function calls
to host calls, and maps consecutive results back to one user content in call
order. Native IDs survive; missing IDs get host-only synthetic IDs. A real
checkpoint becomes user text, while a recent signed tail replays unchanged.
When rebuilding foreign history, omit foreign call IDs on the Gemini wire and
match responses by the host's call/name mapping; only Gemini-native IDs replay.
Follow `Gemini.request_body/3`, `consume/3`, and the session/child/SDK fixtures to
trace both directions. `STOP` is success; all other terminal reasons and missing
completion refuse tools while preserving observed usage. Low/medium/high efforts
map to uppercase API enums; none omits the control.

Trace profile validation, saved execution, ModelCall preparation, and Ollama wire
construction. The profile integration fixture checks the synthetic HTTP body,
saved facts, and idle resume for `none`; the model proof also checks omission.
A recorded setting proves the request, not internal model behavior.

Actual adapter `endpoint/1` supplies a non-secret origin and full-target digest.
Session pins main destinations; helper approvals display them. Invalid endpoints
refuse before journal creation. Equivalent implicit/explicit defaults compare
equally. Legacy request-free sessions allow only implicit defaults or exactly
pinned profiles. Never weaken destination identity to make a changed route resume.
Gemini alone declares the fixed wire query `alt=sse`. The adapter appends it to
the validated model path; destination validation permits only that spec's query.
The digest covers the query, while the reported origin has none. Operator base
URLs still cannot contain a query. Existing-provider golden digests are unchanged.

## Follow an output ceiling to the wire

Provider owns `validate_output_limit/1`, `output_tokens/1`, and
`narrow_output_tokens/2`. Absence adds no wire field. OpenAI API permits
16..1000000; Anthropic/Ollama/Gemini/OpenRouter/compatible/Grok permit 1..1000000. ChatGPT subscription/demo refuse
explicit caps without dropping them or switching billing.

| Adapter | Effective field |
| --- | --- |
| OpenAI API Responses | `max_output_tokens` |
| Anthropic Messages | `max_tokens`, narrowed by existing adapter value |
| Ollama Chat | `options.num_predict`, narrowed by existing summary options |
| OpenRouter/compatible Chat Completions | `max_tokens` |
| Gemini GenerateContent | `generationConfig.maxOutputTokens` |
| Grok Responses, API or registered OAuth | `max_output_tokens`, visible text only; total-output budget reservations refuse |
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
`Transport.safe/2` permits diagnostic identifiers, withholding arbitrary upstream
prose, control bytes, oversized values and secret-like prefixes. Chat Completions
applies it to mid-stream error messages and codes before removing the selected
API key. Numeric HTTP error codes in 100..599 become decimal identifiers;
out-of-range integers, floats and structured values are withheld.
Host errors should use mapped reasons or fixed operator prose; never inspect an
arbitrary reason into CLI text. `CLI.Errors` supplies recovery routes and refuses
binary term/control dumps. Slash commands, endpoint paths and service labels
remain readable; error producers own fixed causes without private paths.
Explicit configuration inventories still show
the source paths the operator needs to inspect.
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
| Gemini original replay parts | 4096, with an aggregate 8 MiB ceiling |

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

Configuration-file producers name operator/project scope and the corrective
option rather than interpolating a path. They know startup refused before a task.
The renderer bounds binary prose and refuses controls and term syntax; it does
not infer private paths or effect uncertainty from a slash. Preserve ordinary
`/context refresh`, endpoint hints and service names when adding a cause.

Add the causal CLI fixture in `test/ipse/cli/errors_test.exs` when extending this
boundary. Assert the exact distinct refusal, unchanged journal bytes, absent
dispatch/state creation, and absence of a synthetic private value. Do not replace
a detailed expectation with a substring that the old generic refusal also met.

## Verify a complete setting change

For an operator-facing readiness check, follow `CLI.Doctor.run/3` before changing
Session startup. It reuses Config resolution, artifact preparation, MCP parsing,
Auth status and bounded journal headers without creating a conversation, testing
locks, refreshing tokens or launching workers. Current UID comes from the
existing Rust helper's read-only `--uid` facility through a bounded Port in Runner,
without a shell. This host identity query does not select a sandbox workspace.
Native shell admission independently refuses application/helper overlap. No
platform command or dependency is added. Native diagnosis reports helper and
workspace policy, without executing the kernel confinement path.

`Config.inspect_sources/4` supplies bounded per-file parse/trust findings even
when ordinary resolution refuses a project source. It does not merge settings
or grant project trust. Keep the resolution refusal alongside the source rows;
otherwise a useful inventory could hide the cause that prevents startup.

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
mix test test/ipse/provider/conformance_test.exs test/ipse/provider/http_test.exs
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

For an adapter change, use the shared ProviderFixture for local byte-fragmented or
whole responses. Its task returns captured headers and the decoded request, so
wire assertions check what the adapter sent. ProviderConformance takes a fixed
provider/adapter and native event builder. Its common cases require visible deltas,
private continuation, exact tool arguments, ordered native replay, usage, terminal
markers, HTTP errors and the transport byte limit. Implement the protocol builder
and run these cases before special signature, route-pin or accounting fixtures.
Synthetic conformance proves local contracts, without establishing service access
or live compatibility.
