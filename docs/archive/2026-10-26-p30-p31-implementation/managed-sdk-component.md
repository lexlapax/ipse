# Explicit managed collection SDK boundary

The later [verified actual-input settlement repair](managed-actual-accounting.md)
supersedes this checkpoint's conservative successful-settlement description.
The dated implementation and original evidence below remain historical.

Dated **2026-10-26**, following protected storage prerequisite `2712b25` and
inference-dispatch checkpoint `5510ddb` on `codex/p30-p31`. This is a focused
internal engineering checkpoint, not P31E acceptance, operator activation or
managed freshness qualification. The [plan](../../plan.md) owns milestone status;
[the collection SDK chapter](../../developer/collection-sdk.md) teaches the live
boundary. Earlier [pure contracts](managed-policy-component.md),
[atomic storage](managed-collection-component.md) and
[normalization](managed-normalizer-component.md) retain their own provenance.

## Authorized boundary and ownership

A new `host.collection.managed` capability admits the distinct closed
`collection.managed` request. Existing `host.collection.read`/`write` grants do
not imply it. Both SDK versions retain their ordinary protocol and capability
rules; the actual independent-worker controls use SDK 2, including its mandatory
paged-result capability and public source-proof helper. No worker depends on a
host normalizer, SourceIndex or managed-policy module.

The request carries exactly `op`, `recipe_sha256`, `request` and `proofs`. Its
original inner commit and proofs remain unchanged within the existing 8192-byte
worker limit. Every managed commit explicitly declares `advance_floor: true`;
false refuses before an intent. Structural limits allow eight changes and one
to eight proofs; the current reviewed adapter/normalizer supports exactly one
new revision-zero record. Unsupported batches refuse rather than rewriting.

The action intent and result use **version 3**. Their managed effect binding is
**version 2**, carrying namespace, exact Session pin, outer descriptor SHA,
original commit SHA, recipe SHA and inner operation. Outer invocation version 3
and paged result version 4 retain their existing exact original bindings. Legacy
collection actions retain version 2 and their original binding. No version/tag
promotion makes an old saved receipt a new grant.

Session supplies only its exact currently admitted action, owned job and live
worker/effect-descendant lease. The private proof query resolves original source
handles/quotes again. Under ProjectIdentity, current Consent resolves the pinned
settings-v2 registries and requires exactly one matching mapping for the actual
candidate, constraints and verified sources. The worker's recipe digest is a
selection hint, never a classifier or stronger permission. Read-only outer
exports remain categorically unable to publish or lend ordinary write permission.

`Consent.publish` repeats current source/constraint checks before
`Collection.execute_managed/6` runs the trusted Normalizer under the collection
lock. The Core result binds the original request, recipe and normalization
receipt to the normalized commit and durable managed binding. SDK normalization
receipts require version 2, exact derived metadata shards/pages and finite
ordinary/pending deadlines. Publication returns no sidecar values.

Reservation precedes effects: one operation, the complete encoded original
worker request, two maximum 6144-byte sidecar values, exact bounded change/key/
revision/separator overhead, 2048 normalization bytes and 16384 output bytes.
The boundary test measures full control-byte escaping and maximum safe-integer
revision envelopes. Known outcomes settle this conservative vector once inside
`Consent.publish`; unknown owner/transaction outcomes retain liability.

## Reserved metadata and activation refinements

Legacy worker gets, commits and scan-after keys reject `host.validity.*`.
`Collection.scan_visible/4` filters those keys from validated metadata before
selecting values, under one existing native collection lock. Continuations name
actual public records only; an all-private collection returns an empty public
page. Internal operator `Collection.execute/4` remains raw and unchanged.

Status retains native aggregate counts but reduces migration/checkpoint control
metadata to its ID and complete control-metadata digest. It discloses neither
private continuation keys nor import plans. A complete projected action reply
must still fit 16384 bytes; it never truncates a value or returns an undisclosed
private continuation.

The approved pure Activation refinement adds `draft(project_sha, activation,
base_catalog)`. This produces review-only catalog/source/digest data before a
grant exists, breaking the identity/policy setup cycle without a fabricated
policy or prepared identity. Strict `derive/2` still validates the saved policy
and exact artifact/routes before delegating. Optional `main_timeout_ms` is an
explicit 1000..100000-ms value, included in the activation digest and returned
overlay data. Absence preserves previous behavior; no runtime is clamped or
modified by these pure functions. The parent owns actual fresh/resume overlay
application after the unchanged base configuration fingerprint.

## Reproducible focused checks and first outcomes

All runtime checks use the unique private source/build tree
`/tmp/ipse-managed-sdk-20261026-01/{project,build}` and a private copy of the
existing helper SHA
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
Dependency BEAMs were copied from the prior complete component build; existing
source dependencies remained read-only. No shared build path or helper was
modified. The initial non-escalated Mix attempt failed at its local TCP lock
(`:eperm`); authorized isolated execution then compiled normally.

| Log in that private directory | Actual outcome |
| --- | --- |
| `compile.log` | Full private application, 125 files, strict compile passed |
| `tests-first.log` | 17/24; managed execution context and read-outer denial binding were incomplete |
| `debug-one.log` | Synthetic-only diagnostic isolated the missing `:parent` context; not an accepted test result |
| `tests-one-repaired.log` | Actual managed publication and saved replay passed after context repair |
| `tests-second.log` | 24/24 after context and read-outer denial-binding repair |
| `tests-third.log` | 38/38, including expanded binding tamper controls and legacy Session/actions/admission regressions |
| `tests-final.log` | 39/39, 15.5 seconds, seed 20261026; explicit SDK-1/2 capability controls included |
| `tests-status-final.log` | 40/40, 17.9 seconds, seed 20261026; final private-plan/status regression included |
| `tests-checkpoint.log` | 40/40, 17.9 seconds, seed 20261026; foreign-shard fixture made deterministic |
| `compile-status-final.log` | Final private strict application compile, 125 files |
| `compile118-final.log` | Eleven affected/prerequisite modules, Elixir 1.18.5, empty diagnostics; host OTP 29 |
| `format118-status-final.log` | Thirteen owned code/test files match Elixir 1.18.5 formatting |

