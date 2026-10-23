# P26 internal adversarial review, 2026-10-19

Historical investigation record, not an external acceptance or completion verdict.
Current instructions are in the [memory user manual](../../operator/memory.md)
and [developer training chapter](../2026-10-22-before-structural-consolidation/docs/developer/memory.md). See the
[remediation record](index.md) for subsequent verification and disposition.

## Intent and frozen scope

P26 must keep model reads within expiry and dependency visibility, preserve stored
values in backups, restore recoverable notes faithfully, retain permanent
suppression and separately approved CAS writes, reject incompatible configured
scopes, and handle missing collection without crashing or reserving an ID.
The user explicitly chose backups that include expired notes with unchanged expiry.

Three read-only review sessions examined `d300b68dcebf0b8fbc6e596d075e324253f2180d`
plus the initial remediation diff, SHA-256
`aa82f50dfa5e7669e102c7849997a776d924937439d0568a62ca118b4d954642`.
They read the same intent, rubric and code-quality instructions, the changed source
and tests, manuals, prior review, and surrounding host contracts. They ran no
tests, builds or model calls and changed no files. The root retained implementation
and verification ownership. The existing full suite remained live during review;
source changes waited for its terminal result.

## Reviewers

| Session | Requested model | Findings |
| --- | --- | --- |
| `p26_adversarial_a` | `gpt-6-astra` | Legacy dependency visibility; optional working-memory scope binding |
| `p26_adversarial_b` | `gpt-6.1-sol` | Legacy dependency visibility; working-memory scope issue noted as secondary |
| `p26_adversarial_c` | `gpt-6-sol` | Legacy dependency visibility; legacy export/import dead end |

The host exposed requested choices but no independently verified serving-model or
fallback metadata. These are independent review sessions, not proof of distinct
resolved models. All reviewers returned `ISSUES` with source-reachable paths and
unexecuted probe designs.

## Act on

1. **Legacy parents do not block derivatives.** All three reviewers found that
   `Memory.exclude_derivatives/2` seeds exclusion from expiry and suppression,
   while `Records.visible?/2` also rejects unmigrated version-one records.
   A version-two child of a legacy parent remains readable. Reuse the canonical
   eligibility predicate, test transitive exclusion and migration recovery, and
   check actual provider-received messages through a public Session.
2. **Legacy backups have no public restore path.** Reviewer C found that export
   preserves version-one active values but import refuses them. Migration can
   operate only on a record already in the destination. Reproduce the fresh-store
   dead end, then allow validated approved import without making legacy content
   visible before explicit migration. Preserve expiry and suppression precedence.
3. **Optional working-memory bindings skip admission comparison.** Reviewer A,
   independently noted by B, traced an operator-owned working-memory instance
   with a project-only binding through admission to later State refusal.
   Apply selected-scope validation to both memory artifacts. Keep unbound working
   memory valid and persistent memory's required binding intact. Exercise initial
   admission and prepared-entry revalidation with positive controls.
4. **Missing collection with a cause returns a different outcome.** Root source
   inspection found that `collect` with a missing target and `cause_source` exits
   through `not_a_direct_derivative`, bypassing the repaired `not_found` branch.
   The manual promises `not_found` for missing collection. Test both argument
   forms and return the missing-target outcome before inspecting dependency cause.

These are reachable domain cases with cheap local regressions. Root accepts them
for reproduction and repair before external review. Source inspection alone does
not close them.

## Consider, noted and dismissed

No additional findings require a product decision. Reviewer B treated the optional
working binding as secondary because normal user configuration leaves it unbound.
Root accepts it because the supported operator configuration already admits that
binding and the same small scope check should cover both artifacts. No reviewer
proposed a verified additional authority, CAS or output-bound defect. An absence
of findings is not a runtime guarantee.

## Agreement and remaining gate

