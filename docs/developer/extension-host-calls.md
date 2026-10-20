# Continue an extension through host calls

A worker cannot reach into Session to read storage or run a tool. It returns a
closed `host_call` proposal. Session checks authority and commits intent, the
owned host task performs IO, and a committed receipt returns to the worker.
This chapter develops a read/compare/write sequence and explains the state
contract behind it.

## Negotiate the operation

An artifact declares `host.actions` alongside the capabilities for its operations
and an `invoke.*` or `event.job` entrypoint. Operator trust must permit the complete
set. Transform, notification, and feed replies do not enter this protocol.

| Capability | Operation family |
| --- | --- |
| `host.state.read` | `state.get`, `state.list` |
| `host.state.write` | `state.put`, `state.delete` |
| `host.state.scan` | Value-bearing pages and extended state reads; also requires `host.state.read` |
| `host.state.bound` | Requires an operator logical binding; also requires `host.state.read`, grants no operation itself |
| `host.question` | [Structured questions](extension-questions.md) |
| `host.tools` | [File and shell tools](extension-tool-actions.md) |
| `host.mcp`, `host.results` | [Operator-bound MCP calls and saved result windows](extension-mcp-actions.md) |
| `host.actions.mixed` | Separate read/action counters; requires every operation's own grant |
| `host.model` | [Profile-bound inference](extension-model-calls.md) |
| `host.services` | [Routed typed services](extension-services.md) |
| `host.context` | [Context publications](extension-context.md) |
| `host.history` and explicit private-view grants | [Own-session history](extension-history.md) |
| `host.usage`, optional `host.usage.scan` and `host.usage.children` | [Accounting reads](usage-accounting.md#teach-an-extension-to-read-facts) |

An operation capability without `host.actions` refuses inert validation. Project
configuration and callback output cannot expand the operator's ceiling.

## Read a revision before writing

The lab memory worker's `read/1` follows this shape:

```elixir
{:ok,
 %{"api_version" => 1, "kind" => "host_call",
   "request" => %{"op" => "state.get", "scope" => "project", "key" => "note"}},
 state}
```

After admission and a synced `extension_action_intent`, the task reads storage
outside Session. Session validates and syncs the result before calling the same
worker at `host.actions`. The payload contains `api_version`, `invocation_id`,
`operation_id`, sequential `step`, and `outcome`:

```json
{
  "api_version": 1,
  "invocation_id": "00000000000000000000000000000000",
  "operation_id": "11111111111111111111111111111111",
  "step": 1,
  "outcome": {"status": "ok", "value": {
    "generation": 0,
    "record": {"key": "note", "revision": 0, "deleted": true,
      "value": null, "operation_id": null}
  }}
}
```

The IDs illustrate host-issued values. Missing records use revision 0 and a null
value. To create the note, propose a put with the observed revision:

```json
{"op":"state.put","scope":"project","key":"note","expected_revision":0,"value":{"text":"Use small changes"}}
```

This is a request fragment inside the same outer `host_call` reply. The write
needs separate full approval, even if the enclosing command or model tool was
approved. Approval displays instance, artifact digest, derived namespace, and
complete request. `--yes` enables session-wide execution; denial produces a known
`denied` receipt without changing the record. No callback runs while approval waits.

On a successful receipt, finish with the export's schema-valid `kind: result`.
On conflict, inspect returned metadata and make a deliberate domain decision.
Do not reread and automatically overwrite a tombstone on behalf of stale work.

## Closed state requests

Every request has `op`, `scope`, and exactly the operation's fields. A `state.put`
may also contain `expected_generation`, `write_before_ms`, or both. Scope is
`operator`, `project`, or `session`.

| Operation | Required fields | Successful value |
| --- | --- | --- |
| `state.get` | `key` | Namespace generation and full record |
| `state.list` | `after`, `generation`, `limit` | Sorted record metadata and `next`, without values |
| `state.scan` | `after`, `generation`, `limit` | Sorted full records and `next` |
| `state.put` | `key`, `expected_revision`, object `value` | New generation and record |
| `state.delete` | `key`, `expected_revision` | New generation and retained tombstone |

`after` is a key or null, `generation` an integer or null, and `limit` 1–16.
Keys use 1–64 ASCII letters, digits, underscore, dot, or hyphen, starting with a
letter or digit. Values are plain objects up to 8 KiB encoded. SDK envelopes remain
16 KiB. Revisions and generations range from 0 through 2^53−1; exhaustion refuses
writes. Successful puts and deletes increment both record revision and namespace
generation. The record retains its last write's operation ID.

Compare-and-swap requires the exact revision. Conflict returns metadata without
revealing the current private value. Delete increments revision even for a missing
key, so an old captured revision cannot recreate it. An explicit write using the
current deletion revision is allowed. Domain suppression policy must distinguish
that deliberate write from a stale extraction result.

## Bind a write to a namespace snapshot

A per-record revision cannot protect a decision based on other records. For
example, two writers can read one remaining source slot and insert different
keys. Both target revisions are zero. Include the observed namespace generation
when the prepared put depends on the complete snapshot:

```elixir
request = %{
  "op" => "state.put", "scope" => "project", "key" => "new-source",
  "expected_revision" => 0, "expected_generation" => snapshot_generation,
  "value" => new_source
}
```

State compares the target revision and then the namespace generation under its
existing file lock. Either mismatch returns `conflict`, with the current
generation and value-free target summary. A different key's write can cause this
conflict. The host does not rescan or retry. The extension owns the domain policy
that made the snapshot relevant; State treats the value as opaque JSON.

The optional condition is a non-null integer from 0 through 2^53-1. Other
operations reject it. Omitting it preserves ordinary per-record CAS. A successful
conditioned put must report generation `expected_generation + 1`; a conflict must
prove a revision or generation mismatch. Conditioned conflict summaries cannot
name this action as their previous writer. These rules validate both live and
saved receipts. The persisted state format and operation grants do not change.

Exercise the serialized distinct-key test in `test/extensions_state_test.exs`.
Both reads observe generation zero. The first put succeeds; the second conflicts
even though its own key remains missing. The separate-process test exercises the
actual native lock, where a competing process may instead receive the existing
lock-contention refusal. Neither outcome authorizes replay.

## Bound a prepared write by time

If a prepared put must expire while it waits for approval, include
`write_before_ms` in the exact request:

```elixir
request = %{
  "op" => "state.put", "scope" => "project", "key" => "note",
  "expected_revision" => observed_revision, "value" => replacement,
  "write_before_ms" => observed_expiry_ms
}
```

The extension owns the deadline policy and derives these observed values from its
read. State treats `value` as opaque JSON. The optional deadline is an absolute
Unix millisecond integer from 0 through 2^53-1. Explicit null, nonintegers, extra
keys and this field on other operations refuse validation. Omitting it retains
ordinary put behavior. The condition grants no authority or additional calls.

Revision and optional generation conflicts take precedence over deadline failures. State samples its clock
under the existing namespace lock and again after syncing temporary output,
immediately before rename. At or after the deadline, the write returns a known
`failed` outcome without changing the stored value, revision, generation or last writer's
operation ID. Temporary output is cleaned. Lock contention still refuses; it does
not queue until a deadline passes. Other IO failures remain uncertain according
to the existing outcome rules.

The failed value has exactly `code: "write_deadline_elapsed"`, `checked_at_ms`,
`generation`, and the unchanged `record` summary without its value. The summary
must match the request key and expected revision. Its operation ID belongs to the
previous successful write. Receipt validation requires a deadline-bearing put and
a recorded checked time at or after its deadline. It compares recorded timestamps,
not the current clock, so idle recovery never reinterprets or retries the failure.
When `expected_generation` is present, this failed receipt must also retain that
exact generation: both CAS conditions matched before the deadline refusal.
Successful receipts keep their ordinary shape. Interrupted writes without a
durable receipt remain unknown.

The deadline's decision point is the final clock check under the lock before
publication. It is not a hard real-time promise about syscall completion or a
defense against wall-clock rollback. Never remove a refused deadline to retry
automatically. Start a deliberate domain operation after inspecting the outcome.

## Read a stable page

List and scan can pin a generation; concurrent writes then conflict on later pages.
Scan returns at most 16 records and 12,000 encoded array bytes. A byte-limited page
may return fewer records, with `next` set to the last returned key when more remain.
Every admitted value fits a page, so a nonterminal page advances. Null means the
remaining keys were exhausted at that read, not that the namespace is immutable.

## Scope, storage and recovery

Without a logical binding, namespace identity includes instance, artifact digest,
configuration-source path hash, scope, and the applicable canonical project path
or session ID. Changing artifacts or moving configuration therefore isolates that
legacy store.

An operator trust record can explicitly share reviewed state using:

```json
{"state_bindings":[{"version":1,"instance":"notes","id":"reviewed-notes","scopes":["project"]}]}
```

Merge this fragment into the relevant trust record. At most eight bindings are
allowed, unique by instance. IDs use the state-key alphabet; scopes are distinct
and nonempty. A selected identity pins the binding without its instance field.
Namespace descriptor version 2 uses binding ID, scope, and applicable project or
session, so different reviewed artifacts with the same grant intentionally share
authority. A `host.state.bound` artifact refuses activation without such a binding.

Bindings do not grant reads/writes, cross project/session boundaries, migrate
schemas, or relax execution identity. Project-configured instances cannot receive
bindings or override a bound operator instance. Workers supply neither paths nor
namespaces. Operator scope spans projects; project scope binds the working
directory; session scope also binds the durable session ID.

Storage is private `IPSE_HOME/extension-state-v1/NAMESPACE/state.json`, with at
most 256 records including tombstones and a 1 MiB file ceiling. Persistent-inode
advisory locks protect CAS; synced temporary writes and same-directory rename
publish updates. Corrupt, duplicate-key, oversized, symlinked, or permissive state
refuses access without repair. Orphan `.pending-*` files remain inert.

A filesystem completion owner retains the native lock through admitted read,
validation, sync, and rename even after caller cancellation. Cancellation cannot
undo that write. Cleanup may wait while the owner finishes, retaining the Session
lock; absence of a journal result leaves the effect unknown.

Action receipts bind invocation, operation, step, identity, namespace, request,
approval, and outcome digest. Final results bind the ordered action chain. Pure
recovery rejects orphaned, reordered, duplicated, altered, or unknown-continuing
chains before repair. Idle resume never executes a callback or operation. Inspect
revision and operation ID before explicit recovery of a possibly completed write.
Hashes check consistency, not publisher or same-user authenticity.

## Keep long reads finite

Ordinary invocations permit 16 host calls. Initialization/callback deadlines remain
five seconds. Explicit `host.state.scan` permits only get/list/scan through step
512, with a two-minute boundary-admission deadline. Effects and unrelated calls
still refuse after step 16, so a long scan cannot end in a late write.
`host.usage.scan` separately permits accounting reads through step 10,000 with the
same deadline. Combining grants does not extend either family's limit.

`host.results` separately extends same-invocation result reads through step 512.
Explicit `host.actions.mixed` replaces the cumulative-step allowance with at most
512 reads and 16 other calls, 528 total. This permits a long read followed by an
approved effect without widening legacy grants. See [MCP actions](extension-mcp-actions.md#separate-long-reads-from-action-authority)
for the closed read set and durable counter checks.

State is private data. It does not enter inference unless explicitly published.
Deletion removes the current value, not journal history or prior provider
transfers. Extensions own domain schema, TTL, export, and explicit migrations.

## Test a stale write

Read `State.execute/4`, `Operation`, and the action loop in `Host` together with
the state fixtures. Trace a read, a concurrent delete, and the stale put. The put
must conflict without resurrecting data. Then inspect the interrupted-write case
that leaves a journal intent and confirm resume performs no IO.

```sh
mix test test/extensions_state_test.exs test/extensions_state_scan_test.exs test/extensions_state_binding_test.exs test/extensions_invocation_test.exs
```

These tests cover CAS, tombstones, pagination, logical binding ceilings, approvals,
receipt validation, and no-replay recovery. Change storage or continuation logic
with both live behavior and pure saved-record checks in view.
