# Bind sources to delivery and completion

Define what occurred before choosing how to deliver it. A proposed action,
admitted intent, recorded outcome, visible text frame, and accepted answer are
different facts. Session owns work, Journal owns durable evidence, and projectors
expose only an authorized view. An event grants no effect or private-read authority.

| Owner | Read |
| --- | --- |
| Durable source identity/pages | [`Journal`](../../lib/ipse/journal.ex) |
| Metadata/private projection and answer binding | [`Session.Lifecycle`](../../lib/ipse/session/lifecycle.ex) |
| Epoch/wait and admitted-tool state machines | [`RuntimeLifecycle`](../../lib/ipse/session/runtime_lifecycle.ex), [`ToolLifecycle`](../../lib/ipse/session/tool_lifecycle.ex) |
| Visible text broker/ephemeral projection | [`Session.TextStream`](../../lib/ipse/session/text_stream.ex) |
| Selected text workers | [`Extension.TextResources`](../../lib/ipse/extension/text.ex) |
| Optional diagnostic policy/projection/leases | [`Observability`](../../lib/ipse/observability.ex), its Channel process |

Use synthetic records/providers for the exercises. [Event contracts](extension-events.md)
own notifications/jobs/feeds/history; [accounting](accounting.md) owns canonical
counters and liability. Neither is replaced by diagnostic capture.

## Give a durable occurrence its own identity

A source binds Session ID and physical JSONL byte offset. Its version-one event
ID is the first 128 bits of SHA-256 over `ipse:journal:v1:<session>:<offset>`.
A separate canonical record digest binds private content. Identical text at
different offsets is a different occurrence; different views share one occurrence.
Deliveries/actions identify attempts to consume it.

Run this complete exercise in `iex -S mix`:

```elixir
root = Path.join(System.tmp_dir!(), "ipse-source-exercise-" <> Ipse.Usage.id())
{:ok, id} = Ipse.Journal.create(root, %{})
record = %{"type" => "message", "message" => %{"role" => "user", "content" => "same text"}}
{:ok, first} = Ipse.Journal.append_with_source(root, id, record)
{:ok, second} = Ipse.Journal.append_with_source(root, id, record)
false = first["event_id"] == second["event_id"]
true = Ipse.Journal.source_matches?(first, record)
File.rm_rf!(root)
```

This uses inactive fixture appends. Active Sessions use their owned writer.
Required-source refusal writes nothing; optional observed append can retain
mandatory evidence when source projection refuses. Never duplicate/suppress the
append to satisfy an observer. Sources establish consistency, not permission or
same-user authenticity.

`Journal.source_page/4` reads complete records without callbacks/repair, default
32/max64, with 1-MiB raw page/record bounds. Duplicate keys, nonobjects, oversized/
incomplete lines, and mid-record cursors refuse. A non-null cursor may require a
final empty EOF read. `/5` adds an exclusive validated boundary and parses nothing
later. Open-tail paging is not a transactional snapshot; history adds fixed cuts,
view grants, and explicit gaps.

## Project a closed view

`Lifecycle.project/3` validates source/content and returns version/data_version,
event ID/type/source/origin/view/correlations/data, with versions one and host
origin. Metadata excludes private content/hashes. A private view exposes selected
content, without the raw record/native history. SDK objects retain 16-KiB bounds
and private strings 8 KiB. Overflow refuses rather than truncates.

| Saved source | Public occurrence | Private view |
| --- | --- | --- |
| Original input | `prompt.received` | `prompt.original` |
| Expanded user message | `prompt.expanded_committed` | `prompt.expanded` |
| Transform result | `prompt.projection_committed` | `prompt.projection` |
| Final effective input | `prompt.effective_committed` | `prompt.effective` |
| Accepted completed answer | `answer.committed` | `answer.original`, `.presented` |
| Admitted tool input/outcome | `tool.intent_committed`, `.outcome_recorded` | `tool.input`, `.result` |

Expanded/projection views are not final effective input. Selected boundary delivery
creates final markers with original-source/turn links; missing legacy links stay
missing. Answer binding joins assistant digest/presentation/request/turn/effective
prompt after completion and successful presentation. Physical preceding evidence
must validate on restore. Original/presented views fit 8 KiB independently; a large
original does not hide a small presented view. A causal ID grants no prompt access.

