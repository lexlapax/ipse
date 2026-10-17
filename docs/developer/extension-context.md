# Extension context and evidence

P22A12 adds the `host.context` capability to the existing
[finite host-action protocol](extension-host-calls.md). An explicit invocation or
[event job](extension-event-jobs.md) can publish bounded context for subsequent
model requests in its own session. Before-request jobs provide an awaited recall
seam; after-turn contributions become eligible only for a later request. This API does
not select a memory algorithm, retrieval provider, embedding model or database.
Selection, retrieval and scheduling policy remain explicit extension declarations. The existing prompt hook
continues to support attributed annotations independently.

## Publishing and clearing

Declare `host.context` with `host.actions` in the reviewed manifest and operator
trust ceiling. Return an outer `host_call` containing this closed request:

```json
{
  "op": "context.publish",
  "items": [{
    "id": "project-note",
    "version": "revision-1",
    "text": "The operator prefers small reviewed changes.",
    "priority": 10,
    "source": {"kind": "assertion", "uri": "fixture:preferences"}
  }]
}
```

`items` replaces only this activation instance's current contribution set.
An empty list clears that set. No instance can clear another instance's data.
The scope is the current session/workspace; it cannot be promoted to operator
state or implicitly inherited by a child or a fresh session. Persist records
separately through approved [state calls](extension-host-calls.md) if needed.
Publishing context grants no file, shell, state-write or provider permission.
It needs no mutation approval because it only contributes to already authorized
session context, like a tool result or prompt annotation.

Each set has at most eight unique lowercase ASCII IDs (32 characters). Versions
are nonempty strings of at most 128 UTF-8 bytes; text is nonempty and at most
2,048 bytes. Priority is an integer from 0 through 100. URI is null or a nonempty
string of at most 1,024 bytes; it is unverified metadata and is never fetched.
Unknown fields, malformed values and duplicate IDs are refused. The existing
16 KiB SDK object and 16-action invocation limits apply. The host validates the
complete continuation envelope, including provenance, before accepting a set.

All active sets together must render within 16 KiB. Exceeding the limit returns
`failed` with `{"reason":"context_refused"}`, preserving the previous sets.
The host does not truncate contributions, evict another instance or discard
mandatory instructions/history to make room. Priority orders accepted items;
it is not permission to displace other data. Order is descending priority,
then instance and local ID. The normal whole-request context/compaction limits
still apply and may safely refuse a request.

## Assertions and recorded evidence

An assertion remains explicitly unverified. Extensions cannot label it trusted
or verified. To bind an excerpt to an earlier successful host action in the same
invocation, use:

```json
{
  "kind": "receipt",
  "operation_id": "00000000000000000000000000000000",
  "path": ["result", "text"]
}
```

The illustrative ID must be replaced with the operation ID returned by the host.
Path selects a string within that action's outcome `value`. String segments
select object keys; integer segments from 0 through 255 select array positions.
There are at most eight segments, each string at most 128 bytes. An empty path
selects the value itself. The contributed text must be a literal substring of
the selected string. Failed, unknown, missing, ambiguous or other-invocation
receipts are refused. A value-service result normally uses `["result","text"]`;
a file read uses `["text"]`. This performs no new retrieval or callback.

The host adds provenance to each admitted item: instance, full activation identity
digest, publishing operation ID and the complete source-action receipt digest
(null for assertions). Prior receipts already bind their source and service
target identity. Resume recomputes this chain, not merely its outer hash. This
verifies recorded text provenance, not semantic truth, freshness or whole-source
completeness. Source URLs and extension-supplied version labels remain assertions.
This complements P14's MCP research ledger without pretending a new contribution
was captured through an MCP call.

## Admission and recovery

An `ok` continuation contains `items` with host provenance and `snapshot_sha256`
for the complete resulting session contribution map. Intent precedes execution;
the result is synced before installing that map or continuing the callback.
Each subsequent main-model request syncs an `extension_context_snapshot` after
request admission and before provider dispatch. It pins request ID, map digest,
exact rendered content and content digest. Summary requests do not receive this
additional context. The main system message appends JSON-encoded data after
mandatory host instructions and explicitly identifies assertions/provenance limits.
Original messages, native continuations and mandatory instruction snapshots are
not edited. Compaction accounts for the additional system bytes.

Idle resume restores cached sets/snapshots without initializing an extension,
retrieving again or silently refreshing a record. Missing/altered snapshots for
completed requests and inconsistent source proofs refuse before partial-tail
repair. An admission interrupted before its snapshot remains unknown and is not
dispatched on restore. Cancellation does not undo an already committed context
action; the unfinished callback is never replayed. Later publishing/clearing is
explicit. Clearing or forgetting current records cannot erase old journals or
text already delivered to a provider. Cached data has no implicit freshness/TTL
claim; extensions must deliberately replace it when their policy requires.

`Session.diagnostics/1` exposes only item count, rendered bytes and digest under
`extension_context`; private text stays out of this diagnostic summary. Full
contributions/receipts are private session journal data. Disabling an extension
requires a fresh session or the existing frozen-runtime/reviewed-handoff path
for pinned sessions; a callback/config change cannot rewrite saved context.

No dependency is added. JSON validation and native journal/ownership mechanisms
are reused; bounded map/list path access uses ordinary Elixir data operations.
See [operator procedure](../operator/extensions.md#context-and-evidence),
[service composition](extension-services.md) and [actual checks](testing.md).
