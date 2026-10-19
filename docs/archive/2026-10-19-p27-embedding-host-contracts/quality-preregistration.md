Historical preregistration, 2026-10-19. Copied from the local decision artifact before held-out exposure. Current acceptance is owned by [the plan](../../plan.md#p27-optional-research-graph-and-rag); this is a dated decision, not measured quality.

# P27 quality gate preregistration

Recorded before reading held-out corpus, qrels or expected answers. Root accepts
the execution and scoring distinctions in quality-execution-brief.md. This is a
decision, not measured evidence.

Require at least 90% supported answers or correct abstentions and at least 95%
semantic citation precision across the complete frozen workload. Report exact
denominators and independent blind semantic review of actual saved claims/spans.
Literal quote membership alone cannot establish semantic support. Use the first
prediction per variant/query for quality. Retain failed, partial and unavailable
rows and do not move these thresholds after seeing outcomes. Zero authority,
scope-isolation, automatic replay or suppression-resurrection failures is mandatory.

Recall@5 and source nDCG@10 are matched measurements, with source/span coverage
separate and empty relevant sets marked N/A. No invented numeric floor is added
to the plan. Report per-query results and paired deltas for lexical, graph,
extraction, dense, hybrid and rerank before selecting any optional engine.
Lexical must operate usefully with no embedding/model/network dependency.
No optional engine is selected merely because it exists or performs more model
work. Explain measured utility, cost and uncertainty; retain weak or failed rows.

Only available explicitly selected local embeddinggemma:latest and qwen3.5:9b
profiles may be used for actual model comparisons, with fresh recorded inventory
and frozen model/profile/destination digests. No model downloads, paid endpoints,
synthetic encoder substitution, provider fallback or unaccounted worker inference.
All product inference runs through Session and its real canonical accounting and
shared budgets. Report resource samples and their limits rather than claiming
whole-system peak memory or electricity measurements.

Implementation, tuning choices, prompts, command mappings, corpus generations,
metric code, policy and profiles still need a clean source/artifact freeze before
held-out prediction. Score only hashed finalized predictions. If exposed held-out
failures require changes, preserve them and identify a subsequent rerun as exposed,
never a new unseen hold-out. Full P27 remains open until the unchanged plan's
domain, lifecycle, quality, source/native/installed and platform gates all pass.
