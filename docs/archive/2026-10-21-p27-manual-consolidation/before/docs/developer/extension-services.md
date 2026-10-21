Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../../developer/extension-composition.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Compose extensions with typed value services

Use a value service when one extension needs a typed result from another selected
extension. The caller declares an alias and schemas; the operator binds that alias
to an exact target artifact and service. Host opens a separate owned target worker
and returns a recorded result. No discovery callback selects dependencies or
silently starts another package.

The lab's memory/lookup pair is a complete example. Read
`examples/extension-lab/spec.exs`, `src/lookup.ex`, and the recall branch in
`src/memory.ex` together. Lookup returns a synthetic corpus string. Memory uses the
host receipt to publish an attributable excerpt for the next model request.

## Artifact requirements and operator routes

The caller's optional manifest `requires` field is a closed version-1 object:

```json
{
  "version": 1,
  "services": [{
    "alias": "search", "contract": 1,
    "arguments_schema": {"type": "object"},
    "result_schema": {"type": "object"}
  }]
}
```

There are at most eight unique lowercase ASCII aliases, each at most 32
characters. Argument and result schemas use the bounded object-schema subset.
Nonempty requirements need `host.actions` and `host.services`; the service
capability without requirements is invalid. Executable `describe/0` must match
normalized requirements, exports, and capabilities exactly. Missing requirements
normalize to empty for artifacts that use no services.

Add a route to the caller artifact's operator `extension_trust` record:

```json
{
  "service_bindings": [{
    "caller": "client", "alias": "search", "target": "retrieval",
    "artifact": "TARGET_ARTIFACT_DIGEST", "service": "query"
  }]
}
```

This fragment needs the containing record's normal artifact/capability fields.
Replace the digest placeholder with the actual target reference. `caller` selects
the exact caller instance. `target`, `artifact`, and local `service` must all match
an already selected target. A route does not install or enable it. There are at
most 64 bindings per trust record, with unique caller/alias pairs and no unknown
fields. Project trust cannot grant routes.

Active schemas must equal the target's `invoke.service` argument/result schemas
and contract must be 1. Missing or extra active routes, unavailable targets,
schema mismatch, and cycles refuse activation before initialization. Inactive
caller routes stay inert. Child subsets must contain the required targets with
separate child ceilings.

`Services` and `Registry` use private acyclic OTP graph utilities to order identity
construction. Each caller pins its requirements and sorted routes including the
target's complete activation-identity digest. Code, options, scope, lease, runtime,
and downstream routes are therefore transitively bound. These hashes establish
compatibility consistency, not publisher authenticity.

## Owned value calls

The caller returns an ordinary outer `host_call` with this request:

```json
{
  "op": "service.call", "alias": "search",
  "arguments": {"text": "explicit query"},
  "checkpoint": {"next": "use_result"}
}
```

Arguments must fit the bound schema and whole SDK envelope. Checkpoint is an
object up to 8 KiB, returned only to the caller. This call consumes the ordinary
16-action budget. Session checks caller, route, target, and both leases, then
syncs action intent before target startup. The receipt's `service` field pins
exact target identity and descriptor; unrelated operations use null.

The target receives `invoke.service` with standard invocation/session/turn/local
ID/arguments fields, plus `service_contract: 1` and `parent_invocation_id`.
Its invocation ID is the host operation ID. Worker initialization and callback
have the usual five-second bounds. The target can return only a schema-valid
`kind: result` value. Host calls, questions, nested services, or effects in that
reply fail this value contract; the host never executes them.

After normal target cleanup, the caller's `host.actions` outcome has status `ok`
and this value shape:

```json
{
  "result": {"text": "typed service value"},
  "service": {"instance": "retrieval", "name": "ext__retrieval__query",
    "artifact_sha256": "TARGET_ARTIFACT_DIGEST",
    "operation_id": "00000000000000000000000000000000"}
}
```

The host constructs provenance; domain result fields remain untrusted data.
This whole value must fit the continuation envelope. It is not automatically
research evidence or model context. The root caller may compose further services,
state, questions, and tools under their separate grants. A standalone explicit
service invocation still follows its own invocation capabilities; this routed
contract intentionally permits only target values.

## Recovery and future contracts

Intent/result records bind alias, arguments, target identity/schema, receipt, and
final invocation chain. Restore checks those bindings against pinned metadata
before tail repair. Idle resume restores cached results without starting either
worker. Cancellation or owner death stops the owned target VM. Interrupted calls
remain unknown and are never retried; target expiry before result admission
refuses the commit even if callback code ran.

This API supplies neither implicit inference nor file/network authority. Trusted
worker code retains ordinary OS permissions, so value validation is not proof
that arbitrary code is effect-free. An interactive or effectful nested-service
API would need an explicit versioned contract for pause, approval, cancellation,
and unknown outcomes rather than reinterpreting ordinary result data.

## Exercise a bad dependency

In a scratch lab configuration, compare the caller's required schema with lookup's
export. Change one schema field and confirm activation refuses before worker
startup. Then follow the required-recall crash case in the lab verifier: inference
must not start when its required lookup is unknown.

```sh
mix test test/extensions_services_test.exs test/extensions_registry_test.exs
```

The service fixtures check route/schema equality, cycles, pinned dependencies,
owned calls, cancellation, and saved receipt validation. Use the
[installed compatibility lab](extension-proof.md) to prove your packaged target
runs without loading its module into the host.
