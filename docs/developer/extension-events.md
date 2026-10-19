# Observe prompt and completed-answer boundaries

A notification delivers a selected read-only view and expects an exact
acknowledgment. Use it when an extension needs to observe original/effective
prompts or original/presented completed answers without proposing host actions.
For persistent extraction or recall, use [event jobs](extension-event-jobs.md).
For observations while work proceeds, use [feeds](extension-feeds.md).

Start with `examples/extension-lab/src/metadata.ex`. Its declaration receives
metadata and its callback echoes identifiers. Read it beside `Subscriptions` to
see which source fact is committed before any executable delivery.

## Inert declaration and authority

A completed-answer notification adds these fields to a complete manifest:

```json
{
  "capabilities": ["event.notify", "event.answer.presented"],
  "subscriptions": [{
    "id": "observe_answer", "event": "answer.committed", "event_version": 1,
    "view": "answer.presented", "mode": "notify",
    "schedule": "after_turn", "required": true
  }]
}
```

Prompt notifications omit `schedule` and retain their six-field declaration.
Answer notifications require `schedule: after_turn`. Event version is 1 and mode
is `notify`. IDs are lowercase ASCII up to 32 characters. Unknown stages,
versions, views, modes, wildcard topics, and executable filters refuse before
activation. Executable `describe/0` must match manifest declarations exactly.

| Event | Allowed views | Additional private-view capability |
| --- | --- | --- |
| `prompt.received` | `metadata`, `prompt.original` | `event.prompt.original` |
| `prompt.effective_committed` | `metadata`, `prompt.effective` | `event.prompt.effective` |
| `answer.committed` | `metadata`, `answer.original`, `answer.presented` | `event.answer.original` or `event.answer.presented` |

`event.notify` is present exactly when notifications exist. Each private grant
is present exactly when a declaration uses it. All declared capabilities need
operator trust. Metadata selection, installation, and diagnostic capture grant
no private content authority. Children receive only their own permitted session
facts. A notification cannot return effects even if the same artifact separately
has invocation action grants.

Subscriptions share a four-per-artifact and eight-total active ceiling with jobs
and feeds. Their normalized digest is pinned in `subscriptions_sha256`, and
restore checks the inert snapshot against exact activation identities.

## Boundaries and delivery

On explicit `Session.prompt/2`, `lifecycle_prompt_received` binds the original
argument to a turn ID. `lifecycle_prompt_committed` binds final effective user
text to the saved expanded/transformed user message and original source.
These are visible user-text views, excluding full provider context, mandatory
system instructions, and native continuation.

Both prompt stages deliver after skill expansion and all prompt transforms.
Received subscriptions run first, then effective subscriptions. Within each stage,
instance order/ID followed by subscription ID controls delivery. A received
notification describes an earlier occurrence; it does not intercept expansion.
Each callback gets a fresh VM, with no private state retained between notifications.

After saved native completion and successful presentation, `lifecycle_turn_settling`
precedes `lifecycle_answer_committed`. The answer fact binds original answer,
presented answer, final native message, request/turn IDs, and effective-prompt
source. All views retain one occurrence ID. It is absent for intermediate tool
messages, failed inference, or failed presentation. After-turn prompt jobs run
first, then answer declarations in instance/ID order. The answer marker is frozen
before maintenance and cannot be changed by later jobs.

An answer-only selection records prompt boundaries for causal recovery but gives
its worker no prompt view. Native question continuations preserve source context;
they do not create new prompt occurrences.

## Write an acknowledgment handler

Session syncs `extension_event_intent` with delivery ID, identity, declaration,
source, turn, and exact payload digest before worker initialization. The closed
callback payload has `api_version: 1`, host-issued 32-hex `delivery_id` and
`turn_id`, `subscription_id`, and the selected version-1 `event` envelope.

```elixir
def handle("event.notify", payload, state) do
  {:ok,
   %{"api_version" => 1, "kind" => "ack",
     "delivery_id" => payload["delivery_id"],
     "event_id" => payload["event"]["event_id"]},
   state}
end
```

Echo the actual IDs. An invented ID or `host_call` reply fails. Event metadata
contains bounded host correlation and byte counts. A private view adds only
selected content and its binding. Neither view contains credentials, hidden
reasoning, native provider data, or arbitrary journal bodies. Source and event
schemas live in [lifecycle events](lifecycle-events.md).

Initialization and callback have separate five-second deadlines. Complete payloads
retain the SDK's 16 KiB object and 8 KiB string limits. Projection overflow records
`not_started` with a null payload digest before worker startup; text is not
truncated. Answer markers retain at most 8 KiB per private text view. An oversized
view becomes unavailable while retaining original byte counts and private digests.
A small presented view and metadata may remain available when original text is
too large. Original/effective source records also obey a 1 MiB bound. Oversized
original input refuses while idle; oversized effective input stops before delivery
and inference.

## Outcome and recovery

After reply validation and worker close, Session commits `extension_event_result`.
Outcomes are `acknowledged`, `not_started`, or `unknown`. Acknowledgment requires
an exact response, live lease, and confirmed cleanup. Timeout, invalid reply, or
interruption is never silently retried. A missing cleanup receipt stays visible;
VM disappearance alone does not establish descendant cleanup.

A required prompt non-acknowledgment stops that inference attempt. A required
answer failure stops later maintenance and marks settlement error, without
retracting the saved or displayed answer. Optional failure commits a receipt and
fixed notice, then permits later work. At most 10,000 delivery intents are
admitted per session. Finite plans and one active delivery bound work; no unbounded
subscriber mailbox exists.

Recovery validates declaration, identity, source/turn, exact payload, ordering,
unique deliveries, and required receipts. Session startup and saved diagnostics
also resolve physical source positions against the actual journal before repair.
A coherent-looking reference alone is insufficient. Native and extension-tool
questions retain adjacent `lifecycle_question_sources` checkpoints when prompt
context exists. Missing or altered checkpoints refuse rather than guessing.

Idle resume initializes no subscriber and restores no executable queue. An
unfinished intent remains historical unknown. Fresh identical text receives new
turn/event/delivery IDs. Only explicit question answers continue their pending
work; completed notifications are not delivered again.

## Exercise metadata and private views

Read the metadata worker, then locate the private-view fixtures in
`test/extensions_subscriptions_test.exs`. Compare payloads for the same occurrence:
the event ID should stay stable while authority changes the selected data.
Change the acknowledgment's event ID in a scratch worker and confirm that a
required prompt subscriber prevents inference.

```sh
mix test test/extensions_subscriptions_test.exs
```

The tests cover strict acknowledgment, native/presented separation, byte bounds,
optional/required failures, process cleanup, source tampering before repair,
question continuation, and byte-identical idle resume. Use
[conformance](extension-conformance.md) to assert request counts and saved receipt
counts for your own declared subscriber.
