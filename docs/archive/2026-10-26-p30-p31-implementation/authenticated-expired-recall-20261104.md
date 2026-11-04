# Authenticated expired-neighbor recall

Dated **2026-11-04**. This is a historical synthetic correctness checkpoint based
on `d3dab913c96fcf4455120470b6a157bebe4547e8`, with the reviewed six-file
patch `181e697d594d4a7b68d44fd34644dbc949c6af17a1750a89c60de478bad070c4`.
The [plan](../../plan.md) owns current status; current behavior belongs in the
[operator permissions chapter](../../operator/knowledge-permissions.md) and
[Collection SDK chapter](../../developer/collection-sdk.md).

An expired ordinary neighbor previously stopped bounded recall before it could
reach a still-valid current note. The host now returns the narrow typed refusal
`collection_record_expired` only after current consent, original source ownership,
authenticated metadata, matching record/witness identity and pure structural
validation establish expiry of that exact selected record. It releases no expired
body or usable dependency. The worker boundedly skips that specific known refusal
and retains final-generation checks. Invalid metadata, policy refusal, missing or
unknown sources and other errors keep their existing behavior. The full protected
callback explicitly preserves this typed error through its outer `with` boundary.

The complete host passed a strict 195-file compile and rebuilt all four bundled
artifacts. The packaged Knowledge worker passed all 28 recall tests. The full
ManagedRead.execute control passed with actual native permission/revocation/expiry
and explicitly trusted local source-owner facts; the latter is not itself a live
Session-source attestation. Signed-source and adversarial metadata checks, plus
retained red/green callback results, support the classifier boundary.

A fresh complete native renewal control passed **one selected case, four excluded,
12.5 seconds**. It captured real Session-backed notes at day 0, renewed permission
at day 364, and at day 386 delivered valid current text while skipping an
expired ordinary neighbor. When the original source was removed, the current
note was withheld and the source failure was not relabeled as expiry. Saved
reconstruction, original source preservation, and idle reopen without new
input/worker/action/request/dispatch intent were asserted. The two provider
requests were synthetic loopback calls, with zero paid-provider calls. Normal
native filesystem and permission checks remained enabled. Frozen source/runtime,
pathset, symlinks, dependencies, helpers and fixtures were unchanged afterward.

The first typed-product attempt exposed the outer callback swallowing the typed
error; its fresh replacement used the repaired complete product but stopped after
seed because its fixture omitted provider_fixture.ex. That setup failure did not
renew permission or infer. The passing third attempt corrected only the helper
closure and path references, using the identical second-attempt product. Every
failed root remains preserved without replay. The complete chronology and exact
manifests are in the [evidence receipt](authenticated-expired-recall-20261104/README.md)
and its [53-file manifest](authenticated-expired-recall-20261104/evidence.sha256),
SHA256 `5a8cc93f5c330e0176956237a9b2888f45b901787384245a2564937dae9158c4`.
No raw journals, source text or provider bodies are copied into this checkpoint.

The retained 2,000-note cohort remains unchanged. Its renewal waits for the final
combined host identity, followed by a distinct populated read and one complete
day with actual Session turns and native effects. Annual normal work plus 10,000
mixed changes, resource peaks, quality and release qualification remain open.
This checkpoint supplements the earlier [owned-cache qualification](recall-owned-cache-20261103.md);
it does not replace or relabel any prior failed populated-cohort attempt.
