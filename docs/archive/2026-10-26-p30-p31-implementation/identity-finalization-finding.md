# Existing V2 settlement before final Identity release

Recorded 2026-10-27. **Accepted P2; independently closed for the exact repaired V2
graph below.** Original before evidence is historical and remains immutable. Current
accounting guidance belongs in [Accounting](../../developer/accounting.md) and
[the Collection SDK](../../developer/collection-sdk.md). This follows the
[managed actual-accounting component](managed-actual-accounting.md); that earlier
independent pass remains immutable and explicitly excluded final outer Identity
failure injection.

## Demonstrated boundary

The existing V2 `ManagedCollectionCall` calls `Consent.publish` from inside
`ProjectIdentity.with_binding`. Consent saves measured actual usage before that
callback returns; Identity checks/releases its outer native owner afterward.
Failure at the latter boundary makes the action unknown after the smaller actual
has already been durably settled.

An independent real SDK2/Session/native test closed the retained native port
immediately after return tracing observed `Consent.publish/5` return a settled
receipt. All five finite attempts showed actual Collection generation 1,
Session `done:error`, a journaled unknown managed outcome and a durable **settled
3,407 input bytes against a 16,130-byte reservation**. Inert resume performs no
worker/effect replay and preserves that row. The positive control reports success
and the same measured debit. Other resource dimensions remain conservative.

This disproves a blanket statement that every outer native/cleanup unknown keeps
the full reservation. It does not demonstrate unmeasured work or an exceeded
reservation: the Collection effect actually completed. The native port kill and
return tracing are privileged fault instrumentation, not a worker escape.

The first test summary was 1/6 because the auditor incorrectly expected clean
shutdown acknowledgment after deliberately killing the native lane. Every finding
assertion had already passed. The unchanged first driver/log and all fact JSONs
are preserved. A cleanup-only companion expects `cleanup_unconfirmed`, asserts the
Session is dead and reaches the existing inert-resume assertions: **6/6**. This
is a successful characterization of the bad state, not a repaired contract test.
No further before repetitions are needed.

## Proposed correction and remaining uncertainty

Root accepted deferred Consent publication for V2 and V3: retain durable publishing
and full reservation across Collection, required postproof and Identity activation,
check and release. Only checked outer Identity success may request a separate
receipt-preserving known settlement. Before that point, failures leave actual
null/full reservation. Private handoff data must retain exact operation, request,
reservation, measurement and receipt binding; no worker-supplied cost or authority.
Settlement of already-proven work must remain possible after revocation without
starting a new effect. Owner loss must prevent late settlement. Resume never
replays publication or automatically runs deferred completion.

Final Consent settlement acknowledgment loss is different: the actual/receipt may
already be durable. Inspection must distinguish that state; documentation cannot
promise that every persistent unknown outcome retains full after every possible
settlement acknowledgment loss. Charging V3 full only would not correct the
existing V2 window. The existing known-actual settlement API discards the receipt
and is insufficient unchanged.

After repair, preserve the original bad-state probe and report its changed result
honestly. Because the traced function becomes deferred publication, a closure
companion needs that explicitly recorded seam adaptation and full
publishing-or-unknown/actual-null predicates. No repaired graph is approved here.

## Exact before graph and evidence

Owner graph `/tmp/ipse-managed-actual-accounting-20261027-06`, committed component
`d79598d2e094a1bfe727cfad46cd78e1b1decee1`; independent copy
`/tmp/ipse-independent-identity-settlement-20261027`.

All 2,338 manifest-admitted source/runtime files and exact set membership matched
owner/copy before and after execution. Manifest SHA-256:
`63bd5e53b0edcd53daf0f26df43656293f8261c645d766906cf0e77195adddcf`.
ManagedCall source `cb9a03f3...`, Identity `66ebd609...`, Consent `3803b34c...` and
the actual private d84 helper are fully hashed with matching BEAMs in the report.
No production recompilation or overlay, public source/index/helper mutation,
model/network/gold or PTY operation occurred. Shared108c was not executed/rebuilt.

Complete immutable before source/runtime/probes, synthetic journal/control facts,
raw first/corrected logs, call-order proof, helper bindings and replay instructions:

