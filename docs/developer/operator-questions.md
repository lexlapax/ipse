# Structured operator questions

The native `ask_operator` tool accepts a `questions` array of one to three objects.
Each has an `id` (ASCII letter followed by up to 63 letters/digits/underscore/hyphen),
nonblank `prompt` (at most 2000 characters) and `kind`: `single`, `multiple` or
`text`. Choice questions have two to eight options with unique `id`, nonblank
`label` (120 characters) and optional `description` (512 characters); optional
`recommended` is an existing option ID. Text questions omit options/recommendation
or use null. Unknown fields, duplicate IDs and invalid combinations are rejected.
The existing MCP schema adapter/JSONSchex provides bounded schema/JSON validation;
identity and cross-field checks are small host policy, not another schema engine.
Arguments/answer JSON are at most 16 KiB, and free text at most 8000 UTF-8 bytes.

The tool definition explicitly uses `strict: false` and nullable optional choice
fields to avoid Responses normalizing absent fields into mandatory dummy choices.
Host validation still runs before waiting. This follows the public
[function-calling optional/strict guidance](https://developers.openai.com/api/docs/guides/function-calling).
It does not relax tool permissions or accept extra schema keys.

## Session and client interface

Session emits `{:ipse, pid, {:question, id, arguments}}`. `id` is the persisted
provider call ID, separate from individual question IDs. `Session.info/1` includes
the pending ID/arguments and phase `:question`. `Session.answer/3` accepts exactly
one map entry for every question: an option ID for `single`, a nonempty unique list
of option IDs for `multiple`, or nonblank text. Invalid/stale/duplicate answers
return an error and keep current state; no default/recommendation is an answer.
Answers are clarification data, never action permissions.

There is no live model worker while waiting. Any later calls in the same proposed
batch are journaled as not started; after an explicit answer the model reconsiders
work with all original assistant/native fields retained. Future mutations still
use ordinary approvals. Headless and child sessions cannot wait for input; they
record an error and finish without an implicit answer. Child-to-parent question
routing remains unsupported. The terminal supports numbers/IDs, comma-separated
multi-select and text, with `=` escaping literal slash commands. Partial terminal
answers remain local until the whole bundle is submitted.

## Durable events and interruption

`operator_question` version 1 records the exact call/validated arguments, model
step count, covered effective-message count and canonical prefix SHA-256 before
emitting the question. Resume validates call/argument identity, schema and prefix
integrity, then restores the pending question without a synthetic unknown tool
outcome, inference or replay. Existing unrelated interrupted outcomes retain their
normal handling. A headless resume refuses pending input without journal changes.

`operator_answer` version 1 atomically stores the complete tool-result message
before continuation; its explicit answers are revalidated against the question.
`operator_question_closed` stores a cancellation result with no answer. Original
message events stay intact, and new event messages compose with context checkpoints.
Corrupt committed questions/answers stop resume. VM/session or monitored-owner death
preserves an unanswered question; explicit close/cancel/EOF settles it as not started.
A committed answer survives death during the next provider request, while idle
resume does not restart that request. The OS lock still serializes session owners.

All journal content, including operator answers, remains private local transcript
data. The implementation adds no dependency or inference request for validation.
See [verification](testing.md#p17-structured-operator-questions-2026-10-16) and
[operator usage](../operator/usage.md#operator-questions).
