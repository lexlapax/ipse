# Word ingestion investigation

2026-10-31, after `dff87f8`. Historical development evidence, not Word acceptance.
The [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance) owns remaining
scope; current extraction and acquisition limits remain in the
[Corpus manual](../../operator/corpus.md).

## Check the premise before widening style admission

The general Microsoft SDK guide and its format-specific product appendix differ
on which Word versions write `stylesWithEffects`. The
[MS-DOCX part definition](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-docx/6d73a0c5-2d94-461e-81c8-843ad0e911a6)
describes a copy of the styles part. Its
[product-behavior appendix](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-docx/11e00e62-c73a-4371-93d5-cddcc63fcbf0)
specifically attributes writing it to Word 2010 and excludes later versions.
This differs from the version account in the
[general SDK guide](https://learn.microsoft.com/en-us/office/open-xml/word/how-to-extract-styles-from-a-word-processing-document).
Neither statement supplies a safe rule for merging differing visibility graphs.
No parser gate was changed on that basis.

The prior three O14 strict-conversion fixtures were too narrow to prioritize
general Word usability. The complete small-DOCX inventory at the same frozen
Microsoft SDK revision was inspected. Before extraction, selection chose one
non-O14-strict path for each of five filename groups: comments, table, hyperlink,
footnote/endnote and simple/hello. These are conformance/regression development
inputs, including a normalization fixture whose name identifies missing row
metadata; they are not asserted to be five ordinary, independently valid modern
Word documents. No upstream code was executed or model request made.

## What the original bytes establish

Every Git blob and byte count was checked before parsing. Four files produced
partial text (329, 1, 2 and 1 segments); the endnote fixture refused style
visibility validation despite having no alternate style part. Warnings preserve
omitted parts and unexamined relationships, including an external hyperlink that
was not followed. No document prose is included in the public result record.
Reading the fixtures does not establish text correctness or rendered fidelity.

The larger comments fixture yielded 6,181 text bytes across 329 segments.
`Documents.source_payload/3` refused it under both 8-KiB legacy and 64-KiB staged
payload selections. The helper requires at most 32 segments, counts chunks per
segment and bounds serialized locator metadata. Both supplied-byte intake and
workspace acquisition call this helper before storage. The existing paged
locator path therefore does not by itself establish support for such input.
This is an actual helper refusal plus inspected caller wiring, not an executed
native Session refusal or proof that removing one limit makes ingestion work.
The three smaller parsed fixtures produced helper payloads successfully.

The [machine record](word-ingestion-gap-20261031.json) preserves exact paths/blob
hashes, original SHA256s, parser counts/warnings, helper outcomes, license hash,
artifact identity and owning implementation hashes. Raw public inputs/results
remain under `/tmp/ipse-word-broader-20261031`; logs are
`/tmp/ipse-word-broader-20261031.log` and
`/tmp/ipse-word-broader-source-payload-20261031.log`. An initial attempt to decode
a saved error term with `binary_to_term(..., [:safe])` refused an unloaded atom;
the safe decoder was retained, and the final helper probe freshly parsed the
original bytes instead.

## Required next implementation evidence

Prioritize a complete many-paragraph acquisition and cited-retrieval journey.
Design chunk packing and paged locator handling together, keeping exact original
paragraph/cell locators and offsets, bounded stage/metadata allocation, stale-file
refusal, old-selection preservation and no replay. Do not simply raise the
segment guard or count a parser-only pass as ingestion. Add a native Session
positive and source-change/interruption controls on this geometry, then qualify
the independently built installed artifact. Style differences and actual Word
rendering remain separate unresolved fidelity work. The full P30/P31 goal remains
active; this investigation changes the next implementation target, not its scope.

The later [v14 block-packing increment](word-block-packing-20261031.md) identifies
the fixture's mixed paragraph/table geometry and resolves its bounded acquisition
path. The original refusal and format/quality limitations above remain historical.
