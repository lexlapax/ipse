# Proposed complete result transport, 2026-10-19

Design and investigation record; the new transport is **not implemented**. The
[resumption record](resumption.md) owns current repair work; the
[plan](../../plan.md#p27-optional-research-graph-and-rag) owns acceptance. Existing
[query behavior](../../developer/knowledge-extensions.md) still refuses oversized
results. This document selects a design to implement and verify, not a passing
runtime or security verdict.

## Preserve the complete result

The synthetic reproduction produces ten full quotations in a 16,911-byte result.
All three knowledge packages currently refuse above 12,000 encoded bytes. Their
ordinary workers close after each invocation. Existing `effect.result.read`
windows cover approved upstream MCP/embedding effects in the same invocation;
they cannot publish a computed domain result for later reading.

Keep the complete ranked evidence, quotations, origins, attributed claim bases,
gaps and coverage. Graph claims may cite evidence absent from the top ten. A
single citation may exceed one page. Fragment exact encoded bytes rather than
cropping or requiring each logical item to fit a page. Research remains
independent and creates no Corpus/Graph State store.

Two independent design candidates compared immutable journal publication with a
retained temporary worker. An independent cross-judge preferred journal
publication conditionally. The lead selects that family because it preserves
ordinary confirmed worker shutdown and permits deterministic recovery without
inference replay. The alternative adds worker leases, expiry and unavailable
results after restart. Its unchanged logical collection bound would also refuse
Graph's admitted 256-claim shape. Requested model choices differed; serving
identities were not independently exposed.

## Callers consume a delivery, then a value

The worker-side SDK helper freezes the complete value once. Small values retain
the existing inline reply. An explicitly granted producer can instead offer a
bounded output descriptor and answer sequential byte requests during the original
invocation. Host drains it before closing the worker. A final committed receipt
publishes the reference only after exact validation and confirmed close.

Proposed call sites, not current APIs:

```elixir
# Worker query completion, after its existing domain revalidation.
{:ok, delivery} = ResultPublication.prepare(value)
{:ok, delivery, state}
# delivery is an ordinary bounded SDK result or a private SDK Output value.
# An invalid/over-cap aggregate returns {:error, :invalid_result_document};
# the domain callback must return its existing bounded capacity refusal.
# Bootstrap freezes Output and owns the terminal transport phase.

# Trusted Session client or evaluation driver, after the exact final receipt.
Session.materialize_result(session, delivery)
# => {:ok, %{value: complete_value, provenance: historical_receipt}}
# => {:error, reason}; no usable partial value

# Model-facing bounded structured view, not base64 decoding by an LLM.
saved_result_read(%{"output_id" => id, "path" => ["evidence", 0, "citation", "quote"],
                    "offset" => 0})
```

Delivery is an explicit inline/saved union. A descriptor is never validated or
presented as if it were the original domain value. Evaluation hydrates every byte
and checks the full hash/schema before span verification, answer preparation or
metrics. Failure remains the first failed prediction; it cannot trigger another
query or inference. Record the descriptor and assembly proof alongside the
complete execution evidence.

The CLI provides an explicit saved-result inspection procedure. Model views use
typed path segments (object keys or array indices), bounded child summaries and
UTF8 string windows. A large child is a labeled reference, not silently omitted
content. Expose array counts and final completeness. Deterministic client
materialization uses raw byte windows internally. It does not ask a model to
reconstruct base64 or inject an unbounded tool message. The separately declared
answer-context policy runs only after complete hydration.

## Keep authority in Session

Add explicit opt-in capability `invoke.result.pages` for paged output. Existing capabilities and
inline receipts retain their contracts. A selected artifact cannot infer this
grant from source text, a cursor or an upstream effect descriptor. Artifact builds
and operator configuration must advertise the new capability and SDK helper.
Paged producers require manifest/description SDK version 2. SDK-1 artifacts
retain their existing contracts. Older hosts reject SDK-2 manifests before
loading code; new hosts independently validate the SDK/capability pair and exact
description handshake. Protocol framing and bounded JSON envelopes remain version
1. SDK version 2 adds the private callback-result union, not larger wire values.

Version-one publication is restricted to original top-level `invoke.tool` and
`invoke.command` execution. Standalone/routed services, event jobs,
transformations and other callbacks keep their inline contracts. A producer offer
in those paths fails before source begin/drain or read authority. Artifacts with
both services and queries may still return ordinary inline service results.
Offers from `host.actions` question-recovery execution are also unsupported in
this first contract; ordinary inline question recovery retains its old behavior.
Committed saved results remain readable after restart without a producer.

Bootstrap recognizes the SDK-2 private Output value only for an eligible stage
with the grant. It freezes/encodes once, discards the domain callback state and
enters a terminal frozen state. It intercepts `result.output` itself rather than
calling the domain module. Worker separately admits that stage only after a
granted producer offer; its stage maps to `invoke.result.pages` rather than a
literal `result.output` manifest capability. Direct reads before an offer, reads
without the grant, and subsequent domain/action callbacks fail closed. Native
close remains available. Bootstrap and Worker both enforce the transition.

Session derives result identity from the admitted session/invocation, export,
arguments, artifact/options identity, logical schema and full byte digest. A
reference is a locator, not a bearer grant. Only Session calls Journal.Writer.
The owned Host task submits bounded begin/chunk/seal requests to Session, which
checks its current job lease before each durable append. It never receives a
writer handle or chooses a journal path.

Public human reads require ownership of the same Session. Model reads additionally
require a committed source already disclosed through a model-visible tool result.
An `/ext` command result remains separate from the model conversation; knowing its
ID does not authorize a model read. Child Sessions and unrelated extensions gain
no access. Do not reinterpret `host.results`, `host.history` or routed
`service.call` to grant this new authority.

## Use historical receipt semantics

An explicit read returns the immutable output of the original invocation. It does
not assert current source eligibility, republish context automatically or execute
a new query. Displays and proofs identify it as `historical_receipt` and retain
the original identity/time. Later source forget, expiry or replacement governs
future retrieval; it does not rewrite retained output bytes. This follows the
existing memory contract's separate journal/previous-conversation retention
limits, rather than introducing a promise of retroactive erasure.

Changed installed artifacts/options cannot relabel an old receipt. Restored reads
validate its original pinned identity without executing old code. Session export,
transcript sharing and redaction must explicitly account for retained source
records. Hidden source records must not become an automatic model history feed.
If a future product requirement demands revocation of retained historical bytes,
it needs a separate contract covering existing inline receipts too.

## Bound and validate the aggregate separately

Keep each SDK object at 16,384 encoded bytes, strings at 8,192 bytes, depth at 12,
collections at 128, worker frames at 32,768 and cumulative traffic at 64 MiB.
Keep each output page below 12,000 encoded bytes. A raw fragment of at most 4,096
bytes becomes at most 5,464 base64 bytes; validate the complete response wrapper.
Each fragment contains exactly `min(4096, byte_count - offset)` raw bytes.
This fixed stride determines every offset and the exact fragment count before
reservation; a short nonfinal fragment refuses. Fragments may split JSON tokens or UTF8 bytes because decoding happens after
assembly. Public string views instead respect UTF8 boundaries.

The new logical document has a separate finite contract: at most 4 MiB encoded,
depth 12, strings 8,192 bytes, 4,096 entries per collection and 262,144 total nodes.
The larger aggregate collection permits Graph claims without changing the SDK
collection limit. Require a map root and the unchanged declared result schema.
Use the maintained JSON codec/schema engine behind the existing checked schema
subset. Add a separate bounded aggregate entry point; do not weaken
`Schema.validate_object/1` or accept a descriptor against a domain schema.

Refactor the existing ordered-object/duplicate-key decoding logic behind a shared
adapter. Keep `Manifest.decode_json/2`'s 1-MiB ceiling unchanged. The new aggregate
entry point has its own 4-MiB ceiling, performs resource preflight before parsing,
rejects duplicate decoded keys at every depth, and uses the checked schema
compiler/JSONSchex without the ordinary SDK object-size check. Apply the byte cap
to both received bytes and canonical re-encoding; hash the exact received bytes.
Keep the existing finite-float rule. Integers remain exact, with complete integer
tokens limited to 1,024 bytes, including a minus sign. The maintained Jason
decoder has this stricter compile-time limit and no per-call override. Encoding
uses the same limit so a valid encoded document can be decoded. Do not change
the global codec configuration. A raw `Jason.decode` shortcut is insufficient.

Before decoding untrusted complete bytes, bound lexical nesting, token count,
encoded string size (49,154 bytes including quotes) and primitive-token length
(8,192 bytes). Then use the existing parser
and validate the decoded resource limits and declared schema. This preflight is
a resource guard, not a new JSON grammar/parser. It prevents a short-byte-limit
document with extreme nesting or huge numeric tokens from allocating an
unbounded decoded structure. Document why the ordinary 16-KiB adapter cannot
provide this aggregate boundary.

Permit one source per invocation, at most 1,024 fragments, 64 published sources
and 64 MiB of encoded source records per Session, further restricted by the
operator's existing journal byte/event/record ceilings. Account for pending and
orphan records too. Reserve before draining; exhaustion yields no successful
partial result. Existing small inline results keep their behavior.

Before source begin, Session reserves remaining byte/event capacity for begin,
every fragment, seal, the final result and existing quota-marker headroom. Compute
JSONL sizes from the admitted fixed fields and exact base64 lengths; charge
record ceilings independently. The owner-only Writer reservation prevents other
appends from consuming that capacity. Every reserved append decrements the
reservation. Other events may use only unreserved space. Cancellation releases
unused reservation before recording its control outcome. Physical orphan records
remain charged; unused reservations do not become replay authority after restart.
Bound begun source attempts, including orphans, at 64 per Session. Offers refused
before begin remain subject to ordinary invocation/journal ceilings.

Insufficient reservation refuses before source begin. If even the bounded
failure/quota record cannot fit, retain the existing terminal journal-quota
behavior; continued Session writes are not promised. Unexpected write/fsync,
lease or cleanup failure after admission yields unknown publication, no public
reference and no replay. Do not pretend reservation guarantees successful IO.

Four MiB is a bounded capacity choice, not a guarantee for every legal Graph
combination. Up to 256 facts with eight full basis citations each can exceed it,
especially with 8-KiB origin receipts and JSON escaping. Report explicit capacity
refusal instead of dropping claims, provenance or top-k. Measure target and
near-cap cases. No existing model, action, callback, Research body/time or traffic
limit is increased or reset.

The new grant introduces a 120,000-ms aggregate output deadline, starting at
Session invocation admission before initialization. This is a new finite bound,
not an assertion that every current export already has one. Store its monotonic
deadline with the owned live job and take the lesser of it and any existing
tighter deadline. The same deadline covers initialization, computation/approval,
actions, drain, aggregate validation, appends, close and final commit. Each callback
uses the lesser of its existing bound and remaining time. Check before and after
each boundary; neither an offer nor a fragment restarts the clock. Readable
committed results get separate bounded local read tasks, without inference.

No producer execution resumes across a question/restart in version one, so a
fresh `Host.resume_export` clock cannot renew output time. Record nondecreasing
elapsed samples in source begin/seal/final receipt, bounded by 120,000 ms; pure
recovery validates recorded samples without consulting a current clock. Expiry
after seal or confirmed close still blocks final publication and leaves an
unreadable charged orphan. If final sync finishes after the last clock sample,
the durable receipt remains the commit; no realtime disk-completion guarantee is
claimed. A committed result cannot be retroactively uncommitted by a later timer.

## Commit once and recover without execution

States are computing, draining, sealed, committed, or interrupted. The producer
offer ends domain computation: later replies can only supply the expected frozen
fragment. Reject effects, questions, new offers, changed hashes, offsets, byte
counts or premature/late EOF. Never retry a timed-out producer callback.

Session appends bound source-begin/chunk/seal records. Each chunk commits its
offset, digest and exact bytes. Identical internal repeats are idempotent;
conflicting repeats refuse. Verify contiguous progress, exact byte/page counts,
full digest, aggregate limits and schema, then sync the seal. A seal alone grants
no public access. Close the worker through the ordinary confirmed path before
Session syncs the new versioned invocation result. That final result is the only
publication commit and retains the ordered host-action chain commitment.

The wire and receipt shapes are closed and versioned:

| Record | Fields and authority |
| --- | --- |
| Worker offer | `api_version: 1`, `kind: "result_producer"`, `output: {version: 1, byte_count, sha256}`; the declared logical schema comes from the admitted export, not the offer |
| Host page request, stage `result.output` | `api_version: 1`, `invocation_id`, host-derived `output_id`, `offset`, `limit: 4096` |
| Worker fragment | `api_version: 1`, `kind: "result_chunk"`, `output: {version: 1, output_id, offset, next, complete, data_base64, sha256}`; the digest covers decoded fragment bytes |
| `extension_output_begin` | Version 1, invocation/output IDs, original intent digest, declared-schema digest, total byte count, complete byte digest and elapsed sample |
| `extension_output_chunk` | Version 1, invocation/output IDs, offset/next, decoded byte count, fragment digest and base64 data |
| `extension_output_seal` | Version 1, invocation/output IDs, exact byte/chunk counts, complete digest, ordered chunk-chain digest and elapsed sample |
| Final saved delivery | Explicit version-2 `extension_invocation_result`, original intent/action binding, elapsed sample and small `saved.result` descriptor; descriptor JSON is the bounded display text, not the domain value |

Derive `output_id` from the original admitted intent digest, byte count and complete
digest. One offer is permitted per invocation. Public reference fields are
version 1, kind `saved.result`, output ID, byte count, full digest and
`historical_receipt: true`. Source records carry the remaining original binding;
the reference never supplies replacement identity. A standalone syntax check of
a version-2 result is insufficient: the pure projection/restore validator must
also validate its complete source closure and action chain before accepting or
repairing the journal. Keep version-one inline validation unchanged.

`restore_context`'s pre-repair validation consumes every new record type through
the pure source state machine. Validate legal interrupted prefixes too: one begin
per invocation, contiguous unique offsets, chunk/page counts, hashes, aggregate
shape/schema and original identity. Only a valid final result makes the source
public. Missing/foreign source closure or tampered committed records blocks
startup before tail repair. Source records never become automatic model messages
or ordinary history-content rows. Derive the read index and quota charges from
validated records, including unreadable orphan prefixes.

Unsealed prefixes validate record syntax, admitted identity, resource bounds,
offsets and hashes, without requiring a valid logical document. A producer can
supply every declared byte and then fail JSON/schema validation; its complete but
unsealed prefix remains unreadable diagnostic evidence. This legal failure must
not prevent Session recovery. A seal always requires complete aggregate and
declared-schema validation, and an invalid sealed or committed document blocks
recovery. Test malformed and schema-invalid complete prefixes both before and
after adding a seal.

## Enumerate every readable child

Use `output_id` consistently in descriptors, APIs and cursors. The bounded view
cursor is `{output_id, source_sha256, path, kind, offset}`; it grants no authority.
Resolve it against Session's committed source index and current disclosure set on
every call. A changed digest, invalid path/kind, noncanonical offset or foreign/
undisclosed source refuses. A caller may start another authorized path explicitly;
that is a new read, not permission conveyed by a cursor.

Object children use stable decoded-key byte order; arrays retain their original
order. A cursor carries canonical positional path segments so a large/escaped
key cannot make its cursor exceed the SDK limit. Initial human-facing paths may
use keys or array indices. Enumerate at most 16 children per call, reducing that
count to fit the complete 12,000-byte/SDK response. Each child has its ordinal,
type, bounded name and explicit value/name reference when not inline. Oversized
object names remain reachable by ordinal and UTF8 key-name windows. Strings use
at most 1,024 raw UTF8 bytes per view, backing up to a code-point boundary and
requiring progress. Scalars/subtrees inline only when the whole wrapper passes
all SDK bounds; otherwise return explicit references.

Each response reports target kind, total children/bytes, current offset, next
cursor or null, and `complete` for that requested target. Reaching the last child
or byte ends the cursor exactly; a subtree reference is not an omitted value.
Raw deterministic materialization separately verifies every fragment and the full
document before returning a value. Test all 4,096 children, 8-KiB strings and
oversized names, including cursor tampering and command/model isolation.

Cancellation revokes the job lease before further appends or final publication
and closes owned worker/native resources. Interrupted computation/effects remain
unknown. A sealed orphan remains unreadable and consumes quota. Restore validates
all source records and final linkage before any repair; a complete committed
source can be read without starting a worker. Corrupt sources fail integrity
checks. Notification loss after final sync does not undo a committed result.

## Implementation ownership and proof gates

One internal host `ResultSource` module owns source format, integrity, authority,
bounded reads and assembly. One portable SDK helper owns worker freezing and
fragment replies. Host adds a terminal drain branch; Session owns appends/read
leases and derived indices. Catalog/Invocation/Projection add an explicit saved
delivery variant. CLI/tools/evaluation consume the public reader. No host module
loads Evidence, Store, Corpus, Graph or Research. No new dependency is required.

Before changing knowledge finish paths, prove the generic contract with a
synthetic producer: exact output including a citation larger than a page and
Graph bases absent from ranked evidence; aggregate/shape/schema refusal; tamper,
offset/hash/count/EOF and foreign-identity rejection; owner loss/cancellation at
each commit boundary; confirmed native shutdown; no public orphan; restored
historical reads with no worker/model; command/model disclosure separation; and
source/installed parity. Exercise operator journal limits and original deadlines.

A preliminary throughput prototype uses the **existing** Worker and an owner
process forwarding to Journal.Writer, not the proposed publication API. On local
macOS it drained exactly 4,194,304 bytes in 1,024 pages, wrote 5,806,670 journal
bytes and confirmed worker close in 1,785 ms. Largest SDK page was 5,635 bytes;
each callback retained its 5,000-ms bound and the outer clock was 120 seconds.
Exact byte hash was
`84354b6624fd58aa6f46e7574eeaf39294e6ff426fb00c53d7b15bc5927d11bb`.
This establishes local transport feasibility only. It does not prove the new
schema, authorization, publication, recovery, platform or installed contracts.
Repeat actual integrated near-cap checks once implemented.
