# Synthetic Ollama tool-assisted draft withdrawal, 2026-11-07

Historical focused evidence; the [plan](../../plan.md) contains current scope.
The working tree included the draft changes and an unrelated, uncommitted
terminal diagnostic. No real Ollama service, account, or retained notes notebook
was used.

The adapter retains native Ollama assistant messages for later requests. The
draft projection accepts a tool-bearing interval only when the native calls
match normalized calls in order, including the adapter's generated ID shape,
name and serialized arguments. It requires complete tool exchanges in each
interval and refuses IDs shared with retained history, including IDs found in
retained native Ollama messages. Unknown call fields and unmatched shapes refuse.
The independent `plain_text_only?` managed-lineage rule is unchanged.

The focused native projection suite passed **5 tests**. The synthetic actual
Session and loopback adapter controls passed **2 tests, with 22 excluded**:
the existing no-tool case and a tool-assisted case cover cancellation,
acceptance, saved reconstruction and subsequent requests. The new case observes
the synthetic tool result in the draft continuation and its absence from later
requests. A targeted adversarial control rejects an ID hidden in retained native
history. An initial sandboxed Mix attempt failed because Mix could not open its
local locking socket; the recorded passing runs used host loopback access.
The offline build also passed. A subsequent attempt to run the entire draft
Session test file did not start because the host stayed below its memory gate.
An independent source-only review found no concrete cross-boundary association
or provider mismatch in the examined paths; it did not execute tests or
exhaustively prove malformed or mixed-provider histories.

These checks do not qualify arbitrary native shapes, live Ollama models,
installed terminal use, general P31I clarification or the final integrated
candidate. Unsupported continuation remains a refusal, not a provider switch.
