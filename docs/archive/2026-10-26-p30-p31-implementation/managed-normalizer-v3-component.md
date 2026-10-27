# Authenticated automatic NormalizerV3 prerequisite

Recorded 2026-10-27. This component adds only the new host-private
`Collection.NormalizerV3` and its owning tests. The original Normalizer's version-2
behavior and bytes remain unchanged. The original fixture graph below includes
no Core/SDK integration. A later, separately frozen author test graph exercises
actual Collection/Identity publication without changing this interpreter. Neither
graph establishes SDK-v3 dispatch or P31 capacity/lifecycle acceptance. See the exact
[results and source bindings](managed-normalizer-v3-results.json) and the
[ManagedPages prerequisite](managed-pages-component.md).

## Caller contract and closed output

`normalize(witness, read, options)` requires the existing Normalizer options
`request`, `recipe`, `constraints`, `verified_sources`, `policy_sha256`, `now_ms`,
plus `domain_cap` and the actual Identity `catalog` callback receipt. These are
host-private values. Shaped JSON, source proofs, a parsed management capsule or
an arbitrary callback do not establish current consent or source authority.
The actual held Collection witness/read closure and same-owner scoped capability
remain caller-required provenance.

Automatic normalization supports exactly one fresh revision-zero public insert,
with explicit `advance_floor: true`. Literal identity must use the fixed
`note.<lineage>` key. A proposal uses fixed `pending.<proposalidentity>` and stays
`never_current`. The same reviewed recipe, constraint, original-request hash and
authenticated-source-member checks as version 2 apply. Legacy override records
must be absent. Existing public records and retained live identities both refuse.

The format is read first. An existing record must authenticate the exact immutable
ManagedPages descriptor under an active matching catalog. A missing format is
allowed only for an actually absent native root and matching prepared catalog.
An existing root missing its format refuses; unsigned version-2 pages acquire no
adoption or resealing authority.

The interpreter obtains the current anchor and live rows through actual neighbor
refs and exact selected-value reads. Every observation matches the callback's
root summary, state, manifest and root hash; ManagedPages rechecks the old MAC,
range and nonsingle minimum. Nonnull stored choices or retirement refuse until a
typed adapter exists. Literal and proposal first-observation clocks remain
separate. Deadlines clip to the earlier retained baseline; recapture, later
policy or persistent relabeling cannot renew them. Reaching the deadline refuses.
Small private clock logic is duplicated to preserve the existing interpreter's
unchanged contract, rather than introducing a new shared policy framework.

Live rows preserve lineage, exact value hash, recipe hash and historical policy
hash. The fixed category codes are ordinary=0, preference=1, current=2, pin=3,
history=4; this automatic slice emits only 0..2. Eligibility codes are current=0,
never-current=1, history=2; automatic proposals always emit 1. Clocks use exact
canonical base36, and hashes use canonical Base64url. No pin/history or operator
choice is minted here.

The two local plans produce at most five sidecars, four nonnull values and one
deletion with the exact positive old revision. Initial publication has three
sidecars: format, anchor and live. Existing formats are never rewritten/deleted.
The original public change remains exact and first. Signed page revisions bind
the actual publishing operation and old global generation plus one.

The closed version-3 receipt is at most 2048 bytes and contains lineage, public
key, first/deadline, category, eligibility, format-value hash and an exact ordered
`metadata_changes` list. Each member has key, expected revision and the canonical
whole wrapped-value hash, null exactly for deletion. No caller-selected byte
estimate or synthetic authority receipt is added.

## Charged reads and reproduced maximum plan

There is no whole-store load or cache bypass. Every read reaches the original
held closure; an additional local counter charges the existing Directory costs
and refuses over 32 units. The no-cache worst case is:

| Operation | Units |
| --- | ---: |
| Format, legacy override and explicit public-key absence | 3 |
| Semantic anchor lookup, neighbors and selected value | 5 |
| Semantic live lookup, neighbors and selected value | 5 |
| Anchor local repair, including a buddy | 6 |
| Fresh live insertion repair | 5 |
| Total | **24** |

