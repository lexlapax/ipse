# Private Session observation host-anchor checkpoint

This is an incomplete experiment, not a production Session feature or an
authenticated durable activation policy. It extends the private
[v3 observation prototype](observation-session-private-v3-receipt.md); apply
the [checkpoint patch](observation-session-host-anchor-private.patch) only
after that prototype. The patch SHA-256 is
`c2813174d40a88edeb28f71980bb2975962f38eccc591a90338e3ffc0f9f3e5c`.

Instead of a boolean, this experiment accepts a closed host-supplied artifact
and extension-identity digest pair. Fresh Session creation compares both to
the selected semantic admission. Resume compares them to the journal header.
An independently supplied guard therefore refuses a stripped header or a
mismatched artifact. Real synthetic Session tests also reject a malformed
boolean and a forged inactive action job, and keep the protected read blocked
before worker delivery.

The [test output](observation-session-host-anchor-private.log) SHA-256 is
`1fa864dde42ebaa55a79cfa2f74221fe4964a95c8ec16b0799585d6dd7b9c2aa`.
The private graph ran `test/ipse/extension/collection_call_session_test.exs`
with seed `20270337` and max-cases 1: 16 passed. It used the 7.2.11
test-only helper override SHA-256
`05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`;
this is not kernel or installed-runtime qualification.

The guard is caller configuration, not an independently protected activation
anchor. Omitting both it and the header can still resemble legacy history.
The prototype does not deliver same-view observations to a worker, authenticate
worker results, enforce current root and consent through later use, or integrate
the asynchronous receipt writer. These remain required before enabling the
path. The existing fail-closed read guard is retained.
