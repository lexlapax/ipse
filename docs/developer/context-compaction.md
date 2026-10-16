# Context compaction

`Ipse.Compaction` prepares and validates bounded context checkpoints.
`Ipse.Session` owns the model request, cancellation, durable commit, and effective
conversation. Model summaries use the selected provider and model. A deterministic
older-tool-output fallback makes no model request. Neither path changes provider,
credential source, billing mode, or workflow engine.

## Preserved information

The preferred model-summary path retains the latest two user turns, including every assistant/tool
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
after tools have settled. The model-summary path requires a complete older prefix; unresolved calls
cannot be split away. The summary request must fit the ceiling, the generated
JSON must fit 16,000 bytes, and the resulting context must shrink below the
trigger threshold. Pinned ledgers and recent exchanges are never silently trimmed
to make this work. Oversized user input, recent tool results, or an ever-growing
intent ledger can therefore stop work with recovery guidance.

If planning that summary fails, Ipse tries deterministic tool-output reduction,
including within a single long user turn. It retains every message and all user
text, assistant text, provider continuation fields, call IDs/names/arguments, and
host approval/outcome metadata unchanged. The two newest assistant tool-call
batches, including all parallel results, remain full. Only older results over
4096 bytes with known settled outcomes and approved or approval-free provenance
are eligible. Unknown, denied, historically unclassified, and already reduced
results remain untouched. Unresolved or duplicate calls prevent reduction.

Eligible output becomes an explicitly incomplete beginning/end excerpt (256
characters each), with original byte count and SHA-256 plus a warning to inspect
original evidence rather than repeat an effect. This changes tool-result text;
it does not preserve its full semantic content. The original journal stays intact.
The entire proposed projection must shrink below the trigger or none is saved.
A later model summary carries original result provenance forward, rather than
hashing the shortened text as though it were the original output.

The [P12 trial](testing.md#p12-task-tracker-coding-trial-2026-10-15) exposed the
earlier complete-turn-only limitation; [P13](testing.md#p13-long-turn-compaction-2026-10-16)
reproduces that failure with the fallback. Retained user text, arguments, native
payloads, recent results, or an intent ledger can still prevent a safe checkpoint.


`--context-bytes` adjusts the ceiling (minimum 8192); `--no-compact` retains
hard-ceiling behavior without either reduction path. These byte bounds are not model
token counts or a guarantee that any provider accepts a request of that size.
A model summary consumes one configured model call and normal provider usage.
Deterministic output reduction consumes neither. Summary deltas are not forwarded to the UI.
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

The `tool_results_compacted` version-1 event instead stores the covered effective
message count, canonical prefix and projected-message digests, deterministic
result indices, and before/after sizes. Session syncs it before continuation.
Restore verifies the original prefix, call settlement, eligibility/indices, and
regenerated projection digest before accepting it. It composes with earlier
summary/output checkpoints and leaves later messages untouched. Corrupt events
stop resume; owner death after commit retains the projection without replay.

Failures record a `compaction_failed` event with prepare, summary, or validation
stage and a bounded host diagnosis. Planner/validator causes are shown to the
operator; provider-summary failures use a static message to avoid exposing raw
provider bodies. Inspect effects and retained evidence first. A short continuation
can make an older turn eligible for a model summary; otherwise explicitly adjust
the ceiling or start a new session with necessary context. No failure retries a
tool or changes provider.

## Provider guidance and verification

The summary path keeps provider continuation data for recent exchanges, and the
output-reduction path keeps all such fields. Tool-output reduction is a host
tradeoff with marked incomplete results, not intact replay of every exchange;
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

## Diagnostics and explicit handoff

`Ipse.Diagnostics.context/3` partitions the exact JSON encoding into fixed
categories, including map/list framing, escaped field names/values, instructions,
user/assistant text, the newest two result batches, older results, tool-call
arguments/envelopes, provider-native data, checkpoint data and host provenance.
Only numbers and fixed labels leave that calculation. Original field content is
not inspected or returned. The shared `Compaction.target_bytes/2` keeps the
diagnostic trigger consistent with the planner. Category sizes are encoded bytes,
not model tokens or independent minimum checkpoint sizes.

`Session.diagnostics/1` adds current phase/step/wait/worker facts. Saved inspection
uses the public pure `Session.restore_context/1` restoration path and research
ledger validation without opening a live Session, repairing a tail or inference.
Its scope omits current system/skill instructions and labels a missing saved
ceiling. Compaction refusals now record exact request measurements in a private
`compaction_failed` event. Model/summary workers record bounded-category completion,
failure/cancellation and elapsed milliseconds; approval/tool time is excluded.
Idle resume does not add measurements or replay requests. This is a minimal
local diagnostic foundation; broad lifecycle/OTLP tracing remains P22 work.

`Ipse.Handoff.export/3` requires an explicit bounded operator note and emits a
small versioned recovery artifact with source-event digest and unknown-call
references. It never copies arbitrary source metadata, history, approval settings
or native continuation into a new session. Original events stay private and
unchanged. Export neither creates nor resumes a session. Existing compaction
rules are unchanged: there is no undocumented trimming of required native data
or pinned intent. Unknown outcomes still require inspection. P21 may independently
implement explicit artifact import as a separate supervised feature.

See [operator recovery](../operator/recovery.md) and
[P19 evidence](testing.md#p19-diagnosis-and-explicit-recovery).
