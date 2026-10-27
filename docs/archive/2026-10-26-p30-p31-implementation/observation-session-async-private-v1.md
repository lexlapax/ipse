# Private Session same-view and asynchronous receipt experiment

This is an incomplete, unreviewed experiment. It is not a production path or
permission to deliver an observation. Apply the [private patch](observation-session-async-private-v1.patch)
after the [observation v3 prototype](observation-session-private-v3-receipt.md).
The patch SHA-256 is
`f7f6da697422652fabf6dd1c90baa5897b0f2ec0b8b07cd3def499d33139ba1c`.

For an explicitly configured diagnostic get or snapshot, a real Session's
selected Collection host effect obtains a same-view observation while holding
its identity and consent callbacks. The Session matches its current job and
action, checks the caller's resource scope, current source snapshot, live
identity and deadline, constructs the exact result and receipt, and initiates
the private asynchronous journal append. A successful observation is never
returned to the extension. The experiment also includes the earlier
[host-anchor checkpoint](observation-session-host-anchor-private.md).

The [test output](observation-session-async-private-v1.log) SHA-256 is
`7970aa98ee63fcfceb7042c901866f08698c52fcc5d176de9bf2559bc63a0b38`.
The isolated test run passed 27 tests using seed `20270343`, max-cases 1, and
the test-only 7.2.11 helper override SHA-256
`05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`.
It includes real Session tests in which the writer is deliberately stalled,
the append is late, or the Session owner is killed. This is not native kernel,
installed-runtime, or platform qualification.

The patch includes an instrumentation-only telemetry hook for stalling the
writer; it must not enter production. A queued append may complete after the
deadline or cancellation. In that case, or when an action result and its receipt
cannot be reconciled, replay must refuse; this experiment deliberately does not
expose a result or claim a usable receipt. The host-supplied activation guard
is not a durable independently authenticated policy anchor. Current root and
policy through all later uses, worker delivery, cancellation, trusted replay,
the single-use completion protocol, and extension/model/effect egress fencing
remain unimplemented and require independent audit.
