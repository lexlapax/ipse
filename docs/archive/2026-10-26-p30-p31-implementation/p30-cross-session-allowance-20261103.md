# Synthetic cross-Session decision experiment — 2026-11-03

This is a scoped investigation, not P30 qualification. The [current plan](../../plan.md)
remains authoritative. It checks an existing finite local shadow experiment; it
neither changes the implementation nor proves a monetary cap, model quality,
installed-package behavior, live-account access, or a general cross-process budget.
The third settled-case refusal below has only a generic recorded failure code.

## Source and execution

The isolated snapshot `.p30-cross-session-1405.xt5krtGZ` was extracted from
commit `14058f244ac2012050482c1770cf320fd6f7e399` with `git archive`.
Locally available dependencies were copied into it; they were not independently
inventoried. The build ran with `IPSE_BUILD_COMMIT` set to that commit,
`MIX_ENV=test`, `HEX_OFFLINE=1` and `ERL_FLAGS='+S 2:2 +A 2'`:

```sh
./dev/build.sh
IPSE_KEEP_SHADOW_FIXTURES=1 mix test test/extensions/knowledge/shadow_cross_session_test.exs --seed 0
```

A 200-second outer timeout bounded the final test. The first build attempt
[failed before compilation](p30-cross-session-allowance-20261103/cross-build.log):
Mix could not acquire its TCP filesystem lock in the sandbox (`:eperm`). The
build and tests then ran with local socket and PTY access. The successful build
log remains in the snapshot as `cross-build-unsandboxed.log`, SHA-256
`d1716ac65511e136efad15c5eaf89432988ea6c8d78e25a6797bf9dae2ab83d8`;
`priv/ipse-runner` SHA-256 was
`ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b`.
No live account, paid call or external inference service was used: both the main
provider and the decision provider were synthetic numeric-loopback services.

The final four test overlays and their [manifest](p30-cross-session-allowance-20261103/formatted-fixture.sha256)
are preserved under [final](p30-cross-session-allowance-20261103/final/). The
manifest SHA-256 is `41e8fad9c5eb9cbc09d80053743cb08965d20f4af9afa6c18e1afebc5b1ac70b`
and matched all four files after the run. The combined
[log](p30-cross-session-allowance-20261103/cross-formatted-run.log) has SHA-256
`b6d7dc7e38242ab9084c3417a3d22a18ba2707906716460197c77e0ac173f40e`:
**2 passed**, seed 0, 41.1 seconds. This is not a full-source test suite.
The earlier passing combined [fixture](p30-cross-session-allowance-20261103/previous-combined/),
[manifest](p30-cross-session-allowance-20261103/previous-combined-fixture.sha256)
and [log](p30-cross-session-allowance-20261103/cross-previous-combined-run.log)
are preserved separately; formatting changed the settled-case script before the
final run. The existing Rust driver remains in its prior formatting style.

## Two settled calls and a third refusal

The first synthetic path authorized one two-call local experiment, captured a
real eligible note from a closed source Session, and drove three separately
started assessment Sessions with native approval. The test checked that the
first two calls reached the synthetic decision service and settled as one-call
reservations. On the third, it checked a failed decision action, no third
reservation and no third decision dispatch. The Collection snapshot was
unchanged and all three assessment journals reconstructed. The fixture did
not explicitly assert distinct Session IDs. A later read-only check of the
retained synthetic journals found three distinct assessment journal files;
that observation was not an assertion executed by the test.

The third recorded action value was `decision_request_failed`, a **generic**
code. The two settled one-call ledger entries and the lack of a third
reservation or dispatch are independently observed; this result does not prove
that exhaustion was the specific reason for refusal. A cross-Session finite
allowance must not be qualified from that inferred cause.

## Unknown outcome and service quarantine

In a separate fresh experiment, the first approved synthetic decision request
was dispatched and the loopback server returned malformed JSON. The test
observed a failed action and one `unknown` reservation for one model call. A
new Session then received the explicit unknown-service error before sending
another provider request. The test compared the decoded reservation maps before
and after the new Session and found them equal; it did not compare raw ledger
bytes. It also checked a different Session ID, no `decision.create` action in
the new journal, no further synthetic provider requests, and an unchanged
Collection snapshot. This proves the tested new-Session quarantine, not an
original-Session resume or a general no-replay qualification.

The [initial unknown variant](p30-cross-session-allowance-20261103/failed-unknown/)
expected a second approval and failed after that new Session was refused at
service admission. It had already checked the first unknown reservation; its
watcher timed out waiting for an approval that did not appear. Its manifest is
[retained](p30-cross-session-allowance-20261103/unknown-fixture.sha256).
The complete synthetic log remains in the isolated snapshot as
`cross-unknown-run.log`, SHA-256
`c5c5b88a52381113c6cd6815deb1dc7cb5d549205856a45999dcf1a9290f7dfe`;
it includes the synthetic terminal transcript and is not copied into this
archive. The corrected quarantine scenario used a fresh synthetic experiment;
it did not replay the earlier uncertain operation. Its separate
[log](p30-cross-session-allowance-20261103/cross-quarantine-run.log) passed
one test with one excluded, seed 0, 15.6 seconds.

The original two-settled-call [fixture](p30-cross-session-allowance-20261103/first-pass/),
[manifest](p30-cross-session-allowance-20261103/cross-fixture.sha256), and
[log](p30-cross-session-allowance-20261103/cross-first-run.log) are also retained.
`IPSE_KEEP_SHADOW_FIXTURES=1` left synthetic homes and journals in `/tmp` for
inspection; their retention is subject to temporary-directory cleanup. The
complete snapshot and logs likewise need preserving if their full details are
required later. No private user transcript is included in this receipt.
Independent evidence review found no further overclaim. A sanitized git-backed
documentation check passed 1,107 Markdown files and 9,099 links with zero errors.
