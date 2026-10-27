# Adaptive managed metadata: pure codec and leaf proof

Historical nonpublishing investigation, **2026-10-27 Pacific time**, Stage 1 of
the reviewed adaptive design. The [IMB1 controls](managed-binary-metadata-proof.md)
and [JSON no-fit control](managed-metadata-proof.md) remain unchanged. The actual
[managed series](managed-storage-continuation.md) still failed its 4,000-note
target at 3,724 successful publications with 3,324-byte actual notes. Its store
and pending oracle were not resumed or changed. Fresh 4,000 × 6,144 accounting
below is a separate exploratory cross-product, not a new baseline requirement.

**No product capacity, authenticity, lifecycle or annual qualification is
claimed.** These are developer modules and pure tests. No Collection,
Normalizer, SDK, native helper or stored metadata was changed by this experiment.
Synthetic MAC-shaped tags grant no authority. Host inverse validation, import,
actual managed allocations and a complete year of domain actions remain open.

## Encode exact facts and validate canonical pages

The [adaptive codec](../../../dev/knowledge/managed_metadata_adaptive.ex) keeps
immutable IMB1 as the single legacy evidence/native-candidate field definition.
Its new raw version is `IMB`/2, inside closed JSON `version: 3`, `data`, `mac`.
An empty data string and canonical 43-character tag cost exactly **75 bytes**.
Measured values include this envelope and complete unpadded Base64url expansion.
Kind and lower/next fences come from the pure directory context; production
authentication binding that context is not implemented here.

Present clocks use canonical unsigned LEB128 below 2^49, otherwise seven
big-endian bytes, with explicit presence/fixed selectors. Seven-byte ties use
LEB128. Integers remain exact through 2^53−1; nil differs from zero. First-plus-
delta pairs preserve exact baselines. Legacy evidence keeps its frozen encoding,
complete source proof, quote and 256-byte reason. The separately reviewed future
native capsule retains its 64-byte reason and challenge-derived exact input
hash; it is neither an implemented host mint nor a human attestation.

Retirement controls remain separate: omission is an intentionally incomplete
control; compact `native_literal_note` plus time conditionally retires only the
exact lineage's fixed native-literal derivative with original history retained;
the full control keeps exact key, value hash and time. The compact projection
does not retire paraphrases or arbitrary recipe prefixes, and is not a product
typed-management contract for all 8,920 declared retirements.

Identities use their exact longest common byte prefix with the predecessor,
initially the lower fence. Decoding checks closed keys, version, canonical tag
syntax, minimal integers, flags, safe clocks, kind, dictionary order/use, row
order/uniqueness, complete consumption and next-fence ranges. Re-encoding must
reproduce the full page. An empty page is valid only at a single leaf's zero
sentinel. Whole values are bounded to 6,144 bytes and 128 rows.

Live rows retain all four lineage/value/recipe/historical-policy hashes.
Canonical page dictionaries preserve exact recipe/historical-policy hashes;
current policy does not substitute for historical policy. Shared, catalog4,
catalog8 and per-row distinct controls measure different populations explicitly.

## Prove local occupancy without granting host authority

The [pure leaf planner](../../../dev/knowledge/managed_metadata_adaptive_leaves.ex)
uses supplied current-reference arrays. `proof.a.`/`proof.l.` are private
calculation names without product registration. Initialization/oracle checks
fully load their supplied fixture; this is not a production no-full-store lookup
proof. A local plan accepts at most two unique edits and only required selected
and neighbor values. Missing sentinels, duplicate/unsorted references, poison,
range violations, duplicate edits, absent deletions and extra selected values
refuse. Underfull leaves are allowed only when the entire tree is one leaf.

**Local-plan precondition:** old occupancy must already have been proved by
`initialize`/`validate_tree` under the **same immutable geometry and catalog
profile**. Local decoding checks canonical closed rows, ranges and ≤C, but does
not recheck old selected leaves against ≥L. This does not validate every
globally malformed/imported tree or make profile changes safe. Future production
must check selected old minima in a nonsingle tree and bind the immutable
geometry/catalog before sealing, or separately prove an equivalent trusted
producer invariant. A MAC alone is not that proof. No product adoption follows
from this explicitly narrower pure precondition.

