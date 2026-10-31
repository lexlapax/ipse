# Native reviewed forgetting through the standalone owner

Dated **2026-10-28**, branch `codex/p30-p31`, continuing the
[typed Core component](../2026-10-28-managed-turnover/index.md).
This is focused available-host diagnostic evidence, not P31C1a/E completion,
production admission, installed qualification or annual-turnover acceptance.
The [plan](../../plan.md) owns milestone status and the
[operator manual](../../operator/knowledge-permissions.md#forget-a-selected-native-note)
owns usage.

## Owned management boundary

`ipse knowledge forget NOTE_KEY` selects the actual existing project binding,
derives its knowledge namespace, reads the existing protected management epoch,
and authenticates the selected signed literal against the installed native
recipe. It starts no model or extension worker. Capture permission may be
revoked or expired, and original-source availability/TTL is not a deletion
prerequisite. Normal execution/enclosing ceilings and explicit effect denial
still apply. Historical recipes not recognized by the current selected bundle
refuse rather than being silently adopted.

The standalone caller establishes an owned Resources scope, a private original
management journal and retained ownership lock. It reserves terminal journal
space before review. Complete native review facts bind the actual project,
namespace, management epoch/fingerprint, job/client/journal nonces, exact target,
recipe, root, revision and requested suppression. The same file-effect process
retains the volatile Review permit throughout preview, native review and Core.
All project/control/collection locks are released during terminal input.

After exact confirmation, the owner syncs `managed_lifecycle_intent` before
entering the current Identity publication callback. New
`Consent.forget_deferred/8` validates the same-owner live review, current exact
management epoch/fingerprint, duplicate ID, quarantine/capacity and finite
reservation. It permits exactly one `collection.forget`, no headless admission,
zero model/download/cost dimensions, at most 64 KiB input and 16 KiB output.
It persists `publishing` before the short Core callback. This is separate from
the read-only Consent callback and automatic capture policy.

The host-only normalizer consumes the actual permit inside the Core transaction
after rechecking the exact signed target. It deletes the literal/live row and
retains signed lineage suppression/retirement atomically with an advanced import
floor. The caller captures actual normalized request/receipt sizing inside that
same owner, using the shared managed-publication accounting calculation; output
retains its conservative ceiling. It verifies the returned Core binding and
actual consumed native-review hash. Only successful Identity finalization and
release permit deferred Consent settlement. The owner journals the terminal
storage result, checks Writer close, retained-lock release and Resources cleanup
before reporting success. Interrupted/unknown results never replay.

`knowledge operation JOURNAL_ID` performs bounded original-journal inspection
in the actual matching project and reports historical journal/current control
status. The command changes neither journal nor ledger and checks no current
note eligibility. It never settles or reconciles an uncertain operation.

The original Session, shared evidence and management review journal remain;
the latter retains the confirmed target facts. This is selected-derivative
suppression, not erasure of all copies.

## Review findings and repairs

Independent read-only review found no concrete defect in the new Consent/Review
reservation state machine. The subsequent CLI review found two integration gaps:
normal mode/deny ceilings were missing and cleanup return values were ignored.
The caller now uses canonical Mode capture/ordinary mutation checks and
downgrades failed Writer/lock cleanup to unknown.

The first actual CLI journey then refused before review because the initial
approval-origin check compared an atom with Config.runtime's canonical string.
The [failed run 46775](managed-forget/logs/sol-forget-cli-native-46775.log) is
retained, not counted as a pass. The gate now reads the canonical Mode value.
No effect was admitted in that failed forget attempt.

## Focused verification

Tests ran in `_build/operator-assertion-sol`, `MIX_ENV=test`, with the retained
private available-host helper/profile already identified by the
[capacity provenance](capacity-available-host.md). Production admission was
unchanged. All terminal statements, sources and homes were synthetic.

| Run | Scope and result |
| --- | --- |
| [46768](managed-forget/logs/sol-consent-management-46768.log) | 33 passed, 6.4 seconds: existing Consent/Review states plus five actual native-terminal management controls for revoked/expired capture, stale epoch, forbidden effects and failure after consumed review |
| [46774](managed-forget/logs/sol-forget-cli-compile-46774.log) | Initial CLI integration compiled with warnings treated as errors |
| [46775](managed-forget/logs/sol-forget-cli-native-46775.log) | Retained failed CLI run; origin representation mismatch refused before review |
| [46776](managed-forget/logs/sol-forget-cli-native-46776.log) | 1 passed, 5 excluded, 12.7 seconds: actual native enable/capture/revoke/forget, Core deletion, signed receipt, measured settlement, original Session unchanged, repeated absent-target attempt changes no collection root and makes no inference |
| [46777](managed-forget/logs/sol-management-mode-46777.log) | 1 passed: read-only/planning/draft/enclosing ceilings, explicit deny, headless and noninteractive approval origin refuse before creating a home |
| [46778](managed-forget/logs/sol-forget-operation-native-46778.log) | 1 passed, 5 excluded, 12.0 seconds: complete native journey plus operation inspection leaves management journal bytes and protected control unchanged; changed source compiled with warnings treated as errors |

The [artifact manifest](managed-forget/manifest.json) binds the exact final
source/test snapshots from the executed graph and retained logs by size/SHA-256.
These snapshots are historical evidence, not another editable implementation.
Source changes in other concurrent sections are not qualified by these tests.

No aggregate suite, installed binary journey, paid/live inference, new kernel
admission, automatic recall, proposal acceptance, typed correction/pin/duration,
actual annual turnover or release ran for this section. Whole-manual editorial
acceptance, final adversarial review and full source/package verification remain
open. Direct Core cancellation/changed-facts controls remain separately scoped
in the preceding component record; they are not presented as a complete CLI
cancellation/owner-loss matrix.

## Added exact production-profile integration

After the [narrow native qualification](../2026-10-28-native-profile/index.md),
root copied the verified host runtime/resources into a fresh isolated graph at
`/tmp/ipse-management-production-20261028-46779`. Only the Runner BEAM and its
actual private helper were replaced with the production-source profile build:

- Helper `6407e40e96498029ff7e13d96215a263812732aad1979b4c3e5f4b867b5a4d56`.
- Runner `d1236876607bec78f93b3d18a3b293b4fea21a8f36e2027f3e086c153333f0b5`.

The [runtime/resource manifest](managed-forget/production-runtime.json) binds
the isolated files; neither the earlier diagnostic graph nor shared `priv`
was overwritten. All fixture home, state and workspace locations were on the
qualified actual tmpfs. No ambient helper override was used.

The [first launcher](managed-forget/logs/production-launcher-46779.log) failed
before any test or native operation because Elixir's `-pa` consumed one expanded
path and interpreted the next as a source filename. The corrected bootstrap
adds the complete path list through `:code.add_paths/1`; it changes no product
behavior. The [actual native journey](managed-forget/logs/production-native-46779.log)
then passed **1 test, 5 excluded, 12.6 seconds**, seed 122574. It covers the same
enable/capture/revoke/forget/settlement/inert-inspection assertions under the
qualified production-source helper.

This adds actual native management integration on that exact tmpfs profile.
It does not reclassify the old Btrfs diagnostics, qualify Btrfs on the newer
kernel, establish installed-package acceptance or supply final whole-source
regression. The supported location/volatility limits remain explicit.

## Added CLI cancellation and stale-epoch controls

The same isolated production-profile graph ran two further scenarios in
[46782](managed-forget/logs/production-refusals-46782.log): **1/2 passed,
6excluded,24.9s**. The stale management-epoch case passed: a change while the
native review was displayed prevented mutation, retained a refused intent/result
and preserved the target. Cancellation failed earlier, while displaying the
preceding disable review; it did not reach the forget review. Another agent had
a native PTY fixture running concurrently. Terminal contention is a plausible
cause, not a demonstrated product diagnosis.

After that other fixture closed, only cancellation was rerun, serialized, in
[46783](managed-forget/logs/production-cancel-46783.log): **1 passed,7excluded,
12.4s**, seed48529. Cancelling the actual forget review left the target and
original Session unchanged, wrote a refused result without a mutation intent,
and allowed inert management inspection. These are one passed stale-epoch case
and one passed cancellation rerun, not a clean two-test aggregate pass. The final
expanded fixture snapshot is retained separately with the later
[retention CLI cohort](retention-cli.md); it includes additional retention cases
and is not represented as a byte-exact snapshot of these earlier two runs.
