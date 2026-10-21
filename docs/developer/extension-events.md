# Observe turns and run scheduled jobs

Choose a notification when an extension needs one selected prompt or completed
answer view and can return only an acknowledgment. Choose a job when it needs an
owned invocation with state, services, context publication or separately approved
effects. Jobs run before the request for awaited recall, or after the completed
answer for maintenance. Work proceeds through one serial effectful lane.

Read `examples/extension-lab/src/metadata.ex` for a notification, then
`spec.exs` and `src/memory.ex` for recall/capture jobs. Start from
`handle("event.job", ...)` and follow its state read, routed lookup and context
publication. The examples need a built checkout and Elixir toolchain; their
synthetic proofs need no account or model service.

## Select a source view explicitly

All declarations are inert manifest data and must match executable `describe/0`.

| Event | Views | Private capability |
| --- | --- | --- |
| `prompt.received` | `metadata`, `prompt.original` | `event.prompt.original` |
| `prompt.effective_committed` | `metadata`, `prompt.effective` | `event.prompt.effective` |
| `answer.committed` | `metadata`, `answer.original`, `answer.presented` | `event.answer.original` or `event.answer.presented` |

Metadata grants no private content. Each private capability is present exactly
when a declaration uses that view, and every capability needs operator trust.
Children receive only their own permitted session facts. Installation,
diagnostics and an answer-only selection grant no prompt view.

Event version is 1. Subscription IDs are lowercase ASCII up to 32 characters.
Unknown stages, versions, views, modes, wildcard topics and executable filters
refuse activation. Notifications, jobs and feeds share four subscriptions per
artifact and eight active subscriptions total. Normalization pins
`subscriptions_sha256` in activation identity and saved metadata.

## Write a notification and acknowledgment

Add this fragment to a complete manifest for a presented-answer notification:

```json
{"capabilities":["event.notify","event.answer.presented"],"subscriptions":[{"id":"observe_answer","event":"answer.committed","event_version":1,"view":"answer.presented","mode":"notify","schedule":"after_turn","required":true}]}
```

`event.notify` is present exactly when notifications exist. Answer notifications
require `schedule:"after_turn"`; prompt notifications omit schedule and retain
their six-field declaration.

Before worker initialization, Session syncs `extension_event_intent` with delivery
ID, identity, declaration, source, turn and exact payload digest. The closed
callback payload contains `api_version:1`, host-issued 32-hex `delivery_id` and
`turn_id`, `subscription_id` and the selected version-one event envelope. Echo
the actual delivery/event IDs:

```elixir
def handle("event.notify", payload, state) do
  {:ok,
   %{"api_version" => 1, "kind" => "ack",
     "delivery_id" => payload["delivery_id"],
     "event_id" => payload["event"]["event_id"]}, state}
end
```

An invented ID or `host_call` fails, even if this artifact separately has action
grants. Each notification gets a fresh VM; private state does not survive it.
Initialization and callback have separate five-second deadlines. The SDK retains
16 KiB objects and 8 KiB strings. Projection overflow records `not_started` with
a null payload digest before startup; text is never truncated to fit.

After reply validation and confirmed worker cleanup, Session commits
`extension_event_result`. Outcomes are `acknowledged`, `not_started` or `unknown`.
An acknowledgment also requires a live lease. Timeout, invalid reply and
interruption are never silently retried. VM disappearance alone is not proof of
descendant cleanup; a missing cleanup receipt remains visible.

## Declare a job with an exported handler

A job names a handler in the same artifact's `exports.jobs`. This manifest
fragment declares awaited recall:

```json
{"capabilities":["event.job","event.prompt.effective","host.actions","host.state.read","host.context"],"subscriptions":[{"id":"recall","event":"prompt.effective_committed","event_version":1,"view":"prompt.effective","mode":"job","handler":"recall","schedule":"before_request","required":true}],"exports":{"version":1,"tools":[],"commands":[],"services":[],"jobs":[{"id":"recall","description":"Recall selected scoped evidence","arguments_schema":{"type":"object","additionalProperties":false,"required":["event"],"properties":{"event":{"type":"object"}}},"result_schema":{"type":"object","additionalProperties":false,"required":["status"],"properties":{"status":{"type":"string","enum":["ok"]}}}}]}}
```

Job descriptors share eight-per-group and 32-total catalog limits. Missing or
empty jobs normalize to none. They do not enter the model tool catalog and
cannot be called through `Session.invoke_export/4`. `describe/0` must match
capabilities, exports and subscriptions. Only `before_request` and `after_turn`
are supported; answer jobs always use `after_turn`.

`event.job` permits the declared job, while `host.actions` and each operation's
capability authorize proposals. They do not replace required approval. The
notification acknowledgment contract stays read-only regardless of job exports.

Session records source-bound delivery intent, validates arguments and commits
invocation intent before executable startup. Callback stage is `event.job`, with
standard invocation/session/turn/handler/arguments fields.
`arguments.event` contains the selected event-delivery envelope. Top-level
`trigger` is host-created with kind `event`, delivery ID, source event ID and
schedule. Similar-looking argument fields remain domain data.

The callback returns a schema-valid final `result` or a finite `host_call`.
Use [state and questions](extension-state.md), [composition](extension-composition.md)
and [approved effects](extension-effects.md) for the corresponding protocols.
Event selection, a prior tool approval or a question answer cannot authorize a
new write or model egress.

