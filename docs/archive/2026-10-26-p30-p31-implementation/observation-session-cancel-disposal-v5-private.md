# Private bounded disposal of a quarantined Session

This historical 2026-10-27 experiment follows the [quarantine prototype](observation-session-cancel-quarantine-v3-private.md).
The [patch](observation-session-cancel-disposal-v5-private.patch), SHA-256
`e25eeaf8d1d998ab318f2672b0119fc16073eb21a495f06a3b8ba6667ba5a2e6`,
applies after the [private observation v3 base](observation-session-private-v3-receipt.md).
It includes test-only Session and Writer instrumentation and is not suitable for
production promotion.

The experiment permits an explicit close of a quarantined Session. It first
replies `cleanup_unconfirmed`, then stops the owner and its writer; the existing
lock guard waits on tracked peers before releasing the lock. The public
`Session.close_confirmed/1` path is exercised: its observation-drain query must
receive a non-idle snapshot rather than the generic quarantine error. Earlier
private code returned the error and produced a `MatchError` before close.

The [log](observation-session-cancel-disposal-v5-private.log), SHA-256
`2f5b8e3b3c2a12d55304cc25aad51d5e9f5a1aa296d8e8c3b9a8e15f92f2f9f2`, records
32 focused tests passing with seed 20270375 after formatting and strict compile.
In one synthetic real Session, a test hook pauses the Writer's actual tracked
file effect before its observation append. The lock remains unavailable after
cancel and close until that effect is released; the effect then writes the
late envelope, and guarded replay refuses the journal. Another control kills a
cancel caller, requests public close, and holds a test-registered effect peer
with a private native helper Port and delayed file write. The lock remains
unavailable until the peer completes and exits. These controls use the isolated
test-only 7.2.11 helper override SHA-256
`05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`.

Close deliberately reports unknown, not successful cleanup or settlement.
The old Session remains unavailable for resume; this is bounded disposal,
not a complete user recovery path. Tracked process exit is not a general OS
cleanup receipt. All Session resource types, asynchronous owner loss, durable
activation, current-root and later-use barriers, kernel qualification and an
independent adversarial review remain open.
