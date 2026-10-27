# Private recovery receipt status experiment

This incomplete 2026-10-27 experiment builds on the [bounded disposal prototype](observation-session-cancel-disposal-v5-private.md).
The [patch](observation-session-recovery-status-v6-private.patch), SHA-256
`a263b590b27c53d30445061ef6ff80f3f2bf9ba5dd7e141d03d7fec48a02b0b4`,
applies after the [private observation v3 base](observation-session-private-v3-receipt.md).
It contains test-only Session and Writer instrumentation and is not suitable
for production promotion.

For an explicit cancel while the original append is pending, the Session keeps
the owner-issued Writer request and classifies its real late response as
`pending`, `recorded` or `unknown`. A deadline whose response was already
consumed stays `unknown`. A private subscriber-only inspection returns that
volatile classification and the scoped cleanup response without the observed
value. Neither is an operator authorization, durable recovery record or proof
of arbitrary OS cleanup.

The [log](observation-session-recovery-status-v6-private.log), SHA-256
`53d3d30c14625d215262718158cb5a187c94c564aae8f6c7054a9b3e7f23f058`, records
32 focused tests passing with seed 20270379 after formatting and strict compile.
They include a stalled Writer whose late append is explicitly drained, a
caller-death and delayed-helper disposal test, and an actual failed Session
resume after a late journal file effect. The extension trace remains unchanged
across that failed resume. These tests use the test-only 7.2.11 helper override
SHA-256 `05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`.

The experiment does not append a withdrawal event, accept operator input,
enable reuse of an old Session, or provide a current-root or later-use barrier.
Any durable recovery must bind a real native operator observation, the exact
intent and previously committed envelope, prove no observed value or later
effect was exposed, validate event ordering on replay, and maintain the lock
through independently confirmed cleanup. Uncertain appends or cleanup remain
unknown. Authenticated durable activation, production kernel qualification,
complete Session resource coverage and independent adversarial review remain
open.
