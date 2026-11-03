# Retained-cohort read-only diagnostic, 2026-11-03

This separate synthetic diagnostic followed the [failed full-day run](integrated-full-day-failure-20261103.md).
It did not resume that run, its unresolved first turn, or any of its 14 closed
effects. It did not complete the integrated day or establish annual acceptance.

The diagnostic used the original source owners in the retained cohort, commit
`b10df4a556c097b686eecba1267e3d6425f0f8bc` and the frozen runtime from that
cohort. Its exact [driver](retained-probe-20261103/native_notes_retained_probe.ex),
[launcher](retained-probe-20261103/native_notes_retained_probe.exs) and
[loopback fixture](retained-probe-20261103/provider.exs) are retained alongside
the [checksums](retained-probe-20261103/SHA256SUMS) and comparison records.
Focused fixture/mode tests [passed 11 tests](retained-probe-20261103/focused-tests.log);
two focused semantic-consent and mutation-grant tests [also passed](retained-probe-20261103/fence-tests.log).
Their respective SHA-256 hashes are
`cfcbc34400cc828763a745589f6ae35bd9fab184f07a3b026969269454a35bf1` and
`dafa909288c5d6ffe89dac993e8ccca8174da95cbfcb48393658f3b0451b3222`.
The host action ceiling was `read_only` with a
`read_only` enclosing ceiling, and the new Session recorded that mode with
active semantic admission. This is a host action fence, not an OS-enforced
read-only mount; startup could perform harmless lock or metadata activity.

Before the prompt, the diagnostic checked the prior effect closure chain, the
unresolved turn hashes, absence of pending cleanup names, and existing Session
locks. It checked the actual post-effect-14 collection and control against the
last closure report. It wrote its own distinct Session journal and lock in the
original sessions directory because source authority is bound to original
directory and inode. The prior 4,981 retained-root files and the external seed
audit files had matching pre/post hash and inode inventories. Authenticated
pre/post root and control receipts were identical, with collection generation
2,114. The only final added files were the new Session's journal and lock. The
separate 97-file forensic backup still matched its originals. The controlled
environment had no known competing owner; the sequential lock check was not an
atomic global exclusion of all possible concurrent writers.

The new Session returned `:error` before an inference-dispatch intent or an
accepted fixture request. Its journal records 13 successful action results:
one `context.publish`, one `context.available`, one collection index and ten
collection gets. Of 11 worker-input results, ten were `delivered` and the last
was `unknown`. That last `host.actions` intent records a 4,993-ms interval
between checked-at and deadline. The journal then records `cancelled` and a
`cleanup_failure` closure with `cleanup_confirmed: false`. The
[child log](retained-probe-20261103/child.log) records only that the Session
returned `:error`; it does not identify why the handoff became unknown or why
cleanup was unconfirmed. No listener accept-timeout error is recorded.

The original full-day listener had a 30-second accept timeout. This diagnostic's
listener had a separate 180-second accept bound, a 30-second body-read bound,
and a 150-second request/completion guard; the configured provider inference
timeout was 15 seconds. The parent-written diagnostic intent and child-log
filesystem timestamps are 2026-11-03 01:25:35 and 01:26:26 Pacific: about 51
seconds for the child invocation including setup and lock checks, not a timed
worker handoff. Child-created fixture-clock timestamps are simulated. The final
worker-input result has no completion timestamp or reason, so neither a
five-second expiry nor any other initiating timeout is established. No request
reached the fixture and the provider inference timeout is not shown to have
started.

The diagnostic output remains at `/tmp/ipse-retained-readonly-b10-20261103-01`;
the new synthetic journal remains in the original root. The archived checksums
identify both retained paths and the archived comparison files, but a copied
journal would not retain original inode-bound source authority. Two entries in
the manifest refer to `/tmp` and can only be checked while those files remain.
No subsequent
diagnostic or automatic replay was started. The cause remains unknown.
