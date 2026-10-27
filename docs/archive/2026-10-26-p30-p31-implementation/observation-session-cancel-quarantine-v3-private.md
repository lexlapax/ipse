# Private observation cancellation quarantine

This is a private, incomplete experiment dated 2026-10-27, not a production
patch or a completed cancellation protocol. The [patch](observation-session-cancel-quarantine-v3-private.patch)
has SHA-256 `bf94b32236daa24d77322bed6d0bd95f5e625dad3530cb7d0f056c487b7dd60f`
and applies after the [v3 observation prototype](observation-session-private-v3-receipt.md).
It contains test-only telemetry barriers and a test-only host-call handler; it
must not be promoted as runtime code.

This experiment fences a Session when a submitted observation append is pending
or its outcome becomes unknown. It returns `cleanup_unconfirmed`, cancels the
worker, requests scoped cleanup asynchronously, retains the Session owner and
lock, and refuses further Session calls. A timed-out request may still append
afterward. It is not retried, no observation value is delivered, and the
experimental replay path refuses the affected history.

The [test log](observation-session-cancel-quarantine-v3-private.log), SHA-256
`6c8a767631a18bb537691d3f25ceffa5f8e455ceef2249d9ae6b6094ae6069e2`, records
31 focused tests passing with seed 20270370 after formatting and strict compile.
One synthetic real Session test pauses the journal writer and checks repeated
cancel, close, prompt and source calls. Another queues a cancel request, kills
its caller before Session processes it, then kills the Session while a
test-registered effect peer still holds a private native helper Port and a
delayed file write. The session lock remains unavailable while that peer lives;
after the peer writes, closes the Port and exits, the lock is reacquired. A
separate timed-out append test drains the writer mailbox after resuming it and
checks replay refusal. These tests use an isolated test-only 7.2.11 kernel
override helper, SHA-256
`05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`.

The quarantined Session has no graceful user recovery or normal reuse path.
The effect peer is registered through a synthetic test hook, so these controls
do not establish cleanup for all native effects, pre-existing independent
Session resources or hostile same-BEAM callers. A process exit alone is not an
OS cleanup receipt. Scope shutdown and writer completion can remain unknown;
the design must retain the lock through independently confirmed cleanup and
must not infer that a late append did not happen. The full current-root,
later-use and effect barriers, authenticated durable activation, production
kernel qualification and independent adversarial audit remain open.