Metadata copies only validated fixed host fields. Supported families cover Session
start/resume/close, waits, model admission/usage/completion, committed messages/tools,
context/compaction, questions, children, extension actions/delivery/resources, and
turn settlement. Source modules own exact strings/enums. Exclude paths, arguments,
raw provider IDs, error prose, prompts/answers/native payloads, credentials, private
digests, and counter/pricing data. Do not invent causal links from adjacency or
promote legacy completion into a newer boundary.

## Record epochs and waits independently of delivery

RuntimeLifecycle enrolls for local/export capture or selected `lifecycle.record`.
That capability records sources without starting a worker or granting reads/actions.
Otherwise idle resume appends no runtime facts. Turning capture off does not end
an enrolled epoch. Final initialization starts a fresh epoch; resume records the
previous epoch/closure without inventing legacy history. Logical close precedes
exit; actual cleanup and PID death remain separate evidence. Observed owner loss
keeps cleanup false. Untrappable death/lock loss can leave the epoch open, without
a speculative finish appended after ownership is lost.

Approval wait starts before UI publication; policy allow/deny invents no wait.
Questions start after checkpoint with actual causal source. Only a valid decision
closes its wait. Cancellation/interruption/expiry differ. Resumed questions start a
new epoch/wait/monotonic timer; old incomplete waits and restart downtime are not
folded into that duration. Runtime facts permit 10000 plus one stop notice, reserving
closure capacity at start. Exhaustion stops recording visibly while work/cleanup
continue. Tool recording has a separate quota.

## Bind admitted tool input and result

Default-off `lifecycle.tools` requires `lifecycle.record`, without starting a worker
or granting private access. Live tool views need exact `event.tool.*`; history needs
`host.history.tool.*`. Metadata tool feeds still require recording. No old marker
means no reconstructed private view.

After real approval and synced ordinary tool intent, Session records
`lifecycle_tool_intent` before task dispatch. A fresh host tool ID binds Session,
epoch/turn/request, assistant call/index, source intent, and approval. Reused provider
IDs still yield new occurrences. Feed callbacks cannot veto work already admitted.
The closed private shapes are:

```json
{"name":"read","arguments_json":"{\"path\":\"notes.txt\"}"}
```

```json
{"text":"the exact recorded tool result"}
```

Outcome binding uses the real recorded tool message and source. Status is host
result-recorded/error/unknown, not an assessment of business success. Metadata
omits name/arguments/text/raw IDs/hashes. Each encoded private object fits 8 KiB;
larger views are unavailable with private counts/digests retained, not shortened.
Private feeds close with a view gap; metadata/history have their own coverage.

Timing spans admission through recorded outcome. A resumed extension-tool question
keeps tool identity/source but uses a new epoch and omits duration, without adding
downtime to an old monotonic timer. Cancellation preserves possible effects as
unknown; abrupt loss can leave intent only. Denied/invalid/unstarted proposals
create no execution marker. Native questions, commands/services, and nested host
tools retain their own identities.

Tool recording permits 10000 facts plus stop notice, reserving outcome capacity
per input. Missing bindings or exhaustion stop recording/affected feeds while
ordinary tools and approvals continue. Restore validates request/turn/epoch/call
position/intent/approval/result/view/digest before repair. Physical source-to-marker
resolution permits ten records, including eight feed intents before a torn suffix.

## Enroll visible-text consumers before dispatch

TextStream brokers visible provider text; summaries/private reasoning never enter
it. Saved native/assistant state stays authoritative. While idle,
`Session.subscribe_text(session)` returns a handle; explicit version two uses
`Session.subscribe_text(session, 2)`. Unsupported versions and busy enrollment refuse.
No selected/embedded consumer means no broker. Four consumers share capacity;
insufficient capacity refuses before initialization/inference even for optional peers.

Embedded `required: true` belongs to that process and does not resume automatically.
Selected workers need `stream.text`; v2 additionally needs `stream.text.events`.
Only operator trust may set `text_required: true`. Session commits resource intent,
registers actual broker readiness, then ready before main dispatch. A live PID is
not readiness. Workers may span turns. Failed optional resources can be replaced
on fresh input only after cleanup; lost required policy needs explicit release.

