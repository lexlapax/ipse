# Reclaim accepted decisions after their actual signed deadline

Dated **2026-11-01**. Source implementation on base `d688302`, following
[reviewed accepted forgetting](accepted-decision-forget-20261101.md) and its
[post-effect loss control](accepted-decision-forget-loss-20261101.md).
Historical author evidence; [the plan](../../plan.md) owns acceptance and
[the operator procedure](../../operator/knowledge-permissions.md#reclaim-an-expired-native-note)
owns current usage. This does not complete sustainable turnover, P31 or P30.

## Reproduced gap and repair

An accepted decision stores a signed finite deadline, but `knowledge expire`
previously admitted only literal/history representations. Genuine registered
capture, public native acceptance, disabled capture and an actually elapsed
15-second saved-policy bound reproduced a refused reclamation: **0/1 passed,
8 excluded, 27.7 s**, seed 791611, exit 2. The retained original log is
`/tmp/ipse-accepted-expiry-baseline-20261101.log`; its synthetic root is
`/tmp/ipse-native-knowledge-session-eeebff8c15a13866d3181e99df468b45`.
No uncertain operation was replayed; subsequent attempts used fresh roots.

The repair reuses existing Identity → management Consent → Collection ownership,
the private management journal, deferred settlement and measured accounting.
It adds no native protocol, storage encoding, dependency, worker operation or
global allowance. Accepted decisions remain distinct from literal records.

- `ObservedRead.with_managed_reducing_record/7` is the renamed host-private
  destructive target reader shared by forgetting and elapsed reclamation.
  It authenticates the signed type-3 row and same-root immutable link; ordinary
  literal reads, current-use reads and retention/replacement admission stay separate.
- `PendingAcceptance.expired_retained_decision_metadata?/2` supplies a pure closed
  metadata/deadline predicate. `ManagedLifecycle.prepare_accepted_expiry/3` builds
  the distinct `managed_accepted_decision_expiry` facts and one deletion. Neither
  helper establishes native authority or grants current use.
- `NormalizerV3.expire_accepted/3` shares the existing bounded expiry interpreter.
  Under the actual publication owner it reopens format, anchor, live row, target
  and immutable link, rederives exact facts and checks fresh host time. Null or
  unelapsed deadlines refuse. Public/live removal advances the destructive floor;
  original signed anchor clocks and the acceptance link remain unchanged.
- `Consent.expire_deferred/7` admits the explicit typed expiry packet, retains the
  same positive management epoch, finite reservation and zero-service limits,
  and accepts only the matching normalization receipt. Capture may be disabled;
  headless/service/retention/replacement authority is not widened.
- The public CLI selects the reducing reader and new fact/normalizer dispatch.
  It spends no new Review permit for the previously signed elapsed policy.
  Intent precedes publication; uncertainty remains inspectable without replay.

The original 32-read, five-sidecar, 6-KiB-value and 64-MiB bounds remain unchanged.
Finite ordinary, preference and current accepted deadlines can qualify; a saved
policy's earlier expiry can bound a persistent category at acceptance. This does
not implement later non-session accepted retention changes or replacement.

## Genuine journey and retained development failures

The opt-in accepted-expiry cases build isolated Knowledge artifacts and capture
through the registered Ollama adapter with synthetic HTTP responses. The trusted
fixture shortens the saved policy immediately before real native acceptance.
The actual accepted record must contain that deadline and the selected category.
It refuses reclamation before expiry with unchanged target/control, disables
capture, waits for actual wall time, temporarily withholds the original source
under its retained lock and invokes the public CLI. No runtime clock, native
review, source receipt or storage receipt is manufactured.

After success the target/live row must be absent; DomainAuth opens the unchanged
anchor clocks and original link. The separate pending peer and every original
Session journal remain unchanged. Exactly one expiry operation settles with
zero model/download/cost usage and matching intent/result. Operation inspection
reports settled/no replay. The subsequent duplicate-acceptance control retains
the unchanged link and exact post-expiry generation.

The first repair run reclaimed successfully but the enclosing pre-existing test
expected the old collection generation (**0/1, 8 excluded, 28.0 s**). Its repair
requires exactly one generation advance and unchanged link, then snapshots that
root before the duplicate attempt. The next combined expiry/recall/forget/loss
cohort passed **2 tests, 7 excluded, 87.4 s**, seed 791613.

Adding authenticated absence checks exposed the test observer's `{:ok, nil}`
result being classified by Identity as domain-unavailable after successful
reclamation (**0/1, 8 excluded, 28.4 s**). An initial correction mistakenly
changed the ordinary Collection response pattern (**0/1, 8 excluded, 14.5 s**).
The corrected observer wraps the entry in a non-nil map and unwraps it after
the checked owner closes. No runtime change was needed for either observer.
The strengthened ordinary journey passed **1 test, 8 excluded, 39.2 s**.
These failures remain in separate `/tmp/ipse-accepted-expiry-*.log` files.

The shared literal/history normalization, native expiry, pure accepted targets
and control-ledger cohort passed **61 tests, 73.7 s**, seed 791614. Control-ledger
syntax tests cover all three categories, invalid/persistent/future deadlines,
wrong target kinds, zero-service limits, duplicate admission and deferred settlement;
they do not authenticate Collection rows.

The final genuine category cohort passed **3 tests, 8 excluded, 116.1 s**, seed
791616, exit 0. It covers ordinary, preference and current decisions through
real native acceptance and actual elapsed deadlines, including the strengthened
authenticated anchor/live checks. The retained log is
`/tmp/ipse-accepted-expiry-categories-20261101.log`; synthetic roots are:

- `/tmp/ipse-native-knowledge-session-40c85e5b2702bbf49e29b4a141373a55`
- `/tmp/ipse-native-knowledge-session-a01b1110bc34d487668fc7b6f7478f4b`
- `/tmp/ipse-native-knowledge-session-cd1cab9df2e15f1f26f47b64654946cc`

Every native/PTY cohort ran serially. Builds started only after those test
handles were terminal; source behavior stayed fixed during each run.

The complete build passed **183 host files and three inert bundles**. Formatting,
strict compilation, CI action policy and the credential-free demo passed.
The final facts/control-ledger cohort passed **10 tests, 2.1 s**, seed 791618,
including accepted headless, wrong-operation and model/download refusal checks.
The original literal and historical expiry CLI journeys passed **2 tests,
21 excluded, 45.5 s**, seed 791617. The final accepted recall/forget/loss journey
passed **1 test, 10 excluded, 49.0 s**, seed 791619, after the category-aware
capture helper was finalized. Logs retain each command scope separately;
none is a new complete-suite aggregate.

The native helper remains
`5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.
Operator management and developer SDK/testing guidance were reconciled around
the complete expiry workflow, preserving separate retention, replacement,
current-use and uncertain-outcome rules. Documentation checks passed **1,010
Markdown files and 8,389 local links, zero errors**; pre-existing inaccessible
private-ledger directory warnings remain, without inspection or modification.

The post-run selected-input inventory is
`/tmp/ipse-accepted-expiry-inventory-20261101.json`, SHA-256
`5c7a7df5e3fdefeaae3445700eac057b5af01c41994e4574a67bc5f3ff8a5c67`.
It records 21 source/helper/build/dependency inputs, 18 command logs and
52 retained synthetic original/management journals and child logs from the
three final category roots and final recall root. This is not a pre-launch
freeze or a complete source/runtime inventory.

The available host reports Linux `7.2.11-arch1-1`; retained synthetic stores are
on tmpfs. This is source native-storage evidence, not OS shell confinement,
reboot durability, other filesystems, macOS or installed delivery.

No real model calls, model downloads or external review were used. Annual
turnover, general suppression compaction, complete installed lifecycle,
accepted non-session retention/replacement and full-source qualification remain
open. The last completed full-source aggregate remains **3,538 passed, 60 failed,
109 skipped, 112 excluded** at `e86b1b8`; focused passes do not replace it.
