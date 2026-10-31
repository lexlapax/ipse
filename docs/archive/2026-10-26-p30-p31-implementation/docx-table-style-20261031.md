# Bounded named table styles in DOCX

2026-10-31. Historical local implementation and synthetic verification record.
This follows the [current local checks](current-local-followup-20261031.md) and
does not qualify the full Word fidelity journey or complete P31F. Current user
procedures belong to [Corpus](../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace)
and implementation training to [Knowledge extraction](../../developer/knowledge-extensions.md#inspect-the-extraction-boundary).

## Reproduced gap and repair

A valid table selecting a nonhidden named table style refused with
`unsupported_docx_style_visibility`, even though the existing style parser could
validate its type and inheritance. The new positive test failed on the old
source; its paired hidden/ambiguous-style controls passed. The initial result
was 1/2 passed, 21 excluded, in `/tmp/ipse-docx-table-style-before.log`.

Microsoft's [table-style reference](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.tablestyle?view=openxml-3.0.1)
places `tblStyle` in table properties and describes its reference into the style
hierarchy. The [table structure guide](https://learn.microsoft.com/en-us/office/open-xml/word/working-with-wordprocessingml-tables)
separates table properties, rows and cells. The adapter reuses its existing
bounded style graph rather than introducing another XML parser or dependency.

The table reference must be directly under that table's properties, resolve to
a table style, occur once and precede its first row. Per-table state preserves
independent selection and locators. The existing style parser still rejects
table visibility properties, including conditional and inherited hiding;
paragraph/character hiding and direct hidden-run exclusion are unchanged.
Unknown, wrong-type, duplicate and late references refuse. Numbering properties
remain unsupported. This implements a bounded nonhidden formatting subset,
not a Word renderer or complete table-layout model.

DOCX recipe `ipse-documents-v12` identifies the added accepted-input semantics.
Text, Markdown and PDF retain `ipse-documents-v2`; older stored extractions are
not silently relabeled or rebuilt.

## Verification

Both new source controls passed (2 passed, 21 excluded). The four-file parser
selection then passed **38 tests**, with **3 skipped**, in 38.3 seconds:

```sh
mix test test/extensions/knowledge/documents_test.exs \
  test/extensions/knowledge/documents_fidelity_test.exs \
  test/extensions/knowledge/documents_parser_stage_test.exs \
  test/ipse/document_parser_test.exs
```

The separate artifact probe builds a fresh Corpus artifact and checks visible
Unicode cells and locators plus hidden-table refusal from that artifact's code.
The selection also covers hostile ZIP/XML bounds, annotations, headers,
visibility, owned parser cancellation and the parser-free runtime. The skipped
cases are not counted as PDF-backend or platform passes. Logs are
`/tmp/ipse-docx-table-style-after.log` and
`/tmp/ipse-docx-table-style-regressions.log`. No external model, new package,
JavaScript/Python runtime or private user document was used.

The existing acquisition/ingestion Session selection also passed **20 tests in
75.1 seconds**. A new focused Session case then acquired the styled table from a
real private workspace, completed explicit storage approvals and retrieved its
exact Unicode cell quotation with the original binary hash, recipe v12 and
table/row/cell locator. It checked zero inference, Saved reconstruction and
confirmed close: **1 passed, 14 excluded, 7.1 seconds**. Logs are
`/tmp/ipse-docx-table-style-session.log` and
`/tmp/ipse-docx-table-style-native-acquisition.log`.

The native/host/bundle rebuild and formatting checks passed. The operator Corpus
and developer Knowledge guides were reviewed as whole documents; their Word
instructions now name the bounded table subset and explicit v12 reacquisition.
The review also corrected stale prose about worker-side pending-queue counting
and vector-page production versus the separately available group/finalization
commands. Documentation links and archive ownership remain separately checked.

The earlier full-source and managed-Collection failures remain separate open
results. Larger ingestion, real Word fidelity, storage/quality and installed
qualification are not established by these fixtures.
