> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/developer/extension-state.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Continue state operations and operator questions

Build a read/compare/write sequence whose state and questions survive process
loss. A worker proposes a closed host call; Session validates authority and
records intent, owned host work performs IO, and a committed receipt returns to
the worker. Domain code never receives direct Session or storage handles.

Follow the lab memory worker in `examples/extension-lab/src/memory.ex` alongside
`Extensions.Operation`, `Actions`, `State` and the action loop in `Host`.
For other operation families use [typed effects](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-effects.md),
[composition](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-composition.md), [accounting](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/usage-accounting.md) or
[feeds/history](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-feeds.md).

## Negotiate before proposing an operation

An artifact needs `host.actions`, an `invoke.*` or `event.job` entrypoint, and
each operation's capability. Operator trust must allow the complete set.
Transforms, notifications and feed replies cannot enter this protocol.

| Capability | State or continuation contract |
| --- | --- |
| `host.state.read` | `state.get`, `state.list` |
| `host.state.write` | `state.put`, `state.delete` |
| `host.state.scan` | Value-bearing scans and extended reads; also needs read capability |
| `host.state.bound` | Requires an operator logical binding and read capability; grants no operation itself |
| `host.question` | Explicit structured operator question |
| `host.actions.mixed` | Separate read/action counters, without granting the operations themselves |

An operation capability without `host.actions` fails inert validation. Neither
project configuration nor callback data can expand operator authority.

## Read a revision and propose a write

The worker returns this callback reply to request one read:

```elixir
{:ok,
 %{"api_version" => 1, "kind" => "host_call",
   "request" => %{"op" => "state.get", "scope" => "project", "key" => "note"}},
 state}
```

Session commits `extension_action_intent` before storage IO. After validating
and committing the result, it calls the same worker at `host.actions` with
host-issued invocation/operation IDs, sequential step and outcome. For a missing
record, an illustrative payload is:

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

Create the record by returning another outer `host_call` reply containing this
request fragment:

```json
{"op":"state.put","scope":"project","key":"note","expected_revision":0,"value":{"text":"Use small changes"}}
```

The write needs separate approval even if the enclosing command/tool was
approved. Approval shows instance, artifact digest, derived namespace and the
complete request. No callback runs while it waits. `--yes` permits session-wide
execution; denial records a definite denied result without changing storage.
Finish with a schema-valid export result only after the receipt. On conflict,
make a deliberate domain decision; do not automatically reread and overwrite
a deletion on behalf of stale work.

## Preserve record and namespace compare-and-swap

State requests have `op`, scope and exactly their admitted fields. Scope is
`operator`, `project` or `session`:

| Operation | Required fields | Result |
| --- | --- | --- |
| `state.get` | `key` | Generation and full record |
| `state.list` | `after`, `generation`, `limit` | Sorted value-free record metadata and `next` |
| `state.scan` | `after`, `generation`, `limit` | Sorted full records and `next` |
| `state.put` | `key`, `expected_revision`, object `value` | New generation and record |
| `state.delete` | `key`, `expected_revision` | New generation and retained tombstone |

Keys contain 1..64 ASCII letters, digits, underscore, dot or hyphen, beginning
with a letter or digit. Values allow 8 KiB encoded; SDK envelopes still allow
16 KiB. Revisions/generations are integers from zero through 2^53−1. Successful
puts and deletes increment both counters and retain the operation ID of the
last successful write. Exhausted counters refuse writes.

CAS requires the exact record revision. A conflict exposes metadata, not the
current private value. Deleting even a missing key increments its revision, so
an older captured revision cannot recreate it. A deliberate new write using
the current tombstone revision remains possible. The extension owns suppression
policy distinguishing that decision from stale extraction.

If a put depends on other records, include `expected_generation`:

```elixir
request = %{
  "op" => "state.put", "scope" => "project", "key" => "new-source",
  "expected_revision" => 0, "expected_generation" => snapshot_generation,
  "value" => new_source
}
```

Two writers can otherwise observe the last available slot and insert different
missing keys with revision zero. State checks revision, then optional namespace
generation under the lock. Either mismatch conflicts with value-free target
metadata. It does not rescan or retry. The optional generation is non-null and
within the same integer range; other operations reject it. Success reports
`expected_generation + 1`; conditioned conflict proves a revision or generation
mismatch. A rejected action cannot claim to be the previous successful writer.

