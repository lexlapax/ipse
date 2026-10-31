# DOCX text structure follow-up

2026-10-27. This records an uncommitted P31F source correction, not Word
qualification or an installed ingestion workflow. The earlier
[parser receipt](document-parsers.md) describes the preceding recipes.

Two synthetic counterexamples reproduced incorrect v3 results. A `w:t` directly
inside a paragraph, outside a run, was returned as complete text. A valid
paragraph tab-stop declaration was emitted as a literal leading tab. The
extractor now requires text and text controls to be direct run children,
recognizes paragraph tab-stop declarations without emitting text, and retains a
partial-coverage warning for their unsupported layout. Actual run tabs still
produce tabs. DOCX now reports `ipse-documents-v4`; consumers must not assume
earlier extraction recipes are equivalent or silently reuse their indexes.

The two pre-fix focused tests failed as expected (seeds 20270423 and 20270424).
The DOCX fidelity and document suites passed 25 tests on the working tree (seeds
20270425 and 20270426) and on an isolated graph based on `668e6a3` with only the
four selected source and test files overlaid (seed 20270427). Its tree was
`eee6682cf02c32edefba75483a19c74d58f0b49a`, and tracked bytes still matched the
index after the run. The clean graph compiled without the copied native helper,
so it emitted an expected missing-helper warning; this is not a strict whole-host
compile. A separately built `corpus/state-lexical` artifact reported the v4 recipe
in an isolated VM. This checks artifact inclusion, not installed acquisition or
quality. The initial temporary graph attempt exceeded the `/tmp` quota and its
own partial directory was removed; the successful graph is under `_build`.

Source SHA-256 values: `docx.ex`
`6ac7e9fb520f955c9db5a6c9465cccc4460b08428f46486bf95ce965d25dad94`;
`documents.ex` `4bee402570e091de6083153838ab7b97b813d1099e9e54a2d199eeea24d037b6`;
fidelity test `5b56ae825db166559e1579aae5788178d2d8568384c0a8b492428750df1b5f52`;
document test `19e08b5f754135f77db872fbeb73f140051c9f74aa4cf639a13ec161709d8633`.

The tests are synthetic and do not establish real Word compatibility, citation
quality, protected source acquisition, migration or the P31F acceptance gate.
The changes require adversarial review and the full applicable checks before a
focused commit and push. The unadmitted native host limitation remains separate.

## Subsequent v5 continuation

A synthetic malformed paragraph placed a run inside paragraph properties. With
seed 20270702 the v4 extractor emitted that metadata text as ordinary paragraph
content and reported complete coverage. The uncommitted v5 recipe refuses a run
inside the recognized paragraph, run, table, row, cell, section or table-grid
property containers, including when an insertion wrapper is nested inside them.
Ordinary inserted runs remain supported. This conservative check addresses the
reproduced structure; it is not a general OOXML schema validator or real Word
qualification. Existing v4 indexes must not be silently treated as v5 output.
The working-tree document suites passed 26 tests with seed 20270703. An isolated
graph based on the earlier v4 graph with the four changed source and test files
overlaid had tree `e2c478a0de85d61104403ce1880ac59360a66e0e`; the same suites
passed 26 tests with seed 20270704 and one case at a time. These are synthetic
tests, not installed acquisition, migration or Word interoperability evidence.

A fresh `corpus/state-lexical` artifact built from the isolated v5 source graph
was loaded in a separate VM. A synthetic probe confirmed the v5 recipe, refusal
of a run in paragraph properties, and normal visible-text extraction from the
artifact's own beam. The probe is now part of the document fidelity suite. With
the added test and support file, fixed tree
`daeeee2fe4a55fa7b72985854fb74d3d6367b732` passed 27 document tests with seed
20270706 and one case at a time. The isolated graph emitted the expected warning
about its missing native helper; this is not strict host compilation or installed
workflow qualification. The frozen independent qualification set was not run.

## Subsequent v6 continuation

The v5 extractor accepted both strict and transitional Word namespaces but
selected the first matching attribute when an element supplied both forms of
the same name. A synthetic run with contradictory visibility values therefore
returned the text and claimed complete coverage. That pre-fix test failed with
seed 46290. The uncommitted v6 recipe refuses duplicate recognized attributes
in both document content and style metadata, including equal duplicates and
either attribute order. A single strict-namespace visibility attribute remains
supported. The recipe version changes so earlier extracted indexes cannot be
mistaken for v6 output. This is a conservative ambiguity check, not a complete
OOXML schema validator or real Word qualification.
The working-tree document and fidelity suites passed 28 tests (seed 46291),
including a fresh artifact build and extraction probe. The five changed Elixir
files passed the formatter check, and the documentation checker reported zero
errors. These are synthetic tests; the frozen independent set was not run.
