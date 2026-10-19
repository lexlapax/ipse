# Reducing model context while retaining evidence

Compaction changes the effective conversation sent to a model. It does not delete
journal history or authorize repeated work. `Ipse.Compaction` prepares and validates
pure checkpoint projections. Session owns summary inference, cancellation,
durable commit, and replacement of its effective messages.

Read `prepare/3`, `finish/4`, `restore_tool_results/2`, and `digest/1` in
`lib/ipse/compaction.ex`. There are two reduction paths with different trade-offs.

## Follow the summary path

The default encoded context ceiling is 400,000 bytes. Core system instructions
and the labelled user-role reference message count toward it. At a model-request
boundary after tools settle, automatic compaction triggers above 80% of the
ceiling. `--context-bytes` accepts at least 8,192; `--no-compact` disables reduction
but retains hard admission limits. Encoded bytes are not provider tokens.

The planner selects a complete older prefix, retaining the latest two user turns
and all their assistant/tool/native data exactly. Older user requests remain
verbatim in an intent ledger. The action ledger pins prior call IDs, names, exact
arguments, host approval/outcome metadata, and result excerpts with SHA-256,
original bytes, and shortened flag. Excerpts use at most 256 characters. Legacy
results without host classification remain historically unclassified; output text
cannot prove approval.

The summary request contains normalized older transcript JSON in one user message
under a separate summarization instruction. Older opaque/native reasoning is
excluded from that request; the full original stays in the journal. The provider
must return exactly three string arrays:

```json
{"decisions":["Keep changes local"],"facts":["The failing case is reproducible"],"open_questions":["Which input triggers it?"]}
```

Check the exact keys in `valid_summary_map?/1` when editing the schema. One exact
outer JSON Markdown fence is tolerated; surrounding prose, multiple documents,
extra/missing keys, non-string values, tool calls, and over-limit raw content refuse.
Summary JSON must fit 16,000 bytes, its request must fit the context ceiling, and
the resulting context must shrink below the trigger. Required ledgers/native data
are never trimmed to make the projection fit. Structural checks cannot establish
semantic fidelity of a model-written summary.

Summary inference uses the selected provider/model and consumes normal usage and
budget. Ollama summary-only config requests the schema, `think: false`, zero
temperature, and a 4,096-token cap narrowed by configured limits. Ordinary turns
retain their options. Summary deltas never go to the UI.

## Reduce old tool output when a summary cannot be planned

A single long turn may have no complete older prefix. The deterministic fallback
keeps every message, user/assistant text, call arguments, native continuation,
and host metadata. It shortens only eligible settled results over 4,096 bytes.
The two newest assistant tool-call batches, including all parallel results,
remain complete. Unknown, denied, historically unclassified, already reduced,
unresolved, or duplicated calls cannot be shortened.

Eligible output becomes an explicitly incomplete beginning/end excerpt of 256
characters each, original byte count, SHA-256, and a warning to inspect original
evidence before repeating an effect. This loses result text intentionally; it
never claims full semantic preservation. The whole projection must fit below the
trigger or nothing is saved. A later summary carries original provenance rather
than hashing the excerpt as if it were the source result.

## Commit once and restore deterministically

Session syncs `context_compacted` before changing its messages. Version 1 binds
the checkpoint, covered effective-message count, canonical JSON prefix digest,
and before/after sizes. `tool_results_compacted` instead binds original/projected
digests and deterministic result indices. Original `message` events remain intact.
Canonical digests sort JSON object keys recursively rather than depend on term
serialization.

Resume folds events in order, reconstructs unknown outcomes, validates covered
prefixes and checkpoint metadata, and applies only the effective projection.
Later messages survive. A damaged committed checkpoint stops recovery; no alternate
projection or inference is silently chosen. Owner death after commit retains the
checkpoint without replay. Cancellation does not save partial output.

`compaction_failed` records prepare/summary/validation stage with a bounded host
diagnosis. Raw provider errors are replaced with a static message. Oversized user
text, recent results, native payloads, or the pinned ledger can still prevent
reduction. A shorter continuation, explicit ceiling change, or reviewed fresh
session is an operator choice, never an automatic provider/billing switch.

## Practice a checkpoint change

Read the "preserves two recent user turns" fixture in `test/compaction_test.exs`.
Compare the recent native message before/after `finish/4`. Then read
`test/tool_result_compaction_test.exs` and identify why a denied result stays full
while an older approved settled result can become an excerpt.

```sh
mix test test/compaction_test.exs test/tool_result_compaction_test.exs test/compaction_session_test.exs
```

The pure suites establish projections and validation; Session fixtures establish
sync-before-replacement, accounting, cancellation, and recovery. When changing
checkpoint structure, test a committed corrupted field and a crash immediately
after commit. A smaller context alone does not prove safe recovery.

`Ipse.Diagnostics.context/3` measures exact encoded categories using the shared
trigger; it exports numbers and fixed labels, not source text. Saved inspection
uses pure restoration without replay. Explicit [handoff](../operator/recovery.md)
exports a bounded reviewed note into a fresh idle session, not native history,
permissions, or executable calls. Handoff validation and compaction remain separate.
