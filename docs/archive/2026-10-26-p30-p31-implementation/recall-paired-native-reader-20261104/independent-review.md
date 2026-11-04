# Independent paired-reader review — 2026-11-04

Accepted exact four-file patch SHA256
`57d411afed6313cfc8241a360bd41905bda01fe341b4d581479b026afc01cd5c`.
It is the byte-for-byte concatenation of the reviewed ObservedRead `875226…`,
ManagedUse `446d4b…`, component tests `cb045a…` and worker tests `fc638c…`.
`git apply --check` passed against the current main preimage without mutation.

All 1–32 request/recipe specifications are validated before Collection IO. Each
two-literal scope uses 26 of the existing notes reader's 32 units under the
fixed notes profile. The actual native witness is normalized and checked by
the existing root_identity validator, including exact v4/v5 root, namespace,
manifest and root hash. Every pair must match its predecessor's root exactly.

The adapter reuses unchanged held_values, neighbor and signed literal validation
code. Its callback returns the existing two-tuple success contract containing
plain historical data. Collection's native check/release completes before the
caller receives those data or starts the next pair. No read closure or native
capability escapes, and no StoredSources IO occurs inside this held callback.
Source proofs, policy and expiry are derived/rechecked afterward as before.

Only worker v4 observations select the new adapter. The old managed_records and
ReadView remain unchanged, preserving their separate view/corruption/barrier
controls. The worker retains fresh caches for its independent passes and a
separate final actual native-root match. Reusing a checked root identity within
one pass supplies neither permission nor ownership across passes.

The held route does not allocate a ReadView cache, so its separate four-MiB
encoded cache envelope no longer governs this path. This is a deliberate
availability/resource difference accepted by the parent. Existing eight-MiB
decoded block, 8,192-record index, selected value/reply and 32-unit scope bounds
remain. Exact observation/proof/current-authority equivalence is required for
originally accepted inputs; identical refusal outside the old cache envelope
is not claimed.

A draft callback originally returned a three-tuple that the existing Collection
contract would reject. Review caught it before compilation/execution, and the
adapter-only correction preserves that contract. The old draft remains retained.
No production hook or native protocol change was added for tests.

Independent receipt inspection confirmed the first focused component run:
55 outer tests, 50 excluded, five executed and zero failures; six postchecks
zero. The new component compares three genuine signed literals with both old
batch and singular observations, counts real quota calls 16→2, and rejects an
invalid member and 33 requests. The added 33-distinct control compares 32+1
paired observations and ordering against the old implementation, requires 16+1
quota calls and a direct-33 refusal before any inventory. Its execution and the
final paired-worker focused run belong to the sibling's separate receipts.

The earlier authenticated root-reuse worker case independently passed one of
202 tests with 201 excluded, exact reviewed source/tests and all postchecks
zero. It covers independent pass counts, no extra v3 root reads in a mixed
pass, v3-only fallback, conflicting v3/v4 claims, source loss, expiry and
revocation. Deterministic root changes specifically between passes, after the
second observation before final native use, and across changed >32-record
chunks remain explicitly unexecuted. Existing unchanged fences were read;
these receipts do not pretend to be those interpositions.

The separate populated storage-only benchmark found 32-literal elapsed time
4.14→2.50 seconds with exact outputs and unchanged original/runtime state.
It is an instrumented private storage comparison, not current-use, retained
recall, annual feasibility or installed qualification. No further benchmark
or retained consumer was run by this reviewer.
