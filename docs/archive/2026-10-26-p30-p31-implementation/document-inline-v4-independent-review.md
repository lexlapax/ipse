# Live inline v4 and source-use v4 — independent scoped review

2026-10-29. Accepted for the bounded infrastructure scope below; no new blocking
source defect found. This is a read-only review of
[inline origin](document-inline-v4.md) and
[source authentication](document-source-use-v4.md), against the
[prior v4 direction](shared-producer-v4-progression-independent-direction.md).
It does not accept actual v4 Session producer dispatch, completed-group proof,
public v4 adoption or the full P30/P31 milestone. The [plan](../../plan.md) owns
remaining acceptance.

## Evidence verified

The inline manifest is
`4e3707b2170c413fe9d084121c8a6b5f3c53ba16f42b3142156d220b995c36df`;
all19 direct rows, all1697 runtime rows and all175 source-tar members match.
Its complete-input graph's application inventory names216modules. The archived
CollectionStore, DocumentEmbedding and Session copies equal the corresponding
tar members. Their respective SHA-256 hashes are
`5d4fcc07ff19b789c20ede46b604641b39ded77b8e69eceb5cd0f2e5ae76d2ce`,
`2db4d9e3c8cb667a8dc552825a29c202ced939c95e9d4f499903938e34e1f9c2` and
`a8d3dabb8f50bb369615d660f846ac14cfd4ad6acc0aca89be7fc0defa291ea6`.

The source-use manifest is
`ff35d3a1b24985ea1bd5a96ea60b5c4f13820677a6269f70b4c6302fdc0353ca`;
all12 direct rows and both669-file runtime inventories match. The sole runtime
difference is DocumentSourceUse.beam. Source SHA-256
`ea0dcd6555b7d88f281a58682677263e5ffd44222d60baa9dbfa6355d270625b`
is also the exact DocumentSourceUse source in Root's combined175-input tar.
The [verification script](document-inline-v4-independent-review/verify.exs)
and [output](document-inline-v4-independent-review/verify.log) only hash/read
files, inspect the source tar and consult the application inventory. No test,
application, effect, native helper or model request was run by this review.

Retained logs support strict full-source compile47233, nine focused Session
cases47235, and one native storage-boundary case47236 with nine excluded.
The SourceUse logs support two new synthetic relation cases and two selected
v3 regressions. Earlier incomplete bundled-source compile47231 and JSON alias
failure47234 remain failures, with their original source/logs retained. The
combined own-root/document Session graph has compile evidence, not combined
runtime acceptance.

## Source disposition

For a selected document identity, CollectionStore obtains the actual old row
inside its existing Identity-bound file effect and retained document reader.
An absent slot requires expected revision zero. Reuse requires a positive exact
revision and a closed compact-v4 ready row at the same canonical key. The root
witness must equal the original request generation. The reader's opaque success
marker must survive its checks and cleanup before the actual put proceeds.
DocumentStage then uses the original generation and expected revision; it does
not refresh the epoch. The intervening-write native case demonstrates this
specific CAS boundary and a later fresh pending write. Its seeded ready is
synthetic and does not establish completed-domain-work provenance.

The Session handler binds its job, active intent and phase, accepting only its
current trusted task or that task's registered file-effect peer. The extension
JSON does not supply a live observation. Preparation further binds identity,
Session, parent, approval, exact request hash, key, namespace, project, native
generation and data hash. A second preparation refuses. Only the matching
validated action result, after durable Session recording, can convert the
volatile observation into a claim. Known success must contain the exact
operation/request and native next generation, record revision and hash; ordinary
CollectionStore result validation additionally checks key and byte count.
Unknown/failed and tested operation/hash mismatches consume the observation and
poison the state. Malformed results rejected before this path create no claim.
Saved records do not reconstruct volatile origin. Batch spending and matching
known-result advancement remain one use; guard versions must match the origin.

Guard2 accepts only canonical partition/ordinal keys0–31, closed pending-v4
shape and eight-aligned cursor/count relation. Authentication independently
loads actual anchors, source heads and complete bounded bundles, derives the
total chunk count from authenticated heads, requires the exact globally ordered
position slice and checks original ranges, identities, canonical/raw hashes and
actual input bytes. The current-source check still applies to every source in
the claim after blocking admission work. Guard1/v3 follows its separate existing
relation. No Host chunking policy, automatic current eligibility from stored
snapshot bytes, or ordinary unguarded embedding fallback is introduced.

The Host ready predicate is intentionally structural. Domain code must still
prove that reused ready work belongs to an advanced completed group or selected
prior job, and bind that proof to the same epoch/CAS. This review does not credit
ready receipt fields as authentic model provenance or the previous-ready
descriptor as proof of a completed group. The slot31/256-count case is a shape
control; the new ordered relation uses an11-chunk synthetic source. Neither is
populated native maximum, full metadata geometry, permanent-ID budget, facts,
cleanup, import or migration acceptance. No new output, tty or public v4 gate is
qualified here. Original source/Registry clocks and final transport admission
remain required, with the existing admitted-inflight liability contract.
