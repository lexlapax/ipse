# Absent heading-style metadata correction

Root relayed the independent source checker's finding of 36 metadata diagnostics:
the v1 author source uses Elixir `nil` for absent heading style, and OTP JSON
serialized that atom as the string `"nil"`. This is author metadata, not document
text. No candidate code/output, question/gold content or other oracle expectation
was exposed by the diagnostic.

Preserve all v1 source, output, raw files, freeze and receipts unchanged. Prepare
`author_oracle_v2.exs` as a copy with exactly these source changes:

1. The absent-style expression `else: nil` becomes `else: :null`.
2. The fresh-output refusal names `expected-oracle-v2.json`.
3. The exclusive output write names `expected-oracle-v2.json`.

The expression applies to body paragraphs 1, 3 and 4 for each of 12 inputs:
36 absent heading styles. Paragraph 2 retains its literal `Heading1` value.
All authored text, visibility decisions, raw identities, hashes, span arithmetic,
locator coordinates, story/block order and the 12-document/62-question
denominator remain unchanged in source. Actual output equivalence beyond the
36 expected JSON-null metadata changes must still be mechanically checked after
authorized execution; no v2 output or success is claimed before that run.

| Preimage or prepared source | SHA-256 |
| --- | --- |
| v1 author_oracle.exs | 3f5f217db9db20556bc2dcaba098c29d1c402ba7e9590b31eadf2a202601e9ee |
| v1 expected-oracle.json | 890fc96281f60bb73eee4d6a71d044edc2250bf5a30b147e8d585b2eb5f858ed |
| v2 author_oracle_v2.exs | 37061b96da1ba15bb262a759928c1aa28bcfb937574eba2a358ad7f6add30cf8 |
| v2 materialize_oracle_v2.sh | aa572fd7c74bdb3a3ac74c86e809338975da801fac26dc5b5a69951fcb358785 |

The complete `diff -u` was reviewed and showed only the three changes above.
No VM or materializer was run during this correction preparation. Root must
release a short pure OTP slot before `materialize_oracle_v2.sh` is executed.
