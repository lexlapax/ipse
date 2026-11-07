# Word literal-bullet extraction, 2026-11-07

This is historical source-runtime evidence, not current milestone status. The
[plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance) records the
remaining document and milestone gates.

DOCX recipe v19 adds a narrow direct single-level literal `•` numbering subset.
Its version-two numbering locator records the declared character and suffix;
the character is not inserted into quoted source text. Numbering-level font
properties, bullet overrides, other glyphs and unsupported numbering shapes
continue to refuse. The declared character does not establish rendered glyph
appearance under inherited fonts. V16–v18 decimal evidence keeps its original
recipe and remains readable; existing sources are not silently rebuilt.

An isolated source copy based on the earlier frozen runtime, with the committed
draft and recall changes and this Word candidate, passed the default
`./dev/build.sh`. The default build did not enable PDF. The credential-free
`./bin/ipse demo` also passed. Its freshly built
Collection Corpus manifest SHA-256 was
`1fd6a5e63696a17aea05d7950e1b4964e8d278f57164df23765eb05e237c5f02`;
its Documents and Numbering module hashes were respectively
`6f7981d67177b1ca35bf005270d2f67d40ba42c57c41b84da87817b11cf24f19` and
`4d08e9ce2e04581f6e4cfb0d35683a0b099925ae9d7315729d92c8f1d1ae133d`.
These hashes were unchanged after the focused tests.

The extraction, citation and paragraph-packing files passed **51 tests**. A
separate synthetic Collection Session test passed one case with 38 excluded:
it acquired a 40-paragraph bullet document, returned a source-bound citation
with bullet metadata outside the quote, refused a changed original, recovered
after restoration, and checked Saved/close/idle resume without replay. The test
fixture was retained privately. Host checks found no remaining selected test
process, input-lock holder or test-port listener. The modified Elixir files also
passed the formatter check under Elixir 1.18.5/OTP 27.

One initial build preflight did not dispatch because available memory was below
the selected threshold. The passing tests are synthetic source-runtime checks;
they do not establish general Word fidelity, interrupted-effect recovery,
installed use, the PDF verifier or model quality. The complete current-source
regression and the wider document capacity and lifecycle requirements remain open.
