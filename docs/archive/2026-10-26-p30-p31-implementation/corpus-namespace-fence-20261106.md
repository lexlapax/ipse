# Corpus namespace revalidation candidate — 2026-11-06

Historical synthetic development evidence. The [plan](../../plan.md) owns
acceptance status; the [Corpus manual](../../operator/corpus.md) and
[extension training](../../developer/knowledge-extensions.md) describe current
use and implementation.

A synthetic State fixture reproduced a source insertion after snapshot capture:
the previous query returned one source while reporting complete, revalidated
coverage. The candidate compares the selected store's generation at final
revalidation with its captured generation. Empty snapshots use a bounded
generation read; successful 33–64-token batch revalidation retains its
cross-chunk generation. A later file-current check repeats the namespace fence
using accumulated invocation counts. This may conservatively conflict on an
unrelated same-scope write, and MCP generations remain service assertions.

An author-run, warning-free source fixture passed eight synthetic controls,
including State/MCP paths, remote selected references, empty snapshots,
unknown/denied outcomes, a simulated document-current callback and 64 synthetic
token rows. A separate corrected compatibility fixture passed 25 controls,
including 32 synthetic fetched sources and 32 actual selector records through
the existing in-memory Research fixture. Collection controls established only
initial routing. Its first attempt passed its assertions but failed its wrapper
because the wrapper expected an incorrect exclusion count; that failure remains
separate. The repository wrapper then passed one outer test with a freshly built
Graph helper and all eight inner controls. Its log SHA-256 is
`945cc092c4be600b2882bdd28712b941966c698a7554cf898162e5bc31d272d0`.

The namespace-only Corpus source SHA-256 was
`dc5d3c1bee4011201805b359558943a5b38393fcb78536ceccc061ff0c872dad`;
the Store source SHA-256 was
`6782be241d5189bca46446937fc54b0baa481814b28ddd45f90d1c75825b5e98`.
A later [full-snapshot time-bound candidate](corpus-query-time-20261106.md)
has separate synthetic controls. Its check before proposing reranking does not
control a later approval or dispatch; remote-selected and Collection completeness
remain outside that time bound.

These checks do not establish a real filesystem document check, full Collection
result, external MCP, installed artifact, native Session or complete P31
qualification. Clock rollback and recovery between samples and the period after
the last observation remain separate limits; this is not a lease through delivery.
