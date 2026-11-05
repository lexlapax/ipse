# Independent Word logical-text authoring plan

This is the exposed historical remediation cohort: D021–D030 and V003-v1/v2,
all 12 pinned original DOCX inputs. The later checker must preserve all 62
historical question slots. This author does not inspect those questions or gold,
and makes no fresh held-out claim.

The author reads only these original public ZIP/XML bytes and the frozen contract.
The reader uses OTP ZIP, xmerl, crypto and JSON, with no Ipse application/parser,
model, provider, native helper, renderer, network or new dependency. It verifies
each exact original size/hash before ZIP processing; caps 32 known-name XML parts,
64 KiB per part and 1 MiB total declared expansion; rejects DTD/entity declarations
before XML parsing and refuses external XML fetch. A CPU-limited wrapper permits
one short serialized raw read. It emits original XML and raw sibling-indexed
node identities only: no candidate-style logical extraction or visibility result.

After reading raw XML, manually author complete expected story/block order,
included/excluded runs and explicit visibility reasons. The selected revision
policy includes insertion text and excludes deletion text. Preserve actual raw
revision attributes as provenance, but do not invent product revision-ID fields.
Record logical paragraphs, table rows/cells, headers, footers, notes and comments,
their original part/node addresses and logical source order. Account for every
text-bearing raw node and all structural text characters (tab, break) if present.
Annotate non-visible metadata separately. No page/layout evidence is required.

The independent expected text representation uses a newline between blocks,
explicit empty blocks where relevant and UTF-8 half-open byte spans. Each included
fragment carries its raw node identity and local block span; each expected block
carries a part and paragraph/table-cell locator plus its story span. The later
independent checker maps this complete raw oracle to the actual product contract
without giving candidate extraction results back to this author.

## Exposure record

Read AGENTS.md in full and `git status --short --branch` names only. Initial
`rg --files` exposed names of documentation paths containing design/protocol/
knowledge, with no contents. Read the exact authorized input-pins.json in full.
Read docs/knowledge-design.md matching frozen-contract headings and
docs/archive/2026-10-26-p30-p31-implementation/baseline.md matching Word-related
requirements, plus baseline lines 738–770. Read docs/plan.md keyword matches and
lines 1200–1405; the permitted plan itself incidentally disclosed historical
12 v16 refusals, 12 v17 partials and 62 support-check aggregate counts. No old
extraction outcomes/files, question/gold files, parser/candidate source, private
cohort, credential or other-agent oracle has been read. The corpus is already
exposed remediation regardless of author independence.

Root released one serialized raw-read slot. The first reader attempt exited 1
after 0.38 s: supplying Unicode codepoints to xmerl's UTF-8 input produced a
bad-character error at U+2212. Four output files for the content-types and root
relationship parts were produced and preserved under `failed-attempt-1-raw/`.
The reader was corrected to supply UTF-8 bytes to xmerl and rerun within the
same slot. It exited 0 after 0.25 s; all 12 original hashes matched and each had
six XML parts. The lane was then released promptly. Both attempts used the
fresh-output refusal, exclusive writes, 30 s CPU limit and 35 s wall timeout.

Read raw-package-index.json in full; raw document.xml for all 12 sources;
footnotes.xml, comments.xml, [Content_Types].xml, _rels/.rels and
word/_rels/document.xml.rels for D021; D021 document-node JSON prefix and full
footnotes/comments node JSON. The index independently showed the other five
parts byte-identical across all 12 inputs. An attempted D021 header1.xml read
returned no such file; no header/footer/endnote parts exist in this cohort.
No candidate or answer content was seen. Agent status orchestration exposed a
separate scope-correction summary (no oracle text or candidate content).

## Manual authoring freeze

`author_oracle.exs` contains literal title, heading, substantive body, table label,
table value, deleted text and inserted text for every original. Those literals
and their raw node assignments were manually authored after reading the complete
raw document XML. Repeated annotation/footnote/comment text was separately read
from D021, with identical part hashes for the rest. The script's only automated
work is calculating UTF-8 spans/hashes and validating that these fixed authored
assignments account for every raw text node exactly once. It never reads an
Ipse extractor or answer gold and never obtains expected strings from raw nodes.

The expected structure has 12 visible blocks per input: four body paragraphs,
four table-cell paragraphs, the revision paragraph, the annotation paragraph,
one referenced footnote and one comment. Every source has 14 included text nodes
and three excluded nodes (one deletion and two footnote layout separators), so
the complete corpus has 144 blocks, 168 included nodes and 36 excluded nodes.
Body direct-paragraph identities 5/6 correspond to raw part-wide paragraph
ordinals 9/10 after the four table cells; both coordinates are preserved as
author evidence. These are not proposed product representation fields.

The author representation serializes body blocks in original XML order, then
footnote and comment stories, with one newline between blocks and no trailing
newline. Separate block/story/document UTF-8 spans avoid dependence on candidate
serialization. References and comment boundaries add no synthetic marker text.
The normal footnote and comment content are explicitly distinct stories, not
unattributed assertions. Page layout is outside this gate.
