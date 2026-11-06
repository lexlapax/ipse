# Supplied-Word retrieval comparison, 2026-11-06

This record reports a bounded comparison within each of 12 supplied Word
documents. It is not completion of P31: the [current plan](../../plan.md)
owns milestone acceptance. The earlier [installed acquisition result](../2026-11-05-word-installed-row-context/index.md)
remains unchanged, including its 122/124 citation joins.

The fixed cohort paired 76 public source/question combinations with both the
existing BM25 route and an explicitly selected local
`qwen3-embedding:0.6b-q8_0` route. Both methods used the same supplied bytes,
within-document State store and `top_k: 10`. The dense route used native
1,024-dimensional embeddings. No fallback, download or extra warmup was used.
This path does not establish installed acquisition or current-file revalidation.
The source extraction receipts retained their existing partial status and
unsupported-Word-content warning.

The single fresh run completed with all 152 result slots recorded and confirmed;
all 152 result statuses were `partial`. Twelve source cases closed and each
passed its same-ID idle/no-replay check. The run recorded 148 completed
embedding requests and 10,081 input bytes. Its separately declared metadata
HTTP ceiling was 1,788; that ceiling is not a count of actual metadata requests.
The [call-accounting record](live-call-accounting.md) adds these 148 requests
to the prior five conservatively charged local attempts.

After the first results and their source, runtime, artifact and ownership
postchecks were independently frozen, one unchanged scorer joined them to 62
frozen expected support slots per method. It found a returned citation matching
the expected support and byte/locator checks in **61/62 BM25 slots** and
**62/62 dense slots**. BM25 returned empty evidence for one of these support
slots; dense returned none empty among them. The [safe aggregate](word-semantic-supplied-comparison-20261106.json)
contains counts without private prompts or expected text.

These are returned-support coverage and citation-fidelity observations for this
cohort. The test does not measure precision, the relevance of other returned
chunks, model-answer quality, general Word coverage or whether dense retrieval
should become a default. It does not establish that revision kind or revision
ID fields are returned. Other sources and changing files were not tested by this
comparison.

The fresh runtime was built from commit `2a56c60b8f8bcabe047f189d37f82f4e12cb8b5a`
and used the separately prepared state-dense artifact. Before execution, the
original `/dev/shm` 256 MiB allocation check failed with user quota exhaustion.
A fresh native quota check and equivalent allocation passed on the existing
per-user tmpfs used by this run, with more than 4 GiB filesystem space and 3 GiB
available memory at preflight. Those observations are not a guarantee of peak
space for every possible outcome. The earlier failed
[comparison attempt](word-semantic-03-failure-20261106.md) remains separate and
was not replayed.

The frozen first-result manifest SHA-256 is
`32c082d0e9617b31e0447f32803effe9a1b00d4611c0b673a97c1044fd9f24bf`;
the retained-input inventory is
`35c7975c185c2d75a2cdce6eae059022885a0cba2c2a97f4ff2fd351d73a706e`.
The scorer and all retained input hashes passed before and after the single
scoring run. Outer and independent checks found no remaining owned process or
shared Input holder. Private results and detailed per-question scoring remain in
the local verification workspace; this record publishes only safe aggregates.
