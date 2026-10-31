# Source-bound native review display — 2026-10-28

This focused component supports the in-progress Session supersession path. It
does not establish source eligibility, complete the Session integration, or
qualify any milestone. The [plan](../../plan.md) owns acceptance.

Ordinary `Review.with_review/3` is unchanged. The internal four-argument variant
gives a trusted display guard a one-use, same-process continuation. The guard
must hold and revalidate its source and policy leases while calling the
continuation. A private native frame binds the exact display bytes and finite
wall deadline; the helper checks that deadline during terminal output and emits
its existing displayed acknowledgement only after the complete display. The
guard returns and releases the leases before the caller waits for the native
challenge input. The later publication callback must independently reacquire
and rederive facts and authority before consuming the existing one-use review
permit. Neither a display acknowledgement nor a saved receipt grants that
authority. Foreign, duplicate and unused-after-return continuations refuse.

The wall-clock check and OS write are separate operations, so the implementation
does not establish a kernel-atomic deadline under arbitrary descheduling or clock
changes. Partial output, owner loss and missing native cleanup are not treated as
proof of successful review. Existing terminal ownership and restoration receipts
remain in use. Independent adversarial review and more interruption controls are
still required.

## Focused evidence

The private `_build/guarded-review-v3-sol-20261028` cohort uses helper SHA-256
`6fbc519033aafaf1718386ef4ef1f91e55724b6d1cffe2bc82ad192280b3098f`.
[Runtime](guarded-review/runtime-sha256.txt) and
[source/fixture](guarded-review/source-sha256.txt) inventories identify that
cohort. The native production helper was compiled before the later test-only
expired-frame addition to `ipse-operator.rs`; that addition is excluded by the
production compilation. The remaining current-source and full installed checks
are not represented by this inventory.

- Strict native and Elixir compilation had no diagnostics: [native](guarded-review/ipse-guarded-review-native-46939.log),
  [initial Elixir](guarded-review/ipse-guarded-review-compile-46940.log), and
  [v3 Operator](guarded-review/ipse-guarded-review-v3-compile-46951.log).
- The [initial PTY controls](guarded-review/ipse-guarded-review-suite-46948.log)
  passed valid, expired, duplicate and foreign continuations. The
  [protected-lock control](guarded-review/ipse-guarded-review-lock-46947.log)
  used an independent process to reacquire the actual lock before the terminal
  fixture sent the confirmation. These controls use synthetic facts, not managed
  note sources or capture consent.
- A retained unused continuation refused without display in
  [46950](guarded-review/ipse-guarded-review-stored-46950.log). The later
  [v3 positive lock](guarded-review/ipse-guarded-review-v3-valid-46952.log) and
  [foreign-use](guarded-review/ipse-guarded-review-v3-foreign-46952.log) controls
  passed after making the displayed acknowledgement an atomic state transition.
- The native [elapsed-frame control](guarded-review/ipse-guarded-review-native-46946.log)
  verified no synthetic secret reached the terminal and no display acknowledgement
  was emitted. An [earlier attempt](guarded-review/ipse-guarded-review-native-46944.log)
  incorrectly assumed the PTY contained no test-harness output; the corrected
  assertion checks the secret itself. The first [exact-filter invocation](guarded-review/ipse-guarded-review-native-46943.log)
  selected zero tests. The affected ordinary v2 Unicode/full-input/restoration
  [regression](guarded-review/ipse-guarded-review-v2-regression-46953.log) passed.

The first genuine Session correction/temporal-supersession journey was separately
run by the lifecycle owner. Its receipt, negative controls and combined-source
limitations are recorded separately; the synthetic component results above do not
substitute for them.

## Interrupted display-frame repair

Independent review found that ordinary cancellation finished a partially queued
display frame before sending cancellation. In the guarded path, an owner could die
and release its source lease during that completion. Pre-acknowledgement guarded
cancellation now closes the control port immediately and marks cleanup unconfirmed;
it does not finish the pending frame. Ordinary and post-display cancellation retain
their restoration-receipt path. The [v4 runtime](guarded-review/cancel-runtime-sha256.txt)
and [test/source snapshot](guarded-review/cancel-source-sha256.txt) identify this
separate cohort; strict [compilation](guarded-review/ipse-guarded-review-v4-compile-46954.log)
had no diagnostics.

