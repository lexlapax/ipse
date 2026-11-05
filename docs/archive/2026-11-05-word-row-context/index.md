# Word table-row context checkpoint — 2026-11-05

Historical source-runtime evidence. Current instructions belong to the
[Corpus user manual](../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace)
and [knowledge-extension training](../../developer/knowledge-extensions.md).
The [plan](../../plan.md) owns remaining acceptance. Provenance is the inspected
source and execution hashes below; no superseded manual body is copied.

This record covers a bounded Corpus retrieval change and its source-runtime checks. It does not close the installed Word qualification or establish general Word fidelity or answer quality. The checks below were run in the source checkout on 2026-11-05; later package and installed results require their own binding and record.

## Behavior and boundaries

A direct BM25 snapshot query retains its positive lexical hits first. When one has a single-block Word table-cell locator, remaining `top_k` slots may contain source-exact chunks from different cells in the same source version, part, table, row, and applicable region or annotation. These companions have `method: "table_context"` and score zero. They are nearby evidence, not lexical scores or a claim that the text answers the question. Ordinary citation validation, acquired-file checks and final store revalidation still apply. Stored document blocks and ingestion recipes do not change.

The additional scan is skipped when there is no qualifying table-cell hit. `coverage.table_context` reports the supported single-block chunk scope, returned count, and whether eligible chunks exceeded remaining slots. A chunk crossing original blocks is not expanded; an untruncated result does not prove row completeness. Long citations retain their existing quote bound. Optional reranking can change returned order. The indexed Collection namespace query, hybrid and graph component ranking, and independent Research do not gain this expansion.

## Verification

| Check | Observed result | Scope |
| --- | --- | --- |
| Relevant three-file suite before the no-anchor guard | 59 passed, 1 skipped, 6 excluded; 173.0 s | Source-runtime regression, including the new row-context cases. |
| Evidence and row-context tests after the guard | 32 passed; 37.3 s | Focused source-runtime regression, including no-hit and paragraph-only equivalence. |
| New State and Collection Session cases after the guard | 2 passed, 32 excluded; 24.2 s | Fresh synthetic workspace-document acquisition, citation, and changed-file refusal. |
| Bundle refresh | Four inert bundled artifacts rebuilt | No installed-package qualification follows from the rebuild. |
| Formatting and strict compilation | Passed | Source checkout; warnings treated as errors. |
| Credential-free demo | Passed on second attempt | First attempt failed during environment/toolchain setup; no dependency was installed in that attempt. |

These suites overlap and must not be added together as independent cases. The full three-file suite was not rerun after the guard; the post-guard checks are the two focused rows above. Native/optional cases excluded by the test command and the skipped public-document case were not exercised by this suite.

The first two-case Session attempt failed both cases: the fixture required staging for a small document that can publish immediately, and the Collection case used a stale shipped artifact before bundle refresh. The fixture was corrected to accept either documented publication path, and the artifacts were refreshed. An earlier full suite then failed eight executions at six stale v17 assertions for newly extracted documents; those assertions were corrected to v18. Explicit historical v17 compatibility controls remain unchanged. The failed attempts remain failures, not retroactive passes.

Before this change, an installed attempt stopped after two of 24 planned source/profile cases: the first State case produced five of six citation joins, and the following Collection case refused before acquisition on an unsupported protected-storage filesystem. The remaining cases were not dispatched. A separate fresh public admission probe on the supported tmpfs profile succeeded. This identifies a supported execution location; it does not repair or reclassify the failed installed attempt. A fresh package built from the final reviewed change and the complete installed run remain open. No private questions, expected values, transcripts, or approval inputs are included in this record.

The operator Corpus and developer knowledge-extension chapters were reviewed as whole documents; the private revisions explain row context and its scope in the existing retrieval and Word sections. Local referenced paths were checked. The documentation checker and any final source/package checks must be reported from their actual later results.

## Source identities

SHA-256 values identify the inspected checkout bytes; they do not establish a commit or package provenance.

| Path | SHA-256 |
| --- | --- |
| `extensions/knowledge/src/evidence.ex` | `12c58708d0e7aeca7bab37d1d32abee9e5ac5422ce86682dacb1ad745338d5b8` |
| `extensions/knowledge/src/corpus.ex` | `6673342151a16df044d3c120b7ada8797d985875af3c3d9650918b7744f6a1cc` |
| `test/extensions/knowledge/document_row_context_test.exs` | `33d8496a9ab623cd4bf4a7010843b3410c785881a0bf2d7155982c549fdf95d0` |
| `test/extensions/knowledge/document_acquisition_session_test.exs` | `8fc7d2a79615dd5a28440ddf6542022e973ce32218f1eb1f3af10e0d63b3cc02` |
| `docs/operator/corpus.md` | `a6a63aa68f5ff57ae6863b0c98bd540de43ac5ba6550f241454c0aaf238301bf` |
| `docs/developer/knowledge-extensions.md` | `68b5ef3ad56cf62f82576de9c55e449be227af8ea27b5c6e6035dc650fafe8a9` |

## Retained check identities

The following SHA-256 values bind the private local check logs without reproducing their contents. They are receipts for these executions, not independent verification of their claims.

| Check | Log SHA-256 |
| --- | --- |
| Earlier failed focused Session attempt | `33121090406a26c4796167f9239fb6502cfb2e8475eea2ed3e6bebeb2eee01ec` |
| Earlier failed full suite | `fc2ab743525d8e6fc41f14ff4b55914fd7165f41691fedecdaffc625131b4191` |
| Pre-guard full suite | `d7822c41524f11f041ef84a6ccd6b96df807ddd636ac62a807461487117d4343` |
| Post-guard evidence/row tests | `06753c3a73ff00c798a5f4e07347cfb623529af34f5b1ce96bd1bd50f5021e9e` |
| Post-guard two-profile Session tests | `ec8615fdea99ffc3e6efaaba0a85ddbd091ff6218356659f54775e49fa7fcdcc` |
| Bundled artifact refresh | `04880fc72dd1a88907e5bd5109913353b91786478dff8a18085e204f1f163b8c` |
| Failed demo setup | `41dcec1bc7877980a32c2502e02a091d756cd4efeb15b8b6d83628030bceae73` |
| Successful demo | `4d519054e66315e7d9f448d9b55943942bd4c5925ebc183149d477ddc30ed76f` |