An embedded receive fragment acknowledges each normal frame:

```elixir
receive do
  {:ipse_text, server, %{"sequence" => sequence} = frame} when server == handle.server ->
    :ok = Ipse.Session.TextStream.ack(handle, sequence)
    frame
end
```

A real client loops through end/closure and monitors the broker. The handle belongs
to its consumer PID. Wrong caller, stale/duplicate sequence, and stale producer
refuse. Workers get opaque serialized handles, not PIDs. Normal kinds are start,
UTF-8 text up to 2048 bytes, and end with transport outcome/coverage. Unsequenced
closed carries reason/queued/pending/unacked counts and is not acknowledged by
embedded clients. Broker death without a completed end is incomplete.
`TextStream.unsubscribe/1` releases live enrollment; the idle Session can release
it through `unsubscribe_text/2`, including after broker loss.

## Distinguish text occurrence from consumer sequence

V1 stream ID equals request ID. V2 assigns fresh broker epoch and stream IDs,
even when a request ID is reused. This epoch is independent of runtime/diagnostic
epochs; generation one is not a restart counter. Stream sources bind Session/epoch/
event/stream/request and half-open accepted UTF-8 byte ranges. Start is `[0,0)`,
end is a point at accepted length. Pending cancelled text has no accepted range;
position overflow closes. Closed sources instead identify the subscription, with
no invented request or position.

```text
consumer A: text [0,2), text [2,6), end [6,6)
consumer B: text [0,6),             end [6,6)
```

Ranges give different text event IDs but the same final point ID. Sequence orders
one consumer, not global occurrences. Splits respect Unicode while offsets count
bytes. IDs are domain-separated canonical source/frame-kind digests, without text
hashes. `valid_frame?/1` checks schema/ID/scope/numeric/Unicode/range consistency;
`project_frame/2` returns selected metadata or `text.visible` in host envelopes for
text started/delta/finished/subscription-closed. Outer subscription/sequence stays
separate. Projection grants no authority or worker authenticity. Session binds
request IDs to accounting; a standalone broker cannot prove inference. Durable
projection/history/feeds reject these ephemeral sources. Frames are not journaled/replayed.

## Apply pressure without blocking Session

Each consumer permits one outstanding frame, 64 queued entries, and 64 KiB queued
text. Adjacent text coalesces preserving concatenation and UTF-8 boundaries. Direct
`push/3` permits 64 KiB; `push_delta/3` fragments larger provider deltas sequentially,
without widening queues. One producer call can wait outside queues. Its task waits
while Session stays responsive. Five-second pressure closes blocking peers; optional
loss detaches and required loss fails delivery. Controls share entry capacity.
Cancellation releases blocked pushes and makes accepted text incomplete. Consumer
death frees buffers; Session death stops broker/producer.

Session commits request admission and registers the real producer before dispatch.
Only it can begin/push/finish. Outcome accounting commits before end is queued.
Optional peers do not delay answer admission for terminal ack; required peers do,
within five seconds. A healthy optional peer may get complete transport before
required peer loss refuses the answer. No later frame rewrites that receipt.
Acknowledgment proves receipt, not display, business success, or playback. Use
Session completion or `answer.committed` for accepted-answer workflows.

Unexpected callback/consumer/broker loss does not release required policy. Another
consumer or summary cannot erase it. Releasing during an active required stream
still fails that request. Worker `stream.text` callbacks acknowledge exact handle/
sequence; unsequenced closed uses zero. Extra keys/results/host calls refuse.
Five-second callbacks, 64-MiB native traffic, and 24-hour helper lifetime remain.
Expiry checks precede initialization and frame/ack admission. Intent/ready/closed
receipts bind activation/resource/turn/digest and real cleanup. Recovery initializes
nothing. Cancellation after confirmed cleanup can release selected resources for
fresh input; embedded policy remains separate. Raw debugger state is privileged.

## Deliver optional diagnostic metadata

