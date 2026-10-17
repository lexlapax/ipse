# Extension host calls and scoped state

P22A8 implements finite host-mediated state operations from typed
[invocations](extension-invocations.md). Workers propose an explicit outer
`host_call` and receive a result through their negotiated `host.actions` callback.
Fields inside ordinary `kind: result` values remain inert. Initial operations
are get/list/put/delete. Tool execution, questions, context/evidence contributions
and composed services remain SDK work; this does not complete P22 or ship a
memory algorithm.

## Negotiation and protocol

Artifacts declare `host.actions` with `host.state.read` and/or `host.state.write`,
alongside their `invoke.*` exports. State capabilities without `host.actions`
refuse inert validation. Operator trust must allow every capability; project
configuration cannot grant it. Transform callbacks do not implement continuations.

An invocation may return this instead of its final schema-checked value:

```elixir
{:ok,
 %{"api_version" => 1, "kind" => "host_call",
   "request" => %{"op" => "state.get", "scope" => "project", "key" => "note"}},
 private_state}
```

The host validates the closed proposal, capability/scope/lease and approval,
then syncs `extension_action_intent` before storage IO. Only the owned task can
request/commit its operation. IO runs outside Session, which remains responsive
while awaiting approval. After syncing a validated result, the same worker
receives stage `host.actions`:

```json
{
  "api_version": 1,
  "invocation_id": "00000000000000000000000000000000",
  "operation_id": "11111111111111111111111111111111",
  "step": 1,
  "outcome": {"status": "ok", "value": {"generation": 0,
    "record": {"key": "note", "revision": 0, "deleted": true,
      "value": null, "operation_id": null}}}
}
```

IDs above are illustrative. The worker retains private state and may return
another proposal or its final value. At most 16 host calls fit an invocation,
with existing five-second initialization/callback deadlines and bounded native
lock acquisition. No callback runs while approval is pending. Approval wait is
operator-controlled; interruption never automatically resumes code. No Session
PID, provider/credential configuration or storage path crosses the SDK.

Put/delete need separate full approval even if the command was explicitly
requested or the enclosing model tool approved. `--yes` supplies session-wide
execution policy; headless/interactive denial creates a known `denied` receipt
without business writes. Read/list need the read capability. Approval displays
instance, artifact digest, derived namespace and complete request. Expiry is
checked before intent and result admission; it does not undo an existing write.

## Closed state requests

Every request has `op` and `scope` (`operator`, `project`, `session`), plus exactly:

| Operation | Other required fields | Result |
| --- | --- | --- |
| `state.get` | `key` | Generation and record including value |
| `state.list` | `after` (key/null), `generation` (integer/null), `limit` (1–16) | Sorted metadata, generation, next key/null; no values |
| `state.put` | `key`, `expected_revision`, `value` (object) | New generation and record |
| `state.delete` | `key`, `expected_revision` | New generation and retained tombstone |

Keys are 1–64 ASCII letters/digits/underscore/dot/hyphen, beginning with a letter
or digit. Values are plain JSON objects at most 8 KiB encoded, with nesting
reserved for the host envelope. SDK requests/responses remain at most 16 KiB.
Revisions/generations are integers 0 through 2^53−1; exhaustion refuses writes.
A missing key is revision 0, deleted, with null value/operation ID. Successful
put/delete increments its revision and the namespace generation. The record's
operation ID identifies its last write.

Writes require the exact observed revision; conflicts return metadata rather
than a private value. Delete retains its incremented revision, even for a missing
key, preventing stale writers from resurrecting it. An explicit write using the
current deletion revision is permitted. List pages can pin generation; concurrent
writes make later pages conflict. Extensions can implement explicit paginated
inspection/export through these reads. No whole-store export, TTL, compaction or
automatic migration is implemented.

## Scope, storage and recovery

The host derives namespace SHA-256 from protocol version, instance, artifact
digest, configuration-source path hash, scope and applicable canonical project
path/session ID. Operator scope spans projects/sessions for that exact identity;
project scope spans sessions of that working directory; session scope also binds
the durable session ID. Project-configured code cannot select operator scope.
Workers cannot supply a path/namespace or select another instance through this API.

State uses `IPSE_HOME/extension-state-v1/NAMESPACE/state.json`, private directories/
files, persistent-inode advisory locks, synced staging writes and same-directory
rename. Each namespace has at most 256 records including tombstones and a 1 MiB
file limit. Corrupt, duplicate-key, oversized, symlinked or permissive state refuses
access without repair. Orphan `.pending-*` files are inert; no collector removes
them. The explicit home/ancestors remain trusted. These checks do not constrain
arbitrary hostile same-user code or certify power-loss durability.

For this small store, JSON/OTP files were selected after evaluating
[DETS](https://www.erlang.org/doc/apps/stdlib/dets.html): it still needs concurrency
coordination and named tables, while this contract needs portable JSON, cross-VM
CAS and no automatic repair. Existing locks/Jason are reused. The larger decoder
limit is explicit for store reads; SDK/manifest limits remain unchanged. No database
dependency is added. [OTP file IO](https://www.erlang.org/doc/apps/kernel/file.html)
documents synchronous-write platform limits; no power-failure test ran.

Action receipts bind parent invocation, operation ID, sequential step, identity,
namespace, request/approval and outcome digest. Final invocation receipts bind
action count and the ordered result-chain digest. Recovery rejects deleted pairs,
orphan/duplicate/reordered results, altered values and continuation after unknown
outcomes. Conflict/denial are known; invalid storage, IO failure or interrupted
effects stop with an unknown outcome. Resume never executes an operation/callback,
including a write committed before its journal result. Inspect revision/operation
ID before explicit recovery. These hashes are integrity checks, not signatures.

State is private data, not automatic model context. Delete removes the current
value, not historical journals or delivered text. Artifact/config-source changes
select different namespaces; offline export/migration must be explicit. See
[operator procedures](../operator/extensions.md#scoped-state-host-calls) and
[verification](testing.md).
