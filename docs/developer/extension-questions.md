# Structured extension questions and continuation

P22A9 adds `host.question` to the [finite host-call protocol](extension-host-calls.md).
Tools, operator commands and standalone services can ask bounded single-choice,
multiple-choice and text questions. Workers close before questions appear.
Pending questions restore without code execution; only an explicit answer admits
a fresh journaled continuation. This does not complete P22 or install a workflow
framework.

## Contract

An artifact declares `host.actions` and `host.question` alongside `invoke.*`;
operator trust must allow them. Its callback can return:

```elixir
{:ok,
 %{"api_version" => 1, "kind" => "host_call",
   "request" => %{
     "op" => "operator.question",
     "arguments" => %{"questions" => [
       %{"id" => "choice", "prompt" => "Which result should be kept?",
         "kind" => "single", "recommended" => "first",
         "options" => [%{"id" => "first", "label" => "First"},
                       %{"id" => "second", "label" => "Second"}]}
     ]},
     "checkpoint" => %{"next" => "show_selection"}
   }},
 private_state}
```

The closed request has exactly `op`, `arguments`, `checkpoint`. Arguments use
the [existing question schema](operator-questions.md): at most three questions,
eight options each, unique IDs and no automatic answer. Checkpoint is a plain
JSON object of at most 8 KiB encoded; the entire proposal obeys SDK 16 KiB/depth/
string/collection bounds. It is private continuation data, not permission, model
context or serialized Erlang state. This operation has null state namespace.

Session checks availability, lease, capability, schema and the remaining
16-operation invocation budget, then syncs action intent. Host confirms worker
cleanup before returning its pause. Session syncs `extension_question` and
publishes the ordinary client `{:question, id, arguments}` event using its
host-generated operation ID. No worker/task waits for input. Unavailable
headless/child questions stop without selecting recommendations. The terminal
reuses its existing question rendering and `/cancel`; no new flag is needed.

## Explicit answer

`Session.answer/3` validates the current ID, complete answers, live identity and
answer/checkpoint envelope before committing. Stale/invalid/oversized answers
leave the question and journal unchanged; content is never silently truncated.

A valid answer syncs an `extension_action_result` with status `answered`, value
`{"answers": ...}`, then a unique `extension_continuation_intent` binding that
result. Only afterward can an owned task reverify the artifact, open a fresh VM,
initialize with original options and invoke `host.actions`. Its payload has the
normal invocation/operation/step/outcome fields plus the exact saved `checkpoint`.
This is an explicitly answered continuation, not idle-resume replay. Authors must
reconstruct work from the checkpoint; arbitrary old VM state is gone.

The callback can finish or propose another supported operation. Prior receipts/
counts carry forward, so questions cannot reset the 16-operation budget. Answers
never authorize a later mutation or change provider/billing/capability ceilings.
After an extension model tool finishes, its actual original call/result settles
and the agent loop can continue. Standalone commands/services need no model
request to ask/answer a question.

## Recovery and cancellation

The pure action reducer validates publication against its pending source-bound
action, answered/cancelled outcomes, unique continuation IDs and result digest.
Further operations/final results require the explicit continuation intent. Final
invocation receipts bind the complete action chain. Projection checks these
records before tail repair.

An interrupted pending question restores schema/checkpoint/parent/step history
and waits without initialization/callbacks. Native tools retain their actual
provider call and approval; recovery removes only that call's generated historical
unknown placeholder while waiting. Other proposed calls settle without execution
when clarification is required. No synthetic native call is manufactured.

Cancellation saves a `cancelled` result without an answer/continuation and stops
the turn; a previously started native extension tool remains unknown. Owner death
preserves a pending question. Interruption after answer/continuation intent
restores idle with unknown work, without reoffering the answer or restarting code.
Inspect receipts before explicitly choosing a fresh action. Missing/altered/
replayed question/continuation records refuse recovery. Hashes check integrity,
not signatures.

These mandatory private records are independent of optional tracing. Checkpoints/
answers are not diagnostics or hidden model reasoning. Expiry cannot be overridden
by an answer; restore still needs the exact pinned code/config/host. See
[operator procedures](../operator/extensions.md#structured-questions) and
[actual verification](testing.md).
