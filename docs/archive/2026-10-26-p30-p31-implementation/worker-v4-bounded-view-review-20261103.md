# Worker input: bounded literal-view candidate — 2026-11-03

This is a review of an isolated candidate, not an accepted runtime change or
completion of the [notes journey](../../plan.md#execution-order-for-p30-and-p31).
The candidate is based on commit `d739f4020b73a8784dc74079c7ed6eedf58ead2b`;
its source and tests were retained in `.recall-v4-d739.qivO7mmY` during review.
That temporary location is not durable evidence by itself.

## Change and independent review

For an all-or-nothing protected Worker input observation, consecutive version-4
literal dependencies can share an owner-bound Collection read view in batches of
at most 32. The same view is closed before a version-3 root, version-5 history
or version-6 accepted-decision observation. Other consumers retain the original
per-dependency observation path. The candidate keeps the original result ordering
and deduplication key, two separate current-policy and signed-record observation
passes, original source leases, final retained Collection root/owner checks and
native Worker input handoff. It adds no deadline, provider or permission.

Independent source review found no concrete authority or ordering bypass in this
scope. Each selected read still reacquires the Collection owner and checks the
exact root; each literal retains recipe, signed-page, source-category and expiry
validation. With the current literal-read recipe, 32 records use 416 of the
view's 512 observation units and 160 of its 512 reads; their 96 signed-page
verifications remain within the existing 128-verification domain limit. The
separate domain byte and time bounds still apply. These counts are not measured
performance or permission to expand those limits.

## Exact focused evidence

The six-entry `v4-final-source.sha256` manifest, SHA-256
`0ceadc5b14404530cee8fcb2ba2507e5a3ec93ea6845fcc4438f79d3fcb23c9e`,
was written before the final focused runs and all entries matched afterward.
It identifies `observed_read.ex`, `managed_use.ex`, the Collection and Session
test files, and the synthetic literal seed and runner. The latter two add a
`split8` fixture: eight literals have eight independently closed original
Session sources. The eight-entry final log manifest,
`final-test-logs.sha256`, SHA-256
`b2b63513f6381f82a32d907ccc9adae78b785ff7249da43c40670b25dda2dc31`,
also matched. The manifests and logs are retained with the isolated candidate.
The source manifest does not inventory every dependency, compiled file, native
helper or bundled artifact; those need their own frozen inventory for a further run.

The final serial focused controls reported:

| Selection | Result and scope |
| --- | --- |
| `managed_v4_batch` | 2 passed: two distinct signed literals match individual reads; a 32-entry repeated-literal boundary and invalid members are checked. |
| `managed_v4_batch_fence` | 2 passed: a root change between reads refuses the batch; loss of the native owner withholds it and preserves an unknown outer outcome. |
| `managed_pack_actual_overflow` | 1 passed: eight-source synthetic Session positive. |
| `managed_pack_actual_overflow_stale` | 1 passed on a separately seeded home: source loss blocks the decision and later Worker input. |
| `worker_input_boundary` | 2 passed: current output delivery and revocation before the next callback. |

The final formatting check and strict incremental compile passed; the isolated
build completed after the repairs below. These are eight focused tests, with
other cases excluded, not a complete module or full-suite result. The eight-owner
Sessions use synthetic local provider responses, not a real account or human.

The first format attempt refused a syntax error; after that correction the
first strict build refused a noncontiguous-function-clause warning. A later
build and format check passed. The initial stale-source test stopped before
dispatch while reusing the positive test's protected home: the saved service
origin and the new synthetic listener's port differed. That is a plausible
pre-dispatch service-identity conflict, but the journal did not preserve the
inner error, so the exact cause is an inference. A separately seeded stale
control passed. An initial owner-loss test expected a known refusal but observed
`{:unknown, :project_identity_lock_lost}`; the corrected assertion preserves
that uncertainty and the final fence tests passed. Original failed logs remain
in the candidate snapshot and in `v4-focused-evidence.sha256`.

## Remaining checks

The 32-entry control repeats one literal rather than testing 32 distinct
records. Several cross-phase source, consent, owner and expiry races and
multi-chunk ordering remain open. A fresh 2,000-note population is being seeded
using an explicitly clock-instrumented test Runner; **no populated candidate
Session has passed yet**. This candidate does not establish the cause of the
earlier retained-cohort failures, a completed integrated day, annual endurance,
real-model quality, installed behavior or cross-platform qualification.
