# DOCX relationship coverage correction

Recorded 2026-10-27. This is a focused parser change, not P31F acceptance. The
[plan](../../plan.md) owns the remaining Word and document qualification work;
the earlier [parser record](document-parsers.md) describes the previous recipe.

The previous extractor read the root and main-document relationship files but
could silently ignore an external relationship and report complete coverage.
It did not fetch that target. The revised extractor reports partial coverage
when an inspected relationship is external, when an internal relationship is
not among its checked parts, or when another relationship file is not inspected.
Warnings for the two checked files identify only their fixed package paths;
unexamined-part warnings omit arbitrary member names, and no warning contains a
relationship target. Relationships lacking Type or Target, having an unknown
TargetMode, or using an absolute scheme or network-path target without explicit
External mode refuse. Authority-bearing main, style and annotation relationships
retain their stricter canonical internal checks. Some ordinary packages with
uninterpreted relationships will therefore be partial; the warning does not
mean their body text is wrong or that the extractor followed a relationship.

DOCX now selects immutable `ipse-documents-v3`; text, Markdown and PDF retain
`ipse-documents-v2`. `Documents.version/1` names the format-specific recipe;
the existing zero-argument function remains the legacy v2 value. No automatic
migration or equivalence of old DOCX v2 results is claimed. Any future persisted
document index must explicitly rebuild or requalify old DOCX receipts under its
own reviewed migration policy.

The DOCX and fidelity tests were run directly on Elixir/OTP without model access:

```sh
ERL_FLAGS='+S 2:2' elixir -e 'ExUnit.start(seed: 20270116); Code.require_file("test/extensions/knowledge/documents_test.exs"); Code.require_file("test/extensions/knowledge/documents_fidelity_test.exs")'
```

The [run](document-relationship-tests.log) reported **23 passed**. It includes a local TCP listener that observed
no connection for a synthetic external URL, tests for root and document external
relationships, unknown internal and unexamined parts, target redaction, malformed
target modes and format-specific version selection. It does not establish real
Word fidelity, PDF behavior, source acquisition, current indexing, hosted builds,
or end-to-end retrieval quality. The test output SHA-256 is
`a90aef686997f06eb1ad47eab4e231c37ccdf40281683c9c1dc1476b98ebf074`.
An independent reviewer inspected the changed relationship logic and ran the
document, fidelity, PDF and parser-stage suites in a separate copied graph. The
[result](document-relationship-independent.log) was **24 passed, 4 skipped**:
the parser/staging executable was unavailable. That run used `--no-compile`;
the source-loading document fixtures matched the current parser sources. Its
output SHA-256 is
`07209c066ca29354f3c0f0f376839258078757f2cb5e3b5b4cb85daada7a618a`.
These are focused source controls; no installed-user or milestone completion is
inferred.
