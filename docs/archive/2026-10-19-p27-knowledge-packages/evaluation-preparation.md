# Evaluation preparation and local tuning, 2026-10-19

Historical evidence after the independent package checkpoint at `bce8624`.
The commit containing this record adds pure answer preparation and scoring
helpers. Use the [evaluation training chapter](../../developer/knowledge-evaluation.md)
for current interfaces. Full P27 acceptance remains in the
[plan](../../plan.md#p27-optional-research-graph-and-rag).

## Synthetic helper verification

The first helper run found three failures: Elixir's `JSON.decode/3` requires
keyword options, but the new answer helper passed a map. The decoder adapter was
corrected. The final combined answer/scorer/metric suites pass 20 tests. They
exercise UTF8 cropping and citation mapping, strict JSON and reference refusal,
all hashes and rows before label loaders, missing/failed/N/A rows, exact and
contained byte spans, independent review and retrieval-only support remaining
unmeasured. No held-out input or model service participates in those tests.

## Actual embedding tuning

An earlier tuning-only run used two permitted synthetic sources and the existing
local `embeddinggemma:latest` model with native 768-coordinate vectors. Three
accounted requests indexed both sources and answered one cosine query. They
reported 75 input tokens. The same shared budget refused the fourth requested
query; read-only inspection after exhaustion succeeded. Cleanup was confirmed.

The prototype exited one because it incorrectly expected Session accounting to
exclude the refused fourth attempt. An offline audit of the original saved
journal, usage and budget passed without repeating inference. Accounting retains
four attempts; the budget books three requests and one refusal. The original
prototype failure remains part of this result.

## Actual text tuning

The initial text prototype made zero model calls. A four-fact extraction request
exceeded the conservative publication effect plan. The prototype's text approval
validator also wrongly required an embedding-style effect binding. Both refusal
paths were retained. A corrected prototype used a fixed allocation of four
requests, one-fact extraction batches and the actual full text approval shape.

The corrected run used the existing local `qwen3.5:9b` model with an explicit
1024 output-token cap. It admitted four requests through one Session and shared
budget. Both extraction calls and reranking returned host-call failures. One
answer call completed with strict cited JSON mapped to the actual shown source.
No response was retried, no provider/model fallback occurred, and cleanup was
confirmed. The failed paths did not retain token observations, so their usage
remains unknown. The completed answer reported 574 input and 449 output tokens.
The budget retained reservations for all three failed requests, booking 12,862
input tokens and 12,737 output tokens within the 16,384 limits. The request limit
of four was exhausted. This evidence does not establish the causes of the three
host failures or successful domain extraction/reranking.

The decoded answer artifact SHA-256 is
`238ccf638c440f3a0579db134cb7249ff4cfe386399f98771a5f3fce78d64c68`.
Its syntactic citation mapping passed; independent semantic support was not
measured. No cost rate card or money policy was configured, so costs are
unpriced, not zero. Production domain modules remained unloaded in the host.

Fresh metadata-only inventories matched the existing local aliases and digests:

| Alias | SHA-256 |
| --- | --- |
| `embeddinggemma:latest` | `85462619ee721b466c5927d109d4cb765861907d5417b9109caebc4e614679f1` |
| `qwen3.5:9b` | `6488c96fa5faab64bb65cbd30d4289e20e6130ef535a93ef9a49f42eda893ea7` |

No models were downloaded and no paid endpoint was used. These runs use only
permitted tuning data. The independently authored held-out workload remains
sealed pending a clean implementation, profile, prompt and evaluator freeze.
Actual matched comparisons, failure controls and independent semantic review
remain required before optional engine selection or milestone completion.
