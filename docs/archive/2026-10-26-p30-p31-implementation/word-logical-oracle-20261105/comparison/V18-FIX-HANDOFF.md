# V18 reserved-note-layout repair: source handoff

2026-11-05. Actual v17 first comparison retained **0/12 agreement**, exit 1,
0.39 seconds, after all twelve extractions and both payload projections were
saved. `v17-first-failure.sha256` pins the unchanged 37 outcome/receipt files.
The oracle and its independent verdict remain unchanged. No v18 execution,
formatting, native or installed check was run by this repair task.

## Causal result and focused change

`Docx.annotation/3` ignored the note's `w:type`. It treated reserved footnote
separator and continuation-separator entries as ordinary annotations, adding
their IDs to evidence coverage and emitting their paragraphs as source text.
Each original consequently yielded fourteen blocks instead of the independently
expected twelve. Both payload profiles faithfully propagated those extra blocks.
Their absent body references also produced `annotation_anchors_unresolved` for
the footnotes part. This was not a payload/storage corruption or a gold mismatch.

The repair recognizes `separator`, `continuationSeparator` and
`continuationNotice` **only on footnotes/endnotes**. Their characters do not enter
evidence, and their layout IDs do not require body anchors. All annotation IDs
still participate in duplicate/count checks, and every paragraph start still
advances the original part-wide ordinal. No ID sign or literal-text filtering
is used. `normal` or omitted type retains ordinary annotations, including
negative/unreferenced IDs. Unknown types and typed comment impostors refuse.
Matching nontext layout markers are admitted only inside the corresponding
reserved note; unsupported markers elsewhere keep their warning.

Changed extraction semantics select recipe **v18**. Existing v14–v17 block-map
and v16/v17 numbered-map contracts remain admitted, with the unchanged geometry
explicitly extended to v18. Current-version test/probe expectations move to v18;
historical v17 packed/crossing controls were added and future-version refusal
moves to v19. No host or SDK file was changed and no dependency was added.

The separate `unsupported_word_content` warning in these originals comes from
body table-width metadata (`w:tblW`), outside the reader's declared layout
support. It remains unchanged; logical text agreement cannot turn it into a
complete-coverage or rendered-fidelity claim.

## Review artifacts and checks for Root

`v18-feature.patch` captures the seven focused changed files; SHA-256
`a692fcd2c777d0a054b684048c7538956cf7754c407c017994fe45dca1a70fe4`.
`v18-feature-source.sha256` pins their current pre-format source;
SHA-256 `249d12ac5e4fcc4dae0e4b738047db1ccc6a0ea054a88268ccc7067ed6e1f067`.
Root owns formatting, runtime checks, artifact build, installed qualification,
documentation integration and commit. Peer source review has been requested.

First focused behavior check when Root releases the runtime slot:

```sh
mix test test/extensions/knowledge/documents_fidelity_test.exs --only annotation_layout
```

Then verify surrounding annotation/visibility/numbering/citation and retained
recipe contracts with the existing three-file suite:

```sh
mix test test/extensions/knowledge/documents_fidelity_test.exs test/extensions/knowledge/documents_test.exs test/extensions/knowledge/document_paragraph_packing_test.exs
```

New controls cover both footnote/endnote layout types and original paragraph
indices; arbitrary separator text and positive layout IDs; ordinary negative/
zero IDs with layout-like text; unreferenced ordinary notes; foreign `x:type`
not authorizing suppression; unknown/empty/miscased types; duplicate normalized
layout/ordinary IDs; comments never becoming note layout; unsupported markers
remaining partial; and dangling body references to layout IDs remaining unresolved.

After those actual checks, freeze a newly built complete v18 artifact and a
separate v18 remediation comparison against the same twelve originals/oracle.
Do not overwrite the v17 failure script, artifact, raw outputs or receipt. Retain
all twelve v18 first outcomes and the full 144-block comparison, then qualify
actual stored/cited installed joins and independent answer quality separately.
Historical 62 full-locator checks and all other Word acceptance gates remain open.
