# P30C coverage-gap follow-up

2026-10-27. This is an uncommitted pure-policy repair, not an integrated
consumer, engine-quality result, protected freshness check or P30 completion.
The [original component](p30c-pure-policy.md) and its
[independent audit](p30c-pure-policy-audit.md) retain their historical evidence;
that audit did not cover this change.

The planner previously reported unknown/unavailable eligibility, incomplete
coverage or a fitting set with missing rows as a zero-call gap while retaining
a candidate pack as its baseline action. A future caller could interpret that
pack as a selection even though the data did not establish one. The planner now
returns a null action in those cases, with an explicit eligibility or coverage
reason. Null means no selection was established, not that the eligible set is
empty. The check applies in production and development, including strategy none.
Available complete fitting sets still return every supplied record; zero-call
behavior remains, and source facts still grant no authority.

Synthetic controls cover unavailable and unknown eligibility, incomplete
coverage, fitting totals without all rows, both planner modes and strategy none,
plus unavailable candidate assessment. The original current-set, pack-byte,
threshold and validation controls remain. A root working-tree focused run
passed 19 tests, seed 20270422.

A separate graph reconstructed from `668e6a3` with the policy, its test and the
developer chapter overlaid had private index tree
`e8366648079e1cc4533e61ab252f35826779f113`. Nine focused suites passed 56 tests,
seed 20270423; the log `_build/p30-coverage-validation-20261027.log` hashes to
`4049e9ac857e03a4e6776534cf98709c316aa9fcd1007f5a13e483a3ab812358`.
Tracked bytes matched the private index; formatting, forced strict compilation
of 141 project files and documentation checks passed. The copied production
helper SHA-256 was
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`;
no protected storage workload or model request was run.

Current policy and test SHA-256 values are
`375a173bae02bb043bb3094d5ecea9fbfdacce15387e566e0b80b4d9fd66189f` and
`1df7b729c8c305e7b9b592b383651b8821a559013a8c6a6e322b5307f1c68ff1`.
The actual managed reader, authenticated coverage and allocation, host operation
admission, registered helper integration, experiment runner, installed journey,
model quality, full baseline and adversarial review remain open. No production
consumer is qualified by this repair.

A later test-only continuation exercised the coverage gap in the actual rebuilt
Knowledge artifact under its minimal public SDK, in both production and
development modes. It also verified that substituting a candidate pack into a
null-baseline plan fails the planner's reconstruction check. The isolated nine
suites passed 56 tests again, seed 20270426, on private tree
`00c8aad3957bdf12f674d62df12d8a212704a191`. The retained log
`_build/p30-coverage-validation-20261027-r3.log` hashes to
`62831a3e08619df4f9cd7bd1aa3dbb91b3a4d0643f2c6364650883e2738bd623`;
the updated test source hashes to
`128115a03cebe29f87236918b049b79244dd38eaa19b0d0c1b7bd105f1962259`.
This still does not authenticate coverage or exercise a live consumer.

## Missing candidate-pack continuation

The earlier correction did not cover complete aggregate metadata with a
nonempty eligible set but no usable candidate pack. The pure planner returned
an empty selection in that case, even though its untrusted facts did not prove
that the eligible set or a possible selection was empty. A new regression
reproduced this in production planning (seed 46300). The uncommitted repair
returns a null action when no pack is established; a true zero allocation still
returns an empty projection, and a complete fitting set still returns all its
supplied records. This remains data-only policy and confers no host authority.

The current working-tree policy, neutral decision, provider wire, transport and
profile suites passed 33 tests (seed 46301). The separately built Knowledge
artifact with its minimal public SDK also exercised the new null-action case in
both modes; the policy file passed 13 tests after that control was added (seed
46302). This is synthetic component evidence, not an integrated consumer,
qualified model or final adversarial audit.

## Aggregate byte consistency

Complete coverage previously admitted an aggregate whose eligible count exceeded
the supplied candidate count while its byte total left no bytes for the omitted
records. A synthetic counterexample produced a decision request from those
contradictory facts (seed 46320). Since each valid rendered record has at least
one byte, the uncommitted planner now requires the aggregate to include at least
one byte per omitted eligible record. Equality at this lower bound is accepted;
it is a consistency check, not authentication of counts, coverage or eligibility.
The decision policy, neutral validator, wire, transport and profile suites passed
34 tests (seed 46321). The policy suite then passed 14 tests with an additional
separately built minimal-SDK artifact control (seed 46322). No engine was called.

## Facts-size boundary control

The planner advertises a 16 KiB encoded facts limit. The policy delegates this
bound to `Ipse.Extension.validate/1`, which uses the host JSON object validator;
there is no separate policy-local size comparison. A working-tree boundary test
now checks both selection and assessment in production and development modes:
exactly 16,384 encoded bytes are accepted and 16,385 are refused. The policy
suite passed 15 tests, seed 46380. This checks synthetic data and does not
qualify an integrated consumer or an engine.
