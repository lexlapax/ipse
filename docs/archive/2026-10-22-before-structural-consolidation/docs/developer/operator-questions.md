> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/developer/architecture.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Suspending a turn for operator clarification

`ask_operator` pauses inference for structured clarification. It does not grant
action permission. `Ipse.Questions` owns pure schema/answer validation, Session owns
the durable suspension, and the terminal client owns its input codes and rendering.
The [user manual](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/usage.md) explains the interactive experience.

## Validate a question before waiting

Start in `lib/ipse/questions.ex` with `definition/0`, `validate/1`, and
`validate_answers/2`. A tool request contains one to three question objects:

```json
{"questions":[{"id":"stack","prompt":"Choose a stack","kind":"single","options":[{"id":"local","label":"Local"},{"id":"remote","label":"Remote"}],"recommended":"local"}]}
```

`id` starts with an ASCII letter followed by at most 63 letters, digits,
underscores, or hyphens. Prompts are nonblank and at most 2,000 characters.
Choice kinds `single` and `multiple` require 2–8 unique option IDs; labels are at
most 120 characters and optional descriptions 512. A recommendation must name an
option. Kind `text` omits options/recommendation or uses null. Unknown fields,
duplicate question IDs, and inconsistent combinations refuse. Argument and answer
JSON are at most 16 KiB; free text is at most 8,000 UTF-8 bytes.

The provider definition uses `strict: false` with nullable optional choice fields.
This prevents wire normalization from forcing dummy options into text questions.
Host validation remains closed and mandatory.

For the example above, the complete Session answer is `%{"stack" => "remote"}`.
An empty map and an unknown ID refuse. A recommendation is never a submitted
answer. Multiple answers require a nonempty unique option-ID list; text must be
nonblank and retains its exact value. Read `test/questions_test.exs` to follow
these cases through `parse_line/2` and `validate_answers/2`.

## Follow the suspended Session

Session emits `{:ipse, pid, {:question, id, arguments}}`. The outer `id` is the
provider call ID, separate from question IDs. `ToolCall.valid_id?/1` permits opaque
valid UTF-8 IDs of 1–256 bytes. Invalid or duplicate IDs reject the whole proposed
call batch before approval or question emission.

`Session.info/1` exposes phase `:question` and pending ID/arguments.
`Session.answer/3` accepts exactly one entry for every question. Invalid, stale,
or duplicate submissions return an error without leaving the pending state.
No model worker remains active while waiting. Later calls in the original batch
are recorded not started; after an explicit answer, the model reconsiders with
original assistant/native data preserved. Future mutations need ordinary approvals.
Headless and child sessions cannot wait; they record an error without inventing
an answer or routing it through a parent.

The terminal displays a fresh `answer CODE VALUE` prefix per displayed question.
Only that exact code is valid. Numbers/IDs, comma-separated multiple choices,
and text use `Questions.parse_line/2`; `=` escapes literal command-looking text.
Partial answers stay client-local until the full bundle is submitted. A valid
partial answer changes the next code, preventing buffered task text or old input
from answering a newly displayed question.

## Recover the wait without replay

Before emitting the UI event, Session syncs version-1 `operator_question` with
validated arguments, call ID, model step count, covered effective-message count,
and canonical prefix digest. `operator_answer` atomically stores the complete
validated result before continuation. `operator_question_closed` records
cancellation with no answer.

`Session.Saved` projects conversation events chronologically and checks each
question against the effective context at that point. Checkpoint normalization
is a temporary view: installing synthetic unknown results there could hide a
real tool result recorded later. Completed questions do not replay earlier
journal prefixes. Canonical hashing still reads each checkpoint's active context;
compaction bounds that context without removing journal history.

Resume validates schema, identity, prefix, and answer bindings. It restores a
pending question without inference or a synthetic unknown tool result. Headless
resume refuses pending input without changing the journal. Owner/VM loss preserves
an unanswered question; explicit cancel/close/EOF settles it as not started. A
committed answer survives a later request crash, but resume does not restart that
request. Corrupt committed questions or answers stop recovery before tail repair.

```sh
mix test test/questions_test.exs test/question_session_test.exs
```

The pure suite teaches accepted data. Session fixtures establish durable waits,
invalid/stale replies, cancellation, recovery, and native-message integrity. When
changing input handling, add a terminal-state fixture as well: Session validation
cannot catch a stale buffered line interpreted by the UI as a fresh answer.
The saved-question scaling fixture keeps active context fixed while quadrupling
historical events. It detects repeated prefix reconstruction through process
reductions; it does not claim constant-cost hashing for a growing conversation.
