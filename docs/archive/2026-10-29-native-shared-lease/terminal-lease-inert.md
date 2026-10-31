# Inert matched-tty guardian and reader lease probe — 2026-10-29

This is a native ownership checkpoint, not guarded display or milestone acceptance. It builds on [owner controls](owner-controls.md), [Session/Host control wiring](session-control-wiring.md), and the [reviewed terminal design](guarded-terminal-integration-independent-review.md). The [plan](../../plan.md) owns acceptance. No production caller invokes this probe, and all protected-output gates remain closed.

The private Linux `v3-inert-lease-probe` requires the actual matching input/output tty, retains the operator channel lock, and never writes to the tty or accepts a display payload. It collects two operation- and role-bound EOF-only owner descriptors and one to four distinct native lock descriptions, retaining their authenticated peers and sender pidfds. Its bounded manifest rejects duplicate address, secret and descriptor identities. The collector's fd3 control is distinct from its tty fd0; its waits monitor previously collected owner descriptors, owner helper pidfds and relevant exporter pidfds. One native monotonic deadline covers the probe's collection and close procedure, but filesystem and kernel calls are not claimed to be hard preemptible.

The guardian forks an inert reader only after collection. Both processes inherit the same lock descriptions, tty/channel lock and owner-control read ends. Neither consumes an owner-control byte or writes protected content. A normal close first tells the reader to exit and reaps it; only then does the guardian drop its lock copies and complete each authenticated `C`/`F`/`G`/EOF settlement in manifest order. Its final `C` frame reports this probe's completed close only. Failure or loss leaves the operation unconfirmed; the guard kills and reaps a surviving child before dropping its own lock copies. If the guardian is killed, the reader retains its copies until it observes loss and exits. Actual terminal writing, owner-fenced final write admission and a complete all-copy protocol for a protected writer are not implemented here.

The probe request is `I` plus a bounded body: 16-byte operation, count, two 68-byte owner entries in Session/Host role order, then 1–4 entries of slot, 16-byte exporter operation and 68-byte lease identity. `H` reports that the manifest was accepted for collection; `L` includes the forked reader PID and is not activation or closure. The private test close is `C` plus the operation. No packet in this protocol carries review facts, worker output or operator input.

Separately, the existing guarded v2 input path now redraws a fixed `approval> ` prefix after release instead of reusing the protected final display line. Ordinary unguarded redraw keeps its existing prefix. A real-PTY editing test confirms that the guarded redraw does not repeat its synthetic protected tail; the affected release-before-input control also passed. This fix does not establish native retained leases for that existing path.

## Focused results

The final source-matched fixture and helper passed five real-PTY controls using four distinct synthetic native Transaction owners and two native owner-control senders:

- Normal: all four locks remain held, the inert reader is reaped, and each source's close is settled in manifest order before the probe reports closure; the original owners retain their locks until their own release.
- Guardian loss: with the reader stopped, the guardian and all original exporters are killed. An independent contender remains blocked on every lock until the reader resumes and exits.
- Reader loss: killing the reader leaves the original exporters holding their locks; the guardian exits unconfirmed and emits no confirmed close receipt.
- Owner-helper loss after fork: the guardian exits unconfirmed without a confirmed close receipt; original exporters still hold their locks until stopped.
- Owner-helper loss during partial collection: the probe exits unconfirmed, emits no confirmed close receipt and leaves no surviving lock after the original exporters stop.

The fixture checks the matched tty has no output at collection. The affected prior Session owner-control selection passed eight tests using the new helper, and the two direct v2 operator PTY controls passed. These are local Linux controls; the terminal fixture's synthetic native senders are not actual Session or Host BEAM processes. The separately tested Session/Host controls are not connected to this tty probe. No protected facts, real Review, model, aggregate, management flow or non-Linux platform was exercised.

The [evidence](evidence/terminal-lease-inert/) retains the exact final native and fixture sources, final helper and fixture binaries, standalone operator-test binary, runtime inventory and all logs. It also preserves earlier helper and fixture binaries/results. An initial helper compile exposed a Rust result-comparison type error; it was corrected before runtime tests. The final fixture adds explicit absence-of-close-receipt checks in the three loss cases. The owner-control regression graph was copied from the earlier owner-control Session cohort, with Runner recompiled for the final helper; it is not a coherent build of the newer Session-control wiring.

Representative commands, from the repository root using a new private empty directory for each mode, were:

```sh
rustc --edition=2021 -D warnings -O native/ipse-runner.rs -o /tmp/ipse-terminal-lease-inert-v2-helper
rustc --edition=2021 -D warnings -O dev/fixtures/terminal_lease_probe.rs -o /tmp/ipse-terminal-lease-probe-v5
/tmp/ipse-terminal-lease-probe-v5 PRIVATE_DIR /tmp/ipse-terminal-lease-inert-v2-helper normal
/tmp/ipse-terminal-lease-probe-v5 PRIVATE_DIR /tmp/ipse-terminal-lease-inert-v2-helper guardian-loss
/tmp/ipse-terminal-lease-probe-v5 PRIVATE_DIR /tmp/ipse-terminal-lease-inert-v2-helper reader-loss
/tmp/ipse-terminal-lease-probe-v5 PRIVATE_DIR /tmp/ipse-terminal-lease-inert-v2-helper owner-loss
/tmp/ipse-terminal-lease-probe-v5 PRIVATE_DIR /tmp/ipse-terminal-lease-inert-v2-helper owner-loss-collect
rustc --edition=2021 -D warnings --test native/ipse-operator.rs -o /tmp/ipse-terminal-lease-v2-operator-tests
/tmp/ipse-terminal-lease-v2-operator-tests --exact tests::guarded_review_redraw_after_release_never_repeats_protected_tail --nocapture
/tmp/ipse-terminal-lease-v2-operator-tests --exact tests::guarded_review_waits_for_release_before_reading_input --nocapture
```

PTY and socket controls ran with approved local permission. The Session regression graph retains the exact helper pin and runtime inventory; it must not be substituted for the separate Session/Host wiring graph.

Remaining work includes a real matched-tty protected writer, immutable payload/destination and all-leases activation, direct integration with the actual Session/Host or separate management owners, continuous per-write control/expiry checks, all reader/guardian copy accounting during every write and redraw, actual Review release-before-input sequencing and effect-side one-use revalidation. The 132-distinct-lease generic path remains beyond the current 131 limit. This probe does not establish any of those guarantees.
