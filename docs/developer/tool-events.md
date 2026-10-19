# Exposing admitted tool facts safely

`Ipse.Lifecycle.Tool` assigns a host tool ID to an actually admitted model-selected
tool and binds private input/results to saved sources. It does not expose arbitrary
proposals or provide approval/veto hooks. Native, MCP, extension, and delegation
tools keep their existing execution and journal formats.

Start in `lib/ipse/lifecycle/tool.ex`, then follow Session's
`lifecycle_tool_intent` and `lifecycle_tool_outcome` appends. Read the source
fixtures in `test/lifecycle_tool_test.exs` alongside those calls.

## Separate recording from reading

Default-off `lifecycle.tools` requires `lifecycle.record`. It records bounded
sources without starting a worker or granting private access. Live subscriptions,
even metadata-only ones, require that source capability.

| Event | Views | Additional live read capability |
| --- | --- | --- |
| `tool.intent_committed` | `metadata`, `tool.input` | `event.tool.input` for input |
| `tool.outcome_recorded` | `metadata`, `tool.result` | `event.tool.result` for result |
| `tool.recording_stopped` | `metadata` | None |

History instead requires `host.actions`, `host.history`, and the selected
`host.history.tool.input` or `host.history.tool.result`. Live authority does not
grant history. Older journals without markers have no reconstructed private view.
See [feeds](extension-feeds.md) and [history](extension-history.md) for enrollment.

## Trace an admitted read

After actual approval and synced ordinary `tool_started`, Session syncs
`lifecycle_tool_intent` before starting its task. Its fresh tool ID binds session,
epoch, turn, request, source assistant call/index, admitted intent, and approval.
Reusing a provider call ID in a later request still creates a distinct occurrence.
The read-only callback may run after execution begins; its acknowledgment cannot
approve or gate execution.

A structured input view preserves the exact name and original arguments JSON:

```json
{"name":"read","arguments_json":"{\"path\":\"notes.txt\"}"}
```

When the real tool message is recorded, the outcome marker binds that source to
the original tool ID/source. Its result view is:

```json
{"text":"the exact recorded tool result"}
```

The host status is `result_recorded`, `error`, or `unknown`, not the extension's
assessment of business success. Metadata carries counts, status/approval, permitted
IDs, and actual causing sources, excluding name, arguments, text, raw call IDs,
and private hashes. Both views remain untrusted data and expose no native payload
or complete assistant message.

Each encoded private data object fits 8 KiB; complete SDK objects retain 16 KiB and
string bounds. Larger views remain unavailable with byte count/private digest,
not a truncated substitute. A private feed closes with a `view_unavailable` gap;
metadata and native history stay available. History reports its unavailable-view
gap. Counts describe encoded structured objects, not raw result-text bytes alone.

## Retain uncertainty across interruption

Process-local timing spans admission through recorded outcome, including operator
waits within that span. An explicitly resumed extension-tool question keeps its
tool ID/source but uses the new epoch and omits duration. Restart downtime cannot
be added to an old monotonic clock.

Cancellation records unknown where the existing tool result says its effect may
have happened. Abrupt exit can leave only intent. Denied, invalid, and unstarted
queued calls receive no fabricated execution events. Native `ask_operator`,
standalone extension commands/services, and nested `host.tools` actions retain
their own question/invocation/operation identities rather than being relabelled.

A session retains at most 10,000 tool facts plus one stop notice, reserving room
for each admitted input's outcome. Missing epoch/source/binding or exhaustion
stops recording and relevant feeds visibly while tools/approvals continue.
Recovery verifies actual request/turn/epoch, call position, intent, approval,
result, and exact view/digest before repair/work. Physical source-to-marker scans
stop within ten records, allowing up to eight feed intents before a torn suffix.

## Practice a private-view change

Read "self-consistent private text changes and mismatched host correlations are
rejected" in `test/lifecycle_tool_test.exs`. Its changed text and digest still fail
because physical journal evidence is authoritative. Then inspect the unavailable
view cases in feed/history fixtures. A digest check alone is insufficient.

```sh
mix test test/lifecycle_tool_test.exs
```

Use this suite for marker validation, bounds, privacy, and incomplete recovery.
When changing actual delivery, also run the focused extension feed/history suites
for the selected view. Test reused provider IDs, an oversized view, cancellation,
and a source mismatch before tail repair. No case should reexecute a tool merely
to reconstruct its event.
