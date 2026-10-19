> Historical reference only. Snapshot of `docs/developer/extension-services.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../developer/extension-services.md).

# Typed extension service composition

P22A11 adds explicit operator-bound value-service contract 1 to the
[host-call protocol](extension-host-calls.md). Requirements and routes are inert
data; discovery does not run registration callbacks. Calls use owned independent
workers and durable source-bound receipts. This initial contract composes typed
values. Nested interactive/effectful services need a separately negotiated future
contract; they cannot silently acquire permission through a value reply.

## Artifact requirements and operator routes

The optional manifest `requires` object is closed:

```json
{
  "version": 1,
  "services": [{
    "alias": "search",
    "contract": 1,
    "arguments_schema": {"type": "object"},
    "result_schema": {"type": "object"}
  }]
}
```

At most eight unique lowercase ASCII aliases (32 characters) are allowed. Schemas
reuse the existing bounded object subset; external references are refused. A
nonempty requirement set requires `host.actions` and `host.services`; declaring
`host.services` without requirements is invalid. Missing requirements normalize
to empty for older transform/tool artifacts. Executable `describe/0` must match
the reviewed manifest's normalized requirements as well as SDK/capabilities/exports.
The original manifest/SDK byte limits remain unchanged.

Each required alias needs one explicit operator trust binding. For a caller
artifact's existing `extension_trust` record, add:

```json
{
  "service_bindings": [{
    "caller": "client",
    "alias": "search",
    "target": "retrieval",
    "artifact": "TARGET_ARTIFACT_DIGEST",
    "service": "query"
  }]
}
```

This fragment must be merged with that record's artifact/capability/ceiling fields;
the digest placeholder is not runnable configuration. Caller artifact identity is
implicit in the containing trust record; `caller` selects an exact instance.
Target instance, artifact reference and local service ID must all match. At most
64 bindings fit one record, subject to the whole configuration's JSON limits.
Duplicate caller/alias pairs and unknown fields refuse validation. Project trust
cannot grant routes; generic project-config trust does not bypass this ceiling.

Both instances must already be explicitly selected. A binding neither installs
nor enables a target. Active requirements need exact argument/result schema
equality with the target's `invoke.service` export and contract 1. Missing/extra
routes for an active caller, unavailable code, schema mismatch or cycles refuse
activation before executable initialization. Routes for inactive callers stay
inert. Child subsets must also contain the required targets with explicit child
ceilings; missing dependencies refuse child startup.

Registry uses OTP `:digraph` in acyclic/private mode and `:digraph_utils` topological
ordering, deleting temporary tables afterward. Dependency identities are computed
first; each caller pins normalized requirement digest and sorted public routes
with the target's complete activation-identity digest. That transitively binds
code/options/runtime/host/scope/source/lease/child policy and downstream routes.
This is integrity/compatibility pinning, not a signature or authenticity proof.

## Owned value calls

A caller returns an outer `host_call` request with exactly:

```json
{
  "op": "service.call",
  "alias": "search",
  "arguments": {"text": "explicit query"},
  "checkpoint": {"next": "use_result"}
}
```

Arguments must match the bound schema and full wire envelope. Checkpoint is an
object of at most 8 KiB, returned only to the caller with its result. The request
uses the existing 16-operation invocation budget. Session checks the caller,
route, target and both live leases, then syncs action intent before startup.
The receipt's `service` field contains exact target identity/descriptor; ordinary
state/question/tool receipts use null. No Session PID, credentials or provider
configuration crosses the worker boundary.

The target receives `invoke.service`, with standard IDs/id/arguments plus
`service_contract: 1` and `parent_invocation_id`. Its invocation ID is the unique
host operation ID. Initialization/callback deadlines and cleanup reuse Worker.
Only a schema-checked `kind: result` object is accepted. Returned host calls,
questions, effects and nested service proposals refuse this value contract and
stop with unknown outcome; core does not execute them. A standalone embedded
service invocation still uses its original explicit invocation capabilities.

After confirmed worker cleanup, the host returns `status: ok` with:

```json
{
  "result": {"text": "typed service value"},
  "service": {
    "instance": "retrieval",
    "name": "ext__retrieval__query",
    "artifact_sha256": "TARGET_ARTIFACT_DIGEST",
    "operation_id": "00000000000000000000000000000000"
  }
}
```

IDs/digests above are illustrative. The result and receipt must fit the full SDK
envelope. Core constructs this provenance; target domain fields are untrusted
data, not automatically verified research evidence. A root workflow may compose
multiple value services with explicit state/questions/tool operations between
them. Value calls do not implicitly run a model, select a provider or grant
mutation permission. Trusted executable code retains its documented OS access;
return-value validation is not an OS sandbox or proof of arbitrary code purity.

## Recovery and future contracts

Mandatory intent/result records bind alias/arguments, full target identity/schema,
receipt and final invocation chain. The pure restorer validates target identity
against pinned metadata/catalog and refuses altered, missing or replayed receipts
before tail repair. Idle resume restores cached values without initializing either
artifact. Cancellation/owner death kills the owned service VM; interrupted calls
stay unknown and are never retried automatically. Target expiry before result
admission refuses commit even if the callback ran.

Unknown contracts/capabilities fail explicitly. A future interactive/effectful
contract must reuse these aliases, operator grants, identities, bounded checkpoints
and receipts while defining nested approval/pause/cancellation and no-replay
semantics. It cannot reinterpret value data as actions. No remote registry,
downloader, background service daemon or mandatory workflow framework is added.

No dependency is added: OTP graph utilities, JSONSchex/Jason and the existing
owned Worker are reused. See [operator configuration](../operator/extensions.md#service-composition),
[artifact contract](extension-artifacts.md) and [actual verification](testing.md).