A real PTY fixture stopped the native helper while a large frame was partially
queued, killed the guard owner, and checked that the actual protected lock was
reacquired and the BEAM controller exited before the helper resumed. The
[repaired control](guarded-review/ipse-guarded-review-backpressure-46962.log)
passed and observed no synthetic late-display prefix; the same strengthened
control [failed on v3](guarded-review/ipse-guarded-review-backpressure-old-46963.log)
because the controller kept running. The fixture resumes the stopped helper even
on failure. It does not claim confirmed native restoration: BEAM may retain a Port
after its controller exits, so the production result remains unconfirmed.

Earlier backpressure fixtures [46955](guarded-review/ipse-guarded-review-backpressure-46955.log),
[46957](guarded-review/ipse-guarded-review-backpressure-46957.log) also passed
on the [old cohort](guarded-review/ipse-guarded-review-backpressure-old-46956.log),
[46958](guarded-review/ipse-guarded-review-backpressure-old-46958.log) and
[46959](guarded-review/ipse-guarded-review-backpressure-old-46959.log); they did
not distinguish the race. The later [46960](guarded-review/ipse-guarded-review-backpressure-46960.log)
and [46961](guarded-review/ipse-guarded-review-backpressure-46961.log) fixture
asserted that the BEAM Port itself disappeared while its OS child was stopped;
it can remain visible after the controller exits. The final control asserts
controller termination and retains cleanup uncertainty instead.

## Direct owner and input-release handshake

A later independent review found that a separate BEAM controller could be
descheduled after the source-lease owner died while the native control pipe was
still open. It also found that the native reader entered its input wait immediately
after display acknowledgement, before the guard necessarily released its locks.
The guarded path now opens the native Port in the lease owner itself. After the
native `y` acknowledgement, the guard returns and releases its leases; only then
does the owner send a private `U` frame. The native guardian forwards that release
to its reader, which does not enter input wait before receiving it. Ordinary v2
input retains its existing protocol.

The separate helper SHA-256 is
`aed2ef0998e3fdf421c8acfe35a9d04d4107ac9194fc1dcf3aee5f1d3be7cc09`.
Its [source](guarded-review/release-source-sha256.txt) and
[runtime](guarded-review/release-runtime-sha256.txt) snapshots are distinct from
the earlier v4 cohort. Two [native controls](guarded-review/ipse-guarded-release-native-tests-46973.log)
passed, including input typed after display but not consumed before `U`. The
[guarded PTY suite](guarded-review/ipse-guarded-release-suite-46975.log) passed
three tests, and the affected [ordinary v2 regression](guarded-review/ipse-guarded-release-v2-46976.log)
passed. Both native and Elixir compilations had empty diagnostics.

Direct Port ownership binds the helper to its immediate BEAM owner, not necessarily
to the Session owner. Supersession currently runs in a file-effect peer that can
outlive its caller. An independent review also found that killing the whole peer
would not prove its ordinary file-server and journal IO stopped. The Session/Host
owner-loss and publication phases therefore remain open, as does review of the
new handshake. No hard no-output-after-upstream-owner-death claim is made.

Subsequent focused controls add a queued cancellation immediately after `y`
to the guarded PTY suite (four tests passed) and exercise cancellation, pipe EOF,
invalid and truncated release frames, and native reader loss before release.
The three native guarded-review tests passed, including restoration and input
queue cleanup. The first native invocation used an unqualified `--exact` name
and selected zero tests; the following filtered invocation selected and passed
the intended controls. A separate guarded-release guardian-death test also
passed, observing the reader's distinct unconfirmed-restoration receipt and
an emptied input queue. These results do not qualify the in-progress coordinated
review exchange. Its proposed split has a further open publisher-death race:
the publisher holds leases while a different process owns the terminal Port.
Closing those independently does not prove their ordering.
