Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../2026-10-22-before-structural-consolidation/docs/developer/extension-composition.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Publish context with recorded evidence

Use `context.publish` to contribute bounded reference text to later main-model
requests in the current session. The extension chooses and retrieves evidence;
the host validates its size, records provenance, and freezes the exact admitted
set for each request. Publication does not replace instructions or silently
refresh on resume.

Trace recall in `examples/extension-lab/src/memory.ex`: it reads state, calls its
bound lookup service, and publishes literal excerpts from those receipts. This
chapter shows why an assertion and a receipt-backed excerpt have different
provenance.

## Publishing and clearing

Declare `host.actions` and `host.context` in the artifact and operator ceiling.
Return an outer `host_call` with this closed request:

```json
{
  "op": "context.publish",
  "items": [{
    "id": "project-note", "version": "revision-1",
    "text": "Use small reviewed changes.", "priority": 10,
    "source": {"kind": "assertion", "uri": "fixture:preferences"}
  }]
}
```

This replaces only the caller instance's current set. Empty `items` clears that
set. No instance can clear another's contribution. The set belongs to the current
session/workspace, with no implicit child or fresh-session inheritance. Use
separately approved state calls for persistence.

Publication needs no mutation approval because it contributes to already
authorized session context, like a tool result. It grants no filesystem,
state-write, network, or provider authority.

A set has at most eight unique lowercase ASCII IDs up to 32 characters. Versions
are nonempty UTF-8 strings up to 128 bytes; nonempty text is at most 2,048 bytes.
Priority is 0–100. An assertion's URI is null or a nonempty string up to 1,024
bytes. The host never fetches that URI. Unknown fields, duplicate IDs, malformed
values, and oversized continuation envelopes refuse. SDK 16 KiB and ordinary
16-action limits still apply.

All active sets must render within 16 KiB. Overflow returns known `failed` with
`{"reason":"context_refused"}` and preserves previous sets atomically. The host
does not truncate, evict another instance, or discard mandatory instructions.
Accepted items sort by descending priority, then instance and local ID. Priority
orders reference material; it cannot displace core data or bypass whole-request
context/compaction limits.

## Assertions and recorded evidence

An assertion is explicitly unverified. To cite a prior successful host action in
the same invocation, replace its `source` with:

```json
{"kind":"receipt","operation_id":"00000000000000000000000000000000","path":["result","text"]}
```

Use the actual operation ID from the earlier receipt. `path` selects a string
inside that action's outcome `value`. String segments address object keys;
integers 0–255 address arrays. At most eight segments are allowed, with strings
up to 128 bytes. Empty path selects the value itself. Contributed text must be a
literal substring of the selected string.

A service's text commonly uses `["result","text"]`; a file read uses `["text"]`.
Failed, unknown, missing, ambiguous, or other-invocation receipts refuse. This
validation performs no new retrieval. Copying a URL or naming a source cannot
replace a valid receipt.

Host provenance adds instance, complete activation-identity digest, publishing
operation ID, and source-action receipt digest. Assertions have a null source
receipt digest. Resume recomputes the chain, including the original service or
state receipt. It establishes recorded text provenance, not semantic truth,
freshness, or completeness. Version labels and URLs remain extension assertions.

## Admission and recovery

The `ok` continuation contains admitted items with provenance and
`snapshot_sha256` for the complete resulting contribution map. Session syncs the
action result before installing that map or continuing the worker.

For each main-model request, Session commits `extension_context_snapshot` after
request admission and before dispatch. It pins request ID, map digest, exact
rendered content, and content digest. Summary requests do not get this additional
context. A labelled user-role reference message carries JSON-encoded data and its
provenance limits. Core rules stay in the system message. Reference text is
neither a new operator request nor permission.

Original messages, native continuations, and mandatory workspace snapshots remain
unchanged. Compaction counts system and reference bytes. Before-request jobs can
publish evidence for the current request; after-turn publication becomes eligible
only for a later request.

Idle resume restores cached sets and snapshots without initializing a worker or
retrieving again. Missing or altered completed-request snapshots and inconsistent
proof chains refuse before tail repair. Interrupted admission remains unknown
and is not dispatched on restore. Cancellation cannot undo an already committed
publication; clearing it later is explicit. Clearing or forgetting current data
cannot erase historical journals or prior provider transfers.

`Session.diagnostics/1` reports only item count, rendered bytes, and digest under
`extension_context`. Full text and receipts remain private journal data. There is
no implicit TTL or freshness guarantee. Exact execution identity still applies
when disabling or upgrading an instance.

## Exercise a provenance failure

Read `Contributions` and its tests alongside the lab recall continuation.
Locate a service receipt path, then predict what happens if the published excerpt
adds one character absent from the recorded source. It must refuse while retaining
the previous set. Next, inspect a saved main request and identify its exact
snapshot rather than reading the extension's current set as historical truth.

```sh
mix test test/extensions_contributions_test.exs test/extensions_event_job_test.exs
```

These checks cover set replacement, bounds, receipt paths, frozen request snapshots,
and recovery. For a user-visible scenario, add `context_contains` and action-status
assertions to a [conformance fixture](extension-conformance.md).
