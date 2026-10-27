# Question fixture repair against the frozen P30B baseline

Date: 2026-10-27. Test-only correction of seven question integration failures
in the frozen full-source baseline. This record establishes no product change,
full-suite pass, live model access or native platform qualification. Current
verification guidance belongs to the [developer testing chapter](../../developer/testing.md);
operator recovery belongs to [the recovery manual](../../operator/recovery.md).
The [plan](../../plan.md#p30-advisory-decision-engines) owns milestone acceptance.

## Failure and exact test correction

The original question fixture counted every user-role message after the two
header messages as an operator turn. Current host Reference envelopes have that
role, so the fake provider chose `clarify-2` for the first prompt, then changed
the question ID again after an answer. Four cases failed their existing
completion or exact-ID assertions. The repaired fake excludes only messages
accepted by public `Ipse.Session.Reference.reference?/1`. A new control keeps
ordinary user messages and invalid reference markers in the turn count; it does
not filter arbitrary prose, roles or marker presence.

Two pure Saved fixtures supplied `"test"` as a Session ID. SourceWindow's current
SourceIndex constructor requires the same 32 lowercase hexadecimal characters
used by real journals. The fixtures now use a valid fixed synthetic ID. No
production constructor or validation was changed. Their normalized pending views,
ordering, corruption precedence and scaling assertions remain intact.

The damaged pending-question case changes a question's prefix digest. Its
durable lifecycle wait already binds that exact question record through
`subject_source`. The test now proves the original source matches, the modified
record does not, and the earlier exact `invalid_runtime_lifecycle` refusal occurs
without modifying the damaged journal or starting provider work. It does not
broaden the expected errors or rebind a corrupt record.

Once the turn-count repair exposed the repeated-answer case, its malicious
rewrite reached another existing earlier guard: changing an earlier answer's
encoded length invalidates absolute source offsets for a later question. Pure
`Saved.restore/2` still must return `invalid_operator_question_checkpoint` for
the damaged answer. Actual source validation and Session resume must return
`invalid_runtime_lifecycle_source`, preserving the damaged bytes and starting no
provider. Both paths have separate exact assertions.

All prior question/answer, approval separation, unknown outcomes, cancellation,
headless/child refusal, owner loss and no-replay checks remain. No deadlines,
runtime source, dependencies, provider selection or helper bytes changed.

## Fixed inputs and before/after execution

Original frozen graph:
`/tmp/ipse-p30b-components-baseline-20261027-01`.
Own copy: `/tmp/ipse-questions-fixture-20261027-01`, with its own `tmp` directory.
Both project and complete compiled application/dependency graph were copied;
tests ran with direct Elixir `-pa` against that copy, without Mix or compilation.
The existing project `deps` source symlink was not traversed in the original
regular-file inventory; dependency BEAMs are included and no dependency source
was compiled. The copied helper was used for ordinary Session/file ownership,
with no PTY, rebuild, live provider or network/model request.

The original manifest has 2,304 regular project/build paths and SHA256
`24206c71b2337bb45f0bfa9ee79a8135c4e944ab521f713d61f5a4f4d5ea54d1`.
The first strict comparison identified exactly the known full-suite execution
output `build/lib/ipse/.mix/.mix_test_failures`; its hash changed during Root's
original full test execution. Excluding only that cache leaves 2,303 exact
original source/runtime inputs before and after the unchanged reproduction.
After the candidate, exactly the owned test differs; the other 2,302 inputs and
all compiled runtime/helper bytes remain unchanged. No frozen input was rebuilt.
The initial strict-comparison failure is disclosed from the author tool output;
it was not separately captured as a raw log. The corrected inventory control,
its unchanged-before output and final candidate output are retained.

| Check | Actual result |
| --- | --- |
| Unchanged question suite | 6/13 passed; same seven failures; 7.1 s |
| First candidate | 13/14 passed; newly exposed answer-source error expectation; 1.3 s |
| Final question candidate | 14/14 passed; 1.4 s |
| Five-file related command | 45/46 passed; 3.2 s; unchanged out-of-scope Saved fixture failure retained |
| Actual Elixir 1.18.5 formatting | Owning test formatted; host OTP 29, not an OTP 27 execution claim |
| Whitespace | `git diff --check` passed |

All ExUnit runs use seed `20261109`, maximum cases 1, the same compiled runtime
and isolated TMPDIR. The related command includes the repaired question suite,
pure questions, RuntimeLifecycle, Saved and Reference replay. All 37 cases across
the first, second, third and fifth files pass. Saved passes 8/9; its unchanged
case at `test/ipse/session/saved_test.exs:213` assumes the last provider input is
the fresh user prompt, although a valid host Reference now follows it. That
same failure occurs in Root's frozen full baseline and remains outside this
repair. The 45/46 result is not relabelled a passing suite or silently omitted.
Root owns the full baseline's other failures and repairs.

Original test SHA256:
`fd5d588467f979ed3e2dd77c7346c29eb7a0c047a7693324d0ed16f847e8cbd0`.
Candidate test SHA256:
`dcdf715619b44d850015e553055f5f6ab34cc1bd8482ab725009c33c560bfdfe`.
Actual copied helper SHA256:
`d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`.
Compiled Runner SHA256:
`128ca19b18c90f049b6a796671473d0ef3fa3c3d7b05cd7be3c231bc53502d42`.

## Evidence and reproduction

Durable evidence:

```
/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/questions-fixture-repair
```

It retains the original full-baseline log, unchanged reproduction, both candidate
runs, related failed command, original/candidate test bytes and full regular-file
manifests, exact helper and relevant BEAMs, drivers, format control and preservation
receipt. `files.sha256` binds these retained payloads with SHA256
`fd91ae9ea606415b4576da0b2e6377a579e93e30cf72790b66195f1dea2684b6`.
The full original and private project/build graphs remain at their declared paths;
the durable directory preserves manifests and selected executables, not another
complete graph. No durable payload is a private transcript or qualification input.

To repeat, copy the frozen graph into another private directory, preserve the
compiled application/dependency paths and its `priv` resolution, and adapt the
retained driver's absolute build path. Run from that private project with private
TMPDIR. Do not execute or modify retained evidence in place. The essential command
used here was:

```sh
TMPDIR=/tmp/ipse-questions-fixture-20261027-01/tmp \
  elixir -pa '/tmp/ipse-questions-fixture-20261027-01/build/lib/*/ebin' \
  /tmp/ipse-questions-fixture-20261027-01/run.exs
```

The driver starts the copied application, requires its test helper, configures the
fixed seed and maximum cases, and requires only the owned question fixture. The
related driver explicitly lists its five files. No current mutable checkout
module was compiled into either command.

The complete developer testing and operator recovery chapters were reviewed for
consistency. They already require original-failure preservation, source validation
before repair, exact typed refusal and no automatic replay. Their product
procedures require no change for this fixture-only correction. Documentation
links are checked separately; no new complete baseline, package, installed,
macOS, OTP 27, live account or model verification is claimed.
