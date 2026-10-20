# Native fixture directory identity

Historical investigation and correction record, 2026-10-20. Source is
`1e31e5bb54ac8a35a7e6b10ff55c88c8006f9c1f`. Current contributor instructions are in
[testing](../../developer/testing.md#test-actual-os-enforcement), and acceptance
remains in [the plan](../../plan.md#p27-optional-research-graph-and-rag).

The macOS [job 118542455311](https://github.com/lexlapax/ipse/actions/runs/39397112612/job/118542455311)
fails the native regular-file copy step. `existing_destinations_and_wrong_sizes_are_preserved`
panics at fixture `Root::new`, line 130, when `create_dir` returns
`AlreadyExists`. The copy assertions have not run. Five other controls pass and
the isolated subprocess entry is ignored. This failure precedes `mix test`,
packaging and the later installed checks, so it is distinct from the preceding
[outer-job cancellation](../2026-10-20-p27-ci-job-budget/index.md).

The fixture name combined a shared process ID with `SystemTime::as_nanos()`.
Parallel threads can observe equal ticks. Nanosecond representation does not
guarantee unique observations. A disposable fixed-clock control creates two live
roots under the same tick using that exact naming formula. It reproduces
`AlreadyExists` at directory creation. The hosted failure retained no clock
samples, so the probe establishes the constructor defect without claiming its
exact historical timestamp sequence.

The correction adds an `AtomicU64` ordinal to the existing process/time name,
inside `cfg(test)` only. `Root::new_at` lets the regression hold the clock fixed.
Both roots must remain distinct while alive. There is no retry, shared-directory
cleanup or change to copy behavior. The source prefix before `cfg(test)` remains
byte-for-byte identical. All size, inode, metadata, symlink, permission, absolute
path and bounded FIFO assertions remain intact.

The unchanged-formula fixed-clock probe fails with exit 101. The corrected
disposable file passes all seven ordinary controls, with one intentional ignored
subprocess entry. The exact corrected file is then applied to the repository
after its unrelated active macOS baseline exits. The native controls are rerun
from that file. The contributor testing chapter is reviewed as a whole and gains
a worked command and explanation. Operator procedures are unchanged.

Local compiler, native controls, production-prefix comparison, formatting,
CI-policy and documentation checks validate this test-only repair. They do not
supply a complete corrected hosted result, Linux run, real-comparison quality,
resource acceptance or P27 completion. Original failed runs remain retained.

## Hosted confirmation and the Linux Bound fixture

The exact `3605ac181ca2b44a239e522ed1e3c352595d8be0`
[hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39399838296)
passes Ubuntu and macOS, including full source, native, package and installed
proofs. It covers the copy-fixture repair and preceding public changes. It does
not cover the subsequent uncommitted review-binding/resource-join correction or
the Bound fixture change described below.

A root-cause search also finds the process/time-only formula in the Linux-only
`Temp` constructor in `native/ipse-bound.rs`. Its parallel tests can encounter the
same collision. No retained hosted failure is attributed to this second site.
An exact extracted constructor with a fixed-clock seam fails at `create_dir`
with `AlreadyExists`, exit 101, on Unix. Adding the atomic ordinal makes that
same extracted regression pass. This is constructor evidence, not a full Linux
authority test.

The test-only correction applies that ordinal and fixed-clock regression to
`Temp`. Bound's production source prefix is byte-identical; native protocol,
authority, FIFO, descriptor-transfer and process behavior are unchanged. Local
macOS compilation with warnings denied and its three platform-independent controls
pass. The Linux-only constructor and full authority controls still require a
Linux run. The existing hosted job runs them on a separate host, preserving the
active Serenity comparison's CPU isolation. A passing earlier matrix or local
extracted probe must not be reported as that future run's result.
