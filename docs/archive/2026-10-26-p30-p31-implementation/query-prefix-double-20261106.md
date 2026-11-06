# Exact query-prefix refusal — 2026-11-06

Historical synthetic development evidence. The [plan](../../plan.md) owns
acceptance status, and the [Corpus manual](../../operator/corpus.md#choose-an-embedding-query-format)
describes configuration and use.

The candidate refuses a dense or hybrid query that begins with its configured
complete prefix before reading the selected State, MCP or Collection store.
This exact-byte rule also refuses a literal query with that beginning; it does
not identify a different or modified wrapper. Queries without a prefix and
ordinary unwrapped inputs retain their existing behavior.

Synthetic domain-worker controls pair each refusal with the same valid unwrapped
State, MCP or selected Collection query reaching its first host request. Fresh
`state-dense` and `collection-dense` artifacts built against a minimal SDK also
pass refusal and unwrapped controls. The State artifact additionally verifies
the exact embedding input and vector binding. The first artifact-test attempt
failed from conflicting inherited library paths; a corrected isolated attempt
passed. Earlier MCP test attempts had fixture syntax and assertion errors before
the corrected controls passed. None of those failures becomes a passing result.

A separate fresh synthetic Collection Session test passed once: one selected
test passed with 80 excluded. It checked the refusal, unchanged six native
status counters and two ordinary dense/hybrid synthetic embedding requests.
It seeded storage directly and checked typed Word citation metadata, not a
complete bytewise store comparison or independent citation-byte join. The
fixture's close callback does not assert its result. A separate host inspection
found no remaining BEAM, runner or timeout process and the Input lock and TCP
39657 free. The SDK inventory changed only by Mix's test-failure bookkeeping
file. The test log SHA-256 is
`d52c06e7306d86e67af888413a3a127d528cfae6749ab39c55d0796de34a44a9`;
the built Corpus manifest SHA-256 is
`e0123608ba58da9fd750c581769f1db0f040b4411a6859cc75bc8407621181d3`.

These results do not establish real MCP transport, installed package, model
quality or local-only network enforcement. Current-source full regression and
integrated P31 qualification remain open.
