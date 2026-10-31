# Managed-reference marker withdrawal follow-up

2026-10-27. This is a repair to the pure, currently unwired managed-reference
projector. It is not a live freshness barrier, protected recall, native-platform
qualification or P31 completion. The earlier
[component record](managed-reference-component.md) and its audits remain
historical and do not review this change.

A host reference message carries an `ipse_reference` marker with the SHA-256 of
its original labelled content. Before this change, the pure projector accepted
that message, replaced its content when a dependency was suppressed, and left
the original marker in place. The result no longer satisfied
`Session.Reference.reference?/1`; downstream code could no longer identify it as
the original reference. This was reproduced with synthetic data before the fix;
`_build/managed-reference-marker-before.log` hashes to
`cc25fefa4a0af687ffeacf2ab0c200a2bbb15230d56610466afc5625294567b4`.
The test did not exercise an integrated Session or show exposure of live data.

The projector now refuses withdrawal of a message carrying that marker, leaving
the caller to retain the original journal and stop rather than produce a
malformed projection. An eligible unchanged reference remains unchanged. A
future reference-aware projection must preserve reference identity and replay
semantics before this case can be supported. Ordinary unmarked managed excerpts
retain their existing withdrawal behavior. This conservative refusal is not the
full requested recall or withdrawal feature.

The managed-reference, reference, reference-replay, reference-wire and source
window suites passed 65 tests, seed 20270428, on the working tree. The same
suites passed 65 tests, seed 20270429, in a fresh graph from `668e6a3` with only
the projector and its test overlaid. Its private index tree was
`8652a266a22a608672c8371d153dc4e395df06f9`; tracked bytes matched the index.
Formatting and a forced strict compile of 141 project files passed. The isolated
log `_build/managed-reference-marker-validation-20261027.log` hashes to
`cfd514a24a07f89170bbb341fb4d9735b1ef9f9c7804d3d754b980ba42f0e8a0`.
No live model or protected storage operation was performed.

The uncommitted projector and test SHA-256 values are
`87bcfc63523abec9b4fa6245a2c4e24258d38dd6506e8c0739e1f16048349970` and
`9b493fe2ab303ab362d43b9f0a3a32436633218963026d091268dc286193e48a`.
Authenticated receipt admission, dependency propagation, current-root and
consent checks, a send-time barrier, reference-aware withdrawal, complete source
and platform verification, and adversarial review remain open.

## Supporting dependencies and expiry on refresh

A later pure-projector review found two additional consistency gaps in the
unchanged-record refresh path. First, the prior check compared recipe, lineage
and source versions but ignored the validity receipt's direct supporting-record
references. Synthetic version-1 and version-2 controls showed that a newer receipt
could add or remove support while the prior occurrence stayed eligible. The
pre-fix failure log `_build/managed-reference-support-before.log` hashes to
`e0436f16b4b330f4ca275f3dc3dbe2a4b9783e98debe79ec807065559042e7d4`.
The check now requires the exact support set for the same occurrence; added,
removed or substituted support refuses. A newer root with unchanged support can
still clear if the host supplies a valid current receipt.

Second, the prior check considered only the current deadline, so a fresh receipt
could extend a finite deadline or replace it with no deadline. The synthetic
pre-fix failure log `_build/managed-reference-expiry-before.log` hashes to
`ff2a80596a5bd0bc4385dec5fd4528d5287f39036c4b23adf56cdc8f8fa4ea06`.
The pure projector now refuses to extend an existing occurrence's deadline,
including after it expired. It accepts a shorter current deadline and retains it
for later checks; an originally unbounded deadline may become finite. New
observations require their own separately authenticated admission. These are
conservative consistency rules, not a protected current-root or policy check.

The five focused suites passed 67 tests, seed 20270506, in the isolated graph
with private index tree `a03d58bf5fea92a77afc181e99ca3c3429036fce`. Tracked
bytes matched the index; formatting and a forced strict compile of 141 project
files passed. The log `_build/managed-reference-marker-validation-20261027-r4.log`
hashes to `c5a2d56f68464ab57ecb65641d86e1ced47e42b4682951c9f0e0a3b9909a5fc5`.
Current uncommitted projector and test hashes are
`2265e697bfba25f57d7d8890a276b5e977b6bce85001530bdfaea836e2c17cae` and
`a9a8625df37d2af8928074a119f10789677e4d4d8629dbee5c081e62e8eecbee`.
These controls use synthetic receipts. No protected read, model request or
independent review was performed; the live integration and all its gates remain
open.

## Previously ineligible receipts

