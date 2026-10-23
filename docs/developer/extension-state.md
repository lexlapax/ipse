# Continue state work and publish bound evidence

Follow the lab's read/write, question, service, and context-publication sequence.
A callback proposes one closed host call; Session admits authority and commits
intent, owned work executes it, and only a committed receipt resumes the worker.
The domain receives no Session or storage handle. Read the
[lab worker](../../examples/extension-lab/src/memory.ex),
[Actions](../../lib/ipse/extension/actions.ex),
[State](../../lib/ipse/extension/state.ex), and
[Session.Invocation](../../lib/ipse/session/invocation.ex) together.

## Negotiate the operations before execution

Artifacts need `host.actions`, an admitted invocation/job entrypoint, and each
operation's capability. Operator trust must cover them. Transforms, notifications,
feeds, and read-only consumers cannot enter this continuation protocol.

| Capability | Allowed contract |
| --- | --- |
| `host.state.read` | Get/list |
| `host.state.write` | Separately approved put/delete |
| `host.state.scan` | Value scans and extended state reads, with read grant |
| `host.state.bound` | Require an operator logical binding; grants no operation |
| `host.question` | Explicit durable question |
| `host.services` | Operator-bound typed value service |
| `host.context` | Replace this instance's current reference set |
| `host.actions.mixed` | Separate read/other counters, without granting either family |

No project or callback can expand the ceiling. An operation grant without
`host.actions` refuses inert validation. [Effects](extension-effects.md) and
[accounting](accounting.md) own other operation families.

## Read a revision and propose a write

This callback fragment requests a project record:

```elixir
{:ok,
 %{"api_version" => 1, "kind" => "host_call",
   "request" => %{"op" => "state.get", "scope" => "project", "key" => "note"}},
 state}
```

Session syncs `extension_action_intent` before IO. The validated committed outcome
returns to `handle("host.actions", payload, state)` with host-generated invocation/
operation IDs, sequential step, and outcome. A missing key has revision zero,
deleted true, null value/writer, plus the observed namespace generation. Propose
creation using that exact observation, with this inner request fragment:

```json
{"op":"state.put","scope":"project","key":"note","expected_revision":0,"value":{"text":"Use small changes"}}
```

Its write needs full separate approval, showing instance/artifact, derived namespace,
and complete request. No callback executes during the wait. Denial records a
known denied result without storage change. `--yes` is the explicit broad allowance.
Return a schema-valid result after the receipt. On conflict, make a domain decision,
without silently rereading and overwriting a deletion on behalf of stale work.

## Keep record and namespace CAS distinct

| Operation | Fields beyond `op`/`scope` | Returned value |
| --- | --- | --- |
| `state.get` | `key` | Generation/full record |
| `state.list` | `after`, `generation`, `limit` | Sorted metadata, no values, plus `next` |
| `state.scan` | `after`, `generation`, `limit` | Sorted full records plus `next` |
| `state.put` | `key`, `expected_revision`, object `value` | New generation/record |
| `state.delete` | `key`, `expected_revision` | New generation/retained tombstone |

Scope is operator/project/session. Keys are 1..64 ASCII letters/digits/underscore/
dot/hyphen, starting with letter/digit. Encoded values allow 8 KiB inside 16-KiB
SDK envelopes. Revisions/generations range from zero through 2^53−1. Successful
writes increment both and retain their operation ID. Exhausted counters refuse.
Deleting a missing key still increments revision, blocking old revision-zero work.
A deliberate later write using the current tombstone is possible; stronger domain
suppression must be enforced by the extension.

For a decision depending on other keys, a put can add `expected_generation`:

```json
{"op":"state.put","scope":"project","key":"new-source","expected_revision":0,"expected_generation":12,"value":{"text":"approved source"}}
```

The numbers illustrate observed values, not values to guess. State checks revision
then optional namespace generation under one lock. Distinct-key writers that both
saw the final free slot cannot both publish against generation twelve. Conflicts
return value-free metadata and do not retry. The optional generation is a non-null
integer; other operations reject it. Conditioned success returns generation+1;
conflict proves a mismatch. Failed receipts cannot name their own operation as
the previous successful writer. See the same-process and separate-process fixtures
in `test/ipse/extension/state_test.exs`.

## Reject an expired prepared write

A put can also carry absolute Unix milliseconds `write_before_ms`:

```json
{"op":"state.put","scope":"project","key":"note","expected_revision":3,"write_before_ms":1700000001000,"value":{"text":"replacement"}}
```

