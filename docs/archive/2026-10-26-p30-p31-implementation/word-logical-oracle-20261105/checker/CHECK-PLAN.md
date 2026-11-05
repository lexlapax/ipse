# Independent complete logical-oracle check plan

2026-11-05; **ready for author freeze, no oracle verdict yet**. This is a bounded
source-review/check plan, not an execution framework or qualification receipt.
Root must separately authorize opening the completed frozen oracle and checking
it. No VM, native helper, renderer, model, network, Git or tracked-file mutation
was used for this plan. No new candidate output or private gold/question content
was inspected. No candidate-derived fact was sent to the author.

## Read set and independence

Reviewed `../author/authoring-plan.md`, `raw_package_reader.exs`, `read_raw.sh`
and the exact original public input pins. Hashes of this read set are retained in
[pre-freeze-readset.sha256](pre-freeze-readset.sha256); a copy of the authoritative
pins is [input-pins.json](input-pins.json). Directory names of the generated raw
files were listed; their content and the unfinished oracle were not read here.

This checker is separate from the oracle author and did not implement the DOCX
parser. Earlier source-only audits exposed parser implementation, product manuals
and historical aggregate v16/v17 outcomes to the checker. Therefore this is a
source-informed independent check, not an implementation-blind assessment.
Fresh candidate results remain unseen. The author's own exposure record and
candidate-output isolation must remain separately disclosed. These twelve
historical inputs remain exposed remediation data, not fresh held-out quality.

## Reader source review

The reader verifies twelve exact IDs, paths, byte sizes and SHA-256s before ZIP
processing. It bounds input to 16 KiB each, 32 entries, 64 KiB declared/actual
bytes per part and 1 MiB declared total expansion; rejects duplicate/unapproved
names; extracts to memory; rejects DTD/entity declarations; refuses external XML
fetch; and retains exact raw XML plus sibling-indexed element/text identities.
It uses existing OTP XML/ZIP/crypto/JSON and does not import Ipse parser/Evidence
modules, infer visibility, form expected logical text or read gold. This is a
suitable raw source aid, not itself an independently checked oracle.

Before accepting its output, check decoded Unicode text against the raw XML
declaration/entities; sibling counters against actual source order; namespace
declarations rather than trusting a `w:` prefix; and complete part/relationship
coverage. The reader checks actual per-part lengths but only *declared* aggregate
expansion: do not claim it enforces a separately recomputed actual 1-MiB sum.
Any known-input execution receipt is narrower than general adversarial parser
qualification. Do not rerun the wrapper during this source-only phase.

## Immutable expected-before-candidate boundary

1. Author finishes every source and records oracle schema/conventions, complete
   expected blocks/fragments/omissions, raw package index and source/reader hashes.
   Root supplies the exact oracle file set and freeze receipt to the checker.
2. Root authorizes checking only that frozen oracle against raw originals/parts.
   Checker records the incoming file hashes before review and verifies all twelve
   inputs. Candidate artifacts/results remain closed throughout this check.
3. Corrections before candidate execution are separate immutable oracle versions,
   with the old version, reason and changed assertions retained; independently
   check and freeze the corrected version. Never overwrite a prior freeze or
   accept a product-derived expected value to settle a disagreement.
4. Checker freezes its full coverage/mismatch/unverified ledger and disposition.
   Root then separately authorizes candidate extraction/installed runs against
   the checked version. A later repair informed by candidate outcomes is a new
   declared remediation experiment, not an edit to these first expectations.

## Minimum complete check ledger

All twelve IDs, D021–D030/V003-v1/v2, stay in the denominator. For **each**:

