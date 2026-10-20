# Bounded fixture completion waits

Historical CI investigation and verification record, 2026-10-20. This test-only
increment follows the [native population correction](../2026-10-20-p27-native-drain/index.md).
Current contributor instructions are in [testing](../../developer/testing.md#diagnose-worker-and-stdio-cleanup).
P27 acceptance remains in [the plan](../../plan.md#p27-optional-research-graph-and-rag).

## Retained hosted failure

The exact `93f71ad54216253da23bd1de4b5847b756515a3b`
[hosted run](https://github.com/lexlapax/ipse/actions/runs/39384645172) failed on
macOS at `mix test`. It reported 1,340 tests, two failures, 34 excluded and one
skip in 1,373.6 seconds. The environment was Elixir 1.18.5, OTP 27.3.4.19 and
arm64 macOS 14, with three schedulers, six test cases and seed 77259.

The pending-question recovery test exhausted its three-second completion
assertion after an explicit answer. The mode/hash-before-label CLI test exhausted
the default sixty-second whole-test watchdog during its third CLI invocation.
Ubuntu was cancelled by fail-fast during the independent source/installed
knowledge proof. Its earlier build, full test suite, demo, packaging, base
installed and extension/model/MCP/embedding/preset proofs passed. Later macOS
native, package and independent proofs did not execute. The earlier green
`f2bfc8d` run does not verify `93f71ad` or either later correction.

These failures are retained. Local timing evidence does not identify the exact
cause of that hosted slowdown.

## Correction and causal evidence

The continuation starts a fresh worker, initializes it, invokes a callback under
the existing five-second Worker timer, closes resources and then reports Session
completion. A three-second observer can expire during a legal callback alone.
The synthetic fixture now deliberately takes four seconds only for the selected
checkpoint. Its final completion wait is twenty seconds. Runtime deadlines and
the inert-resume, unchanged-journal, unchanged-callback-log, answered outcome and
exactly-two-callback assertions remain intact.

In an isolated candidate, the deliberate callback failed the old three-second
assertion. The retained before run reported one failure, 52 excluded and a pending
callback. With the finite twenty-second wait, the selected test passed and the
probe observed a successful 4,004 ms callback with zero pending calls at capture
end. This establishes the observation-budget defect; it does not prove that the
historical hosted callback took four seconds.

The CLI refusal test creates a fixture in one fresh VM and invokes four more
CLI VMs. Its explicit two-minute whole-test watchdog covers that combined work.
All four refusal-order assertions remain. Production model, Worker, native and
inference deadlines are unchanged. Opt-in phase records distinguish fixture
freezing, review, prediction, scoring and tuning with fixed names and monotonic
durations. They print no arguments, paths, dataset/model text or environment
values. They cannot identify the internal child operation responsible for delay.

## Verification and review

The isolated candidate passed both targeted tests, with 75 excluded, in 35.0
seconds. Its complete two affected modules then passed all 77 tests in 262.5
seconds with the existing stdio probe enabled and seed 77259. The candidate
used local Elixir 1.20 and OTP 29. This is not an Elixir 1.18 local check.

A separate read-only internal review traced the Worker timer, Host callback,
Session completion, fixture conditions and bounded payload-free diagnostics. It
found no actionable assertion-weakening, correctness or privacy issue. The
reviewer configuration requested `gpt-6-astra`; this does not certify backend
diversity or external review. A sufficiently overloaded worker may still miss its
unchanged runtime deadline and correctly fail the test.

The contributor testing chapter was reviewed as a whole and integrates a worked
bounded-operation example and executable diagnostic command. The operator
workflow is unchanged. Documentation links and formatting checks passed.

The same 77 affected tests passed in a separate Linux checkout in 240.3
seconds, with the same probe flag and seed. Build, formatting and documentation
checks passed there. The first Linux transfer stopped before tests because macOS
AppleDouble metadata files entered the formatter. That setup failure is retained.
A metadata-free archive supplied exactly the two test files and contributor
chapter to a fresh checkout; no runtime source was altered.

After committing the native unit as `063de411cc5734877f1e6d72f93d987f2eabd49a`,
the repository received the identical reviewed test/manual files. Its two changed
test paths passed again in 31.6 seconds, with 75 excluded. Formatting and final
documentation/navigation checks passed. The complete macOS and Linux source,
native, package and installed baselines belong to the preceding native unit;
they are not rerun or relabeled as this candidate's hosted result.


Hosted verification for the final correction commit remains separate. This
increment establishes no real retrieval quality, completed CPU comparison or
whole-P27 acceptance. The stopped experiments retain their original evidence.