Subsequent command-target review found that the final 40-test command also named
nonexistent `test/ipse/extension/actions_test.exs` and
`test/ipse/extension/semantic_admission_test.exs`. Mix ignored those paths. The
reported **40 actual passing cases remain valid**, including real legacy/managed
Session action and protected-admission behavior, but no standalone suites at
those two paths ran. A separate exact-file run then executed
`mixed_actions_test.exs`, `semantic_consent_test.exs`,
`semantic_consent_v2_test.exs` and `mode_test.exs`: **30 passed**, 0.6 seconds,
seed 20261026, in the same private graph. Its log is
`actual-policy-regressions.log`. Keep that later result separate from the original
40 rather than inventing coverage for an ignored path.

Final focused tests cover actual independent-worker publication, exact outer and
inner replay bindings, normalization/version tampering, protected source proofs,
one settlement, deliberate conflict, pre-entry and in-worker revocation,
ambiguous reviewed mappings, read-only outer ceilings, ordinary-write refusal,
paged SDK-2 output, inert legacy resume, interrupted unknown work, owner loss
paused after the durable publishing receipt, and unrelated/stale/spoofed Session
proof queries. Native collection fixtures exercise private-key exclusion and
actual last-public-key/empty-page behavior. Existing legacy collection/action/
admission suites remain included.

The whole developer collection chapter was reconciled around these live owners,
legacy/managed distinctions and verification. The complete operator extensions
and developer extensions chapters were reviewed; the operator protected-access
paragraph was updated without inventing setup procedures. Documentation links,
current formatter, diff whitespace and final compatibility results are recorded
with this handoff. No dependency was added; JSON/schema work reuses Jason/Ipse.

## Remaining integration and trust limits

This checkpoint does **not** supply live managed read eligibility, protected
ReadView witnesses, every-dispatch retraction, assistant/summary taint propagation,
source-answer eligibility, or fresh/resume activation. Normalization's stored
`current` label is historical metadata, never freshness authority. A worker's raw
collection read is not a current-memory projection. Operator retention/acceptance,
correction and deletion need separately typed host journeys.

No model/account calls, downloads, private qualification inputs, native rebuild,
PTY test, full suite, installed-runtime check, OTP-27 execution or macOS claim
belongs to these focused checks. Same-user coherent journal rewrites remain
outside the cooperative trusted-host integrity model. The parent owns the
combined baseline and independent audit before any broader acceptance claim.

## Tested source identity

All fourteen files below match the final private source snapshot byte for byte.
The Normalizer is a parent-owned prerequisite, included here only to pin the
actual tested interpreter. Other unchanged source/dependencies belong to the
private complete graph, not an inferred installed release.

| File | SHA-256 |
| --- | --- |
| `lib/ipse/extension/actions.ex` | `0256e89297b42b7693c431b09ae0ed280295786f77b39a9210efa11656cdf153` |
| `lib/ipse/extension/activation.ex` | `88cde3bda572f63d14d6be2fac1059caa14a7f2ff131f24d8989d73c31992f0b` |
| `lib/ipse/extension/catalog.ex` | `7cc633542836421c5ecae4e2f2224db295e28af68713f18da8a353c822905584` |
| `lib/ipse/extension/collection.ex` | `d4e6308af1202e5e16b6a21d809f4edd651fa169b145be192030eb897e8ba567` |
| `lib/ipse/extension/collection_call.ex` | `ce6a738b21e413036566ce97c684a0adaeaeb2bc2a14e883c7859ad5afc7d547` |
| `lib/ipse/extension/host.ex` | `77bc84f4551f40228e480ca0a46d4ce9dd418e3cc71973cb35a873550bbe98c7` |
| `lib/ipse/extension/managed_collection_call.ex` | `79ecc940844b77eae44fc61a701fa2aa49876273cf55a80d01a18c66f1b536a3` |
| `lib/ipse/extension/semantic_admission.ex` | `2bc0382570a437b28bc7c4b9ada57d8b3a0dc2aea1b2b4f9f1b2857bd0564819` |
| `lib/ipse/session.ex` | `66dbf75e58b859aabca877cbef7d2df24f4590f34cf624f467820066513c9f10` |
| `lib/ipse/session/invocation.ex` | `af106860f56ee693a3550243c36338d4da5ff352cbaaab058b624b731983b8ed` |
| `test/ipse/extension/activation_test.exs` | `d3b6ea371f74920fb4ff8cd7a4907e473b73ee708ee0dd5e30d73ac914dcd352` |
| `test/ipse/extension/managed_collection_call_test.exs` | `f189cb58a6c624d37265c2a4e3d3b9ffcea0ee47621d1b1b60ae023425452c6d` |
| `test/ipse/extension/managed_collection_call_session_test.exs` | `5ad7b46d5f3551955066e649c4b9bed6fefcce52156a1944a331668618de2a24` |
| `lib/ipse/extension/collection/normalizer.ex` | `4eff99e231e64c0f0f9254abe0c6118126bf5d4781d6b816bf7922e69ecda4b6` |
