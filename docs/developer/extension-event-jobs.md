# Build recall and maintenance jobs

An event job reacts to a committed prompt or completed answer through the ordinary
owned invocation/action runner. Use `before_request` for awaited recall that must
finish before inference. Use `after_turn` for maintenance after the answer is
saved. Both use one serial effectful lane; after-turn maintenance keeps the
session busy until it settles.

The lab's memory worker implements both schedules. Read `spec.exs` and
`src/memory.ex` together, beginning with `handle("event.job", ...)`. Its recall
reads state and a routed value service, then publishes context. Its capture
extracts synthetic labels and proposes an independently approved CAS write.

## Declarations and handlers

A job requires an inert descriptor in `exports.jobs` and a subscription naming
that local handler. This manifest fragment shows an awaited recall:

```json
{
  "capabilities": ["event.job", "event.prompt.effective", "host.actions", "host.state.read", "host.context"],
  "subscriptions": [{
    "id": "recall", "event": "prompt.effective_committed", "event_version": 1,
    "view": "prompt.effective", "mode": "job", "handler": "recall",
    "schedule": "before_request", "required": true
  }],
  "exports": {
    "version": 1, "tools": [], "commands": [], "services": [],
    "jobs": [{
      "id": "recall", "description": "Recall selected scoped evidence",
      "arguments_schema": {
        "type": "object", "additionalProperties": false, "required": ["event"],
        "properties": {"event": {"type": "object"}}
      },
      "result_schema": {
        "type": "object", "additionalProperties": false, "required": ["status"],
        "properties": {"status": {"type": "string", "enum": ["ok"]}}
      }
    }]
  }
}
```

Each handler must exist in the same artifact's job exports. Descriptors share
the eight-per-group/32-total catalog limits; all subscription modes share
four-per-artifact/eight-total limits. `describe/0` must match capabilities,
exports, and subscriptions. Missing or empty `jobs` normalizes to no job exports.
Jobs do not enter the model tool catalog and cannot be invoked through
`Session.invoke_export/4`.

Only `before_request` and `after_turn` are supported. `answer.committed` always
requires `after_turn`. Prompt and answer private views need their exact
`event.prompt.*` or `event.answer.*` grants. Metadata grants no private text.
Every operation also needs `host.actions` and its own capability. A read-only
notification's acknowledgment never gains action semantics because a job exists.

## Execution and provenance

Session commits a source-bound event-delivery intent, validates callback arguments,
and commits an invocation intent before executable startup. The stage is
`event.job`, with standard invocation/session/turn/handler/arguments fields.
`arguments.event` contains the selected event-delivery envelope. Top-level
`trigger` is host-created with `kind: event`, delivery ID, source event ID, and
schedule. Argument fields that resemble these are merely domain data.

Private parent records also bind the delivery-intent digest and original/effective
prompt sources. Answer-triggered records additionally bind the exact answer
source. These private references and hashes do not enter metadata-only public
triggers. Restore resolves physical positions against the actual journal before
repair; a valid-looking source object alone is insufficient.

The callback returns a schema-valid final `result` or a finite `host_call`.
The host journals intent, validates lease/scope/schema, asks for any required full
approval, runs IO outside Session, and commits the result. Event selection, a
previous tool approval, or a question answer cannot authorize a new write. Model
inference needs separately trusted [host model calls](extension-model-calls.md)
and their exact profile/egress approval.

Each job gets a fresh worker resource with separate five-second initialization
and callback deadlines. SDK objects are at most 16 KiB and strings 8 KiB.
Ordinary action chains are at most 16 calls. Jobs share the session's
10,000-invocation and separate 10,000-delivery ceilings. There are no recursive
turns or concurrent background effect lanes.

## Before requests and after answers

Before-request jobs run after skill expansion and prompt transforms, before MCP
discovery, compaction, and inference for that input. An awaited recall can read
state, query a bound service, and `context.publish`. The main-request snapshot
then freezes those accepted contributions. This ordering makes recall usable for
the current answer rather than racing against provider dispatch.

After-turn work starts after saved answer/presentation and a
`lifecycle_turn_settling` binding. It cannot alter that request or retract streamed
output. Context published here becomes eligible only at a later request.
An approval or question can keep maintenance waiting for the operator.

Completion derives from committed action outcomes, not a handler's claim.
With a valid final response and confirmed cleanup, all actions must be `ok` or
`answered` for `completed`. Denied, conflicting, failed, or cancelled actions
produce `failed`. Pure jobs can complete without actions, but their returned
values remain assertions rather than evidence of effects.

Required failure stops later declarations; before-request failure prevents
inference. After-turn failure cannot undo an answer or its accounting. Optional
known failure may continue after a notice. Any unknown outcome stops the lane,
even for an optional job, because an earlier effect may have happened.
Pre-execution schema/budget refusal can be `not_started`; interrupted execution
or cleanup must not be relabeled that way.

## Questions, cancellation and recovery

A question closes the worker and saves a bounded checkpoint. An explicit validated
answer commits its action result and continuation intent before a fresh worker
enters `host.actions`. The original event callback and earlier effects do not
run again. A later write still needs approval and uses the remaining action budget.

Pending-question restore retains prompt sources, answer source when applicable,
schedule, declaration, and immutable remaining plan. Earlier completed declarations
are skipped. The remaining plan runs only through the explicitly answered
continuation. Idle resume without a pending question initializes no job and
restores no executable queue. Interruption after continuation admission stays
unknown.

Cancellation/owner death stops dependent tasks and workers within the OS cleanup
boundary. Committed state/context remains. Interrupted effects are never
automatically retried. Diagnostics count outcomes without showing private inputs.

When implementing delayed extraction, capture the revision/generation before
extraction, retain it across checkpoints, and use it in the later CAS write.
A fresh read after forgetting must not authorize an old captured fact. Host
tombstones supply the mechanism; the extension owns suppression, source cutoffs,
and derivative deletion policy.

## Exercise current-answer recall

Follow the awaited-recall fixture in `test/extensions_event_job_test.exs`.
Find the context action result, the main-request snapshot, and the provider call.
Their order must be fixed. Then compare an after-turn publication, which must
appear only in a later main request. Finally inspect the captured-revision case
where concurrent forget causes conflict rather than resurrection.

```sh
mix test test/extensions_event_job_test.exs
```

The fixtures also test full write denial, false success claims, questions in both
schedules, physical source corruption, and no idle replay after a committed write.
Use [history reads](extension-history.md) for explicit catch-up. A new history
capability does not add job triggers or automatically start reindexing.
