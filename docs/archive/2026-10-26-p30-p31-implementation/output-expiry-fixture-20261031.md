# Native literal result expiry control

2026-10-31. Historical synthetic test repair in the isolated follow-up checkout.
This qualifies one result-release boundary, not general protected output or
the [whole-source baseline](full-suite-20261031.md).

The original control gave a literal five seconds of remaining retention before
starting a consumer that automatically recalled several notes. It could expire
before the intended explicit read, so the test observed interruption instead of
an internally retained value whose final release was withdrawn.

The test already builds a copied, instrumented Knowledge worker. Its fixture now
omits automatic recall consistently from that copy's subscription, job export
and event capability. Artifact inventory must admit the copy before native input
starts. No installed or production bundle is changed. The explicit native read
must produce the selected version-4 receipt before expiry; a three-second
retention and four-second worker pause put its return after expiry but within
the unchanged five-second worker call timeout.

The first fixture edits failed artifact admission; removing just the subscription
was insufficient. A six-second pause then exercised worker timeout rather than
result release. Those failed runs supplied no positive evidence. A later run
reached withdrawal but exposed another obsolete assertion: a content-free dispatch
intent is not proof of network egress, and the safe withdrawal stub can be used
in a subsequent request. The old closed server made continuation look like a
required error.

The final control keeps a real loopback fixture available for that continuation.
It requires the expired text in the internal worker receipt, a withdrawn native
release, the safe stub in the UI and actual HTTP request, absence of the literal
from both provider requests, valid Saved reconstruction and confirmed close.
It passed **1 test in 10.0 seconds**, log
`/tmp/ipse-next-output-expiry-continuation.log`. Production source, policy limits,
worker deadlines and release checks were not relaxed. Automatic recall remains
covered by its separate controls.