Native-absence initialization used 19 units. Retained-live refusal used 13.
The maximum test seeded an authenticated anchor leaf at its exact 2104-byte
minimum. Clipping one retained deadline shrank it by two bytes; local buddy
redistribution changed the interior fence and deleted the old fence at revision
one. A simultaneous 25-to-26-row live insertion split its leaf. The resulting
plan used exactly **24 units, five sidecars, four values and one deletion**.
Every value fit 6144 bytes and the receipt fit 2048.

The SDK's older two-sidecar reservation cannot admit that effect. Versioned SDK
dispatch, byte/change reservation and final consumer receipt/authority handling
remain separate requirements. Actual first-root Identity/CAS binding is exercised
by the separately bound author controls below, not by this maximum fixture.

## Original fixture checks and preserved graph

Nine NormalizerV3 tests passed, together with the ten unchanged ManagedPages
tests (**19 combined**). Identity admission/catalog writes and DomainAuth tags
are actual protected native operations. Collection roots/observations and source
members are explicit trusted development fixtures using the real Directory
selection code. There were **zero actual Collection publications**, real human
attestations, model calls or held-out fixture interpretation.

Controls cover initialization, unchanged original input, host clocks, historical
hashes, separate proposal clocks, expiry non-renewal, source/constraint/request
and catalog refusal, fixed prefixes, missing format, unsigned old metadata,
stored choice/retirement refusal, changed MAC, an old authenticated page moved to
another operation, retained live identity with absent public value, and the
maximum shrink/split/deletion plan.

Actual Elixir **1.18.5 and 1.20.4** each compiled the new module with empty
diagnostics and formatted both source/test files without changes. ExUnit ran on
1.20.4 only. The initial 1.18 verification script had an assignment-spacing parse
error; its original file is preserved, and the corrected verifier passed without
changing production source.

The final private graph `/tmp/ipse-normalizer-v3-component-20261027-03` derives
from the frozen ManagedPages graph, plus these two files. It does not include
later Core/SDK integration. All **4060** source/build/link entries match before
and after the final checks; manifest SHA-256 is
`d75c1b8feea8c723105a46a55b2ec5ebf4c78964826a30024b359b5cfa0f20c9`.
The same private protected helper is bound by SHA-256
`d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`.

