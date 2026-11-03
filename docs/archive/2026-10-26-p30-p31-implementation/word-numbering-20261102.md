# Bounded Word numbering locators

2026-11-02. This is a scoped implementation record, not P31F acceptance.
The [plan](../../plan.md) owns current milestone status; the [Corpus manual](../../operator/corpus.md)
describes the operator-facing behavior.

DOCX recipe v16 adds a bounded direct, single-level decimal numbering subset.
It checks the internal numbering relationship and content type, tracks independent
list instances in body order, and records the derived label separately in locator
metadata. The label is not source text and is not part of a literal quote. Older
v14 and v15 sources and citations retain their original recipes. The manuals
describe the supported subset and refusals; numbering parts still make coverage
partial and this work does not establish general Word rendering fidelity.

Independent source review found two defects before acceptance: ambiguous v16
multi-block span coordinates and mixed WordprocessingML dialects across parsed
parts. The implementation now emits fixed nullable v16 citation span positions
and refuses mixed dialects for numbered extraction. The reviewer rechecked those
repairs; this was a scoped source review, not a final adversarial audit or a claim
that mixed packages are invalid under the format standard.

## Verification

The isolated snapshot was based on `530bd1b5719ecd27299cb5692af4b1b9e0f3a955`
with only the eleven changed Word files overlaid. Its separate dependency, build
and home directories avoided concurrent work. The [fingerprints](word-numbering-20261102.sha256)
identify the tested files. The snapshot and logs were retained at
`/tmp/ipse-docx-review-Fje6Jlkk` during this work; temporary paths are not durable
project artifacts.

- Formatting passed for the selected files. Numbering fidelity: 3 passed,
  29 excluded, seed 271538. Native State and Collection Session numbering:
  2 passed, 24 excluded, seed 765880.
- The broader document, paragraph packing, ingestion and fidelity batch passed
  50 tests, seed 558752, including its freshly built Corpus artifact probe.
  These fixtures do not independently establish Word rendering quality.
- The documentation checker passed 1,079 Markdown files and 8,878 links after
  this receipt and the plan update were added to the indexed isolated snapshot.
  Its first raw-snapshot run failed because it did not have Git metadata.
- The separate PDF-enabled verifier was not run: its offline native build stopped
  when the sandbox denied `sccache`. No dependency was fetched. The full source
  suite, exact installed package, independent Word-quality assessment, lifecycle
  and populated storage qualification remain open on the final integration.
