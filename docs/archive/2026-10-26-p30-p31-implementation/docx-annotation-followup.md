# DOCX annotation identity follow-up

2026-10-28. This is an uncommitted P31F source correction, not Word
qualification or an installed ingestion journey. The previous
[header/footer record](docx-header-footer-followup.md) describes recipe v7.

A synthetic footnote without an ID was returned as an unlabelled paragraph and
reported complete by v7; the new regression failed against that version (seed
46588). Recipe v8 requires footnotes, endnotes and comments to occur as direct
children of their corresponding part, with distinct numeric IDs per part. It
compares numeric values, so `7` and `+07` conflict, bounds ID length, and
refuses annotation-part paragraphs outside an identified annotation. Locators
retain the original ID. Annotation-bearing results are marked partial because
the extractor does not yet resolve body anchors or determine which annotations
are displayed; consumers must not treat their text as document-body assertions.
Existing v7 results require explicit re-extraction or requalification.

The focused regression passed (seed 46589); the document and fidelity suites
passed 30 tests with a separately built artifact (seed 46591). A further artifact
probe tested refusal of an annotation in the body (seed 46592), and expanded
numeric and oversized-ID controls passed (seed 46593). Seed 46590 ran while
source was changing and is not treated as a fixed-source result. All packages,
annotations and source documents here are synthetic. The tests do not establish
Word interoperability, annotation-anchor accuracy, acquisition, protected
storage, or retrieval qualification.

Working-tree SHA-256 values are `e3b5947f234b6814f37cc102b125905d327dba4cd90324640c64ada64d3dfda6`
for `docx.ex`, `3e689ae11849078dbcfec8ec8db6bf49368e92bb6a52b206b5d02437de9e07a0`
for `documents.ex`, `4618518c6eba535841e8e0d7659771fd1969de4f600edf1262da28b7ac3a0873`
for the fidelity test and `e4e8308a5ec50dee3cc0065ba2b0b3265ce24f44337550f202308f4fda89a8bd`
for the artifact probe. These are source identities, not a frozen release.

## Reference-site continuation

The v9 recipe associates an annotation paragraph with a single visible main-body
reference of the matching numeric ID. The site carries the body paragraph or
table-cell locator and a UTF-8 byte offset in extracted visible text. Multiple
visible matches are deliberately left unlinked, hidden and deleted markers do
not count, and dangling references mark coverage partial. References in other
stories and comment ranges are not resolved. All annotation-bearing results
remain partial; the point reference is not a claim about the complete annotated
range or current source authority. The [Open XML comment reference contract](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.commentreference?view=openxml-3.0.1)
distinguishes a point reference from an optional marked range, and the
[footnote reference contract](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.footnotereference?view=openxml-3.0.1)
describes matching a reference to a footnote ID.

The site test failed on v8 (seed 46594), then passed after the change (46595).
The document and fidelity suites passed 31 tests (46596), including synthetic
footnote, endnote and comment markers, UTF-8 offsets, hidden and duplicate
markers, dangling references and a separately built artifact. A subsequent
artifact probe verified an actual reference site in the new artifact (46597).
The 31-test run predates that probe addition. No human Word corpus, pagination,
installed acquisition or retrieval qualification was tested.

The v9 source SHA-256 values are `afa2fb4674826a2f8063ce24cfdb2aaec4b7ffd285761e1e84bef2ba69675f6b`
for `docx.ex`, `c428a3e4caa8c3a610c15cb31508343b9a27cf7a835f83f0bc50a78d27da9981`
for `documents.ex`, `339abc6f6f7312ef21c8f6a2e45d6bb3f114a9acf0097557629a05f7a1a43f04`
for the fidelity test and `456a943c5b03bc7d468e319b35e722a46c0ed0c4f7345a24d555d33cdb70c6b1`
for the artifact probe. These do not identify a frozen release.

## Emitted-body binding correction

A marker-only body paragraph produces no extracted body segment. The v9
reference-site code nonetheless attached a point to that omitted paragraph;
the adversarial regression failed before the correction (seed 46598). Recipe
v10 links a site only when its exact body locator exists among emitted segments
and the byte offset fits that segment. The focused test passed (46599), and the
document and fidelity suites passed 31 tests including the artifact probe
(46600). A subsequent focused table-cell locator control passed (46601). The
31-test run predates the table-cell case. Other annotation limitations above
remain, and no v9 artifact or index is automatically treated as v10.

