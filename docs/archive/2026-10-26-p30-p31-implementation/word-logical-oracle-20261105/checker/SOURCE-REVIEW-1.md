# Frozen oracle: independent source review 1

2026-11-05. **Actual source inspection completed; candidate not evaluated.**
This record binds the incoming author artifacts below and remains separate from
the pre-freeze plan. No VM, renderer, native helper, network, gold/question or
new candidate-output access was used. No facts were sent to the author.

| Incoming artifact | Observed SHA-256, matching Root's release |
| --- | --- |
| expected-oracle.json | 890fc96281f60bb73eee4d6a71d044edc2250bf5a30b147e8d585b2eb5f858ed |
| raw-package-index.json | bc86e870b7f8de6151ae66936f0a6839e493b842518896517c97bb2a371d56ee |
| author_oracle.exs | 3f5f217db9db20556bc2dcaba098c29d1c402ba7e9590b31eadf2a202601e9ee |

## Observed agreements

Read the **entire raw document XML for every one of the twelve sources** and the
entire frozen literal/materializer source. Each source's title, declared heading,
two substantive paragraphs, table label/value and deleted/inserted handover text
agree with the manually authored assignments. All twelve actual original DOCX
SHA-256s were recomputed with the existing host checksum utility and match their
individual original pins. No version/source was substituted.

Read D021's complete footnote/comment/package-authority/relationship XML and
complete document/footnote/comment node trees. For the other eleven inputs,
recomputed hashes establish those auxiliary XML parts are byte-identical; their
footnote/comment node trees are also byte-identical. Across all twelve,
content-types match `ae04c5705dbbcd479a00d5f32895ff011d674ce0bcbe1cd5214577675d06131e`,
root relationships `d91fa571c7e58d33e48db1a3dcb270c137acf6a9ec1cb6d447f3b8890e1574df`,
document relationships `bbd5457ec3218f8d9b3e00f30586223479742598e4a27c351eaa69b5afe54034`,
footnotes `1b59ce48051b7d1112712371b83654fcab81434c503f772a4ceaaf85c7e77c88`
and comments `8a2b867e2c6ef82f7279417166fcd4ed2dc4c69bd73d435588f27deb2e285422`.
This equality is the basis for checking their shared contents once; it is not
an assumption from their filenames.

Package authority identifies the main body, footnotes and comments with matching
internal relationships/content types. No external relationship, styles/default
style, numbering, header/footer or endnote part is present in this exact cohort.
The main stories have one undeclared `Heading1` reference on direct paragraph 2;
it is raw reference metadata, not proof of applied heading styling. No direct
hidden property, run style, hidden default, tab/break, move-to/move-from or list
definition is present. Thus this source check tests ordinary visibility plus
tracked insertion/deletion and footnote-layout exclusion; it does **not** qualify
style inheritance, hidden-run conflicts, lists or other absent features.

Every source has 13 body text nodes: twelve included `w:t` values and one excluded
`w:delText` value. The three footnote text nodes comprise excluded separator and
continuation-separator dashes plus one included ordinary note. The single comment
text node is included as separately attributed comment content. This agrees with
the author's 14 included + 3 excluded = 17 text-node dispositions per source,
12 included blocks per source, 168 included + 36 excluded = 204 raw text nodes
and 144 included blocks across the complete cohort. The retained prefix space
in `Current handover: ` is explicit source text; no normalization is justified.

Revision attributes are `w:del` ID11/Editor/2026-09-02 and `w:ins`
ID12/Editor/2026-09-03 in each original. Excluding the former and retaining the
latter agrees with the selected policy. The footnote reference ID2 occurs after
17 ASCII bytes (`Annotation anchor`). The comment ID3 range encloses bytes
[17,32) of that same paragraph, and its reference follows the range. These source
locations are unambiguous in the raw tree. No marker characters occur in raw text.

## Independently checked source-coordinate crosswalk

The following table is true for **each** of the twelve inspected originals;
`body` below abbreviates `/w:document[1]/w:body[1]`.