| Check | Required independent evidence |
| --- | --- |
| Identity/parts | Exact original size/hash, every ZIP part's size/hash, package authority, story and relationship selection. Account for unexamined parts/relationships explicitly; never follow targets. |
| Complete raw-text accounting | Every text-bearing raw node and structural text control maps to included content, excluded content with reason, metadata/format whitespace, unsupported content with declared outcome, or unresolved. No unaccounted node and no duplicated source fragment. Include tabs/breaks/nonbreaking/soft hyphens and exact Unicode/entity decoding if present. |
| Visibility/styles | For each run, inspect direct properties, declared paragraph/character style and default/inheritance graph from raw sources. Record explicit visible/hidden/ambiguous reasons; unknown or unsupported semantics stay unresolved. Do not reuse the product's selected text as evidence. |
| Revision policy | Inspect insertion/move-to/deletion/move-from ancestry and original attributes. Verify every selected/excluded run under the declared policy. Retain kind/ID as oracle source provenance, not invented product locator fields. |
| Ordered blocks and bytes | Check complete story/block order, empty paragraphs, within-block fragment order, exact UTF-8 half-open spans and hashes. Distinguish a source block's content from synthetic newline joins between blocks. An explicit empty block must not silently add a newline to the product projection. |
| Structural source map | Every block/fragment has a resolvable raw part/node path; verify namespaces and same-name sibling indices against original XML, including text-node identities. Check paragraph/table/row/cell and annotation ownership independently. |
| Notes/comments | Check all declared annotation IDs, complete annotation text, visible references and supported point/range anchors, including ambiguity/orphans. Full note text alone does not establish its body applicability. |
| Coverage/outcomes | Missing expected content, extra content, unsafe hidden/deleted inclusion, wrong locator/order and unsupported/partial warnings get explicit dispositions. No whole-file fidelity pass follows from a literal-support-only result. |

Node IDs are addresses in an independently inspected XML tree, not visual page
coordinates. Page rendering is not required for this bounded logical-text
contract; no rendered/typographic fidelity result is claimed.

## Raw-node to product-coordinate crosswalk

The crosswalk must be checked from source identities, never by matching quote
strings alone. For each part independently enumerate raw WordprocessingML
paragraph nodes in source traversal order, including table paragraphs and empty/
hidden/deleted paragraphs. Record the product contract's part-wide ordinal,
source-story ordinal, direct body ordinal if applicable, table/row/cell and
paragraph-within-cell separately. Confirm the actual relationship of these
conventions on each original rather than treating equal integers as identity.

Paragraph counting is separate from rendered or generated list numbering.
Notes/comments use part-wide paragraph numbering plus annotation identity; no
implicit reset per annotation. Headers/footers are distinct parts with their
own paragraph ordinals. Nested table ownership and counters require explicit
source-tree checks; do not flatten visual cells. Unsupported geometry retains
an unresolved/refusal disposition, not an inferred coordinate pass.

The original gold custodian must independently explain the meanings of existing
`body_paragraph`, `cell_paragraph` and `paragraph` fields before the historical
question slots can join this crosswalk. Their names do not define index origin,
empty/revision counting or descendant inclusion. Preserve all **62 historical
support slots**. Existing category counts remain body paragraph 30, cell paragraph
12, paragraph convention 20, revision kind 10 and revision ID 10; existing full-
locator-unverified 62/62 remains unchanged. This task does not read or infer the
private values. A new mapping ledger may establish new paragraph-coordinate
agreement after independent review; it does not rewrite the historical receipt.
Revision kind/ID remain unrepresented/unverified in returned product locators.
Do not delete fields, shrink denominators, relax thresholds or declare full-
locator equivalence because a quote occurs in the right paragraph.

## Concrete next installed verification after the checked oracle freezes

- Root freezes one exact available installed archive and its actual Corpus
  artifact/recipe and selected State/Collection profile. Existing public setup,
  acquisition, ordinary approval/journal and confirmed-close boundaries are reused;
  no custom shortcut around normal admission is introduced.
- Acquire the same twelve source IDs and hashes. Compare all extracted/stored
  logical bytes and original locators against the independent oracle. Join each
  fixed query support through original hash/recipe, stored source/version/chunk,
  packed original block map and half-open UTF-8 range to the exact returned quote.
  Keep first/last/table/annotation/revision-sensitive supports and negative cases.
- Exercise original change/loss/restoration, stale publication refusal, prior-head
  preservation and Saved/idle no replay on the same bound IDs. Preserve all
  profile refusals, partial coverage and unknown effects in their denominators.
- Separately freeze first actual answers and all material claim/citation pairs on
  the explicitly authorized route, then obtain independent blinded semantic
  reviews using complete source/reference evidence. Retain existing method and
  thresholds; do not count no-model storage checks as answer-quality evidence.

Readiness is procedural only: author freeze, independent source check, historical
gold-convention mapping, actual installed joins and answer-quality judgments have
not passed merely because this plan exists.
