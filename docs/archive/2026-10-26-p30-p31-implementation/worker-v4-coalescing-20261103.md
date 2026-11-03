# Worker v4 coalescing candidate — 2026-11-03

Historical, synthetic development evidence. This candidate is not promoted and
is not a completed P31 recall qualification. Current milestone status belongs in
[the plan](../../plan.md). The earlier bounded-view candidate and its limits are
recorded in [its review](worker-v4-bounded-view-review-20261103.md) and the
[populated recall receipt](populated-recall-d739-20261103.md).

## Change under review

The Worker-only all-or-nothing observer gathers v4 literal dependencies in their
original relative order and reads them in chunks of at most 32, even when other
versions separate them in canonical dependency order. Each view closes before
v3, v5 or v6 observation begins. Results are reconstructed in the original
dependency order. The per-pass cache remains local; both independent protected
observations, per-record checks, source leases, deadlines, existing authority
budgets and final Collection root/owner fence remain in place. Other consumers
retain their per-dependency observation path.

The internal order of reads and failures changes: v4 observations run before
v3/v5/v6. This is not a claim of identical failure timing or ordering. There is
no relaxed verification budget, deadline, source or consent check. Independent
source review found no concrete authority bypass; this is not a proof of all
interleavings or arbitrary raw-storage rollback.

The files under [the evidence directory](worker-v4-coalescing-20261103/)
include focused patches from commit `d739f4020b73a8784dc74079c7ed6eedf58ead2b`
to the prior bounded-view candidate and then to this candidate. Applying both
patches in a fresh scratch directory reconstructed the four changed source and
test files byte-for-byte. This does not establish that every other file in the
isolated snapshot matched that commit. [The evidence manifest](worker-v4-coalescing-20261103/evidence.sha256)
has SHA-256 `8823310014c92bd5f72f64e44df8bdb5f775d5a6d6b4e9d4400bed9b8244ab30`.
The full build artifacts are not archived; the recorded build manifest
fingerprints 641 isolated ebin files and the native helper, not the entire
filesystem or every source and toolchain input.

## Focused checks

The isolated snapshot rebuilt its native helper and ran
`MIX_ENV=test mix compile --force --warnings-as-errors`. The
[compile log](worker-v4-coalescing-20261103/coalesced-compile.log) records 192
compiled files and no warnings. No full suite was run.

- `mix test test/ipse/extension/collection_normalizer_v3_integration_test.exs --only managed_v4_batch --seed 0`:
  [2 passed](worker-v4-coalescing-20261103/coalesced-batch-tests.log). These
  cover existing signed batch behavior and invalid members.
- The same file with `--only managed_v4_batch_fence`:
  [2 passed](worker-v4-coalescing-20261103/coalesced-fence-tests.log). These
  cover root change during a batch and actual native owner loss.
- With a fresh isolated eight-source `split8` fixture and
  `IPSE_LITERAL_AB_ROOT` set to that fixture, the Session test with
  `--only managed_pack_actual_overflow --seed 0`
  [passed](worker-v4-coalescing-20261103/coalesced-mixed-session.log). It
  asserted canonical v3/v4 interleaving, identical ordered Worker and approval
  current values and proofs, and two successful `managed_records/5` calls in
  total across the independent Worker passes. A test-only descendant trace
  counted call arities without passing arguments to its collector. The result
  supports one batch call per pass for this fixture; it does not directly count
  native view openings. Same-key conflicting dependency, missing original,
  artificially expired historical dependency and already-revoked consent each
  withheld the callback. The latter three conditions existed before the call;
  they were not changes interposed between the two passes. The
  [seed log](worker-v4-coalescing-20261103/coalesced-eight-seed.log) is entirely
  synthetic and records its native reviews. That fixture's consent was revoked
  by the test and must not be reused as if fresh.
- The same normalizer test file with `--only managed_v4_33_distinct --seed 0`
  [passed](worker-v4-coalescing-20261103/coalesced-33-distinct.log). The
  fixture published 33 distinct signed synthetic literals, refused a single
  33-item batch, and read 32 plus 1 under one DomainAuth capability. Returned
  keys and values matched reversed request order and all returned root
  witnesses matched. The fixture supplies trusted synthetic proofs. It does not
  run the Worker reducer, establish real source ownership, count individual
  signature verifications, or interpose a root change between chunks.

The [formatted source manifest](worker-v4-coalescing-20261103/coalesced-33-source.sha256)
and [runtime inventory](worker-v4-coalescing-20261103/coalesced-33-build.sha256)
were verified before and after the 33-record check. A previous source manifest
records the eight-source Session test before the 33-record test was added.
Independent review checked the test code, log scope and both manifests without
running the tests.

## Why this candidate was investigated

A separate redacted diagnostic ran the *earlier* bounded-view candidate, not
this coalescing candidate, in a fresh Session against the synthetic 2,000-note
cohort. Its final observed input had two successful observations of 2,292.405
and 2,129.891 ms. The three v4 chunk calls within those passes totaled 2,131.051
and 1,956.492 ms, respectively; their nested `managed_records/5` calls totaled
2,074.087 and 1,865.752 ms. Inner and outer durations overlap and must not be
added together. The input-to-outer-call join is a unique temporal match, not a
proven process ancestry link. The trace redacts call arguments, so it does not
establish chunk sizes or why there were three chunks. Tracing may perturb the
timings. The [redacted events](worker-v4-coalescing-20261103/trace-events.jsonl),
[summary](worker-v4-coalescing-20261103/trace-summary.json) and
[post-check](worker-v4-coalescing-20261103/trace-comparison.json) are retained.
The diagnostic does not prove the cause of the preceding untraced failure.

The changed host has not been run on that cohort. Saved consent pins the full
extension identity, including the host BEAM digest; a separately built host with
the changed `ManagedUse` cannot honestly satisfy the old identity pin merely by
using the same Knowledge artifact. Do not substitute a forged host identity or
silently replace the policy. A new synthetic authorization and separately
identified Session would be needed for a changed-host populated test. Original
source inodes and any prior unknown Session must not be replayed or altered.

Outstanding checks include a 33-distinct-note actual Session with real source
owners, mixed v5/v6 cases, relevant interposed expiry/revocation and source/root
boundaries, a current-runtime populated journey, and the required broader
milestone verification. No 2,000-note success or complete P31 claim follows
from this receipt.