Virtual weight charges full identity plus prefix byte, member bytes and
dictionary costs. Front-coding savings never justify occupancy. Candidate
anchors have minimum 37 and maximum **337** charged bytes, including four
clocks, maximum-duration capsule and full target/value/time retirement. Header
H=7, row capacity C=4,544, lower occupancy L=2,104. Distinct-hash live rows charge
both full hashes plus index bytes: minimum/maximum 170/183, H=9, C=4,542,
L=2,180. A declared global catalog is charged in the header; every row must
belong to it, so splitting/joining never invents a smaller dictionary-union bound.
Unsupported catalog geometry refuses.

Every admitted profile requires C≥5W and L=floor((C+1−W)/2)≥2W, where W is the
global maximum row weight. Deterministic nearest-half splitting gives each child
at least L. Underflow consults the left neighbor (zero uses right); only
overlapping repair components join. Adjacent disjoint components keep their
boundary. At most four old values and six changed keys are admitted for two
edits; oversized plans refuse. The byte limit precedes the row-count limit
because 128 times each global minimum exceeds C. The large full legacy control
has no native-only occupancy guarantee and remains separately measured.

The [eight tests](../../../test/dev/managed_metadata_adaptive_test.exs) cover
clock boundaries, canonical mutations, every truncated prefix, global maximum
weights, dictionary union, poisoned directories and 180 deterministic two-edit
plans against a complete pure oracle. This is not 10,000 durable cycles. It does
not close the SDK's 32-read/sidecar reservations, typed multi-change,
authenticated-neighbor or revision/CAS contracts.
In particular, the pure maximum of three changed keys per edit/six for two edits
cannot silently use the current two reserved sidecars or expand the 16-extra
ceiling. Discovery and complete effect reservation need a separately reviewed
host integration before any publication.

## Evaluate an existing package on the same facts

