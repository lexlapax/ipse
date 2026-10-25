# Run approved effects from extensions

This chapter follows a worker proposal through admission, approval, execution,
accounting and recovery. Work through [extension state](extension-state.md) first.
You need a built checkout and its Elixir toolchain. The examples and focused tests
use synthetic local services; they require no account or paid inference.

Choose the host operation that owns the effect:

| Work | Operation | Additional capability | Implementation owner |
| --- | --- | --- | --- |
| Existing file or shell tool | `tool.call` | `host.tools` | `Ipse.Extension.ToolAction` |
| Selected external tool, resource or prompt | `mcp.call` | `host.mcp` | `Ipse.Extension.MCPCall` |
| Text or schema-constrained inference | `model.complete` | `host.model` | `Ipse.Extension.ModelCall` |
| Native vector generation | `embedding.create` | `host.embedding` | `Ipse.Extension.EmbeddingCall` |
| Read a successful retained effect | `effect.result.read` | `host.results` | `Ipse.Extension.EffectResult` |

Every operation also needs `host.actions` in the artifact and the operator trust
ceiling. An installed package, command invocation or answered question grants no
additional effect authority. Child use requires explicit delegation and
`allow_children`; children cannot use MCP or delegate recursively.

Read `examples/extension-lab/src/memory.ex`,
`examples/mcp.ex`, `examples/model.ex`, and `examples/embedding.ex` beside their
proofs in `dev/verification/`. Each worker returns
a typed proposal. The host supplies credentials and transport only after admission.
Workers are trusted executable code with ordinary OS permissions; these APIs
govern host-mediated effects and do not sandbox arbitrary worker code.

## Follow the common action sequence

The worker returns `{:ok, reply, private_state}`. Put an operation request in this
outer SDK object:

```json
{"api_version":1,"kind":"host_call","request":{"op":"tool.call","name":"write","arguments":{"path":"result.txt","content":"reviewed result"},"timeout_ms":1000}}
```

`Host` validates the closed request and asks the owning Session to admit it.
Session checks the current invocation, grants, activation lease and operation
limits. For an effect requiring approval, it shows the complete proposed request
and its bound execution facts. Headless execution refuses without `--yes`.
Approving an enclosing model tool or answering a question cannot approve this
separate effect.

Session syncs the intent before dispatch. Slow work runs in an owned task outside
the GenServer. Session syncs its result before continuing the worker. Deadline,
worker death, cancellation and lease expiry stop local owned work. They cannot
undo effects that a remote service or filesystem has already performed.

An interrupted intent remains unknown. Recovery validates bindings and action
ordering before repairing a torn journal tail; idle resume restores committed
values without dispatch. Never add automatic replay to resolve an unknown result.

Ordinary invocations permit 16 host calls. `host.results` permits same-invocation
`effect.result.read` calls through step 512, with a two-minute admission deadline;
it does not extend other read families or permit a later effect. Explicit
`host.actions.mixed` permits up to 512 reads and 16 other
calls, 528 total, under each operation's own grants. Denials count. Questions,
publications, services and inference are other calls. The read set is state
get/list/scan, history read, usage read/children/child-read and effect-result read.
Host, Session and recovery each derive these counters from the committed chain.

## Reuse file and shell ownership

`tool.call` accepts exactly `op`, `name`, `arguments` and `timeout_ms` as shown
above. Its deadline is 1..30000 milliseconds. Arguments use the existing closed
tool schema. A shell's optional inner timeout cannot exceed the outer deadline;
omitting it uses the outer deadline. Unknown tools, MCP names, delegation and
recursive extension calls refuse.

Read follows ordinary read policy. Write, edit and shell require mutation
approval unless the session explicitly enables them. Approval identifies the
instance and artifact and uses a null state namespace.

Trace `ToolAction.validate/1`, `Operation.mutating?/1` and `Host` into `Ipse.Tools`
and `Ipse.Runner`. The host snapshots workspace instructions and performs nested
path discovery before admission, outside the GenServer. New guidance stops the
action before approval, intent or execution. The user inspects `/context` and
explicitly invokes fresh work. Existing instruction drift follows
`/context refresh`. Instruction text never enters the worker payload.

