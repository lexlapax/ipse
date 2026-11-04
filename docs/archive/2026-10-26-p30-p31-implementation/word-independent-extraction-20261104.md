# Independent Word extraction outcomes — 2026-11-04

This dated experiment preserves both first failures and a separate repair
evaluation. The [plan](../../plan.md) owns P31F acceptance. Neither a completed
adapter nor a positive literal-support check is full Word, semantic-answer or
installed qualification.

## First frozen outcomes

An independent evaluator reviewed a gold-blind adapter and ran the twelve frozen
DOCX inputs against the shipped v16 bundle
`9677e436d7969da90bb3c752c473489eb218c224f609cdcba852f1849a473fb7`.
All twelve were refused as `unsupported_docx_style_visibility`: zero documents
and zero Collection source payloads. The adapter exited zero because it recorded
every outcome, not because the parser passed. Inputs, complete runtime, paths
and links were unchanged. No application, native input or model service ran.

The [first-outcome report](word-independent-extraction-20261104/first-v16/README.md)
and [qualification receipt](word-independent-extraction-20261104/first-v16/qualification.json)
preserve scope and hashes. Private outcomes were sealed before any diagnosis;
answer keys and document prose are absent from this public packet.

Structural inspection subsequently found undefined selected paragraph style
references. The parser treated those references as malformed inheritance graphs.
Microsoft's ISO-derived documentation specifies that nonexistent selected
[paragraph styles](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.paragraphstyleid?view=openxml-3.0.1)
and [character styles](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.runstyle?view=openxml-3.0.1)
apply no corresponding style.

## Separate v17 candidate and frozen reevaluation

The isolated v17 candidate handles undefined selected paragraph/character
references while retaining malformed-parent, cycle, wrong-type, linked-style,
namespace/entity and ambiguous-visibility refusals. Table-style and inheritance
edge handling were not opened. An undefined explicit paragraph reference with
a visibility-bearing default paragraph remains refused. Existing document/run
visibility and older v14–v16 citation formats retain their checks.

The complete candidate Corpus artifact was independently built and imported:
`63f9a7cd4acd16ae256a7bcf3e8a30748d8c4a047c45d15e9074e0391db312d4`.
Its [source/test patch](word-independent-extraction-20261104/source.patch) is
`17a951c123d05e01834f442ee9d6b2337ed2818c5afcb01059426f8ea5321a7c`.
All 47 distinct focused parser/Evidence controls passed. One initial loopback
permission failure preceded parser execution; the exact case passed in the
actual host environment. It was not converted into a parser pass or skipped.

Before repaired outcomes, the independent evaluator froze the
[support-check protocol](word-independent-extraction-20261104/repaired-v17/PROTOCOL.md)
and its applicability: 62 selected questions with 62 nonempty support entries.
One fresh repaired cohort then produced twelve extracted documents and twelve
Collection source payloads. **All twelve remain partial**, with explicit
unsupported-content and unresolved annotation-anchor warnings.

All 62 literal support quotes were present in both original segments and payload
text; all 62 bounded mapped structural checks agreed. Full paragraph and
revision mapping remains unverified for all 62 entries. The
[aggregate](word-independent-extraction-20261104/repaired-v17/support-aggregate.json)
and [report](word-independent-extraction-20261104/repaired-v17/README.md) disclose
field coverage and unmappable fields. There was no semantic answer, rendering,
full fidelity, Collection commit or installed-user score. All eight execution
and integrity postchecks passed; original gold bytes were unchanged.

The repaired candidate was separate from the source-regression checkpoint when
evaluated. Its positive results do not relabel the twelve original refusals or
claim that the candidate is already shipped. Current source integration,
installed journeys and the remaining P31F gates are separate.

Each evidence subdirectory has an archive-relative `evidence.sha256` plus the
unchanged original exported manifest. Only manifest paths were relocated;
receipt bytes and their original hashes were preserved.
