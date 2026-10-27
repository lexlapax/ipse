# Versioned reference projection increment

Historical engineering record, **2026-10-26**, on `codex/p30-p31` after
`a91dedb`. The [plan](../../plan.md) owns delivery status, the
[context chapter](../../developer/workspace-context.md) teaches current behavior,
and the [baseline](baseline.md#turn-local-context-and-cache-preservation) owns the
remaining integrated acceptance contract. This is an incremental audit, not the
post-implementation audit of P30/P31.

## Implemented boundary

New Session metadata selects `turn_reference_v1`. The first model boundary admits
the seeded header, publisher baselines and ordered tool digest. Runtime response
metadata, scoped workspace changes, skill-catalog changes and extension selections
append as labelled user data after complete native history. Existing occurrences
are unchanged. Full active selections repeat on later real user turns; unchanged
same-turn continuation adds nothing. Explicit refresh and compaction record epochs.
The saved-result reader is declared while empty. A changed catalog stops inference
until a reviewed refresh or fresh session. Legacy sessions retain their original
layout, conditional reader and reconstruction behavior.

Private records bind identity, epoch, position, generations and exact hashes.
Replay binds an envelope to the latest committed input turn, rather than accepting
a syntactically valid arbitrary turn ID. Orphan input at interruption remains
inspectable but cannot authorize an envelope. Reference messages are excluded from
the compactor's real-user turn count and pinned intent ledger. Encoded measurements
still include them. Each main adapter's actual body builder is exercised; Ollama's
existing body construction is now exposed as the same pure builder used by its
live transport.

Versioned context publication counts nested encoding and common reference framing
against the existing 16,384-byte aggregate. A durable admitted replacement intent
invalidates only that caller's previous selection, before execution. A committed
replacement remains even if the later callback fails. Other publishers and legacy
semantics remain separate. No inference is performed to repair context.

## Independent adversarial findings and repairs

The independent auditor inspected source and used separate focused fixtures. Root
reviewed/integrated the repairs:

1. Replay initially checked overall envelope size without repeating the final
   extension-specific ceiling. Rehashed oversized selections could restore.
   Replay and live preparation now enforce the same bound.
2. Reference reconstruction initially synthesized missing tool outcomes at the
   reference insertion boundary. A crafted record could split a native group.
   Unknown materialization is now restricted to a genuine next-user recovery
   boundary or final interrupted reconstruction. References and projection
   replacements require closed groups; streaming native-order checks reject
   orphan, duplicate, malformed and split results.
3. Result-time invalidation alone missed an admitted replacement whose worker
   died before committing a result. Live Session admission and Actions replay now
   invalidate the caller at the durable intent. Interrupted-prefix tests compare
   versioned invalidation with preserved legacy behavior.
4. Existing reconstruction sorted completed results into call order, which could
   rewrite a genuine delayed clarification answer. Versioned reconstruction now
   retains recorded result order and appends only missing unknowns. An actual
   Session `ask_operator` batch/answer/close/resume test checks the serialized
   prefix. Legacy reconstruction remains unchanged.
5. Syntax-only envelope turn checks accepted an unrelated valid-looking ID.
   Transient replay binding validates input receipts and activates their turn
   only after the matching effective user message; wrong/orphan/stale/closed-turn
   references refuse. These checks add no persistent/live Reference state fields.

The validator for native group order is shared by live preparation and Saved
streaming reconstruction. Replay maintains the pending group incrementally;
full projection revalidation happens on replacement, avoiding a full-history
scan for every unrelated journal record.

## Verification and limits

Early focused failures exposed old mutable-header/tail-placement expectations and
an incomplete malformed-record guard. Their repaired assertions check the new
placement and exact legacy behavior. The intermediate combined run passed
210/212 tests; the remaining two assertions inspected the admitted reference
instead of the current/historical tail occurrence. The subsequent publisher/wire
regression run passed **40 tests**. The independent latest replay/context suite
passed **90 tests** after turn-binding repairs. The final combined Session,
input/recovery, workspace, publisher and provider suite passed **234 tests** in
51.1 seconds, with strict compilation. Relevant operator/developer chapters were
reviewed as documents and reconciled; the documentation checker passed 475
Markdown files and 4,307 local links with zero errors. Full fixed-source/package
receipts remain separate; none is inferred from these component counts.

The first fixed-source full run at `221fa2d` subsequently exposed three more
old-layout assumptions: the conformance model inspected only the old second
message, and two saved-result tests expected the reader declaration to appear
only after publication. The checker now inspects the latest valid reference
selection and keeps real-user matching separate. Reader tests assert unchanged
tools before/after publication while retaining the actual unauthorized-read
refusal checks. The repaired conformance/result-reader/decision regression run
passed 27 tests; the original full run remains a failed-run receipt, with final
counts and later baseline evidence recorded separately.

The same full run also exposed Gemini's signed-loop fixture treating the last
content as a tool result, and the source lab treating the last message as real
input/the second message as current recall. Gemini now checks the actual result
followed by the labelled reference while preserving earlier contents, signatures,
tools and system bytes. The lab selects real input and current reference by their
roles/validated markers. Focused reruns passed **3 Gemini tests** and the complete
**one-test source lab**. The fixed `221fa2d` suite finished with **1883/1888 passed,
one skipped, 36 excluded** in 1057.7 seconds: exactly these five known fixture
failures. Its chained demo/package/installed steps did not run after failure.

Wire fixtures cover ChatGPT, OpenAI, Ollama, Anthropic, Gemini, OpenRouter,
Grok API, Grok subscription and explicit compatible-local routes. They verify
unchanged earlier serialized messages/tools, tail role, and signed Anthropic/Gemini
continuation. They contact no service and establish no model/account eligibility,
cache-hit rate, latency improvement or semantic quality.

This increment does not complete C0 or E: source-index/evidence paging, managed
lineage retraction, semantic consent/modes and capture/recall remain required.
The existing generic policy generation is zero. Malformed proposals rejected
before an admitted replacement intent are not a durable replacement; the final
managed-publisher lifecycle still needs its freshness/coverage qualification.
Full automatic knowledge enablement and sustainable storage are not implied.
