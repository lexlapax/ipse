# Combined chat and ordinary-expiry audit — 2026-11-04

Historical source review; the [plan](../../plan.md) owns milestone status and
[manuals](../../index.md) own current behavior. This records a scoped review,
not a replacement for the final combined qualification.

Read-only source review found no concrete blocking defect in the combined
baseline, explicit-resume reoffer, typed ordinary expiry and live-mode/replay
integration. No main files were changed and no additional native input, model
request or storage effect was started for this audit.

The canonical reviewed combined product/test packet is
`_build/verification/notes-integrated-main-20261104-01/product-tests.patch`,
SHA-256 `5fda38ab5c506c83df6124430deb206d82bcf420e4b131edcae3d5e72b026260`.

The [reviewed source manifest](chat-expiry-audit-20261104/reviewed-source.sha256) records the examined source identity. The live-mode delta
changed exactly Session, ChatReviewHandoff, CLI and ToolLifecycle relative to the
initial review. Those four files received a separate delta review after the
root froze the combined source.

Reviewed boundaries:

- Nomination remains an exact reviewed outer-only selection, without nested
  effect mappings or grants. Current policy and normal interactive mode remain
  required; historical structural receipts alone provide no authority.
- A fresh explicit-resume snapshot precedes the first ordinary read. Authorized
  read requests invalidate it; foreign calls cannot consume or replace it.
  Opaque private handles, confirmed closure, one-use management attempts and
  distinct reservations/codes retain the no-replay boundary.
- Original/reoffer source receipts and pending facts are rechecked under the
  retained original source and current Identity/Consent/Collection owners at
  display, publication and later accepted-note use. Missing/unknown or
  contradictory prior accounting cannot become a known cancellation.
- Ordinary expiry is classified only after exact signed literal/root metadata,
  current source policy and original-source ownership. It returns the narrow
  failure code without a body or eligible dependency. Accepted decisions retain
  their separate version-6 path; other failures remain fatal to recall.
- Actual live mode is captured on claim and projected through an owner/ref
  checked private handle, with a Mode roundtrip. Provider/billing are unchanged;
  startup planning and session edit grants do not return. Explicit ordinary
  approval such as `--yes` remains the configured policy.
- ToolLifecycle uses the existing validated sparse mode timeline at each event,
  retains original header metadata and preserves ordinary headerless fragments.
  No new policy class or grant is introduced by replay.

Independent pure verification reran the current Knowledge recall source suite
with the complete immutable runtime SDK. One parent test passed and asserted
all 28 child controls passed. Both VMs used S1/A1. The parent application was not
started; there was no native helper, TTY, paid inference or live account test.
`recall-pure.log` records that result. Scheduling flags were the only test-text
substitution; repository test/source files remained unchanged.

The earlier qualified two-card and ordinary-expiry journeys retain their own
exact source/runtime receipts. This audit does not replace the final combined
main build, focused/full suites, native planning qualification, documentation
checker, installed package or platform gates.

Previously demonstrated negatives include displaced source offsets, changed
pending-selection versus acceptance facts, foreign or stale handoff callers,
unresolved reservations, and forged/missing/future/cross-Session mode changes.
The exact evidence remains with those scoped qualification records. This audit
did not rerun them as new combined native controls. The final mode projection,
ToolLifecycle timeline and expiry/source ownership interactions received source
review; the combined source suite and native planning journey remain pending.

Caller scope is the existing trusted host and exact registered CLI/Session/
reader ownership, with untrusted records and extension results subjected to
the stated validators. No shell-sandbox, hostile operating-system, independent
human, account, installed-package or additional platform claim follows.
