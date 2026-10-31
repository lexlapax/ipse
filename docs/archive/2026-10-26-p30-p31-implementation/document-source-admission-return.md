# Preserve admission through confirmed reader cleanup

Scoped additive repair, 2026-10-29, to the
[initial wired candidate](document-source-admission-initial.md). The
[plan](../../plan.md) owns acceptance. This fixes the trusted caller's return
protocol; it changes neither the Collection reader's contract nor worker authority.

The retained diagnostic reached actual native source authentication and the exact
Session wire/live-claim check. Session spent the first batch, but transport refused:
the callback returned bare `:ok`, while `Collection`'s document-read branch accepts
only its closed `{:ok, _}`, error and unknown forms. The bare value became a known
reader refusal after the spend. This was a functional refusal, not an admission
bypass. The failed operation/home are preserved separately and never replayed.

`Session.DocumentEmbedding.before_dispatch/2` now creates one private reference.
Its actual native callback returns `{:ok, reference}` only after all source,
Session and final clock checks. That exact value must survive Collection checks
and release, Identity revalidation and release, and the tracked file-effect
wrapper. Only the exact returned reference becomes EgressGate `:ok`. Arbitrary
success values, bare `:ok`, error, unknown, exception and loss refuse. The original
batch spend is not reset on an uncertain or refused return.

The [manifest](document-source-admission-return/manifest.json), SHA-256
`abe08ba70b0b18663df91ba1cf244f10db7104708d50605c85088c3d5d1a8020`,
pins the exact source, strict compile launcher/log/freezer, both full runtime
inventories, the overlay hash and original 175-source ancestry. Only the
DocumentEmbedding BEAM differs from the complete-inventory parent; application
module inventory, helper and private assets are unchanged. Source SHA-256 is
`dd95dac4c48792962fadbf2cae523ae6ef7d935269cfa78046ea8fc45fba27b9`.
`47212` compiles the sole owner without diagnostics. The
[independent source addendum](document-source-admission-initial-implementation-independent-review.md)
accepts the exact-marker/cleanup relation without rerunning effects.

Subsequent [actual registered Session controls](shared-producer-guard-session.md)
on this uninstrumented graph pass a four-batch private-artifact positive and a
separate approval-delayed source-expiry refusal. Their native/journal/artifact
evidence and original failed attempts are frozen in that separate record. The
positive's old selected root is absent and its sources have nil expiry; the
negative checks expiry of a source in the complete captured claim, not a claim
about only the first batch's source. A distinct all-source finite-TTL positive is
recorded in the [separate finite-TTL control](shared-producer-finite-guard-session.md)
and [independent review](shared-producer-finite-guard-session-independent-review.md).
Do not claim a maximum populated workload, complete
producer progression or public artifact execution from these bounded controls.
