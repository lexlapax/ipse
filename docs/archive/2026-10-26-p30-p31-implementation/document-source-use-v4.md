# Document source-use v4 guard — focused candidate

2026-10-29. This Host-only section implements the ordered-page portion of the
[shared producer v4 design](shared-producer-v4-progression-design.md); it does
not open a public producer path or qualify group completion. The existing v3
claim and version-1 guard relation remain separate.

A version-2 guard retains the exact five existing fields and accepts only a
canonical `genproducer4.<partition>.<ordinal>` slot, with ordinal 0–31 and no
leading-zero aliases. It must address a closed pending version-4 claim whose
ordinal equals its eight-aligned `vector_cursor`. `pending?/2` checks that closed
shape, bounds, prior-ready descriptor and page input count. `ready?/2` checks the
separate compact ready shape, including selection, cursor, original claim,
page and bounded per-call receipts. These pure Host-private predicates grant no
storage, inference or terminal-group membership authority; their callers still
have to authenticate the relevant stored row, revision and hash.

The existing `authenticate/4` independently loads and authenticates source heads
and complete bounded bundles, recomputes the total number of captured chunks,
and checks the exact ordered source/chunk positions starting at the claim's
vector cursor. It checks each represented original byte range, chunk identity,
raw and canonical input hashes and the actual batch input. It does not implement
the extension's chunking policy or claim that a previous ready page belongs to
a completed group. The native caller still owns actual retained reads, current
authority, operation binding and final inference admission.

Two focused synthetic relation tests passed on the new graph. A real producer
seed with one authenticated 11-chunk source exercised the first eight positions
and the final three-position page, including both of its short inference batches.
Changed claimed total, reversed positions, wrong guard version, malformed slot
aliases and altered pending/ready/receipt shapes refused. A 256-count/slot-31
case checks structural maximum bounds only; it is not an actual 256-chunk or
native-capacity qualification. Two existing v3 source/anchor regression tests
also passed on this graph. Strict single-module compilation passed. These tests
use synthetic in-memory storage closures, not a new native owner or live model;
no aggregate suite or effect replay ran.

The [evidence](document-source-use-v4/) retains the exact Host module, test,
domain chunker and original seed, changed BEAM, complete 669-file inventories
for base and candidate, their one-BEAM difference, and focused logs. The base is
`_build/document-source-use-sol-20261029`; the candidate is
`_build/document-source-use-v4-sol-20261029`. Helper SHA-256 is
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
This is not a combined current Session/producer graph, multi-page terminal
membership, installed-package, non-Linux or full P30/P31 acceptance claim.