Legacy dependency visibility has three-session agreement. The working binding
issue has two-session agreement. Legacy restore came from one reviewer and has
an explicit source path to verify. Root added the missing-target/cause case.
The initial four external findings appear repaired on source inspection, but
these additional cases need failing-before proof, fixes and fresh checks.
External review must target the corrected, verified snapshot rather than this
earlier diff. P26 completion and P27 continuation remain pending.

## Reproduction and second review

The root reproduced all four accepted cases as five failing regressions: legacy
descendant handler visibility, actual fixture-model disclosure, legacy restore,
working-memory admission, and missing collection with a cause. The run passed
17 of 22 tests in 10.9 seconds. After repair, all 29 focused
memory/Session/binding/scan tests passed in 12.3 seconds.

The repairs seed the dependency closure with `Records.visible?/2`, preserve valid
legacy active imports until explicit migration, compare optional working-memory
bindings while retaining unbound activation, and check missing collection before
dependency-cause lookup. Tests retain suppression priority, immutable imported
expiry, transitive recovery after migration, compatible binding controls and
unchanged record slots on failed collection.

Fresh sessions `p26_adversarial_r2_a`, `_b` and `_c` reviewed the same complete
scope at the same HEAD plus corrected diff SHA-256
`b86ef9e0c2b5c9f7ed2e4e671a60ad8ec6521d9b88e47d5a660647b798258b99`.
Requested models matched the first panel; resolved serving identities remain
unverified. All three verified the frozen identities and performed source-only
inspection. A returned `PASS`; B and C returned `ISSUES`.

Root judgment on the additional findings:

| Finding | Reviewer | Judgment and next evidence |
| --- | --- | --- |
| A prepared renewal can wait for approval until after target expiry | B | Act on reproduction and repair. The user explicitly chose rejection after expiry. The approved state proposal currently has CAS but no clock precondition. No runtime proof yet. |
| A newer active import can replace an unmigrated target without `migrate` | C | Act on reproduction and repair. Existing approval does not justify bypassing the documented migration gate. |
| Missing collection with a nonzero expected revision returns conflict | C | Retain the revision precondition; clarify the manual and test it. A stale requested revision should not override the existing conflict contract. This is a documentation precision issue, not a write or crash defect. |

The second panel's severity labels do not establish security impact. Both active
import and renewal still require separate approval. Root accepts the reachable
lifecycle concerns without treating them as an approval bypass. The refreshed
full baseline remains in progress at this point. No external prompt or completion
claim is ready.

The user chose rejection after expiry. Root compared two complete architectural
candidates and an independent cross-judge, then selected the generic locked
deadline described in the [design and proof record](expiry-write-design.md).
Both delayed renewals and the active-import migration bypass reproduced before
repair. The corrected State/memory/Session/binding/scan run now passes 41 tests,
including live controls and actual failed-receipt idle recovery. This supersedes
the earlier source-only uncertainty, without closing refreshed full verification
or external acceptance.

## Third review of the corrected host boundary

Fresh sessions `p26_adversarial_r3_a`, `_b` and `_c` examined HEAD `d300b68`
plus final tracked diff SHA-256
`7e3a139f0ec194287e56e8c875856a7fb1b0af4dda1896fdcd5b93603c9fb9b2`.
All independently verified the frozen and current tracked diff identities,
read the same full scope and surrounding host/recovery paths, and returned
`PASS` with no findings. Requested model choices matched the preceding panels;
serving-model identities remain unavailable. No source, test or runtime changes
occurred during review, and reviewers ran no builds, tests, model calls or services.

The panel traced the existing-target deadline through exact approval, State lock,
post-sync publication check, known failed receipt and idle recovery. It also
rechecked visibility, legacy restoration/migration, suppression, scope admission
and missing collection. Root accepts the source-review verdict. A forced delay
inside temporary staging remains unexercised and is explicitly distinguished from
the executed approval-boundary proofs. Refreshed full/native/package verification
and external acceptance remain separate gates.
