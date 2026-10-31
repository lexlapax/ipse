# Synthetic terminal display admission repair — 2026-10-29

This repairs two conditions from the [independent synthetic-display review](terminal-display-synthetic-independent-review.md). It does not activate a protected output or Review path. The [original cohort](terminal-display-synthetic.md) and its evidence remain frozen. This private Linux candidate still uses synthetic native owners; actual Session/Host and the separate management integration, all-copy closure and real Review sequencing remain open.

The active mode now rejects any lease count other than four before H, descriptor collection, activation or tty writes. The inert mode retains its existing one-to-four admission. Source inspection confirms the existing hardcoded ordered Session/Host role binding, rejection of duplicate address, secret and descriptor identities, and rejection of a repeated exporter PID/slot; these checks do not themselves attest management lease purposes.

The synthetic reader now checks the common monotonic deadline immediately after tty readiness and before each new write, in addition to the wall expiry. The guardian's D status writer does the same around readiness and each status write. The reader's private D progress write also checks both deadlines after readiness. A syscall admitted before a concurrent deadline or owner loss can complete later; partial or late output and closure remain unknown. No check establishes emulator or human observation.

[Focused evidence](evidence/terminal-display-repair/) preserves exact final source, helper and fixture binaries and logs. On real isolated PTYs with native owner controls and native lock exporters, active counts one, two and three were each refused before readiness without terminal output; four-lease active display/settlement and the existing four-lease inert normal case passed. The separately retained [one-lease counterexample](evidence/terminal-display-review/one-lease-probe.log) remains the earlier v6 negative evidence. The wall-expired, prefilled D-status pipe control also passed on the repair.

For the monotonic geometry, a test-only helper stops the reader immediately after tty readiness but before the new admission check; the fixture stops the guardian, allows the five-second monotonic deadline to pass while the wall expiry remains later, resumes the reader and then the guardian, and verifies no tty bytes or D/C confirmation. That control passed. An independently compiled negative derivative removes only the post-readiness monotonic check from this source: the same fixture reports `tty write admitted after monotonic deadline`, confirming that the control exercises the intended boundary. The negative derivative is test-hook-only; its exact source and binary are retained. The production helper contains none of the three display stop-hook markers. Other readiness/deadline checks were inspected in source; this one fixture does not independently interpose the status or private-progress write.

Exact compilation commands, from the source tar, were:

```sh
rustc --edition=2021 -D warnings -O native/ipse-runner.rs -o /tmp/ipse-terminal-display-v7-helper
rustc --edition=2021 -D warnings -O --cfg ipse_terminal_display_test_hook native/ipse-runner.rs -o /tmp/ipse-terminal-display-v7-hook-helper
rustc --edition=2021 -D warnings -O dev/fixtures/terminal_lease_probe.rs -o /tmp/ipse-terminal-display-v7-fixture
```

Each control ran as `/tmp/ipse-terminal-display-v7-fixture PRIVATE_EMPTY_DIR HELPER MODE` with a fresh isolated directory and authorized PTY/Unix descriptor transfer. The production helper was used for `display-short-1`, `display-short-2`, `display-short-3`, `display-receipt-stall`, `display-ok`, and `normal`; the test-hook helper was used for `display-mono-ready`. The negative helper was compiled with the same test-hook flag from `negative-source.tar` and ran the same `display-mono-ready` case. No aggregate suite, protected content, actual Session/Host process attachment or non-Linux platform was exercised.