The admission gate binds the reviewed request and workspace snapshot digest.
The intent records `context_sha256`; restore compares it with the journaled
snapshot. State and question calls use null. Existing path, symlink, `.git` and
parallel-child hardlink protections remain in `Tools`. Session's shell policy
passes through and fails closed when unavailable. A linked leaf task owns IO and
the shell Port. Shell setup retains its additional supervisor window of five
seconds, or 25 seconds for macOS native setup.

Successful file tools return `{"text":"..."}`. A normally completed shell adds
`exit_code`, `output_bytes` and `output_truncated:false`; a nonzero exit remains
visible. `ok` records completed execution, not achievement of a domain goal.
Returned text is at most 4 KiB and must fit the complete escaped SDK envelope.
Timeout, signal, incomplete or oversized output stops as unknown; partial text
does not become a complete continuation value. A read error is known `failed`
with `tool_failed`; an oversized read returns `result_limit` without partial
text. Write and edit failures remain conservatively unknown.

Child mutations relay approval through the parent and claim the whole workspace
conservatively. A helper inference approval does not release an enclosing file
mutation lease or grant another mutation.

## Bind and call an external MCP item

The operator first configures the server and binds a selected item in the caller
artifact's trust record. Project configuration cannot supply or override routes.
This is a trust-record fragment:

```json
{"mcp_bindings":[{"instance":"reader","alias":"documents","tool":"mcp__fixture__fetch"}]}
```

Aliases start with a lowercase ASCII letter, followed by lowercase letters,
digits, underscores or hyphens, up to 32 characters. A trust record permits 64
unique instance/alias bindings; an identity contains at most eight sorted pairs.
See the [operator MCP procedure](../operator/mcp.md).

The worker places this complete request inside the outer host-call object:

```json
{"op":"mcp.call","version":1,"binding":"documents","arguments":{"text":"Public synthetic request"},"timeout_ms":5000}
```

All fields are required. The deadline is 1..30000 milliseconds. Arguments must
fit the selected descriptor's schema and SDK/privacy bounds. The worker cannot
supply endpoints, credentials, descriptors or server settings. Every call needs
mutation approval, including resources and read-only tools.

An invalid route, missing grant or child refuses before discovery. Session also
requires its record ceiling to fit the complete 256 KiB encoded source contract
before discovery. Schema validation needs discovery, which runs outside the
GenServer. Session pins the private descriptor, then checks canonical intent and
action-result capacity, including repeated arguments, before approval and
dispatch. A denial after discovery still sends zero effect requests. The Client
rediscovers and compares the descriptor immediately before dispatch.

A pre-dispatch refusal returns `failed` with `code: "mcp_refused"`. A tool
response with `isError: true` instead returns `failed` with
`code: "mcp_tool_error"`, the redacted `message` and a `truncated` boolean.
Shared MCP response admission rechecks the redacted diagnostic for configured
private values before ordinary or extension publication. A hit returns unknown
with no diagnostic, stopping continuation. Successful tool, resource and prompt
text use the same publication rule; extension source persistence also rechecks text.
The message retains at most 2048 UTF-8 bytes without splitting a codepoint, so
even JSON escaping fits the SDK envelope. This response confirms dispatch, not
rollback: a remote write may have partly completed. Inspect the service before
requesting another approved call. It grants no successful source-read authority.
Transport loss or an invalid response remains `unknown` and stops continuation.

New operations and explicit mixed invocations use version-two action records
with `effect_binding`. Version-one records retain their exact shape. The public
binding identifies the alias, schema, selected manifest and redacted server
configuration. Restore recomputes server fingerprints. Descriptor hashes bind
live rediscovery; they cannot be recomputed from the redacted description.
Hashes establish consistency, not publisher authenticity.

A successful call returns a host-issued source descriptor:

```json
{"version":1,"operation_id":"11111111111111111111111111111111","kind":"mcp.text","source_sha256":"0000000000000000000000000000000000000000000000000000000000000000","byte_count":12000}
```

The values illustrate the shape. Save the actual descriptor in private state.
Complete source text is at most 65536 UTF-8 bytes and its private encoded source
record is at most 256 KiB. Session persists `extension_effect_result` before the
successful action result, binding the parent, operation, identity, request,
effect binding and data digests. A source without that successful result grants
no read authority. The record-capacity check reserves no aggregate bytes or
events; journal exhaustion can still seal a later execution.