| Raw paragraph node | Source part | Part-wide paragraph | Additional source coordinate |
| --- | --- | ---: | --- |
| body/w:p[1] | word/document.xml | 1 | direct body 1 |
| body/w:p[2] | word/document.xml | 2 | direct body 2; declared Heading1 |
| body/w:p[3] | word/document.xml | 3 | direct body 3 |
| body/w:p[4] | word/document.xml | 4 | direct body 4 |
| body/w:tbl[1]/w:tr[1]/w:tc[1]/w:p[1] | word/document.xml | 5 | table 1, row 1, cell 1, cell paragraph 1 |
| body/w:tbl[1]/w:tr[1]/w:tc[2]/w:p[1] | word/document.xml | 6 | table 1, row 1, cell 2, cell paragraph 1 |
| body/w:tbl[1]/w:tr[2]/w:tc[1]/w:p[1] | word/document.xml | 7 | table 1, row 2, cell 1, cell paragraph 1 |
| body/w:tbl[1]/w:tr[2]/w:tc[2]/w:p[1] | word/document.xml | 8 | table 1, row 2, cell 2, cell paragraph 1 |
| body/w:p[5] | word/document.xml | 9 | direct body 5; selected revision text |
| body/w:p[6] | word/document.xml | 10 | direct body 6; note/comment anchors |
| /w:footnotes[1]/w:footnote[3]/w:p[1] | word/footnotes.xml | 3 | ordinary note ID2, note paragraph 1; two preceding layout paragraphs excluded from content |
| /w:comments[1]/w:comment[1]/w:p[1] | word/comments.xml | 1 | comment ID3, comment paragraph 1 |

These independently match the frozen oracle's `locator_basis` values and raw
sibling-indexed paths. This establishes source-convention agreement, **not** a
new result for private gold or returned product citations. There is no nested
table, empty/hidden body paragraph or multi-paragraph note in this cohort.

## Concrete discrepancy and unverified fields

**Metadata typing discrepancy:** direct body paragraphs 1, 3 and 4 have no
`pStyle`, but the materialized JSON stores `"heading_style":"nil"` for them:
36 string sentinels across twelve sources. The literal source used Elixir `nil`;
the chosen OTP JSON encoder serialized it as a string. It is not a raw style
named `nil`, a resolved style or JSON null. The new source crosswalk records
absence of a declared style for these nodes. Do not feed these strings into a
style-equality score. Before a strict metadata pass, Root should either retain
a typed diagnostic/explicit sentinel interpretation in the frozen comparison
contract, or arrange a separately frozen corrected oracle version; do not edit
the released file or silently normalize it after candidate outcomes. This does
not alter the observed literal-text agreement.

The frozen oracle's text-byte counts observed in JSON are D021 420, D022 420,
D023 420, D024 431, D025 392, D026 411, D027 409, D028 416, D029 403, D030 418,
V003-v1 391 and V003-v2 422. The literal construction and offset arithmetic were
source-reviewed. **Independent mechanical verification of every materialized
JSON fragment/block/story/document span and raw-index-to-ZIP byte association has
not run in this source-only slot.** The author's successful equality/materializer
receipt is preserved but not relabeled as an independently executed check.

The historical 62/62 full locators remain unverified, with all original columns
and denominators intact. This checker has not read private gold conventions or
question values; a raw source crosswalk does not establish those conventions.
Revision kind/ID remain unrepresented/unverified in product locators. No
candidate extraction, installed storage/citation, rendered fidelity, actual
answer or independent semantic judgment follows from this source review.

## Disposition and exact next pure slot

**Accept the complete literal-text/source-structure assignments for this bounded
cohort as independently source-reviewed, with the style-sentinel diagnostic;
hold a fully mechanical JSON-byte/span pass pending execution.** No whole Word
gate or full metadata pass is claimed.

Prepared `check_frozen_oracle.exs` for Root's next serialized pure OTP slot. It
pins the three released hashes, independently reopens/rechecks all twelve
original archives, verifies exact raw-part equality, accounts for all 204 text
nodes, recomputes complete UTF-8 spans/hashes and derives 144 source paragraph
crosswalk rows from raw node trees. It records the 36 sentinels without pretending
they are style references. It imports no author code or Ipse module, opens no
candidate/gold data, writes only a fresh checker receipt and uses no renderer,
network, model or native helper. The script is **not yet run or compiled**.

Run from repository root only after Root releases the slot:

```sh
ERL_FLAGS='+S 2:2 +A 1 +SDcpu 1 +SDio 1' elixir _build/verification/word-independent-oracle-20261105-01/checker/check_frozen_oracle.exs
```

Then freeze its actual receipt before candidate extraction/installed comparisons.
All later installed/citation/answer steps remain those in CHECK-PLAN.md.
