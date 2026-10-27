# Private observation cancellation stall

This is a diagnostic of an incomplete Session experiment, not a production
patch or a qualified cancellation protocol. The [private patch](observation-session-cancel-stall-private.patch)
has SHA-256 `da67cab8b488f64b393442b7a9997c7c0ad70d84a6ec8124f6ee84d223c9e862`
and applies after the [private v3 observation prototype](observation-session-private-v3-receipt.md).
It contains test-only telemetry barriers and must not be promoted as runtime code.

In a synthetic real Session, the test pauses the owner-only journal writer just
before an asynchronous observation append. It then calls `Session.cancel/1` from
another process. Cancellation has not completed after 200 ms while the writer is
paused; it completes after the writer is resumed. The [log](observation-session-cancel-stall-private.log)
SHA-256 is `17a72783e0aea266d56ca8b554f4743202395e5048176f62b53b5a75560d3e6b`.
The focused test passed because it demonstrates that stall; this is not a
responsive-cancellation pass. It used the private test-only 7.2.11 helper override
`05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`.

The synthetic probe intentionally withholds observed values and replay remains
fail closed. The stall's exact cause has not been isolated between synchronous
journal work and dependent task cleanup. A queued append may later complete;
neither a timeout nor cancellation proves that it did not. Responsive stop,
unknown-outcome settlement, late-write handling, downstream use fencing and
independently authenticated activation remain open.
