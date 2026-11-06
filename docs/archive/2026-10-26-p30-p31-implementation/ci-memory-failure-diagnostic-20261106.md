# Bounded Memory failure diagnostics, 2026-11-06

Historical diagnostic-verification record. Current procedures are in
[the testing guide](../../developer/testing.md#prove-an-independent-artifact-without-rebuilding-the-host)
and [Memory's operator manual](../../operator/memory.md). This record does not
qualify a source or installed `Memory.run/1` execution, macOS support or hosted CI.

Hosted run `42192551584` failed the installed-memory verifier's first `remember`
command. The earlier waiter discarded error notifications, then raised only
“Memory fixture command failed” on its error terminal. The verifier's cleanup
removed the synthetic store and journals. The observed failure therefore did
not retain a machine cause; a filesystem explanation remains unproven.

## Diagnostic boundary

The verifier still stops at the first failed command. Before its existing
cleanup, the new failure path reads only that verifier's known synthetic Session
journal and emits a bounded projection in the raised error. Immediate invocation
refusal uses no journal, so it cannot borrow evidence from a prior command.
Successful behavior, fixture arguments, required outcomes, provider, approvals,
timeouts and cleanup are unchanged. No Core, native profile or workflow changes.

The projection contains fixed command-phase and terminal labels, whether an
error notification was observed, recognized event-type and action-status counts,
and machine codes from structured failure slots. It examines at most 16 recent
rows within the latest invocation/turn window and retains at most eight distinct
codes. Successful action values are not searched for error codes. A completed
earlier turn cannot supply stale action codes when the new invocation never
starts.

The first source proposal accepted any lowercase identifier-shaped code. Review
rejected that privacy boundary: a failed value or structured notification could
contain a private token that still matches the grammar. The adopted version
accepts only **12 explicit State/Invocation/Host-defined constants**. Unknown
values become the fixed category `unrecognized`; absent codes become
`unavailable`. It exports no raw error prose, arguments, State contents,
transcripts, identifiers, paths or environment. Missing codes cannot establish
the cause of the failed command.

## Actual focused verification

Canonical Elixir 1.18 formatting and scoped diff checks passed. Two pure tests
ran through the existing independently compiled Memory harness against a fresh
private CoW copy of Host05's complete 16-application runtime. They checked:

- Exact projected fields and redaction of payloads, details, successful State
  values and unknown event names, including `private_token` in both a failed
  action's code slot and the first structured error-code input.
- Exclusion of earlier commands, refusal before a new intent, fixed labels for
  unknown inputs, and the 16-row/eight-code limits.

Actual handle `26034` completed with **exit 0: two passed, 36 excluded, 2.8 s**,
seed 481639 and maximum one case. The outer process used direct Elixir with one
scheduler/async thread; the existing harness compiler retained its two-scheduler
setting. The coordination bound was 180 seconds plus ten seconds kill grace;
product/test deadlines were unchanged.

Ipse was unstarted before and after the controls. No `Memory.run/1`, Session,
State operation, native helper, Input/TTY, socket, provider or original notebook
was invoked. Original Host05 and copied runtime/link/inode guards, source and
harness-input posts all passed, with no mutable runtime exemption. Separate
actual-host scoped cleanup exited zero and confirmed the owned PID, process
group, BEAM and helper processes absent. This is not a global Input or listener
neutrality claim.

## Evidence and limits

Private evidence remains under `ci-memory-first-failure-20261106-01`. Only safe
source/result commitments are recorded here; no synthetic or private journal,
State value or raw diagnostic input is exported.

| Evidence | SHA-256 |
| --- | --- |
| Adopted `dev/verification/memory.exs` | `021dc1b2c689e243adc8900d082d2fa66e219d54b0c26747922e2d7370a4a696` |
| Matching `test/dev/verification_test.exs` | `ac99c3821b72b1733d23b165ca15452e6fdaebbd6afeba99c66ddd8a9136f855` |
| Adopted delta | `6dac649a0177d81457ec5a2531c204dee4a496c47f17fa62b958f8a2651be27f` |
| Execution inputs | `7e4658f87519bc1ab2c9b83439d0e36d29f6562d5fd81eb43200ffb732eda0ad` |
| Test output | `5b6f9d995d7619e0d54fac1437b62f3f9e5a82777c3f7b3b48ecd355a2cbe78e` |
| Terminal/post status | `3c56e006bfe96d79c63c7bf466960cf2e4aa14906f164913437ee5929b35526b` |
| Independent scoped-neutral receipt | `bf3a9a26fd38425e60ff4e3b9e6633e668ec32c2ba2c7b274d4cccf4ee559148` |
| Private result summary | `c39957973e08bed5160cef1208c217c1278f1273bbd13d3b9242882f4bd389db` |

The whole current Testing chapter was reviewed, including the existing
independent-harness, cleanup-precedence and packaging instructions. Its
diagnostic guidance now teaches this safe projection alongside the verifier
flow; execution history remains here. The macOS first failure remains unknown.
These pure controls establish neither retrieval correctness nor a passing
installed package, hosted matrix or full source baseline. The separate native
binding controls are outside this record's scope.
