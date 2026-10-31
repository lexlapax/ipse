# DOCX referenced headers and footers follow-up

2026-10-27. Working-tree continuation of P31F; this is a development record,
not milestone acceptance. Current scope and remaining work are in the
[plan](../../plan.md).

The v7 DOCX recipe extracts referenced header and footer parts once, with region
and part locators. It checks relationship IDs and kinds, bounded internal target
names, package membership and content types; unreferenced parts are not read.
Section inheritance and page visibility are unresolved, so referenced regions
always mark the result partial. Existing extraction limits and hidden-text policy
apply to these parts. Older recipe results are not automatically migrated.

Synthetic package tests cover both relationship namespaces, wrong and duplicate
IDs, wrong type, traversal, external targets, MIME mismatch, repeated references,
hidden text and a shared text limit. The document and fidelity suites passed 29
tests with seed 46463, including their independently built artifact probe; the
additional namespace and duplicate-ID cases passed separately with seed 46464.
Formatting, compilation with warnings as errors, documentation link checks and
`git diff --check` passed. The available host did not establish a protected
native storage profile. These fixtures do not establish real Word fidelity,
pagination, a production ingestion workflow or P31F acceptance.
