# Build an accounted embedding action

Work through this chapter after [text model calls](extension-model-calls.md) and
[MCP result reads](extension-mcp-actions.md). Embeddings use the same session,
approval and budget owners, with a distinct typed provider response and explicit
output-token non-applicability. Start with
[`examples/embedding-actions/src/embed.ex`](../../examples/embedding-actions/src/embed.ex).
The worker requests inference and reads bounded pages; it contains no HTTP client
or credential lookup.

## Follow one request

Declare `host.actions` and `host.embedding`. An extension that reads its vector
results also needs `host.results`. Use `host.actions.mixed` when a workflow needs
up to 512 reads and 16 other calls under their separate grants and approvals.
The unchanged ordinary invocation limit is 16 actions.

Return the SDK host-call envelope:

```json
{
  "api_version": 1,
  "kind": "host_call",
  "request": {
    "op": "embedding.create",
    "version": 2,
    "profile": "local_embedding",
    "inputs": ["A bounded synthetic source chunk."],
    "timeout_ms": 30000
  }
}
```

All fields are required and additional fields refuse. Inputs are one through
eight nonempty UTF-8 strings, at most 4,096 bytes each and 12,288 bytes together.
The complete request passes the ordinary SDK's 16 KiB object limit. The deadline
is 1,000 through 120,000 milliseconds. Arguments cannot choose a model, endpoint,
dimensions, credential, headers, output cap, truncation or provider module.

Trace `Operation.validate/1` into `EmbeddingCall.validate/1`, then
`Session`'s action begin handler. `EmbeddingProfiles.prepare/2` selects only the
operator registry and constructs a fresh private runtime. It copies selected
profile and existing budget/origin references, omitting parent history, keys,
tools, injected modules, text output caps and reasoning settings.

The action's v2 `effect_binding` pins `kind: "embedding"`, execution and safe
destination. Metadata snapshots contain the destination's origin and actual
wire-target digest, so recovery can compare hidden URL paths without storing
them in public selection facts. Approval shows the complete request and these
exact facts. Profile existence and an enclosing tool approval grant no egress.
The [operator procedure](../operator/embeddings.md) gives a complete configuration.

## Trace ownership through transport and settlement

Read these modules in order:

| Module | Responsibility |
| --- | --- |
| `Ipse.Extensions.EmbeddingCall` | Closed request, route binding, source/result coherence |
| `Ipse.Extensions.EffectCapacity` | Canonical per-record journal capacity before approval and dispatch |
| `Ipse.Extensions.Inference` | Actual worker monitor, owned task, deadline and usage forwarding |
| `Ipse.Provider.Request` | Fixed credential lookup after admission |
| `Ipse.Provider.Embedding` | Exact OpenAI/Ollama wire route, bounded decode and float32 validation |
| `Ipse.Usage` and `Ipse.Budget` | Canonical measurements and conservative shared liabilities |
| `Ipse.Extensions.EffectResult` | Complete private source and reproducible coordinate pages |

`Inference.execute/4` receives a compiled `:text` or `:embedding` kind and host
function. Worker JSON cannot select its messages, callbacks or modules. The
coordinator asks Session to admit the actual action, then uses the same owned
TaskResources/HTTP profile chain and budget root as other inference. Worker death,
deadline, cancellation or activation expiry stops the owned request. Confirmed
process cleanup does not undo remote work.

Before showing approval, Session compares the selected input count and vector
width against the operator's `journal.max_record_bytes`. `EffectCapacity`
constructs bounded canonical request, source, usage, completion and action-result
records, including the request repeated in the result. It uses the selected
shape and legal metadata limits. A known unrepresentable result refuses without
provider dispatch or a sealed journal. Admission rechecks capacity immediately
before embedding dispatch. This per-record check reserves no aggregate journal
bytes or events; those limits still apply throughout execution.

`Provider.Request.embed/3` resolves only `OPENAI_API_KEY` for OpenAI. Ollama gets
no inherited authorization. The adapter makes one bounded nonstreaming POST:
OpenAI `/embeddings` with `encoding_format: "float"`, or Ollama `/api/embed` with
`truncate: false`. `dimension_mode: "request"` adds dimensions; native mode omits
them. The existing HTTP profile enforces TLS/proxy policy and a 2 MiB response
ceiling. No redirect, retry, fallback or model-download path is added.

The adapter validates every vector before returning any result. OpenAI indices
must uniquely cover the input range; Ollama rows are positional. Count and width
must match selection. Coordinates must remain finite and representable after
explicit float32 little-endian conversion. All-zero vectors, including values
that round entirely to zero, refuse. Input hashes preserve order. Vector SHA-256
hashes decoded float32 bytes. The native-response digest binds the received bytes;
it does not authenticate remote weights or establish semantic quality.

The coordinator captures typed result and normalized final usage before invoking
the budget-guarded final observation. A successful provider response followed by
failed settlement still leaves known counters available to Session. It creates
no readable vector source and receives no refund. If canonical usage exceeds
provable ledger coverage, recovery fails closed for inspection.

## Reconstruct one vector without widening the SDK

A successful v2 action returns this shape, with real IDs/hashes/counters substituted:

```text
{version:2, request_id, attempt_id, profile, reported_model, usage, selection_sha256,
 result:{version:2, operation_id, kind:"embedding.f32le", source_sha256,
         encoding:"float32le.base64", vector_count, dimensions}}
```