Observability defaults off. Its policy/projection/resource functions live in one
module, with independent bounded Channel processes. Journal append retains recovery
evidence once even if optional source projection refuses. Before sink startup,
Session records intent/identity/policy; ready precedes draining, and close retains
intent digest plus actual cleanup. Receipts are durable recovery facts; samples
are optional. New facts only are offered, without replaying history. Enabled resume
can start fresh leases, leaving old unfinished ones unknown. Stopping delivery
neither deletes accounting nor unenrolls an already recorded runtime epoch.

A sink declares exactly local or export capability; export requires operator
instance scope. Project config cannot choose capture policy. Its payload binds
api version, host handle, version-one wrapper sequence/elapsed/group/level/event,
and pinned file/retention limits. The ack fragment echoes actual values:

```elixir
%{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"],
  "event_id" => payload["event"]["event"]["event_id"],
  "sequence" => payload["event"]["sequence"]}
```

No actions/transforms/inference/context may be returned. Five-second init/callback
and 16-KiB SDK bounds remain. Metadata excludes text/private hashes/endpoints/
credentials/state/business assertions. Sequence counts attempted observations;
filtered/unsupported/drop positions leave gaps. Elapsed time is capture-monotonic,
not operation duration. Categories do not imply complete internal stage coverage.

| Policy | Default | Range |
| --- | --- | --- |
| Mode / level | off / info | off/local/export; info/debug |
| Sampling interval | 1 | 1..1000 |
| Queue / encoded event | 256 / 16384 bytes | 1..256 / 1024..16384 |
| File bytes / retained files | 10485760 / 2 | 16384..10485760 / 1..2 |

Four channels use atomic reservation before mailbox admission. Category/level/
sampling refusals count filtered; size/capacity/revoked work count dropped;
unsupported projection remains distinct. Errors bypass sampling/level, not category/
size/capacity. IO/acks run outside Session; mandatory fsync can still delay it.
Invalid reply/timeout/crash/expiry closes the sink while work proceeds.
`stop_observability/1` revokes new admission and discards pending samples; in-flight
transfers can finish. Idle close allows 500 ms then bounded parallel cleanup.
Concurrent close shares a lease. A missing native receipt remains unconfirmed,
even if the worker disappeared, and can fail Session close.

## Keep ring retention distinct from journals

[`builtin:local-trace:1`](../../extensions/bundled/local_trace.ex) writes owner-only
JSONL in `trace-ring-v1` under an existing canonical parent. One persistent directory
lock serializes the catalog, with active slot locks. `retained_leases` is 1..32,
default four. Workers reset only known free-slot files and atomically publish
bindings; full rings refuse without evicting active writers. Lock files remain.

Participants must match policies. Slots permit two 10-MiB files; managed size is
leases×files×file-bytes, default 80 MiB. Catalog/replacement scratch permit 16 KiB.
Bounded names avoid arbitrary scans/deletion. Type/owner/permissions/hardlinks/
schema/policy checks refuse corruption or mismatch without repair/migration.
Legacy logs and unrelated files are neither adopted nor deleted. Interrupted first
catalog publication can invalidate the ring despite successful OS cleanup. Preserve
it and start a new private directory/session; resume reconstructs no catalog.
Recycling deletes no journals and supplies no age/erasure/archive guarantee.

## Verify each completion claim separately

```sh
mix test test/ipse/session/lifecycle_test.exs test/ipse/session/runtime_lifecycle_test.exs test/ipse/session/tool_lifecycle_test.exs
mix test test/ipse/session/text_stream_test.exs test/ipse/session/text_stream_integration_test.exs test/ipse/extension/text_test.exs
mix test test/ipse/observability_test.exs test/ipse/extension/feeds_test.exs test/ipse/extension/history_test.exs
```

Compare identical records at different offsets, resumed waits, original/presented
answers, and private data with forged digests against physical source evidence.
Then saturate text/control queues and compare optional/required peers' transport
receipts with accounting/admitted history. Exercise unequal text boundaries,
reused IDs, broker restart, idle closure, malformed ranges, and cancelled pending
Unicode. For diagnostics compare failed callback with confirmed cleanup against
interrupted catalog publication. They are different failures. [Testing](testing.md)
owns synthetic trace/debugger procedures. A projector/unit pass proves neither
actual delivery authority nor native cleanup. Never replay a tool to reconstruct
an event.
