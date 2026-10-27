# Explicit Collection v3 normalization envelope

Recorded 2026-10-27. This is the host-private Core envelope prerequisite for
authenticated managed metadata. It preserves the original
`Collection.execute_managed/6` version-2 path and adds the explicit
`execute_managed_v3/6` path. The current SDK still selects version 2. This record
does not claim SDK-v3 dispatch, current recall, typed management, sustainable
capacity, lifecycle or milestone acceptance. The [plan](../../plan.md) remains
the delivery ledger.

## Implemented boundary

The trusted callback retains the exact original commit, generation and explicit
floor advancement. Original CAS, operation-ID inspection and writer fencing run
before callback entry. V3 permits at most five metadata changes beyond the
original: four nonnull values and one positive-retained-revision deletion.
Reserved keys are the immutable format key, canonical 32-byte anchor fences and
canonical 33-byte live fences with kinds 00..02. Format cannot be rewritten or
deleted. Ordinary mutation validation rechecks every resulting CAS under the
same actual native owner.

Native-confirmed absence requires exactly three nonnull new metadata records:
format, anchor-zero and live-zero. A materialized root must already retain its
format; missing format refuses. Core does not interpret a format value or grant
adoption merely because the key exists. MAC, page geometry, source authority and
semantic policy remain the trusted interpreter's obligations.

The callback receives actual native root state/bytes/hash and the existing
summary/manifest/original-request/recipe/operation bindings. Its exact-owner,
invocation-bound read closure shares 32 observation units: binary reads cost one,
neighbor requests four including nil positions. An over-budget attempt latches
final refusal. Version-3 normalization must be a bounded JSON object carrying
integer version 3 and fitting 2048 bytes. The durable managed binding hashes the
original request, recipe and normalization; the operation receipt hashes the
exact normalized commit. Known IDs cannot rerun either version's callback.

## Owner and independent checks

The owner graph `/tmp/ipse-managed-v3-core-20261027-01` was strictly compiled from
133 sources on Elixir 1.20.4 / OTP 29. Its first focused run passed **38 tests**
(seed 20261204, 3.7 seconds); its first broad run passed **177 tests** (seed
20261205, 322.9 seconds), both max-cases 2. Sandbox/filesystem/memory tags were
excluded as recorded in those logs. All 2350 admitted regular source/build rows
and membership were unchanged afterward. This is a focused/broad component
baseline, not a full current-tree suite.

The [independent Core audit](managed-v3-core-audit.md) read the boundary and
executed **34/34** tests: eight unchanged owning v3, seven legacy managed, eleven
managed-directory and eight fresh audit cases (seed 20261206, 5.1 seconds).
It found no actionable defect in that scope. Fresh controls include malformed
originals/receipts, duplicate normalized keys, exact metadata CAS, valid live
kinds, closure expiry/foreign use, native loss, cross-version dedup and actual
native-owner contention in one VM. They do not establish two-VM contention or
managed-source truth. The auditor's initial runtime-binding workspace-overlap
refusal and original probe remain preserved separately; no product repair was
needed.

Actual Elixir 1.18.5 independently compiled the one Core source/module with empty
diagnostics and formatted the Core source and owning tests unchanged. ExUnit ran
on 1.20.4, not 1.18 or OTP 27. The owner's preserved manual exercise was the pure
ManagedPages roundtrip, not a wired SDK publication or a native review.

| Input | SHA-256 |
| --- | --- |
| Collection source | `5b02c6dd265f9bcaf7d0201f4953d73bd106ba7dc2b8af4864e4ea75757a6fa7` |
| Executed Collection BEAM | `02cc1a0f0949532c95194447298016b4a06d06aaab221d4052a4e248c2bf624f` |
| 2350-row source/runtime manifest | `7e5744894b4cce77b483208cec1cf2d1b93a5b8746c2871bfd5db957b023d447` |
| Selected private helper | `d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b` |

## Separately bound actual interpreter integration

The subsequent author integration graph overlays only stable NormalizerV3 and
its tests on that frozen Core graph. Its final run passed **15/15**, comprising
nine earlier trusted-Collection fixture tests and six new actual Collection,
Identity and DomainAuth controls. It demonstrates checked native absence before
preparation, first-root publication and checked read-back before activation,
active literal/preference/proposal follow-ons, a 27-publication live split,
CAS/dedup callback exclusion, missing-format/unsigned-V2 refusal and native-owner
loss after a durable Collection commit leaving Identity prepared and outcome
unknown. Its source receipts remain explicit trusted fixtures, not actual
SessionSource/native-operator attestations.

Actual initialization uses 19 read units and observed active publication 23.
The exact five-sidecar merge/24-read geometry remains the earlier fixture case;
the small actual series does not exercise it. See the separately bound
[NormalizerV3 record](managed-normalizer-v3-component.md) and
[results](managed-normalizer-v3-results.json). No prior failed capacity/annual
store was changed, reset or resumed.

## Durable evidence and current limits

The evidence base is
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification`.
The independent literal report, all owner logs, complete source/runtime bytes,
external setup/compatibility/manual drivers and first harness refusal are
retained under `independent-managed-v3-core` and `managed-v3-core-owner`.
The independent record lists exact payload/provenance/preservation hashes and
reconstruction instructions. Owner payload manifest:
`ecb95ce934ae6c73e3f352dead70c5d085f6e2c482e0172c855df1cbc55694b3`;
independent payload manifest:
`cd96946e8295977dbbc14bd0c5a3e39aac3121169d7818ac45841873a9f8f1a2`.
Those preservation receipts include file/directory fsync. The separately copied
actual integration evidence has its own narrower preservation receipt and makes
no directory-fsync claim.

Current manuals teach the host API in [Persistence](../../developer/persistence.md#exercise-the-explicit-core-v3-envelope)
and the restricted authenticated interpreter in
[Knowledge storage](../../developer/knowledge-storage.md#publish-one-fresh-record-with-authenticated-metadata).
Automatic SDK-v3 selection/reservation, final outer accounting, authenticated
current-read filtering, typed retention/correction/forget, adoption/migration,
physical capacity and annual lifecycle remain separate gates. Neither Core's
envelope nor a parsed signed page grants permission for those operations.

The final editorial review read both developer chapters as whole documents,
reviewed the affected operator procedures and repaired allocation-profile,
effective Main-timeout and protected-unknown recovery guidance. Root executed
the exact Core-v3 and pure Pages examples from the Persistence chapter against
the isolated SDK author graph's actual compiled Collection and private helper:
both passed. Chapter SHA-256:
`0cfb818ce427592a8b1cef53c143cd079e464fd45c76edb8fc443ac90106f2df`;
driver `/tmp/ipse-managed-v3-manual-exercise.exs`, log
`/tmp/ipse-managed-sdk-v3-20261027-03/manual-core-pages-first.log`.
This additional manual check uses synthetic Core metadata and grants no source
authority or current-read acceptance. The graph's SDK checks are separate work;
they do not expand the Core evidence counts above.