`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-identity-finalization-before`

| Evidence | SHA-256 |
| --- | --- |
| `REPORT.md` | `2ee4ec4862bc1a65aff1000a8cceab6f99895f7f04ef959e3ec50eb171116902` |
| `files.sha256` | `749890468f51c05bc8cfc78aa1df1f2a87e190a09d1eb93740833c1900f45e15` |
| `provenance.json` | `b974dbf3196e9b7c674ce3f06f25697f73246f81e0ad99e1f9129fb2061d92b5` |
| `preservation-receipt.json` | `ffe0e7c6339e92df57d624fad4fc88a05ea74b144459388ccb5c56e8c603e49d` |

All 2,415 payloads are owner-only data with private-helper alias bytes materialized,
byte-checked and files/directories fsynced. Reproduce only in a new writable copy.
No first-domain activation, SDKv3 postproof, Consent final-settlement rename/ACK
loss, actual provider or whole-milestone audit is claimed.

## Independent repair closure

The independent repaired copy of
`/tmp/ipse-managed-settlement-repair-20261027-01` bound all **2,339** regular
source/runtime rows before/after, exact membership and SHA in both owner and copy.
Manifest SHA-256:
`57c45e85f0178cdd15dff8afa50fbfb87d21607baa299374609bc95062594492`.
ManagedCall source is `1757b4264086895baacdefca68e83b685caa864a3a74f699050aa170b00b00e9`,
executed BEAM `4aa6bb7585c006d79ae883d91fe1d2e67e41d4c129e92df1a68cad990d211c13`.
The full report binds Consent, Resources, unchanged Identity, legacy Collection
and private d84 helper. The graph excludes later V3/Pages/Normalizer integration.

The old bad-state predicates, with an explicitly adapted trace seam at
`publish_deferred`'s provisional return, produced **1/3**: the positive passed;
both fault cases failed exactly at `status == settled`, seeing publishing with
null actual instead. The separate closure companion produced **3/3**, seed
20261208, 6.5 seconds. Both actual native fault cases retained full publishing
16,130 bytes, null actual/receipt, C generation one and unknown journal outcome.
The provisional packet measured less than the reserve; the exact packet amount
was not logged. Cleanup-unconfirmed, Session death and inert resume were checked.
The known-success positive still logs actual 3,407/reserved 16,130. No further
repeats or unchanged broad-suite rerun occurred.

The original before driver is retained verbatim. Trace-function/return-shape,
finite case-count and diagnostic-output relocation changes are recorded apart
from the closure's explicit expected-state changes. The first private preparation
script's ambiguous comparison spacing caused a MatchError, followed by a missing
closure-loader diagnostic; those raw failures remain visible. The shell wrongly
continued dependent commands, so the already-created characterization ran while
the first closure attempt ran no tests. Only that private preparation assertion
was corrected before the single actual companion run. Production inputs were
unchanged throughout. No authentication workaround or provider/model call occurred.

Immutable repaired evidence, **2,436 payloads**, owner-only, bytes verified with
materialized admitted private-helper alias and files/directories fsynced:

`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-identity-finalization-after`

| Evidence | SHA-256 |
| --- | --- |
| `REPORT.md` | `a4907937a5e7e6836676d9faa0f0c77758964e716cfb77e9cc6d63c74a265d44` |
| `files.sha256` | `b9c9f99e7b231d7126e68258efb4709ec90b6ef159c2abd5b6968475a59d0d37` |
| `provenance.json` | `82a2d214123feb76de717f2568440ac7328054dcc7b60ab26040c545485ddaa3` |
| `preservation-receipt.json` | `2c2a4a2f05476bde750f60a62defd9220c9fa10d7cf8d01adde84ee315aee79e` |

Whole Accounting and Collection SDK chapters were reread; the final manual
snapshots and 554-file/4,823-link/zero-error docs check are preserved. Root fixed
the stale managed API name and clarified nested Consent lock versus outer native
owner release. The final-settlement acknowledgment uncertainty remains explicit.
This closes the demonstrated pre-settlement Identity failure window only. No
final Consent settlement ACK-loss, SDKv3 postproof, first-domain activation,
whole implementation or annual-capacity acceptance is claimed.
