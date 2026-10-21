# Compose values and publish evidence

Use a typed value service when one selected extension needs another extension's
result. Use context publication when the caller wants that result to contribute
reference text to a later main-model request. These are separate operations.
A service receipt gives recorded provenance; it does not automatically publish
context or prove that the returned claim is true.

Work through the lab's lookup and memory pair after
[extension state](extension-state.md). Read `examples/extension-lab/spec.exs`,
`src/lookup.ex` and the recall branch in `src/memory.ex` together. Lookup returns
a synthetic corpus string. Memory calls its selected lookup route, then publishes
a literal excerpt with the host-issued receipt. You need a built checkout and
Elixir toolchain; the lab needs no account or model service.

## Declare the value contract

The caller's optional manifest `requires` field describes its dependency:

```json
{"version":1,"services":[{"alias":"search","contract":1,"arguments_schema":{"type":"object"},"result_schema":{"type":"object"}}]}
```

There are at most eight unique lowercase ASCII aliases, each up to 32 characters.
Both schemas use the bounded object-schema subset. Nonempty requirements need
`host.actions` and `host.services` in the artifact and operator ceiling.
`host.services` without requirements is invalid. Missing requirements normalize
to empty for artifacts that use no services. Executable `describe/0` must match
normalized requirements, exports and capabilities exactly.

The operator adds a route to the caller artifact's trust record:

```json
{"service_bindings":[{"caller":"client","alias":"search","target":"retrieval","artifact":"TARGET_ARTIFACT_DIGEST","service":"query"}]}
```

This is a fragment; the containing record still needs its normal artifact and
capability fields. Replace the placeholder with the actual target reference.
The caller instance, target instance, artifact and local service must match
already selected extensions. A route does not install or enable its target.
Project trust cannot grant routes. There are at most 64 unique caller/alias
bindings per trust record, with no unknown fields.

During activation, the requirement's argument/result schemas must equal the
target's `invoke.service` schemas and contract must be 1. Missing or extra active
routes, unavailable targets, schema mismatches and cycles refuse before worker
initialization. Inactive caller routes remain inert. Child subsets need required
targets and their separate child ceilings.

Follow `Ipse.Extensions.Services` into `Registry`. Private acyclic OTP graph
utilities order identity construction. Each caller pins requirements and sorted
routes, including each target's complete activation-identity digest. Code,
options, scope, lease, runtime and downstream routes become transitively bound.
The hashes establish compatibility consistency, not publisher authenticity.

## Call the selected target

Return an outer SDK `host_call` whose request is:

```json
{"op":"service.call","alias":"search","arguments":{"text":"explicit query"},"checkpoint":{"next":"use_result"}}
```

Arguments must fit the declared schema and whole SDK envelope. Checkpoint is an
object of at most 8 KiB, returned only to the caller. A service is an other call
under the invocation budget, so extended read permission adds no service calls.
Session checks the caller, route, target and both leases, then syncs intent
before target startup. The action receipt's `service` field pins the exact target
identity and descriptor; unrelated operations use null.

Host opens a separate owned worker. The target receives `invoke.service` with
the standard invocation/session/turn/local-ID/arguments fields, plus
`service_contract:1` and `parent_invocation_id`. Its invocation ID is the host
operation ID. Initialization and callback retain their five-second bounds.

The target can return only a schema-valid `kind:result` value. A host call,
question, nested service or effect in that reply fails the value contract and is
never executed. After normal target cleanup, the caller receives an `ok` action
with this value shape:

```json
{"result":{"text":"typed service value"},"service":{"instance":"retrieval","name":"ext__retrieval__query","artifact_sha256":"TARGET_ARTIFACT_DIGEST","operation_id":"00000000000000000000000000000000"}}
```

The host constructs provenance; domain result fields remain untrusted. The whole
value must fit its continuation envelope. A root caller may then compose more
services, state, questions or tools under their own grants. A directly invoked
standalone service follows its own invocation capabilities; the routed value
contract deliberately permits only values.

Intent/result records bind alias, arguments, target identity/schema, receipt and
final invocation chain. Restore checks them against pinned metadata before tail
repair. Idle resume starts neither worker. Cancellation or owner death stops the
owned target VM. An interrupted call stays unknown and is never retried. Target
expiry before result admission refuses the commit even if its callback ran.

Trusted workers still have ordinary OS permissions. Validating a value is not
proof that arbitrary worker code performed no effects. An interactive or
effectful nested-service API needs its own versioned pause, approval,
cancellation and unknown-outcome contract.

## Publish a bounded reference set

