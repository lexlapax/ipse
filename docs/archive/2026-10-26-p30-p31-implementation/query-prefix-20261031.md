# Explicit domain embedding-query formatting

2026-10-31, source increment based on `bc5ef75`, isolated from the main checkout's
frozen `c7cb484` full-suite run. This is a bounded retrieval configuration change,
not local-model quality, Collection dense querying or full P31D1/F acceptance.
Current guidance belongs to the [Corpus procedure](../../operator/corpus.md#choose-an-embedding-query-format)
and [vector training](../../developer/knowledge-extensions.md#authenticate-embeddings-and-their-complete-vectors).

## Behavior and ownership

Dense/hybrid retrieval profiles optionally select `query_prefix`, a nonempty
valid UTF-8 string of at most 1024 bytes without NUL. The existing domain profile
validator rejects that field on lexical, graph, remote-query and embedding
profiles. `Corpus.rank_query/2` concatenates the selected prefix with the original
query exactly once before the normal embedding adapter. Absent prefixes retain
the original request. It neither infers a format from a model name nor selects
a provider/model. The [Qwen model card](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B)
documents the motivating asymmetric retrieval format: an instruction on queries,
with original passages used for document embeddings.

The original query remains available to lexical ranking, reranking and citation
selection. Source indexing and stored document vectors are unchanged. The normal
host approval/intent binds the complete dispatched input, and the existing
canonical input digest checks every returned vector page. The host selection
digest still identifies its embedding configuration, not domain query formatting
or actual weights. Freeze the artifact/options and dispatched inputs separately
for evaluation. No core, native protocol, SDK shape or dependency was added.

Collection namespace queries remain lexical-only. The option applies to existing
State/MCP dense/hybrid queries, not to an unimplemented Collection query path.
Changing the query format alone does not require document reindexing because the
stored passage inputs remain the same. A changed embedding configuration retains
its existing incompatibility/reindex rules.

## Executed controls

- Profile/public Corpus/built-artifact selection: **10 passed, 14.8 seconds**,
  `/tmp/ipse-query-prefix-focused-20261031.log`. The public driver indexes and
  queries through both dense/hybrid routes with and without a prefix. It checks
  raw document input, exact query input, original citation and unchanged stored
  records. The validation grid includes byte limits, empty/NUL values and
  wrong-owner fields.
- Strengthened fresh-artifact control: **1 passed, 2.6 seconds**,
  `/tmp/ipse-query-prefix-artifact-20261031.log`. The built `state-dense` artifact
  runs with only the minimal public SDK and dependencies, and emits the exact
  prefixed Unicode input from a public Corpus query. Session/context host modules
  remain absent from that isolated VM. Existing vector-page wrong-input refusal
  also passes.
- Existing package/domain/producer configuration/progression selection:
  **25 passed, 204.6 seconds**,
  `/tmp/ipse-query-prefix-regression-20261031.log`. Nested child summaries are
  separate from this completed parent result.
- Standard build: 179 host modules and three inert bundles. Formatting,
  warnings-as-errors compile and credential-free demo passed. Logs use the
  `/tmp/ipse-query-prefix-{build,format,compile,demo}-20261031.log` prefix.

The affected Corpus and Knowledge training chapters were reviewed with their
existing setup, query, vector identity and recovery flow; the new procedure is
integrated before querying rather than appended as a feature report. Entry-point
ownership is unchanged. The documentation checker validates the links and manual
rules. These controls use synthetic embeddings; no real inference, model load,
download or service configuration change ran. No new extracted-package run is
claimed for this increment. Integration into the main checkout, complete suite,
independent quality and final audit/handoff remain open.