Each job gets a fresh worker with separate five-second initialization/callback
deadlines and unchanged SDK bounds. Ordinary chains permit 16 calls; explicit
mixed grants keep their separate read/other counters. Jobs share the session's
10000-invocation and separate 10000-delivery ceilings. There are no recursive
turns, concurrent background effect lanes or unbounded subscriber mailboxes.

## Trace the order around inference

On explicit `Session.prompt/2`, `lifecycle_prompt_received` binds original text
to a turn. `lifecycle_prompt_committed` binds the effective user text to the saved
expanded/transformed message and original source. Both notifications deliver
after skill expansion and all prompt transforms. Received subscriptions run
first, then effective subscriptions; instance/ID and subscription ID order each
stage. Received notification describes an earlier occurrence, not interception.

Prompt views contain user text, not full provider context, required system
instructions or native continuation. Original/effective source records have a
1 MiB bound. Oversized original input refuses while idle; oversized effective
input stops before delivery and inference.

Before-request jobs run after expansion/transforms and before MCP discovery,
compaction and inference. Awaited recall can read state, query its bound service
and publish context. The main-request snapshot then freezes contributions for
this answer. An answer-only selection still records prompt boundaries for causal
recovery without exposing prompt text to the worker.

After saved native completion and successful presentation,
`lifecycle_turn_settling` precedes `lifecycle_answer_committed`. The answer binds
original/presented text, final native message, request/turn IDs and effective
prompt source. Every view retains one occurrence ID. Intermediate tool messages,
failed inference and failed presentation produce no completed-answer occurrence.
After-turn prompt jobs run first, then answer declarations in instance/ID order.
The frozen answer marker cannot be changed by later maintenance.

Each private answer view retains at most 8 KiB. Oversized text becomes unavailable
while original byte counts and private digests remain; a smaller presented view
or metadata may still be available. No worker payload contains credentials,
hidden reasoning, raw provider data or arbitrary journal bodies. See
[lifecycle records](lifecycle-events.md) for schemas.

After-turn work keeps the session busy until settlement. Approval or a question
may wait for the user. It cannot change the completed request or retract streamed
text. Publications become eligible only for a later request. Native question
continuations preserve source context rather than creating new prompt events.

## Derive success from committed outcomes

Notification and job failures have different completion rules:

| Boundary | Required declaration | Optional declaration |
| --- | --- | --- |
| Prompt notification does not acknowledge | Stop that inference attempt | Save receipt/notice and permit later work |
| Answer notification does not acknowledge | Stop later maintenance and mark settlement error | Save receipt/notice and permit later work |
| Job has known failed action | Stop later declarations; before-request failure prevents inference | May continue after notice |
| Job has unknown action or cleanup | Stop the lane | Stop the lane |

A job completes only with a valid final result, confirmed cleanup and every
action `ok` or `answered`. Denied, conflicting, failed and cancelled actions
produce `failed`, regardless of the handler's success claim. A pure job can
complete without actions; its value remains an assertion, not proof of effects.
Pre-execution schema/budget refusal can be `not_started`; interrupted execution
or cleanup cannot. After-turn failure cannot undo the answer or its accounting.

## Continue questions without replaying work

A question closes the worker and saves its bounded checkpoint. An explicit
validated answer commits the action result and continuation intent before a
fresh worker enters `host.actions`. The original callback and earlier effects do
not rerun. Later writes still need approval and the remaining action allowance.

Pending-question restore retains prompt sources, applicable answer source,
schedule, declaration and immutable remaining plan. Completed declarations are
skipped. Only the explicitly answered continuation runs the rest. Idle resume
initializes no subscriber or job and restores no executable queue. An unfinished
intent remains historical unknown. Fresh identical text gets new turn/event/
delivery IDs.

Restore validates declarations, identities, source/turn, payloads, ordering,
unique deliveries and required receipts. Session startup and saved diagnostics
resolve physical source positions against the actual journal before repair.
Private job parents also bind delivery-intent digest and original/effective
sources, plus answer source when applicable. Those references do not enter a
metadata-only public trigger. Native and extension-tool questions retain adjacent
`lifecycle_question_sources` checkpoints when prompt context exists; missing or
changed checkpoints refuse instead of guessing.

Cancellation stops dependent tasks/workers within the OS cleanup boundary.
Committed state/context remains and interrupted effects never automatically
retry. Diagnostics count outcomes without exposing inputs. For delayed extraction,
capture revision/generation before extraction and retain it across checkpoints.
A later CAS must use that captured identity. A fresh read after forget must not
authorize resurrection of an old captured fact. The extension owns suppression,
source cutoffs and derivative deletion policy; host tombstones supply the CAS.

## Verify observation, recall and maintenance

Compare metadata/private payloads for one occurrence in the subscription tests:
the event ID stays stable while grants change selected data. Change an ack ID
in a scratch worker; a required prompt subscriber must prevent inference.
Then inspect awaited recall's context result, request snapshot and provider call
in order. After-turn publication must affect only a later request.

```sh
mix test test/extensions_subscriptions_test.exs test/extensions_event_job_test.exs
```

These checks also cover full write denial, false success claims, byte bounds,
questions in both schedules, captured-revision conflict after concurrent forget,
physical source corruption, cleanup and byte-identical idle resume. Add request
counts and receipt counts to a [conformance fixture](extensions.md) for your own
subscriber. Use [history reads](extension-feeds.md) for explicit catch-up; history
permission creates no new trigger and never starts reindexing by itself.