Run the serialized distinct-key fixture in `test/extensions_state_test.exs`:
the first put succeeds and the second conflicts while its own key stays missing.
The separate-process fixture additionally exercises native lock contention;
lock refusal is not permission to replay.

## Reject an expired prepared write

For an expiring decision, include absolute Unix milliseconds as `write_before_ms`:

```elixir
request = %{
  "op" => "state.put", "scope" => "project", "key" => "note",
  "expected_revision" => observed_revision, "value" => replacement,
  "write_before_ms" => observed_expiry_ms
}
```

The extension derives the deadline from its observed domain state. State treats
the value as opaque JSON. The condition accepts integers from zero through
2^53−1, not explicit null, and is valid only on puts. Omitting it retains ordinary
put behavior; it grants no extra operation or authority.

Revision/generation conflicts take precedence over expiry. State samples its
clock under the lock and again after syncing temporary output, immediately
before rename. At or after the deadline it returns a known failure, cleans the
temporary output and leaves stored value, revision, generation and last writer
unchanged. Lock contention still refuses. Other uncertain IO outcomes retain
their existing classification.

The failed value contains exactly `code: "write_deadline_elapsed"`,
`checked_at_ms`, `generation` and the unchanged value-free record summary.
Key/revision must match the request; a conditioned generation must also match.
The recorded checked time must meet the deadline. Recovery validates those
recorded timestamps, never today's clock. Success retains its ordinary shape;
an interrupted write without a receipt stays unknown. The final clock sample
is a decision boundary, not a real-time syscall-completion guarantee or a
defense against wall-clock rollback. Never remove a deadline for automatic retry.

## Page and bind storage deliberately

List/scan accept a key-or-null `after`, integer-or-null generation and limit
1..16. A pinned generation makes concurrent writes conflict on later pages.
Scans allow sixteen records and 12000 encoded array bytes. Byte-limited pages
may be shorter, with `next` at the last returned key if more remain. Every
admitted value fits, so nonterminal pages advance. Null `next` describes that
read's remaining range, not an immutable namespace.

Without a logical binding, namespace identity includes instance, artifact,
configuration-source path hash, scope and applicable canonical project/session.
Artifact or configuration moves therefore isolate the legacy store. Operator
trust may explicitly share reviewed state with this trust-record fragment:

```json
{"state_bindings":[{"version":1,"instance":"notes","id":"reviewed-notes","scopes":["project"]}]}
```

Bindings are unique by instance, at most eight, with state-key IDs and distinct
nonempty scopes. The selected identity pins the binding without its instance.
Namespace descriptor v2 uses binding ID, scope and applicable project/session,
intentionally sharing authority across reviewed artifacts. `host.state.bound`
refuses activation without a binding.

Bindings do not grant operations, cross scope boundaries, migrate schemas or
relax executable identity. Project instances cannot receive them or replace a
bound operator instance. Workers choose neither paths nor namespaces. Operator
scope spans projects; project scope binds the working directory; session scope
also binds its durable ID.

Storage is private `IPSE_HOME/extension-state-v1/NAMESPACE/state.json`, allowing
256 records including tombstones and a 1 MiB file. Persistent-inode native locks
protect CAS; synced temporary files and same-directory rename publish updates.
Corrupt, duplicate-key, oversized, symlinked or permissive storage refuses
without repair. Orphan `.pending-*` files are inert.

A put/delete exceeding record, file or revision quota fails before publication
with `code: "extension_state_quota"`, unchanged generation and value-free record
summary. Requested revision and any generation must still match; the summary
retains the previous writer. This is a definite refusal. Unconfirmed IO without
that guarantee remains unknown. A filesystem completion owner keeps the native
lock through admitted validation/sync/rename after caller cancellation. Cleanup
may wait for completion, retaining the Session lock; cancellation cannot undo it.

## Suspend with a durable question

The lab workflow requests clarification before its separately approved file write:

