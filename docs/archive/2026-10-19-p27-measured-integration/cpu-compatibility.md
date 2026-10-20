# Selected local runtime CPU compatibility

Historical verification record, 2026-10-19. This is a two-request runtime check
of source `81a4387d187d46a1c559e6738672b705dc76be11`, not a retrieval-quality or
exact-memory comparison. Use the [knowledge evaluation chapter](../../developer/knowledge-evaluation.md) for current
procedures and the [plan](../../plan.md#p27-optional-research-graph-and-rag) for outstanding P27 acceptance.

The user selected CPU-only execution and an optional Linux backend measuring
workload-charged RAM. The private execution selected existing local model files
by the original manifest hashes. It downloaded nothing and did not contact or
change an existing model daemon, shared cache or system tag. Every selected blob
was verified by a full SHA256 read before the trial. The model owner then made
fresh regular private copies of the manifest/blob closure and 44 explicitly
hashed runtime files, including required library aliases. Those runtime files
totalled 1,783,553,138 bytes. Runtime paths are local provenance, not experiment
admission requirements.

| Model | Raw manifest SHA256 |
| --- | --- |
| `qwen3.5:9b` | `6488c96fa5faab64bb65cbd30d4289e20e6130ef535a93ef9a49f42eda893ea7` |
| `embeddinggemma:latest` | `85462619ee721b466c5927d109d4cb765861907d5417b9109caebc4e614679f1` |

One fresh `EvaluationModelService` lifetime guarded an ordinary public Session.
The selected inference profiles kept the original model names, native embedding
dimensions, text cap, disabled thinking and 120-second deadlines. The Session
allowed exactly two inference requests with finite input/output reservations.
Approval checked each complete request, execution binding and destination against
the selected public host contract. Conversational inference was forbidden.

| Operation | Observed result | Canonical duration | Usage |
| --- | --- | ---: | --- |
| Embedding | One complete 768-coordinate vector reconstructed through result pages, 3,072 bytes | 1,050 ms | 7 input tokens, output not applicable |
| Text completion | `CPU compatibility confirmed` | 6,831 ms | 105 input and 4 output tokens |

Both canonical requests were `completed`, `final` and `totals_known`. Read-only
journal/budget reconciliation booked 112 input tokens, four output tokens and
two requests, with zero unknown liability, unsettled requests, refusals or
overdrawn dimensions. No rate card was selected, so this is unpriced accounting.
There was no retry, provider fallback or renewed allowance.

The native daemon log observed `library=cpu`, a loaded CPU backend and zero total
VRAM. Initial residency was empty. Final inventory contained both selected model
digests with `size_vram: 0`. The full owned lifetime lasted 27,025 ms, including
private staging and inventory. Session, staging and native cleanup were confirmed.
These observations establish compatibility under the selected CPU policy. They
do not prove every transient device allocation, semantic retrieval quality,
whole-comparison latency or an exact memory peak.

The retained CPU declaration SHA256 is
`807c54c20cdffd797b2abebb43aa32559ce4a91e23f339378c2e7df41e52e685`.
The closed verification SHA256 is
`9200f9e648a2febd6d1cc79aa36760b41cc5ae29ffc1ee184040c6cb119f06ec`.
Its evidence list binds the original declarations, command results, complete
canonical usage export, accounting, cleanup acknowledgment and bounded native
log prefix. The private original receipts remain retained for inspection.

Two earlier preparations made no inference. The first exposed the legacy v1
tuning runner's fixed model origin and refused plan validation. A second
compile review caught an unavailable Session attachment function before its
execution. The successful preparation instead used the repository's actual
owned public Session construction and existing embedding/text command artifacts.
These preparation failures did not consume or replay a model request. Neither
was counted as a completed runtime proof.

The separate measured comparison requires its own immutable source, seal,
fresh per-cell daemon/cache copies and native population. Its outcomes require
post-exit audit and independent semantic review. The
[superseded comparison](interrupted-comparison.md) was intentionally stopped
before completion. The original dataset appeared
in the interrupted comparison; repeating it produces a repaired/reused-set result,
not a new untouched held-out quality claim. P27 remains incomplete.