Declare `host.actions` and `host.context` in both artifact and operator ceiling.
Return an outer `host_call` with this request:

```json
{"op":"context.publish","items":[{"id":"project-note","version":"revision-1","text":"Use small reviewed changes.","priority":10,"source":{"kind":"assertion","uri":"fixture:preferences"}}]}
```

Publication replaces only this instance's current set. Empty `items` clears that
set; an instance cannot clear another's contribution. Sets belong to the current
session/workspace, with no implicit child or fresh-session inheritance. Durable
domain data needs separately approved state writes.

Publication needs no mutation approval because it contributes reference data to
already authorized session context, like a tool result. It grants no filesystem,
state-write, network or provider authority.

| Field or set | Limit |
| --- | --- |
| Items | At most eight unique lowercase ASCII IDs, each up to 32 characters |
| Version | Nonempty UTF-8, up to 128 bytes |
| Text | Nonempty UTF-8, up to 2048 bytes per item |
| Priority | Integer 0..100 |
| Assertion URI | Null or nonempty string up to 1024 bytes; never fetched by host |
| All active sets rendered together | 16 KiB |

Unknown fields, duplicates, malformed values and oversized SDK continuation
envelopes refuse. Ordinary SDK bounds and other-call budgets still apply. Rendered
overflow returns known `failed` with `context_refused`, preserving prior sets
atomically. The host never truncates, evicts another instance or discards required
instructions. Accepted items sort by descending priority, then instance and ID.
Priority orders reference data; it does not bypass whole-request context limits.

## Attribute a literal excerpt to a receipt

An assertion is explicitly unverified. To cite an earlier successful host action
in this invocation, replace its `source` with:

```json
{"kind":"receipt","operation_id":"00000000000000000000000000000000","path":["result","text"]}
```

Use the actual operation ID. The path selects a string inside that action's
outcome `value`. String segments address object keys and integers 0..255 address
arrays. There are at most eight segments, with strings up to 128 bytes. Empty
path selects the value itself. Published text must be a literal substring of the
selected string. Service text commonly uses `["result","text"]`; a file read
uses `["text"]`.

Missing, failed, unknown, ambiguous and other-invocation receipts refuse. This
check performs no retrieval. A URL or asserted source name cannot replace a
receipt. Host provenance adds the instance, complete activation-identity digest,
publishing operation ID and source-action receipt digest. Assertions have a null
source-receipt digest. Restore recomputes the original service/state proof chain.
It proves recorded text provenance, not truth, freshness or completeness. Version
labels and URLs remain extension assertions.

## Freeze context for each model request

The `ok` continuation contains admitted items with provenance and a
`snapshot_sha256` for the complete resulting contribution map. Session syncs
the result before installing the map or continuing the worker.

For each main-model request, Session commits `extension_context_snapshot` after
request admission and before dispatch. It binds request ID, map digest, exact
rendered content and content digest. A labelled user-role reference message
carries JSON data and provenance limits. Core rules remain in the system
message. Reference text is neither a new operator request nor permission.
Summary requests do not receive this additional reference context.

Compaction counts system and reference bytes while preserving original messages,
native continuations and required workspace snapshots. Before-request jobs may
publish for the current request; after-turn publications can affect only a later
request. Historical interpretation uses the saved request snapshot, not the
extension's current set.

Idle resume restores sets and snapshots without workers or retrieval. Missing or
changed completed-request snapshots and inconsistent proof chains refuse before
tail repair. Interrupted admission stays unknown. Cancellation cannot undo a
committed publication; clearing later is explicit. Forgetting or clearing current
data cannot erase historical journals or earlier provider transfers.

`Session.diagnostics/1` exposes only item count, rendered bytes and digest under
`extension_context`. Full text and receipts remain private journal data. There
is no implicit TTL/freshness guarantee. Disabling or upgrading an instance still
obeys exact execution-identity rules.

## Exercise dependency and provenance failures

In a scratch lab configuration, change one required schema field and require
activation refusal before worker startup. Follow the required-recall crash case:
an unknown required lookup must prevent inference. Then add one character to a
published excerpt that is absent from its source. Publication must refuse and
retain the previous set.

```sh
mix test test/extensions_services_test.exs test/extensions_registry_test.exs
mix test test/extensions_contributions_test.exs test/extensions_event_job_test.exs
```

The checks cover route/schema equality, cycles, leases, owned cleanup, receipt
paths, atomic replacement, frozen snapshots and recovery. Add `context_contains`
and action-status assertions to a [conformance fixture](extensions.md). Use the
[testing manual](testing.md) to run the lab against an unchanged installed
package and confirm target modules stay outside the host VM.