A byte-verified owner-only copy is retained under
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/normalizer-v3-component`.
Its 4070-entry `files.json` SHA-256 is
`e96d6500994e651d62114bdd36ee2647146614637d900255cb679a447ba2b715`.
The copy preserves source/runtime bytes, logs, strict 1.18 output and the failed
verifier. Its non-following `lstat` walk skips all aliases before recursion or
permission changes. No directory-fsync durability claim is made.

## Independent interpreter audit

The independent audit reported no actionable finding in its scoped interpreter
review. Final execution passed **29/29** on Elixir 1.20.4 / OTP 29: nine unchanged
NormalizerV3 tests, ten unchanged ManagedPages tests and ten fresh controls.
Identity/tag operations were actual; Collection observations were trusted fixtures
and there were zero Collection publications. Fresh tests covered exclusive
deadlines/rollback/overflow, separate proposal clocks, source/catalog/binding
refusals, exact shared32 exhaustion, coherent root drift, foreign/expired
capabilities, signed underfull geometry and cross-project tags.

Its first run was 26/27 because the test expected the lower-level expired reason
rather than Identity's intentional first-use unknown mapping. The initial test
and complete log remain preserved; no production repair or inner assertion was
weakened. Its report also preserves the owner's original 1.18 parse-error source
and explicitly records the missing standalone raw error log.

The literal report is retained at
`p31-verification/independent-normalizer-v3/working-copy/REPORT.md`, SHA-256
`ea00f50923fdfb72344f98c30b00e52ed5de9aac20b69d1031ea3bc519d38012`.
The owner-only 2539-file payload manifest is
`3c5cb9bfddfecd5a341dd4d2f2008a3dec61c9fea03ebac2d39752e5602fb769`;
its preservation includes file/directory fsync. The audit does not independently
qualify the later actual integration tests.

## Separately frozen actual Collection author controls

The new owning `collection_normalizer_v3_integration_test.exs` overlays only this
stable interpreter and tests onto the frozen
[Core-v3 graph](managed-v3-core-component.md). It reuses the prior trusted source
and recipe construction, never its synthetic Collection read/witness helpers.
All Collection observations and witnesses in the new tests come from actual
publications or checked actual ReadViews. They establish no SessionSource or
human/native-operator origin.

Final execution passed **15/15**, seed 238566, max-cases 1, 3.2 seconds on Elixir
1.20.4 / OTP 29: nine earlier fixture tests plus six new actual controls:

- One actual absent-root format read, checked close, Identity preparation, first
  three-sidecar publication and one actual current-root read-back/MAC/inverse
  verification before Identity activation.
- Active literal/preference/proposal follow-ons, preserving format revision one
  while new pages bind the current global generation and operation.
- A 27-publication live split series with actual individual writes, without
  seeding metadata or synthetic receipt identities.
- Actual stale-generation conflict and durable ID dedup excluding callback entry.
- An active catalog refusing another absent store's reset, and an actual present
  store with missing format/unsigned V2 metadata refusing adoption.
- Actual native-owner loss after a verified durable Collection commit: Identity
  remains prepared and outer outcome unknown; a new acquisition confirms kernel
  Identity lock release without automatic retry or reconciliation.

Observed initial/active reads are **19/23 units**. The five-sidecar merge with
24 reads remains the earlier trusted-Collection fixture case; this actual series
does not exercise that branch. No SDK worker dispatch or final Consent settlement
is claimed by these host controls.

The final graph `/tmp/ipse-normalizer-v3-actual-20261027-04` has 4068 unchanged
source/build/link entries before/after, manifest
`1e64ee79f9aa85623abffdfb37c805026109981b0489f2a2dbe07fc31fcf515b`.
The integration test SHA-256 is
`2c805e58e59e3ddf2291cb7634a8803bf6232710303c1bac795f6a464bc513c1`.
The runtime-binding report checks actual private origins for ten modules, their
BEAM/source bytes and the same private helper. Copied BEAM compile-source origins
remain distinguished from their actual executed paths. Report hash:
`5ebcf3b38b37345158b02eb6b57adbaa9e2f55fb8475f4480ec20d324bb9f90e`.
Actual 1.18.5 checked the new test's formatting only; there was no 1.18 ExUnit run.

First author execution was 14/15: the owner-loss fixture queried `receipt` instead
of the actual inspect API's `operation`. Unknown/prepared and durable-generation
checks had already passed. The failed source/log are retained separately from
the corrected runs. A later runner accidentally required an absent test file
before running tests; its failed harness log is retained. The runtime-binding
accessor also correctly refused a workspace overlapping the helper/application;
the corrected sibling-workspace probe changes no product source.

Owner-only evidence at `p31-verification/normalizer-v3-actual-integration` retains
the frozen graph, all failure/success logs, exact binding/result reports and all
30 isolated author fixture stores from the iterations. Its non-following payload
inventory has 4771 entries and SHA-256
`a8926e7e4aed45936b0916ff544555183cd94b9a8b890a73b579bb30393dcbc8`.
The separate result report hash is
`1e2292624fe5b8d15bf38f94b86d5cb46dc65d4c333a505cd3de2b0a439f897c`.
Aliases are recorded without traversal/recreation; files/directories are private.
No directory-fsync durability claim is made for this separate author copy.

Physical quota, imports, typed correction/forget/retention, source expiry,
every-dispatch withdrawal, annual publishing and SDK consumer integration remain
open. The previous failed capacity stores remain untouched.
