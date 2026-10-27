# Private native-observed withdrawal experiment

This unfinished 2026-10-27 experiment follows the [receipt-status checkpoint](observation-session-recovery-status-v6-private.md).
Its [patch](observation-session-native-withdrawal-private.patch), SHA-256
`3971756f18dbf0ad4db852e85b6524749a84860578b58660ec8fcd352792be36`, applies
after the [private observation v3 base](observation-session-private-v3-receipt.md).
It contains test-only Session/Writer hooks and private Session operations; it
has not been integrated or independently audited.

The private Session waits for the original Writer acknowledgment and scoped
cleanup receipt, displays a fixed withdrawal confirmation, consumes a native
input observation, and asynchronously appends an intent-bound withdrawal
record. Replay validates the envelope and immediately following withdrawal,
confirmation display/text hashes and observation shape. Its derived action
view substitutes an unknown result and closes the interrupted turn; it does not
deliver the protected value or replay the extension. This is a structural
experiment, not independently authenticated activation or a general use fence.

The synthetic [PTY driver](observation-session-native-withdrawal-pty.rs),
SHA-256 `c404176d9bac119ae238c3684e0c4ca4d698144e7cb0b86627caa4e955004b98`,
exercised two private controls. In the [acknowledged case](observation-session-native-withdrawal-ack.log),
SHA-256 `659eb2f66935ad233cecc8e7ca65f2cd63cc9837639f297324dc15ab6520148f`,
the marker completed; in the [late case](observation-session-native-withdrawal-late.log),
SHA-256 `f50b9ef99fc13597d6565321e0aec1a0970c4e05bc6c8579205ba29aa5b2d778`,
the call returned unknown before the marker was appended. Both synthetic
journeys restored the Session without re-running the extension, inspected
source pages, made a later synthetic model turn and reconstructed again. They
used the test-only 7.2.11 helper override SHA-256
`05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`.
They are not human, live-provider or kernel-qualification evidence.

An [earlier combined run](observation-session-native-withdrawal-before-fix.log),
SHA-256 `941c8918ca11e0f24bebd64c1d2bac5344318c3eb0a7b68e5f5ca71de4881d0b`,
had 30 passes and two failures: ordinary no-withdrawal cases changed their
expected live-barrier error to a generic replay refusal. The private replay
checker was adjusted to preserve that distinction without relaxing marker
ordering. The exact affected two tests plus a withdrawal-negative test then
passed (seed 20270383, three tests, tool transcript only). Both PTY logs above
are from the corrected source. A full combined rerun after the correction has
not been performed.

The operator observation is authenticated during the live private path, but a
journal marker's structurally valid fields alone do not authenticate its
history or independently protect activation. The user-supplied guard can be
omitted with the header to resemble legacy. Recovery-marker races, all other
Session resource types, late writes, current policy/root and downstream
effects, terminal UI, installed builds, real operator journeys and supported
kernel behavior require further adversarial review and implementation.
No release or milestone acceptance is implied.
