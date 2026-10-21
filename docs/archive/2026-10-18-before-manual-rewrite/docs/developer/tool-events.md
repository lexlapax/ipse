> Historical reference only. Snapshot of `docs/developer/tool-events.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../developer/lifecycle-events.md#bind-admitted-tool-input-and-result).

# Admitted-tool events and private views

`Lifecycle.Tool` gives a model-selected admitted tool a host-issued `tool_id` and
binds its input and recorded outcome to actual saved sources. Select these through
the existing [feed contract](extension-feeds.md) or explicit
[history reads](extension-history.md). Original assistant/tool messages, provider
continuation, execution and approval rules retain their existing formats.

## Recording and read authority

The default-off `lifecycle.tools` capability requires `lifecycle.record`. It
enrolls bounded source recording for admitted native, MCP, extension and delegation
tools in that session. It starts no worker and grants no read, write or inference
permission. Live subscriptions to the three tool types below require this source
capability, including metadata-only declarations. Source limits and unavailable
references end recording visibly while ordinary tools and approvals remain active.

| Occurrence | View | Additional live read grant |
| --- | --- | --- |
| `tool.intent_committed` | `metadata` or `tool.input` | Private input needs `event.tool.input` |
| `tool.outcome_recorded` | `metadata` or `tool.result` | Private result needs `event.tool.result` |
| `tool.recording_stopped` | `metadata` | None |

Historical reads instead need `host.actions`, `host.history` and the selected
`host.history.tool.input` or `host.history.tool.result` grant. Live access does
not grant history. Older journals without these recorded views are not relabeled
or reconstructed from adjacent private data. All subscriptions remain inert
until ordinary trust/selection and explicit work admission.

## What the sources establish

After actual approval and the existing synced `tool_started` intent, Session
syncs `lifecycle_tool_intent` before starting the tool task. Its fresh tool ID is
independent of raw provider call IDs. It binds the real session, epoch, turn,
request, source assistant call/index, admitted intent and approval category.
Repeated provider IDs in later requests still produce distinct host occurrences.
Read-only callbacks may run after execution has begun; their acknowledgment does
not gate or approve the tool.

When an admitted tool's message is recorded, `lifecycle_tool_outcome` binds that
actual result source to its original tool source/ID. Its status is the host's
recorded `result_recorded`, `error` or `unknown`, not an extension's business
success assertion. Metadata carries only byte counts, permitted status/approval,
epoch/tool/turn/request IDs and causing-event links. It excludes tool names,
arguments, result text, raw call IDs and private content hashes.

Private data has a closed structured shape:

```json
{"name":"read","arguments_json":"{\"path\":\"notes.txt\"}"}
```

```json
{"text":"the exact recorded tool result"}
```

Input preserves the original arguments JSON string and tool name; parsed external
arguments are checked against the actual admitted intent where retained. Result
text comes from the saved tool message. Both remain untrusted data. They expose
no provider-native continuation or complete assistant message. Metadata and the
selected private view share one occurrence ID; private source binding never
turns a worker-supplied event into host authority.

Each structured view is retained only when its encoded data object fits 8 KiB.
The complete SDK object retains the normal 16 KiB/string bounds. Larger views
are unavailable, with byte count and private digest retained; no truncation is
substituted. A private feed closes with a visible `view_unavailable` gap, while
metadata and original native history remain available. Historical pages report
the normal unavailable-view gap. Input/output byte counts describe these encoded
structured data objects.

## Interruption, recovery and limits

Timing runs from admission to recorded outcome within a process, including any
operator wait there. An explicitly resumed extension-tool question keeps its
original tool ID and source; its outcome uses the new epoch and omits duration,
since elapsed downtime cannot be inferred from the old monotonic clock. No
callback, tool or earlier effect is replayed on idle resume.

Cancellation/interruption records an unknown outcome where the existing tool
message says its effect may have occurred. An abrupt exit without a result leaves
the tool occurrence incomplete. Denied, invalid and unstarted queued calls do
not receive synthetic execution events. Native `ask_operator`, standalone
extension commands/services and nested `host.tools` actions retain their own
question/invocation/operation identities; this recorder does not relabel them as
model-selected executions.

At most 10,000 ordinary tool facts plus one recording-stop notice are retained per
durable session. Input admission reserves room for its outcome. A limit, missing
epoch/source or unavailable binding stops further recording and closes relevant
feeds visibly. Existing history, usage, cleanup and approval remain independent.

Before repair/work, validation checks actual request/turn/epoch, assistant call
position, intent, approval, recorded result and exact private view/digest. Source
references resolve physically; each source-to-marker scan stops within ten
records, allowing up to eight feed intents without reading a later torn tail.
References are identity/content binding under existing append-only ownership,
not authentication against hostile same-user journal replacement.

Source fixtures cover private/metadata parity, coherent content/reference
tampering, limits and incomplete recovery. Independent workers exercise native
effects with separate approval, reused IDs, unavailable views, historical grants,
question continuation, cancellation and source refusal before tail repair.
Primitive extracted-runtime checks are separate from the
[installed lab](extension-proof.md), which verifies four private/metadata feed
acknowledgments around a model-selected extension tool. Neither establishes
production graph quality. Broader proposal/validation/private-action events and
causal links are unsupported enhancements in the
[coverage audit](lifecycle-events.md#supported-lifecycle-coverage); P22 completion
does not imply those hooks or permissions.
