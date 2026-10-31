# Review lifetime and State deadline containment

Historical scoped receipt, 2026-10-29. This extends
[the Collection deadline gate](strict-deadline-interposition.md) and corrects its
remaining-forgetting interpretation. The earlier manifests and negative results
remain unchanged. This is containment, not completed P31C0 architecture.

The [independent review](strict-gate-lifetime-independent-review.md) found no
additional reachable bypass in its scoped paths. It identified older State and
DocumentStage test expectations that require reconciliation; the underlying
strict effect-lifetime architecture remains open.

## Review expiry did not prevent a late forget

46892 used actual DomainAuth, signed Core state and native `Review.with_review`.
Initial source members are explicit trusted synthetic fixtures; this is not a
Session-origin qualification. After genuine permit consumption, the control
stopped the real retained transaction helper at Collection's staged boundary,
waited beyond the actual 30-second permit deadline, and resumed it. The marker
`FORGET_PERMIT_EXPIRED_BEFORE_NATIVE_SWITCH` precedes the subsequent result.

The outer Review correctly returned unknown. The fixture then failed because it
had expected a known Core success, so the target assertion did not run there.
Read-only inspection46895 of that same retained store, without retrying mutation,
found generation/floor2 and an empty visible record set. The initial generation
was1 with the selected signed literal present. Thus the late forget committed;
post-callback uncertainty did not enforce permit expiry. The failed probe and
independent retained-store readback are both evidence, not a passing safety test.
46890 was the earlier sandbox refusal before native channel admission.

Collection now rejects all Review-dependent forget/retention/supersession
normalizations before mutation staging, including policies without another finite
deadline. The standalone forget and session-only retention owners refuse before
native review or journal creation. Other retention choices remain refused by the
existing deadline gate. The actionable CLI diagnostic does not describe an older
uncertain operation as unchanged. Existing operation inspection and elapsed-policy
reclamation remain separate paths, not newly qualified here.

46900 exercised the current Core gate with a genuinely consumed native Review
permit: the exact fence error was returned, the signed target/root stayed
unchanged, and the outer consumed-review wrapper remained conservatively unknown.
This establishes refusal, not a new enforceable permit-to-effect sink.

## State had its own check-to-rename gap

46894 interposed the actual OTP file-server `rename` request after State's final
clock check. The synthetic destination still awaited rename before expiry; after
releasing it past expiry, State returned `ok` and the file existed with the new
record. No clock replacement or product hook was used. The probe's final cleanup
sent an unnecessary message to the file server after success, producing a harmless
test log error; that cleanup was corrected in the final fixture.

46891/46893 are retained fixture failures: the first matcher assumed a charlist
destination, while the actual file-server request used a binary. Switching the
test comparison to `to_string` reached the intended boundary in46894. These were
not product refusal controls.

New valid `state.put` requests carrying `write_before_ms` now refuse before any
filesystem IO. The exact Core failed value is
`%{"code" => "state_deadline_fence_unavailable"}`; its closed validator rejects
extra fields. Session refuses before mutation intent with an actionable message,
and the private writer has its own backstop. Ordinary no-deadline State requests
keep their approval/CAS path. Dropping a required condition is not an authorized
automatic retry.

Current controls passed:

- 46898: actual Session State deadline proposal refused before intent; its ordinary
  no-deadline counterpart succeeded, with Saved reconstruction checked.
- 46899: Core deadline refusal performed no filesystem IO, checked the closed
  failed receipt and tamper refusal, and retained ordinary write/read compatibility.
  A second control exercised actual standalone forget/session-retention CLI
  refusal without review or a management journal.
- 46900: actual native consumed-permit Core gate retained the signed target/root.
- Strict compile46897 passed six changed modules. Final formatting/help compile
  46902 passed seven modules. 46896 retained only unused argument warnings before
  that correction. No aggregate suite or earlier positive selection was repeated.

## Document coordination and diagnostic provenance

The separate [document correction](document-store-deadline-diagnostic.md) fixes
inherited deadline minimum/restoration and the typed
`document_store_deadline_unavailable` failure. Word's two tested DocumentStage and
CollectionStore BEAMs were overlaid without changing their bytes, Runner or helper;
46904 records their hashes. Source's State/forget controls preceded this overlay
and do not claim a combined document rerun. Older document positives remain
historical; no silent fallback or deadline reinterpretation is admitted.

The earlier ptrace diagnostic executable is preserved, not merely identified by
an inventory hash:

- [Diagnostic executable](strict-gate-lifetime-followup/diagnostic/transaction-deadline-interposition.bin),
  SHA-256 `3430ccc9e7cac23dab8b3b7fd7c01c9cbe642445a9ab3e3e67e25a8c6bb09ce5`.
- [Exact matched helper](strict-gate-lifetime-followup/diagnostic/matched-ipse-runner.bin),
  SHA-256 `a51c2d34654e21b0418b31bbe5ec2423d117230a3a8f3687803d5c1438d1c12e`.

Rebuilding the unchanged diagnostic source with the following command reproduced
the executable byte-for-byte in46901:

```sh
rustc --edition=2021 -D warnings dev/fixtures/transaction_deadline_interposition.rs \
  -o _build/transaction-deadline-interposition-rebuild-20261029
```

The manifest
also retains the vulnerable State/Collection/Review BEAMs used by the probes,
full runtime inventory, source, logs and manual byte snapshots. Old manifests
were not edited to improve their provenance retroactively.

Nine manuals were reconciled for gated native forgetting, State draft/renewal
refusal, ordinary no-deadline compatibility, old-operation inspection and the
distinction from built-in Memory suppression. Lifecycle's parallel Linux
pending-header recovery paragraph was preserved. The gate cohort's ordinary
startup controls do not qualify that separately reviewed header implementation.
Documentation check46903 passed732 files/6178 links before this record was added;
final46905 passed736 files/6210 links with zero errors. Snapshots use `.md.txt` so their
old relative links are not treated as current navigation.

The [manifest](strict-gate-lifetime-followup/manifest.json) records the exact
cohort. No Source native/helper changes, new dependency, paid service or milestone
completion is claimed. The enforceable effect-lifetime architecture, real
literal-v4 A/B control, full managed display sinks, delegation and nested result
delivery remain open. The gates preserve Consent/Review meanings rather than
claiming that an after-the-fact unknown result cancels a completed mutation.
