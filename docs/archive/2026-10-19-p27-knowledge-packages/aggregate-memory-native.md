# Native aggregate-memory collector, 2026-10-19

Historical implementation and verification record after `19d67d2`. This is the
first native backend unit of the [aggregate design](aggregate-memory-design.md),
not P27 completion. The [plan](../../plan.md#p27-optional-research-graph-and-rag)
owns acceptance; the [training exercise](../2026-10-22-before-structural-consolidation/docs/developer/knowledge-evaluation.md#exercise-the-native-aggregate-collector)
and [native protocol](../../../native/README.md#optional-exact-aggregate-memory-scopes)
own current procedures. The user approved the optional systemd user-service
tooling dependency; its source, scope and license are in the dependency inventory.

## Implement the native lifetime boundary

The separate root/cell mode creates fresh scopes and uses clone-into-cgroup before
application exec. Retained counter and kill descriptors bind measurement and
cleanup to those scopes. The outer counter stays unreset; each nested cell owns
an independently reset parent-interval FD and its own fresh lifetime counter.
A private native anchor holds the cleanup capability outside the cell it owns.
Collector loss closes its lease and kills that cell while the outer application
remains alive. Child exec closes its inherited lease, and SIGCHLD normalization
keeps terminal status collectible.

Started and terminal receipts are exclusive, synced private files. Terminal
publication follows scope population confirmation and cleanup. Child logs are
bounded opaque data, separate from the trusted M metric frame. A diagnostic E
frame or an absent terminal receipt does not establish that no work occurred.
No helper failure permits automatic replay.

## Challenge the whole collector

Two read-only contexts reviewed the entire first implementation and its actual
verifier. Both found the preclosed-owner admission gap. One also reproduced lost
cancellation through buffered stdin and identified inherited ignored SIGCHLD;
the other found the missing surviving owner after nested collector death and the
weak equal-size interval test. The lead accepted all five findings.

| Finding | Repair and permanent control |
| --- | --- |
| Owner already closed before launch | Check raw owner state before admission, again before clone, and ahead of completion handling; a closed-exec bootstrap must create neither command marker nor output directory |
| Buffered cancellation hidden from FD polling | Use bounded raw FD reads; keep the owner open while sending a 4,096-byte message ending in C |
| Ignored SIGCHLD auto-reaps measured children | Restore default child handling before retaining children; nested launch explicitly starts with ignored SIGCHLD |
| Cell collector death leaves live descendants | A separate lease anchor owns the retained kill FD; kill the nested collector while its outer caller stays alive, then prove cell emptiness and absence of a successful receipt |
| Equal nested allocations cannot prove interval reset | Use 256-MiB then 64-MiB cells; require the second parent interval to fall below the first while the whole lifetime retains the larger peak |

The strengthened controls fail against the retained pre-repair collector. Both
original reviewers independently traced the entire repaired collector and found
no remaining findings. A fresh third context then read the complete native
implementation, verifier, fixtures, ExUnit coverage and whole affected manuals,
and also reported no actionable findings. These are independent contexts, not
claims of model diversity. Linux execution below was performed by the lead;
reviewers distinguished source review from their local checks.

## Direct final-source evidence

The recorded Linux controls used Serenity's installed systemd 262, distribution
package `262-1-arch`. This is provenance for those runs, not a version allowlist
or a requirement to use that host for another experiment.

The strict Linux build uses `rustc --edition=2021 -D warnings` and passes.
Final native source SHA-256 is
`b5acb7f4e8327a0bc8beee393a5649f32e0d21bb4b28e4040ba047210cfdb8aa`.
The independently checked whole-review inventory matches the final native,
verifier and fixture source hashes.

| Actual Serenity control | Result |
| --- | --- |
| Two serial 64-MiB allocations | Charged peak 68,530,176 bytes |
| Two overlapping 64-MiB allocations | Charged peak 136,290,304 bytes |
| Brief 256-MiB child through actual ERTS Port | Charged peak 343,683,072 bytes |
| Nested cells and independent parent intervals | Passed; whole peak 271,204,352 bytes |
| Timeout with a detached descendant | Scope empty, cleanup confirmed, interrupted outcome retained |
| Owner EOF after launch | Scope empty, cleanup confirmed, interrupted outcome retained |
| Root collector SIGKILL | Started record retained, final receipt absent |
| Preclosed owner | No output directory or application marker |
| Owner-open buffered cancellation | Observed and cleaned promptly |
| Nested collector SIGKILL with outer caller alive | Cell empty, no final cell receipt; outer application completes |

The nested controls also pass with inherited ignored SIGCHLD. There are zero
model requests and no sampling. All transient measurement services are gone.
Private final synthetic evidence is archived with SHA-256
`07e36e4f8e71a74cd43062d3036c990fc7c72b16eb24d8aa5697f4fb8bd2e435`.
The initial seven-control pass is retained separately and does not supersede the
later findings or strengthened controls.

## Local source and installed checks

The complete source suite passes 1,249 tests with 33 explicit exclusions in
724.5 seconds, with the strict stdio probe enabled and the unchanged 60-second
per-test deadline. An older completion wrapper then failed because it expected
32 exclusions. The new optional `memory_scope` test accounts for the extra
exclusion; the new untagged admission test accounts for the extra pass. The
original log and wrapper failure remain retained. A corrected count-specific
guard confirms the completed summary and absence of SIGTERM. The suite was not
rerun to work around that wrapper error.

Build, formatting, warnings-as-errors compilation, CI policy and the scripted
demo pass. Direct Elixir 1.18 formatting checks match the changed Elixir files.
The actual macOS native/stdio suite passes 30 tests with six exclusions, and the
native policy binary passes four tests. Its standalone test compile emits the
existing unused `run_anchor` warning; the strict Linux helper build is warning-free.

A fresh macOS package and its extracted-runtime verifier pass. The installed
helper separately refuses the unsupported measurement mode before creating an
output directory or executing its marker command. Archive SHA-256 is
`726aa1b96026080e8ba02ee157fc81e9fc0e81cc4981f6592093ffed0cc5f009`.
This verifies fail-closed macOS behavior, not an exact macOS aggregate metric.
The whole affected manuals were reviewed with the implementation. A later
editorial correction names the optional measurement test's default exclusion.
At that initial save, exact-commit hosted and full native-enabled Linux gates
were still pending. Their subsequent terminal results follow; earlier
runtime-candidate gates do not cover this native change.

## Exact-commit platform gates

The complete owned Serenity pipeline passes at
`d04b610e3ad37158b7f1b758ab262de9283a5ef1`. Its source suite includes native
sandbox and aggregate-memory tests: 1,267 pass with 15 exclusions in 662.8 seconds.
Build, formatting, strict compilation, CI policy, documentation, demo, package,
base installed checks and all ten installed-helper measurement controls pass.
The Linux archive SHA-256 is
`8f70793294c281f0fedd0d6af5214e1fc919193c2110477dd47206336990a60c`.
The retained evidence includes actual synthetic receipts; an independent archive
read verifies their closed outcomes, source identity and completed suite.

The automatically triggered [hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39344698317)
also completes successfully at that exact commit on Ubuntu and macOS. Each source
suite reports 1,282 total tests, zero failures and 33 exclusions. The macOS native
suite reports 36 total, zero failures and six exclusions, and its four Rust policy
tests pass. Both jobs finish all applicable package, installed, extension and
knowledge proofs. Full terminal logs and status metadata are retained separately.
These gates cover the collector commit, not later sequencing or evaluator changes.

## Remaining integration boundary

This measures the kernel's aggregate charged-memory subject. It is not summed
RSS or complete GPU/device memory, and supplies no exact macOS aggregate.
The current evaluation runner still uses its sampled BEAM observation and marks
resource evaluation incomplete. Complete fresh-cell execution, owned model
service/cache identity, frozen measurement receipts, the full held-out
comparison, independent semantic judgments and engine selection remain open.
The earlier interrupted experiment and its unknown booked liability are untouched.