## Read text without expanding the worker protocol

Use the actual descriptor's operation and digest in this request:

```json
{"op":"effect.result.read","version":1,"operation_id":"11111111111111111111111111111111","source_sha256":"0000000000000000000000000000000000000000000000000000000000000000","offset":0,"limit":4096}
```

An `ok` window has exactly `version`, `operation_id`, `kind`, `source_sha256`,
`offset`, `next`, `complete` and `text`. Append `text` and request the returned
`next` byte offset. Stop only at `complete:true` and `next:null`. Windows contain
at most 4096 UTF-8 bytes and never split a codepoint. Interior offsets and limits
too small for the next codepoint return `result_refused`.

Only an earlier successful call in the same invocation is readable. Another
invocation, arbitrary old journal or interrupted source refuses. A question may
retain an earlier successful source within its invocation; only an explicit
answer starts the saved continuation. Paging grants no publication or new effect.
Recovery recomputes every successful window from its saved source.

Public SDK objects remain 16 KiB. Private worker state may contain arbitrary
Elixir terms, but a durable question checkpoint is at most 8 KiB. Save a descriptor
and cursor there rather than an entire source or vector collection.

## Request bounded text inference

`model.complete` selects one named operator profile. The extension receives
bounded text and normalized usage without credentials, conversation, main tools
or native continuation. A version-one request has exactly these seven fields:

```json
{"op":"model.complete","version":1,"profile":"extract","instruction":"Extract names from the supplied text.","input":"Ada","max_output_bytes":1024,"timeout_ms":5000}
```

Profile IDs start with an ASCII letter and contain at most 64 letters, digits,
underscores or hyphens. Instruction permits 2048 characters; nonempty input
permits 4096 characters. The complete request is at most 8 KiB. Output is
1..8192 bytes and the deadline is 1000..120000 milliseconds. Unknown fields and
direct provider/model/endpoint/key overrides refuse. There are no tools, audio,
embeddings or continuation in this operation.

Version two adds required `response_schema`, permits a 12 KiB complete request,
and accepts only a matching JSON object. Use a native Ollama profile:

```json
{"op":"model.complete","version":2,"profile":"extract","instruction":"Return a JSON object with a names array containing names from the input.","input":"Ada","max_output_bytes":1024,"timeout_ms":5000,"response_schema":{"type":"object","properties":{"names":{"type":"array","maxItems":1,"items":{"type":"string"}}},"required":["names"],"additionalProperties":false}}
```

The root schema is an object and uses the bounded [MCP schema subset](mcp.md),
without references or loaders. It enlarges no input, instruction, deadline or
text limit. `ModelCall.prepare/2` derives native `format`, retaining the selected
reasoning and token settings. Other providers refuse before approval/admission;
there is no schemaless fallback. This path does not use the internal summary
contract. `value_from_record/4` validates UTF-8, bytes, duplicate-free JSON, SDK
bounds and schema, then returns the original text. A schema-valid invented name
is still invented; domain code checks meaning, quotations and attribution.

