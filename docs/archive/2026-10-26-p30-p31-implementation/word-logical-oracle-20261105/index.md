# Independent Word logical oracle, v17 failure and v18 repair — 2026-11-05

Historical engineering evidence only. The [plan](../../../plan.md#p31-usable-knowledge-and-prompt-assistance)
owns current acceptance; use the [Corpus procedure](../../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace)
and [extraction training](../../../developer/knowledge-extensions.md#inspect-the-extraction-boundary)
for current supported behavior. This packet does not qualify P31F, installed
document operation, model answers or general Word rendering.

## What was independently established

An independent author inspected all twelve existing exact-hash public DOCX
archives, D021–D030/V003-v1/v2, without reading the parser, candidate outputs or
question/answer gold. The [authoring and exposure record](author/authoring-plan.md)
discloses incidental permitted-plan aggregate exposure and the already exposed
remediation status. These synthetic-workload inputs cannot regain fresh held-out
status. The original [v16/v17 experiments](../word-independent-extraction-20261104.md)
and their outcomes are unchanged.

The author supplied complete literal logical text, source-node assignments and
visibility/revision dispositions before candidate results: 144 included blocks,
168 included and 36 excluded text nodes, covering every one of the 204 raw text
nodes. The excluded content is twelve tracked deletions and twenty-four footnote
layout-separator values. Separate block/story/document UTF-8 spans and raw
paragraph/table/annotation identities retain attribution without generated
marker text. No renderer, service or new dependency was needed for this bounded
logical-text oracle.

The [independent source review](checker/SOURCE-REVIEW-1.md) read every original
main-document XML, checked shared auxiliary parts by exact byte identity and
verified the raw-node/body/cell/part-wide paragraph crosswalk. The first actual
checker run passed on the host (exit 0, 0.35 seconds), retaining a concrete
metadata diagnostic: 36 absent heading-style values had serialized as string
`"nil"`. The [v1 receipt](checker/pure-check-receipt.json) and original oracle are
preserved; this was not a candidate/parser failure.

A separately frozen [v2 correction](author/v2-null-metadata-fix.md) changed only
those 36 metadata values to JSON null. The actual v2 checker passed (exit 0,
0.29 seconds), verifying the complete twelve original archives, all text/spans,
144 source-coordinate rows, 72 pinned raw nodefiles and strict equality of all
other v1/v2 data. The [v2 receipt](checker/pure-check-receipt-v2.json) records each
actual raw-node path/digest. The [independent oracle verdict](checker/ORACLE-VERDICT-V2.md)
was written and hashed **before** candidate inspection and comparison preparation.

| Immutable reference | SHA-256 |
| --- | --- |
| V1 expected oracle | `890fc96281f60bb73eee4d6a71d044edc2250bf5a30b147e8d585b2eb5f858ed` |
| V2 expected oracle | `e2af13b29bacd36da26490053f1f2b86b6ab37f0c418d43f553537ceb7851a47` |
| Independent v2 checker | `0c0f932090dd3753f28d79c8f4bd4949acf94a45a263dbd9dc8110715d4d4d65` |
| Actual v2 checker receipt | `0161cbbab7313e5f8d52926067903010c075ae389e37b75386a4b7299133eb71` |
| Frozen independent verdict | `24aab8d8d6eccabca80a49769ab8a654b93f2792565569262131bf8095fadee7` |

## Complete first v17 comparison: failed, preserved

After the oracle verdict, the existing complete v17 Corpus State artifact was
copied and pinned without rebuilding. Its [manifest](comparison/v17-extension.json)
SHA-256 is `cb8a100298ced95d615f058ee41c9fe10c0b8ae2d11c2bbca6e1144e25234a8e`.
The [comparison source](comparison/compare_existing_extractor.exs), SHA-256
`e5f6b945d57bb655cad8b66babf859fc44b88f5578b884e433ed63b2dfcbbe21`,
compared every expected block, complete text, exact source/annotation locators and
both State/Collection source-payload projections. The actor used existing SDK
paths and Jason for output serialization, started no Ipse application and
verified the complete artifact inventory before and after execution.
The original comparison-preexecution manifest retains the earlier `338d5870…`
reviewed adapter preimage, also preserved as `compare_existing_extractor.pre-jason.exs`.
Before execution, two reviewed changes selected Jason encoding and added the
post-run application-stopped assertion. The actual run used the complete
`e5f6b945…` source linked above; the earlier adapter was not run.

The actual host run exited **1 in 0.39 seconds: 0/12 bounded logical agreement**.
All twelve first extractions and twenty-four first payloads were retained before
diagnosis. The [complete comparison receipt](comparison/first-comparison-receipt.json)
and [original outcome pins](comparison/v17-first-failure.sha256) preserve the
failure. Each document emitted fourteen blocks instead of the independently
expected twelve: two reserved footnote layout separators became ordinary evidence
before the referenced note. Both payload profiles preserved the extra content;
they did not independently cause the error. No failed input was excluded or
relabelled, and no expected text was changed to accommodate the parser.

The causal source owner ignored footnote/endnote `w:type`, admitting separator
IDs into ordinary evidence and unresolved-anchor coverage. A focused source
repair selects recipe v18, suppresses recognized reserved layout types while
preserving original paragraph ordinals/all-ID validation, retains ordinary
negative and unreferenced notes, and keeps historical recipe contracts. The
[pre-format repair handoff](comparison/V18-FIX-HANDOFF.md) and
[source patch](comparison/v18-feature.patch) record the source repair and its
unexecuted focused controls at this checkpoint.

## Separate v18 remediation: complete logical agreement

After reviewing the focused source change and source-level peer review, the
integration owner formatted the affected files and observed the current
parser-free normal build finish successfully: 197 host source files and four
bundled artifacts. The newly built v18 artifact was then separately copied and
pinned. Its [manifest](comparison/v18/corpus-state-documents/extension.json)
SHA-256 is `9e806128f5864b3d77e8417475c5c03c4c65d5a1ac4465917224ee3b89764c6a`.
No v17 artifact or first outcome was replaced.

The complete [v17-to-v18 comparison-source diff](comparison/v18/comparison-v17-to-v18.diff)
was reviewed before execution. It changes the selected artifact/pins, expected
recipe and fresh output paths, preserving all independent expected content and
criteria. The [v18 comparison source](comparison/v18/compare_existing_extractor.exs)
SHA-256 is `d68087c1750e164a4a47a4934e069f89dea7c1970e82ceb533775064c0fba118`.
The actual host invocation used the current normal sixteen SDK paths and Jason,
35-second wall/30-second CPU bounds, and exited **0 in 0.40 seconds**, terminal
handle `077d53`.

The [complete v18 receipt](comparison/v18/first-comparison-receipt.json), SHA-256
`f4e1b04553bf68916d75cc4060f845ef8823e4f378708daaf9c95390c21090ff`,
records **12/12 bounded logical agreement**: all 144 ordered blocks, complete
UTF-8 text, exact source/table/annotation locators and twenty-four State/Collection
payload projections agreed with the independently checked oracle. The complete
28-file artifact inventory remained unchanged. Every v18 first extraction and
both payloads are retained separately from the twelve v17 failures.

**All twelve v18 documents remain partial.** Their body-table-formatting
`unsupported_word_content` warning remains; the separator-induced unresolved
footnote-anchor warning is gone. Logical agreement is not complete coverage or
rendered fidelity. No Ipse application, native helper, model or installed runtime
was used by this pure comparison, and it proves no stored commit or actual
query-citation join.

The exact formatted source/test snapshot used for this repair is retained under
`comparison/v18/source/`, with original repository paths and byte hashes in the
provenance inventory and [formatted-source manifest](v18-formatted-source.sha256).
The complete three-file Word regression selection then passed **50 tests in
110.6 seconds, seed 738180**, with no failures. Nested helper cases are not added
again to that outer total. The [verification receipts](verification-receipts.json)
record the exact selected files and host build/test log hashes; private logs
are not copied into this public packet. The source snapshot was rechecked against
the actual formatted repository files after the run.

The parser-free offline build used the existing dependency cache and test Mix
environment. It is not a clean release/package verification. Format/documentation
checks and demo remain with the integration owner; this packet does not claim
their pending outcomes. **Installed joins and broader Word/answer-quality
acceptance remain open.** The build, fifty focused tests and pure comparison do
not substitute for those separate receipts.

## Limits and provenance

The source cohort contains a simple table, one insertion/deletion pair and
referenced footnote/comment per document. It contains no style inheritance,
direct hidden runs, lists, headers/footers, endnotes or complex layout. This
packet gains no quality coverage for absent features and makes no page-layout
or Microsoft Word rendering claim.

Historical **62/62 full locators remain unverified**. The source crosswalk does
not establish the private gold's paragraph conventions; revision kind/ID remain
oracle provenance rather than authenticated product locator fields. No original
field, denominator or threshold is removed. Stored/cited installed lifecycle,
actual selected-route answers, independent semantic review, larger workload,
capacity and other P31 gates remain separate.

Oracle and outcome evidence originated under
`_build/verification/word-independent-oracle-20261105-01/`; the v18 source snapshot
comes from its exact repository source/test paths. Archive date is 2026-11-05.
[provenance.tsv](provenance.tsv) maps every copied file to its original repository
path and byte hash. Bodies, original receipts/manifests and
historical scratch paths were retained byte-for-byte. They are provenance, not
portable commands or assertions that scratch files still exist. No archived
script was rewritten or executed while archiving. The packet binds artifact
bytes rather than asserting an unrecorded source commit for that artifact.

The original input files remain at their pinned public fixture paths in the
repository; raw XML/node evidence is included here for inspection. The earlier
raw-reader Unicode failure is retained as an authoring-tool first attempt, not
relabelled as a parser result. No executable binaries, native/Session journals,
private answers, transcripts, credentials or personal codes are included.
[evidence.sha256](evidence.sha256) inventories these archive-relative bytes; the
unchanged original manifests keep their original path conventions. The integration
owner maintains current plan/index links and records later checks separately.
