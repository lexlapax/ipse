# Complete fixture repeat and native CLI exit ordering

Dated **2026-10-27**. Historical receipt after the
[reference-aware fixture repair](reference-fixture-repair.md). The
[plan](../../plan.md) owns remaining implementation and acceptance; the
[testing chapter](../../developer/testing.md) owns fixture guidance.

The private graph `/tmp/ipse-reference-fixture-repair-20261027-02` completed the
full `mix test --no-compile --seed 20261109 --max-cases 2` repeat with its copied
test build, two schedulers, private TMPDIR and repaired private Git setup. It
exited **2**, after **1,680.1 seconds**:

```text
Result: 2418/2419 passed, 4 skipped, 36 excluded
Failed: 1 test
```

All 44 originally failing cases passed in this run. The sole new failure is
`Ipse.CLIOperatorInputTest` at `test/ipse/cli/operator_input_test.exs:46`, timing out
inside `System.cmd` at line 76. The full run's sparse diagnostic cannot establish
the exact terminal phase. Its native child watchdog and enclosing ExUnit case
both retain 60-second limits; the enclosing case can expire before the child
prints its buffered terminal output. No limit was changed to obtain a pass.

All **2,303** admitted source/runtime files matched before and after the repeat;
only Git metadata and the declared Mix execution cache are outside that seal.
Manifest SHA256 remains
`a25520ddda629e3f9120e2d52e0fa866985047e2b7b8d6f1567c56ca6082255b`.
Full failed-log SHA256:
`54877213da7b254e9e55422db1d8dc6f605c35995336cffcac49b439ef8b138d`.
The graph includes the twelve fixture repairs and committed question changes;
new DomainAuth/neighbor/current-reader integration is outside this runtime.

## Independently reproduced fixture stall

The [independent triage and exact evidence](cli-pty-fixture-audit.md) first passed
the four unchanged cases, then reproduced a concrete stall with the unchanged
PTY driver on conversation five after four passes. At 60,017 ms it retained raw
stdout ending with `you> ` before `Finished.`. Its synthetic journal already
contains the verified native answer and successful finished turn. The fixture
never sent `/exit`, because it required another prompt after completion.

The actual CLI starts its next prompt reader while a turn is finishing. Its
reader identity does not change solely on busy-to-idle, so retaining that reader
without a second display is valid. The same-fixture reproduction identifies an
exit-ordering defect; it does not retroactively invent a terminal transcript for
the original sparse full-run timeout.

The reviewed repair requires completion plus the latest normal prompt occurring
after the latest question prompt. Either valid order relative to completion is
accepted; historical initial prompts remain insufficient. It changes only the
synthetic driver's final exit phase. All native question, exact input/source,
fresh choice, literal Unicode, no-effect, saved reconstruction and confirmed
cleanup assertions remain. Production source and helpers are unchanged.

The clean Rust source contains seven portable readiness controls. A new ExUnit
case compiles and runs those same controls with `rustc --test -D warnings`, making
them part of ordinary Mix verification. The four original ExUnit cases remain
unchanged. Root reviewed both files and applied the exact patch:

`3ca24d102f673b77972cb311e256982fc0ba89d3332bb2635b6f2e7d1eaf691e`.

| Candidate check | Actual result |
| --- | --- |
| Private captured-stall plus portable Rust controls | 8/8; one private evidence-dependent case excluded from the clean patch |
| Clean portable Rust controls | 7/7 with warnings denied |
| Original four native CLI cases with candidate driver | 4/4, original deadlines and assertions |
| Finite actual repeated conversations | 20/20; three prompt-before-completion and seventeen completion-before-prompt |
| Final real Mix suite including the new unit wrapper | 5/5; seed 20261113, maximum cases 1; 3.0 seconds |
| Exact frozen owner/private inputs after all checks | 2,303/2,303 unchanged; helper unchanged |

This is independently authored diagnosis/candidate work and Root's patch review,
not an independent audit of the reviewer's own repair. The initial sandbox 0/4
attempt is retained separately: its non-root-owned sandbox `/tmp` fails the
native protected-temporary-root requirement. Authorized native execution used
the real filesystem boundary without weakening that guard. Native operator/PTY
windows were kept serial and explicitly released.

## Preserved evidence and open baseline

The full failed repeat and its exact runtime, original stalled conversation and
synthetic journal, positive/reordered cases, private and clean candidate variants,
final two-file patch, Rust/ExUnit outputs and before/after manifests are preserved
under `p31-verification/independent-cli-pty-triage` in the task's owner-only artifact
root. Report SHA256:
`01ee8628882490e310051c2b13508df9166961933223141a17eac11003801166`.
Its 2,478-payload manifest is
`ca5cc053662e5b14f631b6b62ab517f53a7fb1d31b9ba6e8df30cb546ebb3626`;
preservation receipt:
`916902b3fa054b4684a430c5462196a346d0dd4ba6b3e60f35944dd9fb355588`.
Directories are 0700 and regular single-link data files 0600, with byte checks and
file/directory sync. Execute only disposable working copies, with executable
working helpers and private TMPDIR; never modify retained evidence in place.

The complete full repeat remains **failed**, even after the focused repair
passes. Another completed fixed-source baseline is required after integration.
No package/installed, macOS, human, model/live-account, optional-PDF or
default-excluded OS-enforcement acceptance follows from this record.
