# Extension host calls and scoped state

Host calls let an explicit invocation or a source-bound
[event job](extension-event-jobs.md) request a finite, separately admitted
operation and continue from its committed receipt. Workers return an
outer `host_call`; ordinary `kind: result` fields remain data. Session owns
capability, approval, lifetime and journal admission. The owned task performs IO
outside Session, keeping cancellation and operator input responsive.

This guide owns the common continuation protocol and scoped state contract.
Questions, tools, model calls, services, history, accounting and context use the same action
chain; their linked guides own operation-specific schemas and failure behavior.
P22's foundation is complete within its documented coverage. Production knowledge
algorithms remain separate work; P23's accounted model capability has its own
verification gates.

## Negotiation and protocol

Artifacts declare `host.actions` and the operation capabilities they need,
alongside their `invoke.*` or `event.job` exports:

| Capability | Operation family | Contract |
| --- | --- | --- |
| `host.state.read`, `host.state.write` | Scoped get/list and put/delete | State requests below |
| `host.state.scan` | Bounded value pages and extended finite state-read allowance; requires `host.state.read` | State requests below |
| `host.state.bound` | Require an operator-approved logical storage binding at activation; requires `host.state.read`, grants no operation itself | Scope and recovery below |
| `host.question` | Explicit structured clarification | [Questions](extension-questions.md) |
| `host.tools` | Existing bounded file/shell tools | [Workflow tools](extension-tool-actions.md) |
| `host.model` | Approved one-shot profile-bound inference and canonical usage | [Accounted model calls](extension-model-calls.md) |
| `host.services` | Operator-bound typed value calls | [Services](extension-services.md) |
| `host.context` | Caller-scoped contextual evidence | [Context](extension-context.md) |
| `host.history`, `host.history.*` | Bounded own-session recorded views with separate private grants | [History/catch-up](extension-history.md) |
| `host.usage`, optional `host.usage.scan`/`host.usage.children` | Own-session pages, extended read allowance and separately granted registered-child accounting | [Accounting reads](usage-accounting.md#extension-accounting-reads) |

An operation capability without `host.actions` refuses inert validation.
Operator trust must allow every capability; project configuration cannot grant
it. Transform callbacks do not implement continuations.

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
another proposal or its final value. Ordinarily at most 16 host calls fit an invocation,
with existing five-second initialization/callback deadlines and bounded native
lock acquisition. No callback runs while approval is pending. Approval wait is
operator-controlled; interruption never automatically resumes code. No Session
PID, provider/credential configuration or storage path crosses the SDK.

Explicit `host.usage.scan` selection permits only accounting reads beyond step
16, up to 10,000 steps, with a two-minute boundary-admission deadline. It changes
neither other operation bounds nor their approvals. The accounting guide owns
that allowance; existing workers retain the original finite contract.

Explicit `host.state.scan` permits state.get/list/scan through step 512, with
the same two-minute boundary-admission deadline. It exposes values only in the
already admitted namespace and requires the ordinary read grant. Effects,
questions and unrelated operations still refuse beyond step 16; a long scan
cannot be followed by a late write. Combining scan grants does not extend either
family beyond its own limit. Worker callback deadlines and JSON limits remain.

Put/delete need separate full approval even if the command was explicitly
requested or the enclosing model tool approved. `--yes` supplies session-wide
execution policy; headless/interactive denial creates a known `denied` receipt
without business writes. Read/list need the read capability. Approval displays
instance, artifact digest, derived namespace and complete request. Expiry is
checked before intent and result admission; it does not undo an existing write.

An admitted state critical section has a private filesystem completion owner. It
keeps the native CAS lock through read, validation, temporary-file sync and rename,
including if its caller is cancelled. Cancellation does not roll back an admitted
write; a missing result remains unknown. Cleanup can time out while that owner
finishes, and the Session lock remains retained. This changes no grants or state
request fields.

## Closed state requests

Every request has `op` and `scope` (`operator`, `project`, `session`), plus exactly:

| Operation | Other required fields | Result |
| --- | --- | --- |
| `state.get` | `key` | Generation and record including value |
| `state.list` | `after` (key/null), `generation` (integer/null), `limit` (1–16) | Sorted metadata, generation, next key/null; no values |
| `state.scan` | Same closed pagination fields as list | Sorted full records including values; at most 16 records and 12,000 encoded array bytes per page |
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
current deletion revision is permitted. List/scan pages can pin generation;
concurrent writes make later pages conflict. A scan page may contain fewer than
its requested limit because of the byte ceiling; `next` is the last returned key
when more records remain. Every admissible value fits a page, so a nonterminal
page advances. A final null cursor means that this page exhausted the remaining
keys, not that the namespace cannot change later. Extensions implement domain
inspection/export, TTL and schema migration; core does not interpret stored notes
or automatically migrate/collect them.

## Scope, storage and recovery

Without an explicit binding, namespace SHA-256 retains the original version-1
descriptor: instance, artifact digest, configuration-source path hash, scope and
applicable canonical project path/session ID. Existing descriptors are unchanged.
Artifact or configuration-source changes therefore isolate legacy state.

An operator trust entry may bind an instance to a logical store using
`state_bindings: [{version: 1, instance: "notes", id: "reviewed-notes", scopes:
["project"]}]` (JSON keys are strings). Entries are closed, at most eight per
trust record, unique by instance; IDs are 1–64 characters using the state-key
alphabet. Nonempty distinct scopes form a ceiling, not additional capabilities.
The selected identity includes `state_binding` without `instance`. Its namespace
uses descriptor version 2, binding ID, scope and applicable project/session.
Thus reviewed artifacts, instance names and moved configurations can share the
same data only when the operator explicitly grants the same binding ID. Different
artifacts with that grant intentionally share authority over the store. A
`host.state.bound` artifact refuses activation without a valid binding.

Operator scope spans projects/sessions; project scope binds the working directory;
session scope also binds the durable session ID. A binding cannot cross those
dimensions or grant read/write operations. Project-configured instances cannot
receive bindings or override a bound operator instance, even with project trust.
Workers cannot supply a path, binding or namespace. Binding IDs belong to the
operator, not untrusted project text. The execution identity still pins exact
code/options/configuration/host version; sharing storage does not permit hot
upgrades or changed-session resume.

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
History reads use the owning session ID as their action namespace rather than a
state-store hash; their fixed range and private-view scope are independently
validated under the linked history contract. Their successful pages are cached
receipts, not an instruction to re-read on resume.

State is private data, not automatic model context. Delete removes the current
value, not historical journals or delivered text. Export/migration and collection
must be explicit: changing a binding does not move old data, and a stable binding
does not make arbitrary code/schema upgrades compatible. See
[operator procedures](../operator/extensions.md#scoped-state-host-calls) and
[verification](testing.md).