OTP Base/bitstrings, existing bounded integer routines and canonical
`Collection.Migration` JSON are reused. Collection's receipt-specific Encoding
and Blocks modules do not provide a generic 6-KiB domain-leaf codec. The
alternative **Msgpax 2.4.0** was selected within authorized implementation/
package-evaluation scope and repository Elixir dependency policy; this does not
mean the human specifically named that package. Its [inventory](../../developer/dependencies.md#evaluation-only-packages)
records evaluation-only scope and ISC licensing. No Mix declaration, lockfile,
ordinary-test or release dependency was added.

The [comparison adapter](../../../dev/knowledge/managed_metadata_adaptive_msgpax.ex)
packs closed arrays containing the same front coding, raw hashes, exact clock
pairs, full legacy evidence, native candidate and retirement fields. Every
actual page roundtrips all semantic fields and re-encodes identically. Reports
include complete JSON/Base64/tag bytes, not just MessagePack bytes. Wrapping the
custom binary as a MessagePack binary is measured separately; it still needs
the custom field codec. Controls retain generic MessagePack acceptance of
nonminimal integers, above-safe integers and collapsed duplicate map keys: a
closed schema/canonical adapter remains necessary. This comparison does not
authorize adoption of custom product serialization.

Final acquisition uses existing `Ipse.HTTP.bounded_request/3` with Finch's
verified TLS defaults, two fixed public URLs, a 64-KiB tarball/16-KiB metadata
ceiling and 10-second request/30-second overall guards. Tarball SHA-256 is
`ca933891b0e7075701a17507c61642bf6e0407bb244040d5d0a58597a06369d2`;
Hex inner checksum is
`4647575c87cb0c43b93266438242c21f71f196cafa268f45f91498541148c15d`.
Both and the source/license were reverified before private-HOME library
compilation. Optional Plug and development ExDoc were not fetched or compiled.
Two upstream Elixir 1.20 warnings are retained: protocol function implementations
and an unused Bitwise require.

Earlier acquisition used an existing host curl binary without specific
developer approval for that additional outside-Elixir/Rust dependency. It is
preserved as diagnostic, not a reproduction prerequisite or approved ordinary
dependency. Curl-bound measurements are preliminary. Replacement adapter
connection/metadata-size refusals are retained too. Explicit JSON Accept
succeeded under the same 16-KiB ceiling; neither TLS nor bounds were weakened.

## Keep accounting distinct from qualification

The [declared cases](../../../dev/knowledge/managed_metadata_adaptive_cases.ex)
reuse the pure Notes workload with 30 nominal daily actions and no burst
multiplier: day30/day90/year365 populations 2,182/2,542/**3,642**. The year has
200 persistent records, including 100 pins, 347 ordinary history and 1,460
temporal history. Frozen 3,460 arithmetic remains a separate control. Annual
shapes contain 20,220 anchors, 2,730 session choices, 100 pin choices and 8,920
retirements. These clocks are byte-width declarations, not causal lifecycle
chronology or an authenticated year of Sources. Public values remain charged
at 6,144 bytes but are not materialized. Pending proposals are not silently
counted as current notes.

The [artifact manifest](managed-adaptive-proof-artifacts.json) binds the
[complete evidence bundle](managed-adaptive-proof-evidence.tar.gz): 459 retained
files, including actual page byte counts/hashes, source/loaded-module/input bindings,
package source/ISC license, reproduction scripts and earlier diagnostics.
The final private graph is `/tmp/ipse-adaptive-proof-20261027-05`; all **741**
declared source/BEAM/input/package/helper files hash identically before/after.
The helper is inventoried but never invoked. Final acquisition/compilation is
`/tmp/ipse-msgpax-http-evaluation-20261027-03`; earlier roots remain diagnostic.
Page value bodies were generated and inverse-checked transiently; the original
reports retain counts and hashes, **not persisted page bodies**. Independent
regeneration can compare canonical values against those bound hashes; it is not
reopening a previously persisted page body.
Each
[runner](../../../dev/knowledge/managed_metadata_adaptive_run.exs) job retains a
30-second absolute timer, sampled 512-MiB VM memory guard and 16-million-word
main/test heap bounds. These are developer guards, not product allocation
enforcement. Native/model/publication counts are zero and qualification false.

Forty-one actual page jobs supply 72 joined original controls across both annual
populations, plus short/fresh, four-clock and catalog controls. Every row and
page range roundtrips. Page jobs took **1,299–21,919 ms**, with maximum sampled VM
memory **145,284,152 bytes**. The rebuilt pure year model took 23,943 ms and
72,956,848 sampled bytes and reproduced the frozen input exactly. Eight tests,
generic-parser controls and strict compilation of four pure modules passed.
Actual Elixir **1.18.5 and 1.20.4** both format all six source/test files without
differences. The deliberate deadline control exited **124**, created its guard
receipt and produced no successful result, as required. These are 45 bounded
jobs including that expected negative control, not performance qualification.
An additional [compatibility bundle](managed-adaptive-compatibility.tar.gz)
preserves actual 1.18.5 strict compilation of ten source files containing four
adaptive modules plus seven existing pure dependencies: eleven modules, no
warnings. Attempting tests through
that packaged release first refused because ExUnit is not shipped there; its
diagnostic is retained. The 8/8 execution claim is specifically Elixir 1.20.4.

| Selected canonical packing, 3,642 notes | Complete metadata bytes including 6,144 format reserve | Headroom against 2,789,376 |
| --- | ---: | ---: |
| Native candidate, conditional literal retirement, calendar/shared hashes | 2,616,423 | 172,953 |
| Same, maximum-safe clock profile | 2,718,815 | 70,561 |
| Same calendar profile, four historical catalog hashes | 2,627,342 | 162,034 |
| Same calendar profile, eight historical catalog hashes | 2,649,148 | 140,228 |
| Same calendar profile, every row's historical hashes distinct | 2,921,798 | −132,422 |
| Native candidate, full target/value/time retirement, calendar/shared | 3,389,503 | −600,127 |
| Full legacy evidence, conditional literal retirement, calendar/shared | 7,396,792 | −4,607,416 |
| Msgpax closed-array comparison on first row's identical page membership | 3,106,012 | −316,636 |

The first row has 512 anchor pages (2,050,621 bytes) and 128 live pages (559,658
bytes). The four-safe-clock/full-target anchor control alone is 3,311,039 bytes
in 1,024 pages; its complete result remains a miss. Twenty-four of 72 selected
annual packings fit their respective accounting allowance; this is not a global
capacity proof. Global maximum-weight/page-count bounds are more conservative
than measured selected packings and cannot establish universal budget fit.
Msgpax uses identical page memberships, without a separate optimized repartition;
its measured miss does not prove that every possible MessagePack schema misses.
Every comparison records individual page over-limit outcomes explicitly.

| Separate calendar/shared pure population | Notes / anchors | Metadata plus format reserve | Metadata allowance |
| --- | ---: | ---: | ---: |
| Day 30 | 2,182 / 2,840 | 557,778 | 11,759,616 |
| Day 90 | 2,542 / 4,520 | 753,781 | 9,547,776 |
| Fresh minimum | 2,000 / 2,000 | 460,928 | 12,877,824 |
| Fresh exploratory cross-product | 4,000 / 4,000 | 891,637 | 589,824 |

The exploratory 4,000 × 6,144 case therefore misses by **301,813 bytes**. Neither
workload nor quotas were reduced to conceal it. Initial pins and evergreen
records remain in every appropriate shape; no source evidence, clocks or fields
are silently removed.

Earlier diagnostics remain in the bundle. An initial maximum-row test did not
construct the actual maximum delta; its failing log survives, although its first
JSON filename was overwritten by a later test pass. A later adversarial empty
sentinel with a nonnil upper fence reproduced a decoder gap (7/8 tests); that
negative receipt and the correction precede the final 8/8 graph. Preliminary
format/strict-verifier harness errors are retained with corrected checks, as are
the earlier sampled-watchdog model attempt and missing-fixture refusal. The final
runner uses a separate absolute deadline timer. None of the preliminary graphs
is substituted for the final package-bound results.

Open gates include production authentication/context binding/key rotation,
unsigned/import provenance and migration, authenticated bounded neighbors,
typed plans, SDK reservations, physical staging, source/expiry/choice retention
and actual annual publications. Shared-policy results are conditional. The
adaptive compact/shared safe-clock case improves on the unchanged IMB1 failing
control; distinct hashes and full target witnesses still miss. Original wider-
clock/full-evidence failures remain preserved as their original format's
results. A pure page-size result closes none of those product gates.

## Independent narrow review

The [literal independent report](managed-adaptive-independent-audit.md), SHA-256
`6d8898c09d5576e135147310027e217f4fb330034b7c58f4c10778b1c5d01876`,
found no actionable defect within this pure Stage 1 contract and its explicit
SAME-profile/prior-occupancy precondition. It independently verified all 741
bindings, 459 bundle members, 45 job dispositions and 72 joined controls; reran
the maintained 8/8 tests; added seven independent passing controls; and
regenerated six representative page bodies whose counts, hashes, exact inverse
and MessagePack comparison matched their original reports. It also preserved its
initial harness failures and warnings. This separate review approves no product
adoption, source authenticity, physical capacity, import or annual acceptance.

Its durable copy is under
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-adaptive-stage1`.
The 1,423-file preservation manifest SHA-256 is
`5fd914f93d1ed9f740ede4c159ca488251408a1a7de5fc05e72fc17bc9ce1866`;
provenance is `3b09f7786f743913400b0f90964668c4e0570761c4982a31981aa6e506e4dc69`
and receipt `6795ab8558655d793d257afae313803d5b91b6eb15b2b65686c5a9b7e5b17d29`.
Four admitted alias-row files were materialized and three aliases omitted, with
exact source/target hash checks and the first preservation failure retained.
Native UID/directory-sync calls during preservation are separate from the pure
audit's zero native calls; no codec/store helper work was performed.