A subsequent synthetic test showed that the pure refresh check could accept a
new eligible receipt for an original record whose validity was already
`suppressed` or `unavailable`. The pre-fix log
`_build/managed-reference-ineligible-before.log` hashes to
`75dabe27f529c7a5efc3dd9f62b68ae82c26f0facae6a75642c77e745f057484`.
The same-occurrence refresh now requires both original and current validity to
be eligible. The explicit suppressed/unavailable verdict still withdraws a
safely projectable occurrence. A later new observation needs its own host
authentication and admission; this pure check does not provide either.

The isolated five-suite run passed 68 tests with seed 20270509 on private tree
`c431a167d70e920181e6f0b85bfd6cd366e25c29`. Tracked bytes matched the index,
formatting passed, and forced strict compilation rebuilt 141 files. Its log
`_build/managed-reference-marker-validation-20261027-r5.log` hashes to
`99e459c5acc7f15775c5cbec18bb127e88b5fd66a105b3304dceaf96d68c1b86`.
Current uncommitted source and test hashes are
`c010ee9d4b282d0c20222ab6a4a5d1850c4dc563da9567596063db9cc402abb7` and
`55108a1f784f933862983ff23be657d930d3eeaf0e6bf9783bb0aa59c827fd37`.
The live protected path, full current-source baseline and adversarial review
remain open; no protected operation or model request was made.

## Same-floor anchor consistency

A synthetic refresh with a higher generation, unchanged floor and a different
floor anchor was accepted by the pure projector before the repair (seed
20270707). Collection commits retain the anchor when the floor does not advance;
the uncommitted projector now refuses that substitution. Both version-1 and
version-2 record receipts have controls, including a higher-generation receipt
that retains the anchor. The focused test passed with seed 20270708.
Fixed tree `acae9424087e5b5e611b1ae71ca330053ca00faf` passed 69 managed-reference,
reference, replay, wire and source-window tests with seed 20270709 and one case at
a time; forced test-environment compilation with warnings treated as errors passed.

This is only a consistency check. An increased floor still needs authenticated
lineage and a current-root/consent barrier; the pure receipt does not prove
either. No protected collection or model request was made.

## Legacy null-record refresh

Version-1 null-record dependencies did not identify a selector. They could
represent a whole-root status or snapshot as well as an absence. A synthetic
counterexample changed the collection generation and manifest while keeping
the null record and validity metadata; before this repair the projector retained
the old text as eligible (seed 46453). The pure check now requires the exact
same collection root for an eligible refresh of that ambiguous shape. It still
allows explicit withdrawal, and version-2 exact-selector absence keeps its
separate refresh rules. This does not authenticate a receipt or wire current
eligibility into Session.

An old projection event that refreshed a version-1 null record across a changed
root now refuses historical replay. The production source has no caller of
this projector today, but any private prototype or future integration must
account for that compatibility change rather than reinterpret old null records
as keyed absences. The managed-reference, reference, replay, wire and
source-window selection passed 70 tests on seed 46454. An expanded seven-file
selection including the explicit historical-replay control reported 94 passing
tests on seed 46455, but six protected Session tests printed that their positive
journeys were not run because the filesystem profile was unsupported. Those six
are not positive protected-path evidence. No native Collection or model
operation ran.

## Legacy record and absence output may depend on root metadata

A later synthetic counterexample gives a version-1 record occurrence content
that reports the observed Collection generation. The old projector accepted a
new eligible receipt at a later root because the record and validity were
unchanged; it retained the stale text (seed 46481). Version-2 record and absence
selectors have the same limitation: their shapes do not prove that a worker
ignored generation or other root-dependent information in the read result.

The working-tree projector now requires identical Collection roots for eligible
refresh of every dependency version. Version-1 and version-2 support and
deadline checks still apply at the same root; explicit root-change withdrawal
still removes safely projectable content. This is conservative: an unrelated
write can prevent reuse of an otherwise unchanged record until a separately
authenticated new observation and occurrence are created. Version-1 and
version-2 historical projection events that refreshed across a changed root
now refuse replay, including events previously accepted by the pure projector.
No automatic migration or production Session integration is provided. A future
more selective refresh needs proof of the exact committed result and all
root-dependent outputs, not only an unchanged record identity.

The managed-reference, reference, reference replay, wire and source-window
selection passed 71 tests (seed 46484). Synthetic controls cover both legacy
versions, record and absence shapes, unchanged-root replay, refusal of old
changed-root projection events, and explicit withdrawal. No protected read,
production Session dispatch or current-root authority check was exercised.