Use v2 when retaining embeddings for later comparison. `EmbeddingProfiles.selection_sha256/2`
owns the identity of the approved selection. It hashes a fixed ordered array with
the tag `ipse.embedding.selection`, identity version 1, profile ID, operation,
provider, requested model, billing mode, destination origin and wire-target digest,
dimensions and dimension mode. The existing destination normalizer owns URL
equivalence. Timeouts, inputs, credentials, budgets and request/session IDs do not
change this identity. An unchanged endpoint and model name cannot prove unchanged
remote weights or routing. Keep that limit explicit in any durable index.

Request v1 remains supported with its exact v1 result shape, without a selection
hash. It cannot authenticate a current durable vector. A host refusing v2 must
produce an ordinary refusal; do not fall back to v1 and stamp the current hash
onto an older result. Both request versions use the same private source v2,
descriptor v2 and page-read v2 protocols.

Save the descriptor in private worker state. Request a page:

```json
{
  "op":"effect.result.read", "version":2,
  "operation_id":"00000000000000000000000000000001",
  "source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "vector_index":0, "offset":0, "limit":768
}
```

Use the descriptor's actual operation/source values. The response binds these
values plus input/vector hashes, dimensions, encoding, selected index, coordinate
offset, next offset, completion and Base64 `values`. Decode each page and append
its bytes in cursor order. Continue until `complete` is true and `next` is null;
then compare complete bytes against `vector_sha256` before using the vector.
An exact-end empty page is valid. Cursors count coordinates, not bytes.

One page has at most 768 coordinates, 3,072 decoded bytes and 4,096 Base64
characters. A 4,096-coordinate vector needs six pages. Every public object keeps
the ordinary 8 KiB string and 128-element collection limits. Complete private
source events are separately bounded to 256 KiB; eight vectors at maximum width
fit that bound. Arbitrary private worker state is not an SDK JSON value, but a
durable question checkpoint remains at most 8 KiB. Store a descriptor or small
cursor there, not every vector.

## Validate the durable sequence

Session persists approved action, `extension_embedding_request` and canonical
v2 admission before dispatch. Request ID equals action operation ID; attempt ID
is fresh. The source binds identity, request, selected execution, safe destination
and admission. On settled success, exactly one private v2
`extension_effect_result` precedes canonical completion and public action result.
Its `inference` fields bind request/attempt/profile, reported model, normalized
usage and native-response digest.

`Usage.restore/2` and `Actions.restore/2` independently check their respective
accounting/action contracts. `EmbeddingCall.value_from_completion/4` takes the
full original approved intent, validates its source and derives the public v2
selection hash from that saved binding. Recovery never substitutes current
operator configuration. Standalone Actions validation also compares that hash
with the original binding, including journals with no `usage.read` action.
A source followed by completion requires completed,
final, equal usage and equal reported model, even when the action ends unknown.
Source without completion is a permissible interrupted prefix. Source and even
completed measurement without the successful action grant no read authority.
Readers require an earlier successful same-invocation result and reconstruct
every page from its exact saved source. Idle resume performs no IO or replay.

Closed failures are `embedding_limit`, `embedding_request_failed`,
`embedding_response`, `embedding_timeout` and `embedding_cancelled`. Denied and
unknown outcomes are empty. Completed metered work can fail publication if its
bounded source/result cannot be retained. Keep that accounting distinct from a
successful extension result.

Children require explicit delegation, `allow_children`, both host grants, the
operator registry and exact separate child egress approval. They share the real
parent budget root and retain fresh accounting/origin. Embedding approval owns
no filesystem mutation lease. Child MCP and recursive delegation remain refused.

## Change one boundary and verify it

Build the SDK-only example and run its synthetic loopback proof:

```sh
IPSE_EMBEDDING_ARTIFACT=$(mktemp -d)/artifact
elixir scripts/build-artifact.exs embedding-actions --sdk _build/dev/lib/ipse/ebin --output "$IPSE_EMBEDDING_ARTIFACT"
mix run examples/embedding-actions/verify.exs "$IPSE_EMBEDDING_ARTIFACT"
mix test test/embedding_profiles_test.exs test/provider/embedding_test.exs test/embedding_accounting_test.exs test/embedding_costs_test.exs
```

As an exercise, change a saved input hash, vector width, source digest or operation
tag in a fixture. Require refusal before tail repair and zero additional provider
dispatch. In `test/extensions_embedding_call_session_test.exs`, change only a
successful v2 selection hash and recompute the superficial outcome hash. Both
standalone Actions validation and full Session recovery must refuse. In
the same Session suite, select four 4096-coordinate vectors under a 65536-byte
record ceiling. Require zero requests, no approval prompt and an unsealed
resumable journal. The single-vector and normal-ceiling controls must still
complete. `test/extensions_embedding_result_test.exs` compares real canonical
record sizes with the capacity bound, including maximum legal metadata and
escaped inputs. In
`test/embedding_profiles_test.exs`, compare endpoints and models with identical
dimensions, then change only a timeout. Only the latter keeps selection identity.
Then test cancellation and a settlement failure after the response
arrives. Known counters must survive, readable vectors must remain absent and
applicable liabilities must remain booked. Run the unchanged text model-job
proof after changing the shared coordinator.

Follow [usage accounting](usage-accounting.md), [costs](costs.md) and
[budgets](budgets.md) for operation-aware units and conservative pricing. Synthetic
vectors prove transport, authority and reconstruction. Select retrieval models
only after a separate frozen-workload quality/resource evaluation.