Use a justified deadline from observed domain state. State treats the value as
opaque JSON; it reads no note-specific fields. Zero through 2^53−1 is accepted,
explicit null is not. Omitting the field preserves ordinary puts. Revision/generation
conflicts take precedence over expiry.

State samples its clock under the lock and after syncing staged output immediately
before rename. At/after deadline it removes that output and returns known
`write_deadline_elapsed`, leaving value/revision/generation/last writer unchanged.
The failed value contains exactly code, `checked_at_ms`, generation, and unchanged
value-free record summary. Request key/revision and any conditioned generation must
match; recorded checked time meets the deadline. Recovery validates recorded time,
not today's clock. Interrupted IO without a receipt remains unknown. This decision
boundary is neither a realtime syscall guarantee nor protection against wall-clock
rollback. Never drop the condition for an automatic retry.

## Page and bind storage deliberately

List/scan accept key-or-null `after`, integer-or-null generation, and limit 1..16.
Pinned generations detect writes between pages. Full scan arrays allow sixteen
records/12000 encoded bytes. Byte-limited pages can be shorter; nonterminal pages
advance with `next` at the last returned key. A null cursor ends that read's range,
without making the namespace immutable.

Legacy namespace identity binds instance, artifact, configuration-source path hash,
scope, and applicable canonical project/session. A reviewed operator trust fragment
can share state independently of exact code/source location:

```json
{"state_bindings":[{"version":1,"instance":"notes","id":"reviewed-notes","scopes":["project"]}]}
```

There are eight unique instance bindings, state-key-shaped IDs, and nonempty distinct
scopes. Activation pins the binding without its instance; namespace v2 uses binding
ID/scope/applicable project/session. This deliberately shares reviewed authority
across artifacts. `host.state.bound` requires the binding plus read grant.
Bindings grant no operations, migration, cross-scope access, or executable trust.
Project instances cannot receive them or replace a bound operator instance. Workers
choose no paths. Operator scope spans projects, project scope binds the workspace,
and session scope adds durable Session ID.

State lives privately under `IPSE_HOME/extension-state-v1/NAMESPACE/state.json`,
with 256 records including tombstones and a 1-MiB file. Native persistent-inode
locks protect CAS; synced temporary files and same-directory rename publish changes.
Corrupt/duplicate-key/oversized/symlinked/permissive storage refuses without repair.
Orphan pending files are inert. Capacity refusal is known `extension_state_quota`
with unchanged generation/value-free summary and previous writer, after matching
revision/generation. Unconfirmed IO remains unknown. A filesystem completion owner
retains the native lock through validation/sync/rename after caller cancellation;
Session quiescence can wait. Cancellation does not undo an admitted rename.

## Suspend without keeping a worker alive

A callback's inner request can ask a durable question:

```json
{"op":"operator.question","arguments":{"questions":[{"id":"choice","prompt":"Which note should be written?","kind":"single","recommended":"first","options":[{"id":"first","label":"First note"},{"id":"second","label":"Second note"}]}]},"checkpoint":{"path":"result.txt"}}
```

