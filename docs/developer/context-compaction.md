# Context compaction

`Ipse.Compaction` prepares and validates bounded context checkpoints.
`Ipse.Session` owns the model request, cancellation, durable commit, and effective
conversation. This uses the selected provider and model; no separate provider,
credential source, billing mode, or workflow engine is introduced.

## Preserved information

Compaction retains the latest two user turns, including every assistant/tool
message and native continuation payload in those turns, without reconstructing
them. Older user requests are pinned verbatim. The checkpoint also pins prior
call IDs, tool names, exact arguments, host-written outcome and approval metadata,
and result excerpts with SHA-256, full byte counts, and a shortened flag.
Excerpts contain at most 256 characters. Full results remain in the journal.
Older journals without host outcome metadata are labelled historically
unclassified; words in file/shell output cannot establish a host approval.
Previous approvals never grant permission for future calls.

The selected model summarizes older decisions, facts, and open questions into
three arrays of strings. The input is one user message containing normalized
transcript JSON, governed by a separate summarization instruction. Old native
reasoning/opaque continuation fields are excluded from that request; recent
native exchanges remain intact. The original journal retains all fields.
The summary and checkpoint are historical data, not higher-priority instructions.
Structural validation cannot prove a model summary's semantic fidelity. Exact
user intent, action provenance, recent exchanges, and the original transcript
provide recovery evidence; inspect current state before repeating an effect.

## Bounds and failure behavior

The default conservative encoded context ceiling is 400,000 bytes. Automatic
compaction is attempted above 80% of that ceiling at the model-request boundary,
after tools have settled. A complete older prefix must exist; unresolved calls
cannot be split away. The summary request must fit the ceiling, the generated
JSON must fit 16,000 bytes, and the resulting context must shrink below the
trigger threshold. Pinned ledgers and recent exchanges are never silently trimmed
to make this work. Oversized user input, recent tool results, or an ever-growing
intent ledger can therefore stop work with recovery guidance.

`--context-bytes` adjusts the ceiling (minimum 8192); `--no-compact` retains
hard-ceiling behavior without summarization. These byte bounds are not model
token counts or a guarantee that any provider accepts a request of that size.
Compaction consumes one of the configured model calls per turn and incurs the
selected provider's normal usage. Summary deltas are not forwarded to the UI.
Cancellation stops the owned task and does not save a partial checkpoint.

One exact outer JSON Markdown fence is accepted as presentation; prose before
or after it, multiple documents, missing/extra schema keys, non-string array
values, tool calls, and over-limit raw responses remain rejected. The same
checkpoint validation applies after JSON decoding. For Ollama summaries only,
the host sends the three-array JSON schema with `think: false`, zero temperature,
and a 4096-token generation cap. Ordinary turns retain their existing options.
These controls follow Ollama's documented
[structured outputs](https://docs.ollama.com/capabilities/structured-outputs)
and [thinking controls](https://docs.ollama.com/capabilities/thinking); unavailable
model support fails rather than changing provider or billing mode.

## Durable checkpoint and resume

A successful summary is validated for its exact schema, size, absence of tool
calls, and effective context size. Session appends and syncs a
`context_compacted` event before changing its effective messages. Version 1 stores
the checkpoint, covered effective-message count, canonical JSON SHA-256 of that
prefix, and before/after byte sizes. Original `message` events stay untouched.
The checkpoint contains the deterministic intent/action ledger and the summary;
its rendered content must match its structured metadata.

Resume folds events in order. It reconstructs unknown outcomes, verifies the
covered prefix and checkpoint, and replaces only the effective projection.
Later messages remain intact. A committed checkpoint survives owner death before
the next response; an incomplete final record uses ordinary tail repair.
A damaged committed checkpoint stops resume rather than silently choosing another
context. No restore path executes a tool or automatically restarts inference.
The digest uses recursively sorted JSON object keys rather than runtime-specific
term encoding, so checkpoints do not depend on an OTP term serialization version.

## Provider guidance and verification

The implementation keeps provider continuation data for the recent exchanges;
OpenAI documents preserving all items between the latest user message and a tool
result when manually optimizing context. See official
[reasoning guidance](https://developers.openai.com/api/docs/guides/reasoning).
OpenAI also offers [native compaction](https://developers.openai.com/api/docs/guides/compaction),
whose returned window must be used intact. Ipse's current implementation is a
provider-neutral host checkpoint, not that endpoint or server-side compaction.

See [testing and actual evidence](testing.md#p2-context-compaction-2026-10-15)
for fixtures and the separate live ChatGPT scratch check. The later
[provider acceptance](testing.md#live-provider-acceptance-follow-up-2026-10-15)
also verifies live Ollama, Anthropic, and OpenAI API checkpoint requests over
seeded synthetic history. Future changes must
preserve failure, cancellation, checkpoint integrity, and no-replay behavior.
