# Independent knowledge-readiness review — 2026-10-29

This scoped review covers the advisory `Collection.publication_support/0`,
knowledge CLI status/permission output and native enable notices, together with
the focused readiness fixture. It establishes no protected capture, Session,
installed-user or platform acceptance.

No concrete defect was found in the reviewed change. The support report is
fixed to false with the same `collection_deadline_fence_unavailable` reason as
the existing publication gate. The gate, its callers and their authority checks
are unchanged. The new capture-readiness field requires both saved activation
matching and publication support; it therefore cannot turn a valid grant into
publication authority. Plain status distinguishes a matching saved selection
from the current inability to save protected notes.

The permissions view still contains the exact raw policy and epoch. Its nil
activation-readiness value remains inspection-only, rather than claiming the
selection has passed the separate readiness check. The enable review retains
the complete serialized permission arguments and existing native confirmation,
configuration refresh, binding and compare-and-swap save path. The notice is
shown before confirmation and after saving; it does not change what was granted.

The reviewer inspected the recorded strict two-module compile at seed47003 and
the actual native readiness fixture at seed47004: **one passed, seven excluded**.
The fixture proves a genuinely saved grant reports activation matching while
publication and capture remain unavailable; raw policy, epoch and configuration
bytes are preserved. This is a native permission/status journey with synthetic
inputs, not a Session capture or model call. No passing test was rerun, and the
reviewer changed no implementation. The parent retains those receipts and
batches documentation validation.