The exact fields are op/arguments/checkpoint. Arguments use the
[question contract](architecture.md#suspend-for-a-question); checkpoints are JSON
objects within 8 KiB and the enclosing SDK bound. Save enough data for fresh
initialization, not an Erlang heap. Availability/lease/schema/capability/action-budget
checks precede intent. Host confirms worker cleanup before Session commits the
question and emits it. No worker waits on terminal input. Headless/child requests
stop without inventing answers.

Session checks current ID, complete answers, live identity, and checkpoint/answer
size. Invalid/stale/oversized replies leave journal/wait unchanged. A valid reply
syncs answered result plus unique continuation intent before new initialization.
The continuation receives saved checkpoint and answers under
`outcome.value.answers`. It can construct the next request from those values.
Answering approves no file/model transfer, and prior operation counts carry forward.
Native model-selected tools keep their original call/result identities; commands
need no inference to ask questions.

## Declare the value contract for a service

The lab's memory caller uses a selected lookup worker. Its manifest requirements
include this fragment:

```json
{"version":1,"services":[{"alias":"search","contract":1,"arguments_schema":{"type":"object"},"result_schema":{"type":"object"}}]}
```

At most eight unique lowercase aliases permit 32 characters. Both schemas use the
bounded object subset. Nonempty requirements need `host.services`; that grant
without requirements refuses. Missing declarations normalize to empty. Executable
description must match normalized capabilities/exports/requirements.

The containing operator trust record supplies the route:

```json
{"service_bindings":[{"caller":"client","alias":"search","target":"retrieval","artifact":"TARGET_ARTIFACT_DIGEST","service":"query"}]}
```

Substitute the selected target's real reference. At most 64 unique caller/alias
bindings are allowed. Project trust grants none. The target must already be
imported/trusted/selected. Requirement schemas must equal service schemas and
contract must be one. Missing/extra active routes, unavailable targets, mismatch,
and cycles refuse before initialization. Inactive routes remain inert. Child
subsets still need targets and child ceilings. Catalog's service graph binds each
caller's sorted routes to complete downstream activation identities.

A callback requests the bound alias, without selecting a new target:

```json
{"op":"service.call","alias":"search","arguments":{"text":"explicit query"},"checkpoint":{"next":"use_result"}}
```

The checkpoint allows 8 KiB in the continuation envelope. This is an other-call,
not an extended read. Session checks both leases and commits intent before target
startup. A separate owned target receives normal invocation fields plus
`service_contract: 1` and `parent_invocation_id`; its ID is the operation ID.
Five-second initialization/callback bounds remain. The routed target returns only
a schema-valid inline result, without nested host calls/questions/services/output.
After cleanup, the caller receives `result` plus host-made service provenance.
Domain fields remain untrusted. The caller can then request its own permitted work.
Direct standalone services use their own invocation contract.

Restore validates route/arguments/schema/receipt/chain before repair, without
starting either worker. Owner death/cancellation stops owned work; interruption
stays unknown, and target expiry can refuse admission after callback execution.
A valid returned value does not prove arbitrary trusted code had no OS effects.

## Publish a literal excerpt with its receipt

`host.context` allows this inner request:

```json
{"op":"context.publish","items":[{"id":"project-note","version":"revision-1","text":"Use small reviewed changes.","priority":10,"source":{"kind":"assertion","uri":"fixture:preferences"}}]}
```

Publication replaces this instance's set atomically; empty clears only that set.
Sets are Session-local, without child/fresh-session inheritance. There are eight
unique lowercase IDs of 32 characters, version labels of 128 bytes, text of 2048
bytes, priority 0..100, and nullable unfetched assertion URIs of 1024 bytes.
All sets render within 16 KiB, sorted by descending priority then instance/ID.
Malformed/duplicate/oversized values refuse; `context_refused` preserves old sets
without truncating, evicting peers, or discarding required instructions.

For recorded provenance, replace assertion source with an actual successful action:

```json
{"kind":"receipt","operation_id":"00000000000000000000000000000000","path":["result","text"]}
```

Use its real ID. The path addresses outcome `value`, at most eight object-key/array-
index segments, keys 128 bytes and indices 0..255. Empty selects the whole value.
Text must be a literal substring of that selected string. Missing/failed/unknown/
ambiguous/foreign-invocation receipts refuse. No lookup occurs. Provenance binds
publisher/activation, publishing operation, and source receipt digest. Assertions
have null receipt digest; URL/version labels remain unverified claims.

The committed outcome precedes installation and includes admitted items/provenance
plus full-map digest. Each main request saves `extension_context_snapshot` after
admission/before dispatch, binding request/map/exact rendered bytes. A labelled
user-role reference carries it; core rules remain system text. Summary requests
omit this extra context. Before-request jobs can publish for that request;
after-turn work affects later requests. Historical interpretation uses its saved
request snapshot. Idle resume restores sets without workers/retrieval; changed
proof chains refuse before repair. Diagnostics show counts/bytes/digest, not text.
Clearing or forgetting erases no prior journal or provider transfer.

## Use explicit Memory as the domain exercise

[`extensions/bundled/memory.ex`](../../extensions/bundled/memory.ex) contains Memory,
WorkingMemory, and Records. The host sees generic State requests, not special note
fields. WorkingMemory limits initialization to session scope. Persistent Memory
requires reviewed project/operator binding. Registry compares declared scope with
the binding ceiling before executable activation/revalidation. Neither automatically
captures prompts, calls models, reads history, or publishes context.

Remember reads actual storage revision/logical source generation and proposes a
separately approved put. Generations version one literal assertion; updates must
strictly increase them. Conflicts do not retry. After reading an active target,
remember and active import carry the TARGET's expiry as `write_before_ms`, never
the replacement's later expiry. Delayed approval after expiry becomes domain
`source_expired` without another write. Inspect the real renewal/delayed-approval/
resume controls before changing that translation.

Version-2 active notes bind literal source/digest, positive generation,
`task_card`/`project_fact` kind, title/text/provenance, creation≤update<expiry, and up to eight
literal dependencies. Bounds are source/dependency 512 bytes, title 128, text 2048,
provenance 512, and encoded value 8 KiB. IDs are not entity resolution or path
aliases. Retention is checked at write/import; configuration changes do not rewrite
old expiry. Clock rollback remains a limitation.

Forget writes minimal suppression, not generic deletion. Revision CAS blocks
prepared stale work; domain suppression also blocks reread-and-recreate. Suppression
consumes quota and is not silently collected. Recall scans one fixed generation,
starts exclusion from expired/suppressed/unmigrated/orphan-derived records, and
propagates through dependencies before lexical ranking. Word overlap ranks up to
five with deterministic key ties and exact byte-span/text-hash provenance. It
synthesizes no answer and proves no semantic support. Inspect starts with the actual
get revision, then scans that generation; ineligible data becomes metadata-only,
without a read-triggered rewrite.

Export preserves every stored value, including expired and transitively blocked
active notes. Missing parents may arrive later or approved updates may remove a
dependency; turning hidden values into suppression would change restoration.
Inventory omits text/title/provenance. Collection explicitly replaces expired or
eligible direct-derivative content; traverse dependency edges for further collection
and explicitly forget orphan IDs. A missing target at revision zero returns
not-found without writing suppression, before cause lookup; mismatched revision
still conflicts. Explicit forget of a missing ID deliberately consumes a slot.

Import merges one approved record with target CAS. Suppression wins; stale generations,
unknown formats, and excessive retention refuse. Expired active import can hide a
live target immediately without renewing it. Valid version-one import can turn a
live version-two target legacy/hidden until explicit migration. An expired,
suppressed, or unmigrated target cannot be renewed by active import/remember.
Incoming suppression still wins. Migration preserves generation/expiry/provenance,
so it cannot make expired data visible. Restore fresh namespaces from complete
exports with suppression first; a partial old backup cannot prove no forget occurred.

Memory state is private until returned. Recall/tool history and private scan receipts
can retain even nonselected data. TTL/forget/collection erases none of that history
or prior provider transfer. Close affected sessions and start fresh without that
text in handoffs when needed. Secure erasure, cross-session revocation, backup
removal, and undoing disclosure are not implemented.

## Keep action chains finite and recovery inert

Ordinary calls allow sixteen steps with five-second callback/init bounds. State
scan extends only state reads through 512; result reads through 512 and accounting
through 10000 have their own grants. Extended reads admit no new work after two
minutes. Combining them extends no other family or late effect.
`host.actions.mixed` permits 512 reads plus sixteen other calls, 528 total. Its read
set is state get/list/scan, history, own/child usage, and effect-result reads.
Every operation still needs its grant, deadlines, and output limits.

Receipts bind invocation/operation/step/identity/namespace/request/approval/outcome;
final results bind their ordered chain. Altered/orphan/reordered/duplicate/unknown-
continuing chains refuse before repair. Pending questions restore parent/checkpoint/
counts, without code or runtime handles. Cancellation closes without answer;
owner loss preserves the wait. Loss after answer/continuation intent restores idle
unknown work rather than offering or executing the answer again. Expiry cannot be
overridden by answering. State deletion changes current value, not retained history.

## Exercise stale work, provenance, and both sides of a pause

```sh
mix test test/ipse/extension/state_test.exs test/ipse/extension/state_scan_test.exs test/ipse/extension/state_binding_test.exs
mix test test/ipse/extension/services_test.exs test/ipse/extension/contributions_test.exs
mix test test/ipse/extension/invocation_test.exs test/ipse/extension/event_job_test.exs
mix test test/extensions/bundled/memory_test.exs test/extensions/bundled/memory_session_test.exs
```

Trace read→concurrent forget→stale put, which must not resurrect content. Compare
pending-question resume bytes, then find one continuation after explicit answer
and a separately denied write. Change a service schema and require pre-start refusal;
change one excerpt character and require atomic context refusal. Follow export and
fresh import through missing parents, forgotten ancestors, expiry, and later
approved dependency removal. Domain fixtures prove policy; real Session tests
prove approval/ownership/recovery. Use [conformance](extensions.md#turn-the-behavior-into-a-conformance-scenario)
and the [installed lab](testing.md) for your own complete workflow.