```elixir
{:ok,
 %{"api_version" => 1, "kind" => "host_call",
   "request" => %{
     "op" => "operator.question",
     "arguments" => %{"questions" => [
       %{"id" => "choice", "prompt" => "Which note should be written?",
         "kind" => "single", "recommended" => "first",
         "options" => [%{"id" => "first", "label" => "First note"},
                       %{"id" => "second", "label" => "Second note"}]}
     ]},
     "checkpoint" => %{"path" => "result.txt"}
   }},
 state}
```

Requests have exactly `op`, `arguments` and `checkpoint`. Arguments use the
[operator question schema](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/operator-questions.md): at most three questions,
single/multiple/text kinds, unique IDs and up to eight options. Recommendations
are not implicit answers. Checkpoints are JSON objects up to 8 KiB within the
proposal's SDK bounds. Persist enough domain data to continue after `init/1`
runs again; never serialize an Erlang heap.

Session checks availability, lease, schema, capability and remaining action
budget before syncing intent. Host confirms worker cleanup before Session saves
`extension_question` and emits `{:question, operation_id, arguments}`. No worker
waits for input. Unavailable headless/child questions stop without choosing.

`Session.answer/3` checks the current ID, complete answers, live identity and
checkpoint/answer envelope. Invalid, stale or oversized answers leave the
question and journal unchanged. A valid answer syncs an `answered` result and
unique continuation intent before a fresh worker can initialize and receive
`handle("host.actions", payload, state)`. That payload includes the saved
checkpoint. For example, extract the selected ID from
`payload["outcome"]["value"]["answers"]["choice"]` and construct the next request
using `payload["checkpoint"]["path"]`.

An answer authorizes continuation, not a write or provider transfer. The next
`tool.call` still needs approval, and previous action counts carry forward.
A native model-selected extension tool retains its real original call/result;
commands/services need no model inference to ask a question.

## Preserve finite work and unknown outcomes

Ordinary invocations allow sixteen host calls with five-second initialization/
callback bounds. `host.state.scan` extends only get/list/scan through step 512;
`host.usage.scan` separately extends accounting reads through step 10000;
`host.results` extends same-invocation result reads through step 512. Extended
reads have a two-minute boundary-admission deadline. Combining grants does not
extend another family's allowance or permit a late effect.

Explicit `host.actions.mixed` instead allows 512 reads and sixteen other calls,
528 total. Its read set is `state.get`, `state.list`, `state.scan`, `history.read`,
`usage.read`, `usage.children`, `usage.child.read` and `effect.result.read`.
Each still needs its own grant. This permits an approved effect after a long
read without changing legacy budgets. Operation-specific deadlines and output
limits still apply.

Receipts bind invocation, operation, step, identity, namespace, request, approval
and outcome digest. Final results bind the ordered chain. Pure restoration
rejects altered, orphaned, reordered, duplicated or unknown-continuing chains
before repair. Pending questions restore their checkpoint/parent/steps without
code execution; native-tool restoration removes only the corresponding generated
unknown placeholder. Event-job questions additionally retain their source-bound
schedule and remaining declaration plan.

Cancellation records a cancelled question result without an answer/continuation.
An already started native effect remains unknown. Owner loss preserves a pending
question; interruption after answer/continuation admission instead restores idle
with unknown work, without offering the answer or starting code again. Expiry
cannot be overridden by answering. Inspect operation IDs and stored revisions
before explicit recovery. Hashes establish consistency, not same-user authenticity.

State is private data until explicitly published. Deletion removes its current
value, not journal history or previous provider transfers. Domain schema, TTL,
export and deliberate migration belong to the extension.

## Exercise stale work and both sides of a pause

```sh
mix test test/extensions_state_test.exs test/extensions_state_scan_test.exs test/extensions_state_binding_test.exs
mix test test/extensions_invocation_test.exs test/extensions_event_job_test.exs
```

Trace a read, concurrent delete and stale put: it must conflict without restoring
the deleted value. Compare bytes around an idle pending-question resume, then
answer explicitly and find exactly one new continuation intent. Add a denied
write after the answer to prove clarification grants no mutation authority.
Use [conformance scenarios](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extensions.md#turn-the-hook-into-a-repeatable-scenario)
with explicit answers for your own workflow. An interrupted intent must never
produce IO merely because the journal reopened.
