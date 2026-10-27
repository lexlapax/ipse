# Document extraction fixture checks in the CLI

Historical component evidence, 2026-10-27. Using the isolated build described in
the [P30 component check](../p30-cli-check/README.md), `mix test --no-compile`
ran `test/extensions/knowledge/documents_test.exs` and
`test/extensions/knowledge/documents_fidelity_test.exs` with seed 20261109 and
`--max-cases 1`. All 23 tests passed; the standard platform tags were excluded.
The tests exercised synthetic document extraction and local fixtures, including
inert external relationships. The [manifest](SHA256SUMS) records selected
document sources, those tests and Mix files, but not every dependency or test
support input. Results are from the tool transcript, not an archived raw log.

This does not establish installed document acquisition, PDF qualification,
retrieval quality, source freshness or a completed Word user journey. P31F and
its integrated acceptance remain open.
