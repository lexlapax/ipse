# Eligible query scope and retained limits, 2026-10-19

Historical investigation and verification increment after `e98575e`. Use the
current [Corpus](../../operator/corpus.md) and [Graph](../../operator/graph.md)
manuals for operation, and the [query exercise](../../developer/knowledge-extensions.md#trace-a-source-and-a-query)
for contributor training. The [plan](../../plan.md#p27-optional-research-graph-and-rag)
retains the full acceptance scope. This increment neither completes P27 nor
measures model quality. Held-out corpus, qrels, manifest and evaluator remain
sealed during this investigation.

## Causal observations

Public Session regressions exposed three different classification errors:

- Corpus returned `partial` after deliberate suppression or source expiry,
  despite completing retrieval of the eligible sources. An unpublished source
  with an empty ranking instead returned `abstain`.
- Corpus graph fusion discarded the graph component's incomplete coverage.
  A two-edge graph limited to one edge returned `ok`. Direct Graph queries
  likewise reported `ok` for that bound, `partial` after unrelated suppression,
  and `abstain` for an empty query with an unpublished source.
- A pure Evidence regression distinguished valid expired facts from missing or
  replaced provenance. All were classified as `stale_fact`, making a completed
  traversal at the fact's known expiry boundary partial.

The before runs failed at these specific status assertions. Existing metrics
were not changed to accept the outcomes. The evaluator continues to preserve
package status, and partial results retain zero successful retrieval utility.

## Repair and controls

Both package revalidation paths now use `Evidence.query_scope/4`. It preserves
diagnostics while distinguishing eligible-scope exclusions from missing coverage.
Suppression, non-current sources and valid facts outside their time interval
remain visible in `gaps` and `coverage.exclusions`. Other gaps and incomplete
rank coverage remain partial, including an empty result. A complete empty search
abstains. Final root revalidation still refuses a changed snapshot.

Fact validation checks citation identity and spans before time policy. Missing
or replaced provenance remains `stale_fact`, even when the fact is also expired.
A forged span still refuses. Valid time exclusions use `excluded_fact` with the
fact identity. No source, fact or vector is silently regenerated.

Corpus fusion retains each component's claims, gaps and coverage. It requires
every selected component to complete before claiming complete coverage. The
reciprocal-rank algorithm and its constant remain unchanged. A missing-vector
lexical fallback still produces partial coverage after its accounted query
embedding; a useful passage cannot erase that missing component.

The public controls use independently compiled artifacts, ordinary import and
configuration, approved source/extract/query commands and canonical accounting.
Domain modules remain absent from the host VM. Explicit lexical and graph paths
make zero model requests. The fallback case uses one scripted two-coordinate
embedding from an owned loopback fixture, not a model service. All successful
control Sessions require confirmed cleanup.

## Verification boundary

Local verification used macOS arm64, Elixir 1.20.3 and OTP 29. The focused
Evidence, public completeness, isolated package and seven-variant runner suites
passed 21 tests in 85.6 seconds. The later full suite also includes the stronger
forged-span-at-expiry and confirmed Session-close assertions. With source and
build outputs fixed, strict stdio tracing and both macOS enforcement tags enabled,
it passed 1127 tests with 17 Linux-only exclusions in 515.2 seconds, seed 689564.

Fresh independent lexical Corpus, explicit Graph and offline Research artifacts
passed 16 source proof groups and the same 16 installed groups, with zero model
requests. The installed verifier hid development tools and checked unchanged
archive and extracted host bytes. The existing local archive's SHA256 remains
`d5d2517e87cf358cfe6b6d82060719e6be52ce0e5fcf7920fc4729df7d5c8a4f`.
No release was rebuilt or published. Build, formatting, warnings-as-errors
compile, pinned CI action policy and the isolated credential-free demo passed.
Documentation verification checked 227 Markdown files and 2553 local links with
zero errors. Earlier Corpus-only checks remain distinct from this final
shared Graph/Evidence repair. Hosted exact-source verification is a separate
gate after commit and push.

The exact-source [hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39236420160)
at `e77331d22e53714c48ff7c1b93440598e8042a76` subsequently completed successfully
on Ubuntu and macOS. Every one of the 24 steps per job was inspected. All 24
succeeded on macOS; Ubuntu had 22 successes and only the two macOS enforcement
steps skipped. This closes that revision's hosted platform gate, including its
source and installed knowledge proofs. It does not cover later evaluator changes
or supply held-out quality evidence. Older unexplained MCP discovery failures
remain retained separately.

The seven-variant fixtures strengthen the suppression case to require `ok`
retrieval, actual answer preparation for the matching question and abstention
for the no-match question. They continue to reject forgotten and expired text
in model inputs. They use scripted providers and establish no semantic quality.
The scoring thresholds, held-out workload and first-prediction policy are unchanged.
