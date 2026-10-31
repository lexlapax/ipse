# Independent review of historical choice compaction

Read-only review dated 2026-10-28 of the in-progress
[history compaction and controlled-time evidence](index.md#bounded-history-compaction-and-clock-trace).
The later [signed commitment repair](index.md#signed-choice-commitment-repair)
addresses this finding in the working tree; that repair has not yet received an
independent audit. This is not a complete P31C1a or milestone audit.

## Finding: compaction removes the signed commitment to the prior choice

The history expiry normalizer authenticates the current signed anchor and
compares its complete choice with the expiry facts, then may replace the
anchor's `choice` with `nil` while retaining clocks and the successor edge.
The standalone caller durably appends the complete facts to its management
journal before entering the effect. The honest native test checks the choice in
that journal and reconstructs the earlier review digest.

After this switch, however, the new HMAC-authenticated anchor commits to the
clocks and successor edge, **not to the removed choice**. The prior signed page
becomes unreachable and Collection garbage collection may delete it. The
remaining choice copy and its reconstructible review digest are in the ordinary
management journal/control records. Journal source-origin checks explicitly do
not protect against coherent rewriting; the control ledger's compact receipt
digest is also an unkeyed digest, not a project-domain MAC.

Consequently, after the old page has been collected, an examiner cannot use the
current signed anchor to distinguish the original retained choice from a
coherently altered journal/control copy. A writer able to alter those ordinary
records can replace the capsule and recompute its associated review/receipt
hashes without forging the surviving anchor's MAC. This is a source-derived
integrity counterexample, not a claim that an arbitrary remote user can write
operator files or a demonstrated exploit against the native sandbox. The
review did not run a physical tamper-and-recovery test. The honest equality
control establishes preservation of bytes during that test, not post-GC
cryptographic authentication of those bytes.

The current `IMB2` anchor encoding has only a nil choice tag and the full
native-management capsule tag. Its successor retirement hash binds the new
record value, not the old choice; its clock fields are not an available 256-bit
commitment. A repair needs an explicit versioned compact choice commitment, or
another retained project-authenticated receipt, plus reader compatibility and
capacity accounting. It must bind the exact journaled capsule to that retained
commitment, preserve pinned-history refusal and old-floor import fencing, and
exercise actual collection followed by deliberate capsule/journal tampering.
Reusing a successor hash or clock as an implicit choice digest would change
their established meaning.

Relevant current sources are
[`NormalizerV3`](../../../lib/ipse/extension/collection/normalizer_v3.ex),
[`ManagedPages`](../../../lib/ipse/extension/collection/managed_pages.ex),
[`Management`](../../../lib/ipse/cli/knowledge/management.ex),
[`Consent`](../../../lib/ipse/extension/consent.ex),
[`Collection`](../../../lib/ipse/extension/collection.ex),
[`SourceOrigin`](../../../lib/ipse/journal/source_origin.ex), and the
[native fixture](../../../test/support/managed_shared_support.exs). The
[hash list](evidence/compaction-independent-audit/sources.sha256) identifies the
reviewed working-tree bytes; no source snapshot, runtime test or broad suite was
created in this read-only review.

## Other reviewed limits

The expiry path checks the selected signed history, finite elapsed deadline,
exact original target and root, and advances the destructive floor in the same
bounded native transaction. Pinned history has no finite deadline and refuses
automatic expiry. These are code observations, not a replacement for the existing
native controls or a complete recovery audit. The documented interrupted-effect
test explicitly reports a surviving held file-effect process and an unconfirmed
result; it does not claim immediate process termination.

The controlled-time trace maps native review timestamps to an explicit
development-only virtual frame and uses a synthetic future expiry time. Its
record accurately distinguishes real review and virtual time. It is not an
elapsed-year workload, an end-to-end Session historical-use admission, or
evidence of full suppression compaction. Those qualification gates remain open.