The v10 source SHA-256 values are `3cf1ecb10e4bf03ce8f86f7d61030a928e0aff8b130af133224980516c9baa9a`
for `docx.ex`, `52f892e9207ccb384ec2c330f5b5a760caf93bc38e08f6faeb263ae40bb7b4f0`
for `documents.ex`, `76ed6b61f874fe08f25c7a90ecb8aa07994fea48778920a53fd100dd1f632d2b`
for the fidelity test and `b88c9e589755047f4dfdd367e33446ec940bdd7c437f43bf157593a19eb0e992`
for the artifact probe. These are working-tree identities, not a release.

## Bounded comment ranges

Recipe v11 additionally maps a unique pair of visible direct-paragraph comment
range markers to a nonempty UTF-8 byte span in the same emitted body paragraph
or table cell as the unique matching reference. It checks numeric identity,
marker order and bounds; duplicate, reversed, empty, cross-paragraph, hidden or
unexamined cases do not produce a range. Hidden and deleted text inside a
recognized range is excluded from the offsets, which describe extracted visible
text rather than XML coordinates. An unexamined range marker in the main story
conservatively suppresses all range links. The separate `reference_site` remains
a point, not a substitute for a range. Annotation-bearing output remains partial.
The [Open XML comment reference contract](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.commentreference?view=openxml-3.0.1)
describes matching start, end and reference IDs; other stories and spanning
paragraphs remain unresolved.

The same-paragraph regression failed on v10 (46626) and passed on the new
extractor (46627). A first two-suite attempt used a stale v6 test from the
private graph and failed one version assertion (46628); it is not a pass.
After overlaying the current tests, both document suites passed 32 tests
(46629). A separately built corpus artifact exercised the v11 range (46630).
An added hidden/deleted text control passed separately (46631), after that
32-test run. These are synthetic packages and do not qualify real Word fidelity,
installation, acquisition or retrieval. The running full diagnostic graph was
frozen before v11 and cannot validate it.

The initial v11 source SHA-256 values were
`86afcd58fc9e312cdd1e030c1b1e32c61e83961be632207d56c166855f9e855c` for
`docx.ex`, `9b73e065a8e96b6f39cc31a88264a93e31aabce35fc9ab785e8046126569b7ca`
for `documents.ex`, `10af366f510d694f4a31b4eed08969b7405ad529d6df035d3afe3d2e2ef08430`
for the document test, `9dbc72b5e1374c4775c3ceeea91e5c27f319d00464bd57fc6c4b9c2657c78d3c`
for the fidelity test and `e612eb7b9b06b14cdac9fb779676e8eca87ae52b821451fcdc7231a5088ffc5c`
for the artifact probe. The updated files passed a targeted formatting check.

An adversarial continuation found that a body containing range markers with no
reference or annotation part could still report complete coverage. The new
regression reproduced this against the initial v11 source (46632). The repair
marks any discovered or unexamined main-story range markers partial, even if no
reference exists. Both current document suites, including the separately built
artifact range probe, then passed all 32 tests (46633). Current `docx.ex` and
fidelity-test SHA-256 values are
`f900c49dfade84f216404e1e10fdbd2c8a5bf880f392587719d5aa014c999dc2` and
`35830f151a152e13bb6af30ba54c7f58c8d62e8461b45d2fdf7a02791301015c`;
both passed a targeted formatting check. This repairs the uncommitted v11
continuation; it does not change the real Word and integration limitations.

The later isolated production build produced a PDF-enabled archive. A separately
built corpus artifact (manifest SHA-256
`95d754b000531573ffb94166e81f88aa73286300e4ada8a752d050e3c6303ad1`) passed
the same synthetic document verification against both source and installed
runtime, with the PDF resource backend available and inventories unchanged. This
artifact proof exercises a DOCX revision fixture rather than the v11 range probe;
the latter was tested in the separately built artifact above. The
[continuation handoff](handoff-20261027-terra.md) records the archive identity,
parser tests and its unresolved dirty-source reference. Neither proof qualifies
real Word fidelity, retrieval quality or an installed Knowledge journey.
