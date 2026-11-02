# Test-process clock for native lifecycle workloads

Dated **2026-11-02**. Author-run component evidence based on `39c8043`, with
the explicit new fixture sources inventoried in the [receipt](process-clock-20261102.json).
This is an engineering record, not operator clock guidance. The
[testing chapter](../../developer/testing.md#require-positive-controls-and-inspect-uncertainty)
owns its current verification procedure; the [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance)
owns the still-open lifecycle acceptance.

The later [late-supersession cohort](native-clock-late-supersession-20261102.md)
extends the private bound to 500 days and records controlled stdio propagation.
This original 400-day fixture execution and its exact receipt remain preserved.

## Requirement and choice

The required 30/90/365-day native workload must exercise admission, actual native
review/publication, signed deadlines and recovery at the selected simulated day.
The existing `managed_v3_turnover_native.exs` only maps actual review timestamps
to a virtual frame and supplies an explicit future as-of value for one expiry
component. That does not advance the clocks used by a real subsequent operation.

Passing a later timestamp into a pure Elixir policy function cannot advance
Rust's `SystemTime`, and a broad production clock abstraction would unnecessarily
change the host boundary. No existing project adapter provides process-level OS
clock interposition. The small Rust fixture therefore reuses the already required
Rust standard library, GNU dynamic loader and libc syscall ABI. It adds no package,
external clock library, runtime service or production configuration option.
Its source is project Apache-2.0 code; the existing host libraries keep their own
distribution notices, as recorded in the [dependency inventory](../../developer/dependencies.md#host-and-build-inventory).

The fixture is a separate Linux/glibc x86-64 `cdylib`, never linked into Ipse's
helper. Only an explicitly selected test child receives its `LD_PRELOAD` and
`IPSE_TEST_CLOCK_OFFSET_MS`. It adds a fixed 0–400-day offset to realtime,
realtime-coarse, `gettimeofday` and `time`; other clocks pass directly to the
kernel. Raw syscalls avoid recursive loader resolution. The offset is captured
once per process, not exposed as a live clock-control API. Absent, malformed,
negative or excessive offsets refuse wall-clock reads rather than silently
using real time.

The process must restart to select another day. A future lifecycle driver must
confirm operation settlement, native owner exit and release before advancing
its cohort, and preserve any unknown effects for inspection without replay.
This fixture does not establish that driver or grant permission for a pending
operation. Kernel file timestamps and the machine clock remain outside its scope.

## Executed component checks

The standalone ExUnit module builds its own library and Rust observation program
under a fresh private temporary directory. Plain child VMs have private HOME,
IPSE_HOME and TMPDIR and an independent working directory. They explicitly check
that no Ipse application is started or loaded. No native terminal, production
helper, knowledge store, credential, model request or external service is used.

The final controls cover seven offsets: 0, 999, 1001 milliseconds and 30, 90,
365 and 400 days. Elixir system/OS wall clocks and a Rust child agree with the
selected offset against that child's raw kernel clock. The Rust child separately
checks standard-library `SystemTime`, libc realtime/coarse/gettimeofday/time,
unshifted monotonic readings and real elapsed sleep; the VM also checks its
monotonic sleep. Seven invalid/missing settings require explicit wall-read failure
while monotonic reads still work.

Three bounded development runs passed two tests each, retaining the earlier
logs separately. The final private-home run used seed `791761` and passed both
tests in 2.8 seconds with terminal exit 0. The exact standalone manual command
was then verified separately; its result and exact input/log hashes are retained
in the companion receipt. These are separate two-case runs, not a summed suite.

The independent full-source suite at frozen `39c8043` was already live and remains
a separate cohort. These probes compile only their private clock library and
observation executable, start no Ipse application or terminal, and do not alter
that checkout, its build outputs, helper, or process environment. They neither
replace its eventual aggregate nor qualify the new fixture as part of that run.

## Remaining acceptance

Clock coherence is established only on the recorded host/toolchain. Other
platforms explicitly skip this fixture, and the older Rust floor was not executed.
No complete loaded-system-library, environment or in-memory runtime inventory is
claimed. The receipt hashes the exact fixture sources, generated probe/library
bytes reported by the final test, logs and toolchain version observations.

Actual native lifecycle advancement, two overlapping owner processes, offline
week/import behavior, history/suppression compaction, the frozen intake mix,
10,000 additional cycles and representative/maximum payloads remain open.
This result establishes neither annual endurance, elapsed real time, storage
capacity, installed behavior, independent review nor model quality. It changes
no production permission, deadline, storage limit, operation-ID cap or provider.