Version three has the same required schema, provider selection, request bytes
and output limits as version two, with a request deadline of 1000..600000 ms.
For a worked change, take the version-two request above, set `version` to `3`,
`profile` to `answer` and `timeout_ms` to `480000`. Configure both the root timeout and that operator
profile's `model_call_timeout_ms` to `480000`, as shown in the
[operator procedure](../operator/configuration.md#allow-a-longer-extension-answer).
`ModelCall.prepare/2` must return an effective deadline of 480000; omitting the
profile override or retaining the default root limit must return 120000.

The override replaces the ordinary profile timeout for extension model calls.
Project scopes cannot set it. Its absence preserves historical snapshot bytes,
and ordinary main/child profile settings exclude it. The saved execution still
must equal the value recomputed from the captured scope and request. Delegated
approval additionally rejects an execution deadline above the request's limit.
No version-three request changes the SDK-2 aggregate or read deadline. Longer
SDK-1 answer calls use the existing inference owner, cancellation and accounting.

The fixed host system instruction and labelled user-role JSON carry the approved
instruction/input. Extension instructions do not become system rules. Reading
history, prompts, answers, memory or tool views needs separate capabilities.
Profile existence grants no egress. Full approval displays the request, instance,
artifact, session, profile, provider/model/billing, destination digest, reasoning,
effective output ceiling and deadline.

Destination facts expose scheme/host/port as `origin` and bind the full wire URL
as `target_sha256`. Paths and credentials are absent from public facts. Profile
URLs reject userinfo, queries, fragments and invalid ports; project profiles
cannot replace operator IDs, choose endpoints or grant longer model deadlines. The same adapter route supplies
both disclosure and dispatch. See [configuration training](configuration.md).

`Ipse.Provider.request_complete/4` resolves the selected credential inside the admitted task.
No main key, injected provider module or SDK handle is inherited. Each supported
named profile retains its selected provider and billing mode.
Demo cannot perform inference. Missing credentials, service or model fail without
fallback. Unsupported subscription output caps refuse. Preparation narrows output
and deadline against owner policy and reservations; each request consumes an
owner model step and other-call allowance.

An Ollama profile can explicitly select `reasoning_effort:"none"` for native
`think:false`; omission sends no thinking control. The selected model/backend
must support the choice. It remains visible in approval and saved execution
facts. Input bounds remain independent of the main conversation's context limit;
the service owns its model context window.

`Ipse.Extension.Inference` owns shared text/embedding task, monitor, deadline
and usage forwarding. Worker death or cancellation closes its owned HTTP profile;
remote work may already have happened. Text deltas do not enter the main stream.
Keep text-specific validation in `ModelCall` when changing that coordinator.

## Separate text, wire and accounting outcomes

Before inference, Session records the approved action, `extension_model_request`
and canonical `request_admitted`. Request ID equals operation ID and attempt ID
is fresh. Kind is `extension`, with actual provider, billing, profile and original
child/parent origin. Reservations and conservative settlement use the real shared
budget root. Refusals count as attempts, not admitted budget bookings.

If the producer deadline expires while Session syncs an admission, Session closes
that admission with a failed completion before returning `model_request_failed`
or `embedding_request_failed`. No provider call or budget reservation starts.
Keep this distinct from a pre-admission `model_limit` or `embedding_limit` refusal;
recovery must find a completion for the admitted attempt.

The provider wire is at most 1 MiB including event framing, independently of the
8 KiB text ceiling. This is not a bound on every HTTP buffer or process heap.
A private `extension_model_response` retains original assistant/native data and
exact IDs/digest up to 256 KiB encoded. All request versions return version-one
results; structured output remains the original JSON string in `text`:

```json
{"version":1,"request_id":"00000000000000000000000000000001","attempt_id":"00000000000000000000000000000002","profile":"extract","reported_model":null,"text":"Ada","usage":{"version":1,"counts":{"input_tokens":null,"output_tokens":null,"total_tokens":null},"derived_fields":[],"quality":"unavailable","issues":[]}}
```

The value is at most 12000 encoded bytes before continuation framing. It contains
no auth, hidden reasoning or raw native fields. Missing measurements remain null.
Tool calls, malformed/oversized text, schema-invalid JSON and unavailable bounded
native receipts return `model_response`. Rejected output can still be completed,
metered inference. Other closed failures are `model_limit`,
`model_request_failed`, `model_timeout` and `model_cancelled`. Never infer a retry,
refund or final charge from interruption.

Restore checks the original profile/policy before tail repair, retained response,
canonical completion, request source and invocation/session/turn. Versions two and three
reapply the approved schema. Child usage readers validate the same sources.
Idle resume performs no inference; interrupted work retains unknown/partial
measurements and shared liabilities. See [usage accounting](accounting.md)
and [budgets](accounting.md).

## Generate and reconstruct embeddings

`embedding.create` has a separate operator registry, typed response and accounting
operation. Text containing numbers is not an embedding response. This complete
request goes inside the host-call envelope:

```json
{"op":"embedding.create","version":2,"profile":"local_embedding","inputs":["A bounded synthetic source chunk."],"timeout_ms":30000}
```

All fields are required. There are 1..8 nonempty UTF-8 inputs, at most 4096 bytes
each and 12288 bytes together. The request fits the ordinary 16 KiB SDK object;
the deadline is 1000..120000 milliseconds. Arguments cannot select dimensions,
model, endpoint, credentials, headers, output caps, truncation or provider modules.
Use `host.embedding` and, for pages, `host.results`. The
[operator embedding procedure](../operator/extensions.md) gives complete setup.

Trace `Operation.validate/1` into `EmbeddingCall`, then Session action admission.
`Ipse.Config.Profiles.prepare_embedding/2` selects only operator settings and private budget/
origin references. Parent history, keys, tools, injected modules, text caps and
reasoning settings are absent. The v2 `effect_binding` pins embedding execution
and safe destination. Approval uses those exact facts.

Before approval, `EffectResult`'s capacity planner constructs bounded canonical request, source,
usage, completion and action-result records for selected input count/width,
including repeated arguments and legal metadata. A known unrepresentable result
refuses without provider dispatch or journal sealing. Admission rechecks capacity
immediately before dispatch. Aggregate bytes/events remain unreserved.

`Ipse.Provider.request_embedding/3` resolves `OPENAI_API_KEY` only for OpenAI; Ollama gets
no inherited authorization. `Provider.Embedding` makes one bounded nonstreaming
POST to OpenAI `/embeddings` with `encoding_format:"float"`, or Ollama
`/api/embed` with `truncate:false`. Request dimension mode adds dimensions; native
mode omits them. The HTTP profile keeps TLS/proxy policy and a 2 MiB response
ceiling. No redirect, retry, fallback or model download is added.

OpenAI indices uniquely cover the input range; Ollama rows are positional. Count
and width must match selection. Every coordinate remains finite and representable
after float32 little-endian conversion. All-zero vectors, including values that
round entirely to zero, refuse. Ordered input hashes and decoded-byte vector
hashes bind content. The native-response digest binds received bytes, not remote
weights or semantic quality.

Successful v2 results have this shape, with actual values substituted:

```text
{version:2, request_id, attempt_id, profile, reported_model, usage, selection_sha256,
 result:{version:2, operation_id, kind:"embedding.f32le", source_sha256,
         encoding:"float32le.base64", vector_count, dimensions}}
```

`Ipse.Config.Profiles.embedding_selection_sha256/2` hashes an ordered identity tagged
`ipse.embedding.selection`, version 1, containing profile, operation, provider,
requested model, billing, destination origin/target digest, dimensions and mode.
Timeouts, inputs, credentials, budgets and request/session IDs do not alter it.
An unchanged endpoint/model name cannot prove unchanged remote weights or routing.
V1 remains readable with its original result shape but cannot authenticate a
current durable vector. Never stamp a current hash onto an older result or
silently fall back. Both versions use private source v2, descriptor v2 and page v2.

Save the actual descriptor and request coordinate pages:

```json
{"op":"effect.result.read","version":2,"operation_id":"00000000000000000000000000000001","source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","vector_index":0,"offset":0,"limit":768}
```

The result binds operation/source, input/vector hashes, dimensions, encoding,
index, offset, next, completion and Base64 `values`. Append decoded bytes in
cursor order until `complete:true` and `next:null`, then compare their complete
hash with `vector_sha256`. Offsets count coordinates. An exact-end empty page
is valid. One page permits 768 coordinates, 3072 decoded bytes and 4096 Base64
characters; a 4096-coordinate vector needs six pages. Ordinary 8 KiB string and
128-element collection limits remain. Eight maximum-width vectors fit the
separate 256 KiB private source ceiling.

Session records approved action, `extension_embedding_request` and canonical v2
admission before dispatch. On settled success, one private v2 source precedes
canonical completion and public result. Its inference fields bind request,
attempt, profile, reported model, normalized usage and native digest.
`Usage.restore/2` and `Actions.restore/2` independently validate accounting and
actions. `EmbeddingCall.value_from_completion/4` derives selection identity from
the original approved intent, never current configuration. A source followed by
completion needs final equal usage/model even if the action ends unknown.
A source without completion is an interrupted prefix; only a successful action
grants reads. Recovery reconstructs each page from that exact source.

The coordinator captures known result/usage before guarded settlement. If
settlement fails, known counters survive but no vector becomes readable and no
refund follows. Usage beyond provable ledger coverage refuses recovery for
inspection. Closed failures are `embedding_limit`, `embedding_request_failed`,
`embedding_response`, `embedding_timeout` and `embedding_cancelled`. Denied and
unknown outcomes are empty. Keep completed metered work distinct from successful
publication.

## Verify a changed effect boundary

Build and run one SDK-only fixture per operation you change:

```sh
IPSE_EFFECT_ARTIFACTS=$(mktemp -d)
elixir dev/build-artifact.exs mcp-actions --sdk _build/dev/lib/ipse/ebin --output "$IPSE_EFFECT_ARTIFACTS/mcp"
elixir dev/verify.exs source mcp --sdk _build/dev/lib/ipse/ebin --input "$IPSE_EFFECT_ARTIFACTS/mcp"
elixir dev/build-artifact.exs model-calls --sdk _build/dev/lib/ipse/ebin --output "$IPSE_EFFECT_ARTIFACTS/model"
elixir dev/verify.exs source model --sdk _build/dev/lib/ipse/ebin --input "$IPSE_EFFECT_ARTIFACTS/model" --selection default
elixir dev/verify.exs source model --sdk _build/dev/lib/ipse/ebin --input "$IPSE_EFFECT_ARTIFACTS/model" --selection none
elixir dev/verify.exs source model --sdk _build/dev/lib/ipse/ebin --input "$IPSE_EFFECT_ARTIFACTS/model" --selection json
elixir dev/verify.exs source model --sdk _build/dev/lib/ipse/ebin --input "$IPSE_EFFECT_ARTIFACTS/model" --selection json-none
elixir dev/build-artifact.exs embedding-actions --sdk _build/dev/lib/ipse/ebin --output "$IPSE_EFFECT_ARTIFACTS/embedding"
elixir dev/verify.exs source embedding --sdk _build/dev/lib/ipse/ebin --input "$IPSE_EFFECT_ARTIFACTS/embedding"
```

The four model selections cover text/schema output with omitted/explicit Ollama
thinking policy, exact native schema, approvals, usage and idle resume. These
are transport and ownership fixtures, not retrieval-quality or billing evidence.
Use the [testing manual](testing.md) for the unchanged installed-package runs.

Choose a regression that proves the boundary, including its refusal path:

| Boundary | Exercise | Focused checks |
| --- | --- | --- |
| File/shell ownership | Deny a write, then stop an owner whose shell is still running; require no denied file and no promoted interrupted success | `test/ipse/extension/invocation_test.exs`, `test/ipse/extension/event_job_test.exs` |
| MCP source/capacity | Select a 65536-byte record ceiling; require zero discovery/effects and an unsealed journal. Compare exact 262144-byte encoded source with one byte less | `test/ipse/extension/effect_result_test.exs`, `test/ipse/extension/mcp_call_session_test.exs`, `test/ipse/mcp/` |
| Text wire/result | Keep a small answer with more than 64 KiB valid framing; refuse above 1 MiB wire. Reject oversized text while retaining completed usage | `test/ipse/extension/invocation_test.exs`, `test/ipse/extension/model_call_test.exs`, `test/ipse/extension/model_jobs_test.exs` |
| Embedding identity | Change only a successful selection hash and recompute the superficial outcome hash; standalone Actions and Session must still refuse | `test/ipse/extension/embedding_call_session_test.exs`, `test/ipse/config/profiles_test.exs` |
| Embedding capacity | Four 4096-coordinate vectors under a 65536-byte ceiling must dispatch zero requests; normal-ceiling and one-vector controls complete | `test/ipse/extension/embedding_result_test.exs`, `test/ipse/provider/embedding_test.exs` |
| Settlement | Fail settlement after response; require known counters, no readable vectors and retained applicable liability | `test/ipse/usage/embedding_test.exs`, `test/ipse/usage/costs_test.exs` |

Keep confirmed cleanup assertions. HTTP cleanup needs a local resource receipt
after owner death, not merely a dead process. When changing shared inference,
run both text and embedding controls. Choose retrieval models only after the
separate frozen-workload quality and resource evaluation.
