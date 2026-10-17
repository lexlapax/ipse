# Prompt event subscriptions

Selected extensions can receive bounded, read-only prompt notifications through
the independent worker SDK. The host records original input and a final effective
user-text boundary, then delivers selected views before MCP discovery, compaction
or inference for that input. This implements the first subscription seams in the
[lifecycle design](lifecycle-events.md). Separately admitted
[event jobs](extension-event-jobs.md) support finite actions and awaited recall;
this guide covers read-only delivery. Broader lifecycle observation remains pending.

Use [operator selection](../operator/extensions.md#prompt-event-subscribers) for
trust/configuration and [artifacts](extension-artifacts.md) for installation.
The [source/view adapter](lifecycle-events.md#internal-journal-source-and-prompt-views)
owns occurrence identity and source paging. This guide owns subscription
declarations, callback values and delivery recovery.

## Inert declaration and authority

A worker manifest may include an optional `subscriptions` array, with at most
four unique IDs. Omission means an empty array. For example, these fields belong
inside an otherwise complete artifact manifest:

```json
{
  "capabilities": ["event.notify", "event.prompt.effective"],
  "subscriptions": [
    {
      "id": "observe_prompt",
      "event": "prompt.effective_committed",
      "event_version": 1,
      "view": "prompt.effective",
      "mode": "notify",
      "required": true
    }
  ]
}
```

Every notification declaration has exactly these six fields. Job declarations
add a handler and schedule under the separate job contract. IDs use the existing lowercase
ASCII identifier convention and are at most 32 characters. Event version is 1;
this guide's mode is `notify`. Unknown stages, versions, modes, views,
wildcards and executable filters refuse during inert validation. `describe/0`
must return the same declarations as the manifest. Discovery/import/inspection
executes no callback.

| Event | Allowed views | Required capabilities |
| --- | --- | --- |
| `prompt.received` | `metadata` or `prompt.original` | `event.notify`; private view also needs `event.prompt.original` |
| `prompt.effective_committed` | `metadata` or `prompt.effective` | `event.notify`; private view also needs `event.prompt.effective` |

The declared capability set must match these views. `event.notify` is present
exactly when notifications exist (`event.job` is separate); each private read capability is present exactly
when a declaration uses it. Operator trust must cover all declared capabilities.
Project/child selection retains the ordinary operator ceilings; a child receives
only its own prompt facts, never the parent's conversation feed. There are at
most eight selected declarations across all active instances. Their canonical
digest is pinned in `subscriptions_sha256`, and the inert session snapshot is
checked against those identities on restore.

Read authority grants no storage, model, tool, question or context-publication
operation. Even an artifact trusted for invocation host actions cannot use them
through a notification reply. Installing an extension or selecting a metadata
view does not grant private prompt access. Diagnostic capture settings and these
explicit subscriptions have separate enablement: tracing can remain off while a
selected private subscriber operates.

## Boundaries and delivery

For a fresh explicit `Session.prompt/2`, selected subscriptions add two durable
facts: `lifecycle_prompt_received` binds the original argument to a fresh turn ID;
`lifecycle_prompt_committed` binds final effective user text to the saved user
message and received source. Skill expansion and all prompt transforms finish
before the latter fact. This is final visible **user text**, not the complete
provider context, mandatory system instructions or native continuation.

Both stages are delivered at this post-transform barrier. The received event
describes earlier input receipt; its callback does not intercept skill expansion
or run before the prompt transformers. All received subscriptions run first,
then effective subscriptions. Within each stage, instance order/ID and then
subscription ID determine delivery order. Each callback uses a fresh owned VM;
private VM state is not retained between notifications.

Before executable initialization, Session syncs an `extension_event_intent`
binding delivery ID, identity, declaration, source, turn and exact callback-payload
digest. The owned task then initializes the reviewed worker and calls
`handle("event.notify", payload, state)`. Payload is a closed JSON object:

| Field | Value |
| --- | --- |
| `api_version` | Integer 1 |
| `delivery_id` | Host-issued 32-character lowercase hexadecimal ID |
| `subscription_id` | Selected declaration ID |
| `turn_id` | Host-issued 32-character lowercase hexadecimal turn ID |
| `event` | Version-1 typed source/view envelope |

Event/source fields follow the source/view contract. Metadata includes only host
byte counts and correlation;
private views include selected text and a private content binding. Neither
contains credentials, hidden reasoning, provider-native data or the entire journal.

The only accepted reply echoes the actual delivery/event IDs in a closed
acknowledgment. A handler can construct it as follows:

```elixir
def handle("event.notify", payload, state) do
  reply = %{
    "api_version" => 1,
    "kind" => "ack",
    "delivery_id" => payload["delivery_id"],
    "event_id" => payload["event"]["event_id"]
  }

  {:ok, reply, state}
end
```

No reply proposes effects or modifies the prompt. Worker initialization and each
callback have separate five-second deadlines. The existing 16 KiB SDK-object and
8 KiB string bounds apply to the complete wrapped payload. Overflow refuses
without truncation; a `not_started` receipt with a null payload digest records
projection refusal before worker initialization. Received/effective source records
also have the 1 MiB source bound. An oversized original refuses input while idle;
an oversized effective source stops that attempt before notification/inference.

The finite plan, one active delivery and rejection of another prompt while busy
bound admission; there is no unbounded subscriber mailbox. This is not a live
stream, a general broker or concurrent background scheduling. Those contracts
must be negotiated separately. Session stays responsive to cancellation while
workers run; killing its owner stops the owned task/VM/native process group under
the existing documented OS cleanup limits.

## Outcome and recovery

After callback validation and worker close, Session syncs an
`extension_event_result` with the intent digest, outcome and cleanup confirmation.
Outcomes are `acknowledged`, `not_started` or `unknown`. Acknowledgment requires
the exact response, a live lease and confirmed cleanup. Invalid/host-call replies,
timeouts and interrupted callbacks are never silently retried. Unconfirmed live
cleanup is visible in diagnostics and makes close/cancel report failure.
A protocol timeout can terminate the VM while leaving cleanup unconfirmed,
because the terminating worker cannot return a final close acknowledgment.
Process disappearance alone does not prove complete descendant cleanup.

A required non-acknowledgment stops before inference for that attempt. An optional
failure has a saved receipt and fixed status notice, then permits later deliveries
and ordinary work. Neither policy rewrites history or constitutes a privacy
redaction/erasure guarantee. At most 10,000 delivery intents fit one session;
exhaustion refuses further admission.

Restore validates identity/declaration/payload bindings, order, uniqueness,
source-turn association and required receipts before a model request. Session
startup, saved diagnostics and handoff export additionally resolve physical source
positions against the actual journal; a self-consistent forged reference alone
does not prove source authenticity. Resume refuses corrupt references before tail
repair. Pure `Session.restore_context/1` checks structural/projection invariants;
it cannot verify physical file positions without a journal path.

Idle resume initializes no subscriber and restores no delivery queue. An unfinished
intent remains historical unknown; a fresh explicit input gets new turn/event and
delivery IDs even when its text is identical. Ordinary model continuations and
operator question answers do not create new prompt deliveries. Mandatory journals,
usage, approvals and acknowledged visible-text delivery remain separate.

## Verification and remaining foundation

`test/extensions_subscriptions_test.exs` compiles independent workers and exercises
private versus metadata views, final transformed text, disabled behavior, strict
acknowledgment/no action bypass, bounds, optional/required failures, timeout,
actual VM shutdown, byte-identical idle resume, fresh identical prompts and
coherently forged physical references before repair. See
[actual platform/package evidence](testing.md#current-evidence-and-next-checks).

The separate [job contract](extension-event-jobs.md) now provides finite host
actions, pre-request recall and after-turn maintenance. Remaining foundation work
includes broader lifecycle types/causal links, bounded diagnostic sinks and explicit
catch-up. Continuous private feeds and external adapters need their own negotiated
ownership/flow/egress contract. Notification acknowledgments must not silently
gain effectful semantics in a future implementation. Production graph extraction
and stores remain P25 work; the extension-only P22 graph proof is still required.
