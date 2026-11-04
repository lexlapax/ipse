# Pending assessment current-use qualification — 2026-11-04

Two separately recorded synthetic controls now pass: settled advice is withheld
after grant revocation at output release, and a fresh day-eight grant cannot
release a proposal past its own signed seven-day deadline. They use the actual
main-tool-created pending record, bundled protected assessment path and native
review. No runtime module, permission, source rule, deadline or service-identity
guard changed. These are local protocol controls, not model quality, a production
consumer selection, installed package qualification or P30 completion.

## Own signed deadline: one fresh passing case

The corrected v2 cohort ran **one selected case, one excluded, zero failures in
15.5 seconds**, exit zero. Its source/toolchain/private runtime/original runtime
and exact runtime pathset postchecks were unchanged; the native input lock had
no holder afterward. The already-passed output-revocation case was excluded and
was not repeated.

At synthetic day zero the real capture tool created a pending proposal. The
stored signed normalization bound first admission and a deadline exactly seven
days later. At synthetic day eight a new VM obtained a fresh native-reviewed
experiment grant whose expiry was still in the future. The original signed
record and source journal bytes/inode were unchanged. A pure diagnostic
comparison admitted the dependency just before the deadline and refused it at
day eight; that comparison itself granted no authority.

The actual consumer then requested the purpose-specific
`decision_shadow_pending_v1` read. That real action returned exactly
`collection_source_refused`. It created no v7 managed-read receipt, decision or
Collection-mutation action, decision-provider request or model-call reservation.
The new grant remained unchanged. The full Collection snapshot and original
pending record were unchanged. Saved restoration and same-ID idle reopen passed,
with an unchanged provider-call list, and the source hash/inode still matched.
This checks an explicit synthetic process/stdio wall clock, not eight days of
real elapsed time or a monotonic publication-boundary race.

The first attempt remains a failure: after successful day-zero capture and pure
signed-deadline comparisons, its day-eight child reused a persisted service alias
for a different loopback port and correctly received a service identity conflict
before assessment. That attempt supplies no deadline pass. V2 uses the distinct
`fixture_day8` alias consistently in the profile and registry, with the new route
explicitly reviewed. No prior state, grant or unknown operation was replayed.

Final test-only patch SHA-256:
`1390c660874dbe5a01b2987d6da1977d73feb1e23f10d75dcaa5ad811ea54438`.
The three-line service-identity fixture delta is
`d5c7165e3a2773618121f6eeff019824ab5ffd8680fdd6cc151f8359ff373d9a`.
Passing result SHA-256:
`04b85ab34e530a1bff7a9ef640b8990bcd89129b1f05bd3a4b26be74f708d46b`.
Status SHA-256:
`3f7b49c4129c93a808c91d5ae2e1ef914873f400d6a7218242e8d018eb1f48ad`.
Retained private outer log SHA-256:
`afd4b91c735c11824eecc279ecf387fcefa2b7f0c039f1c828eef02cb9bef715`.

## Settled output withheld: independent earlier passing case

The separate first-cohort output-revocation case passed. After one actual
synthetic decision had settled, revocation removed its grant before output
release. Its raw assessed value received a withdrawn managed release result;
no assessed value reached a later main-model request or CLI result, and no
consumer Collection mutation occurred. Its one-call actual charge remained.
Saved restoration, idle reopen and unchanged provider-call list passed. The case
did not separately compare action-intent counts across reopen. Its original
passing result and first cohort's failing deadline case remain separately
recorded; no successful effect was repeated for bookkeeping.

## Integration and remaining scope

The intended focused command after integrating the two test files is:

```sh
mix test test/extensions/knowledge/pending_assessment_current_use_test.exs
```

Review the operator and developer manuals as whole documents before promoting the
increment. The operator assessment task should explain that withholding advice
after an already-settled call preserves real usage/charge, while an unknown call
keeps its reservation. The developer lifecycle should distinguish experiment
grant expiry from the proposal's own signed deadline and distinguish settlement
from final current-use output release. Existing source/category/provider/approval
and unknown/no-replay limits remain unchanged.

Simultaneous reviewed reservations, current integrated/installed qualification
and frozen matched consumer quality experiments remain independent gates. The
first later simultaneous fixture failed after releasing its two consumers; its
reserved unknown operation is preserved and supplies no passing race claim.
Unavailable engines remain unverified; synthetic advice supplies no quality score.
