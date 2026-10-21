Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../../developer/extension-state.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Pause an extension for an operator question

A question saves a bounded checkpoint and closes its worker before asking for
input. An explicit valid answer admits a fresh worker continuation. Build the
checkpoint as durable domain data; a private VM heap does not survive this pause.

The lab's `workflow` export in `examples/extension-lab/src/memory.ex` is a complete
example. It asks which note to write, then proposes a separately approved file
write. Follow that sequence when adding a human decision to a command or job.

## Return a question proposal

Declare `host.actions` and `host.question` with the invocation or event-job
capability. Return the ordinary outer protocol:

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

The request has exactly `op`, `arguments`, and `checkpoint`. Arguments use the
[question schema](../../../../../developer/operator-questions.md), supporting single-choice,
multiple-choice, and text questions. There are at most three questions and eight
options per question, with unique IDs. Recommendations are never auto-answered.
Checkpoint is a plain JSON object up to 8 KiB encoded. The whole proposal also
obeys the SDK's 16 KiB, string, depth, and collection bounds.

Session checks question availability, capability, lease, schema, and remaining
16-operation budget, then commits action intent. Host confirms worker cleanup
before pausing. Session commits `extension_question` and publishes the ordinary
`{:question, operation_id, arguments}` client event. No worker/task waits for input.
Unavailable headless or child questions stop without choosing an option.

## Reconstruct the continuation

`Session.answer/3` validates the current question ID, complete answers, live
identity, and checkpoint/answer envelope. Invalid, stale, or oversized answers
leave the pending question and journal unchanged.

For a valid answer, Session syncs an `extension_action_result` with status
`answered`, then a unique `extension_continuation_intent`. Only then may Host
reverify the artifact, initialize a fresh VM with original options, and call
`handle("host.actions", payload, state)`. The payload contains the normal
invocation, operation, step, and outcome fields plus the exact saved checkpoint.

The lab handles this continuation with a specific clause:

```elixir
def handle(
      "host.actions",
      %{"outcome" => %{"status" => "answered"}, "checkpoint" => checkpoint} = payload,
      state
    ) do
  choice = payload["outcome"]["value"]["answers"]["choice"]

  request = %{
    "op" => "tool.call",
    "name" => "write",
    "arguments" => %{
      "path" => checkpoint["path"],
      "content" => "Operator selected #{choice}\n"
    },
    "timeout_ms" => 1_000
  }

  {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request},
   Map.put(state, :phase, "workflow_done")}
end
```

This expands the lab's private reply helper so the complete public result is
visible. Keep enough information in the checkpoint
to construct the next request after `init/1` has run again. Never serialize Erlang
terms or assume the previous private `state` has returned.

Answers authorize a continuation, not a later write, provider transfer, or wider
capability. The lab's next `tool.call` still needs its own full mutation approval.
Earlier action counts carry forward, so a question cannot reset the finite budget.
A model-selected extension tool retains its real original provider call/result;
a command or standalone service needs no model request to ask a question.

## Recovery and cancellation

The action reducer validates question publication against its pending action,
answered/cancelled outcomes, continuation IDs, and result digest. Further actions
or final results require the explicit continuation intent. Final invocation
receipts bind the complete chain.

A pending question restores its schema, checkpoint, parent, and step history
without executing code. Native-tool restoration removes only that call's generated
unknown placeholder while waiting; it does not invent a native call or execute
other proposed tools. Prompt/answer jobs additionally retain their source-bound
schedule and immutable remaining declaration plan.

Cancellation records a `cancelled` result without an answer or continuation.
A previously started native extension tool remains unknown. Owner death preserves
the pending question. Interruption after answer/continuation admission restores
idle with unknown work; it neither offers the answer again nor restarts code.
Missing, altered, or replayed records refuse recovery before tail repair. Expiry
cannot be overridden by answering.

## Exercise both sides of the pause

Locate the question fixtures in `test/extensions_invocation_test.exs` and the
before-request/after-turn cases in `test/extensions_event_job_test.exs`. Compare
journal bytes before and after idle resume, then explicitly answer and check for
one new continuation intent. Add a denied write after the answer to prove that
clarification cannot grant mutation permission.

```sh
mix test test/extensions_invocation_test.exs test/extensions_event_job_test.exs
```

Use [conformance cases](extension-conformance.md) with explicit `answers` to test
your own workflow. Missing answers should stop at `question`; never make a
recommended option the fixture's implicit response.
