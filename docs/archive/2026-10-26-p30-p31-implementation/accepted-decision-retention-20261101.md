# Native retention choices for immutable accepted decisions

Dated **2026-11-01**, author implementation on base `8c01345`. This extends
[accepted expiry](accepted-decision-expiry-20261101.md) through the existing
native reviewed management path. Historical source evidence; [the plan](../../plan.md)
owns milestone acceptance and [the operator manual](../../operator/knowledge-permissions.md#change-a-selected-native-notes-retention)
owns current usage. No milestone or installed acceptance is claimed.

## Preserve acceptance while changing retention

Accepted records and immutable links bind their original revision/operation.
Reusing literal retention's public same-value rewrite would break that identity.
The selected implementation keeps the accepted public record, revision, operation
and link unchanged, and updates only authenticated anchor/live metadata.

The original request still asserts the exact same public value/revision under
the held Collection owner. The specialized accepted-retention validator checks
its actual stored hash and admits only the existing bounded V3 metadata changes.
The existing native retention entry binds original/normalized hashes, live Review,
synced intent, retained Writer/management peer and final publication deadline.
Generic managed execution refuses the new receipt kind and does not gain this
metadata-only normalization rule. Accounting includes the original assertion and
actual metadata/receipt bytes conservatively; generic SDK accounting is unchanged.

`managed_accepted_decision_retention` facts and
`native_accepted_decision_retention` receipts stay distinct from literal and
forget/expiry forms. Signed choice capsules bind the unchanged target hash,
original lineage and actual confirmation time. Original clocks and publication
policy remain separate; an explicit pin/ordinary/duration choice supplies the
effective lifetime. Expired effective policies refuse further extension.

Current reads still authenticate the original accepted event, original committed
management journal, immutable link, original Session source and current policy.
Their version-6 acceptance reference can additionally carry a closed retention
witness: the authenticated choice hash, policy and confirmation time. Later use
recomputes and compares that witness from current signed pages. References without
it keep the original strict deadline/value relation; the record/link revision
equality remains. The witness is not a serialized permit or independent authority.

No native opcode or byte layout changes. The existing accepted live marker now
admits the existing pin category for note rows; pending/history combinations
remain refused. Earlier source decoders restricted to accepted categories 0..2
refuse these pins, and earlier reference parsers refuse the new witness.
Installed upgrade/downgrade compatibility remains unqualified. There are no new
dependencies or provider/service choices.

## Genuine native workflow

The opt-in `genuine_pending_accepted_retention` cases start with registered
synthetic-provider capture and actual public native acceptance for ordinary,
preference and current decisions. Each case requires:

- Public native pin; unchanged complete accepted record/link and original clocks.
- Fresh typed current recall through the registered adapter, retaining actual
  original-journal/source owners; unavailable source and altered event refuse.
- Cancelled automatic choice with unchanged state and accounting.
- Public automatic and one-day duration choices, based on actual confirmation.
- A separate native host call selecting a two-second duration through the same
  owned management entry, followed by an actual wait, refusal of an expired pin
  without changing control state, and public reclamation after capture disablement
  with the original source unavailable.
- One generation per committed effect, exact typed intent/settled accounting,
  zero model/download/cost usage for management, unchanged peer/original journals
  and subsequent duplicate acceptance refusal.

The short host call is not a CLI days-parser test; the separate public one-day
case tests that parser. These are automated native protocol/source controls,
not independent human use or real-model quality. Product limits are unchanged.
The expanded trusted fixture selects a finite 16-operation allowance for five
additional lifecycle effects and later refusal controls.

## Retained failures and corrections

All attempts use fresh synthetic roots; no unresolved operation was replayed.
Logs are separate `/tmp/ipse-accepted-retention-*-20261101.log` files.

- The first launcher had a misplaced `cond` expression and failed compilation.
  The corrected baseline failed **0/1, 11 excluded, 15.0 s**, seed 791620: public
  pin refused with `collection_observation_refused` before native review.
- The first implementation reached real review but refused before publication
  (**0/1, 11 excluded, 14.7 s**). Root generation remained 3 and the publishing
  liability/unconfirmed result remained intact. Return-only traces and a
  logging-only isolated-host normalizer overlay identified the live planner's
  accepted/pin combination restriction; these diagnostic runs do not qualify
  unmodified execution. The overlay and trace hook were removed afterward.
- The pure pin control also found the accepted live-row constructor's missing
  pin mapping (**4/5 passed**); both representations now use the same existing
  pin category. The corrected pure controls passed **5 tests, 0.1 s**.
- Pinning then preserved the record/link, but current recall refused
  (**0/1, 11 excluded, 17.1 s**). Read-only checks independently verified actual
  signed metadata, original management journal, source, current policy and
  dependency construction. The final coverage predicate still equated the
  effective deadline with the immutable recorded deadline. The explicit compact
  witness repairs that assumption while retaining the old mismatch refusal when
  no witness exists.
- A standalone malformed-witness coverage test failed **25/26** because its
  caller normally validates the dependency first. The accepted coverage helper
  now validates that closed reference itself; **26 tests passed, 2.7 s**.
- The first complete lifecycle reached the later duplicate check after capture
  had been disabled. The trusted fixture now restores its earlier active policy
  before continuing those existing acceptance controls.
- The first three-category run failed its later duplicate checks (**0/3,
  11 excluded, 88.9 s**), after the native lifecycle/recall checks passed.
  Read-only ledger inspection showed **8 actual operations, all settled, against
  its configured limit of 8**. The expanded fixture now declares 16; this is not
  a product-budget increase or a bypass of the correct refusal.
- The new generic-entry guard initially had test constructor/import errors.
  The broad cohort passed **124/125 in 82.0 s**, with only its missing `Usage`
  alias failing. The corrected generic guard passed **1 test, 47 excluded,
  6.6 s**, seed 791633. It checks both forged receipt-kind refusal and refusal of
  metadata-only rewriting through the generic V3 entry, preserving the root.

The budgeted three-category journey passed **3 tests, 11 excluded, 122.6 s**,
seed 791630. Its retained roots are:

- `/tmp/ipse-native-knowledge-session-f34e0312e7bde330eff09aa2fc09ffc4`
- `/tmp/ipse-native-knowledge-session-03d915d6a320acd14cbaf391417e225c`
- `/tmp/ipse-native-knowledge-session-9e2f945d900ba0e43d316a7dd01f5c1c`

This result precedes the additional explicit expired-repin refusal assertion.
Later receipts must state their exact source/test scope separately.

## Final-source receipts

The retained focused regression cohort completed with **125 passed, 82.8 s**,
seed 791634, `/tmp/ipse-accepted-retention-regressions-final-20261101.log`.
The complete category journeys with the additional expired-repin refusal then
passed **3 tests, 11 excluded, 123.0 s**, seed 791635:

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_RETENTION=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_retention --max-cases 1 --seed 791635
```

The final journey log is
`/tmp/ipse-accepted-retention-expired-repin-20261101.log`; its retained roots are:

- `/tmp/ipse-native-knowledge-session-11631cc40550abdeefaff520c81ca7db`
- `/tmp/ipse-native-knowledge-session-f905fc4d8322e972cda07ffae7adc400`
- `/tmp/ipse-native-knowledge-session-ab875e37be47cf30bd9e064fa5881cad`

Shared literal/full-facts native CLI regressions passed **17 tests, 1 skipped,
291.8 s**, seed 791636, with the complete command:

```sh
mix test test/ipse/cli/management_full_facts_test.exs --include native_sandbox --max-cases 1 --seed 791636
```

`/tmp/ipse-accepted-retention-literal-cli-20261101.log` records the terminal
result. The skip requires the separate `IPSE_TEST_RETENTION_SWITCH` hook; it
was not enabled. These native terminal/storage controls do not establish shell
sandbox enforcement. Source/helper bytes remained fixed during each cohort.

Existing accepted recall/forget/native-owner-loss plus the three finite-expiry
categories passed **4 tests, 10 excluded, 164.7 s**, seed 791637:

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_RECALL=1 IPSE_TEST_GENUINE_PENDING_ACCEPTED_EXPIRY=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_recall --only genuine_pending_accepted_expiry --max-cases 1 --seed 791637
```

The terminal log is `/tmp/ipse-accepted-retention-existing-accepted-20261101.log`.
Its unchanged no-retention-choice paths retain these synthetic roots:

- `/tmp/ipse-native-knowledge-session-f49593a6adaf9094de32cb0452e0bdba`
- `/tmp/ipse-native-knowledge-session-f1d286442c368415ceb5b316b9cb4d05`
- `/tmp/ipse-native-knowledge-session-3996eccc28af09e7d9426ec70ab8bfd1`
- `/tmp/ipse-native-knowledge-session-46b77c1e84d1e5081a3b0e81c626527c`

Actual Session literal retention, literal expiry and history expiry passed
**3 tests, 20 excluded, 64.4 s**, seed 791638:

```sh
mix test test/ipse/session/operator_assertion_integration_test.exs --only assertion_scenario:save_retention --only assertion_scenario:save_expire --only assertion_scenario:save_history_expire --max-cases 1 --seed 791638
```

The terminal log is `/tmp/ipse-accepted-retention-existing-lifecycle-20261101.log`.
The affected operator permission/management chapter and developer Collection SDK
and testing chapters were reviewed as complete documents. The developer entry
point now distinguishes pure fixtures from native lifecycle controls. The public
help descriptions also cover native notes rather than incorrectly limiting
forgetting to literals or expiry to ordinary notes. The help-only wording and a
test-title clarification were finalized after the native cohorts; their behavior
and native helper were unchanged.

The complete final `./dev/build.sh` compiled **183 host files** and built the
three inert bundled artifacts. `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `elixir dev/check-ci-policy.exs`, isolated
credential-free `./bin/ipse demo`, and `./bin/ipse --help` passed. Their final logs
are `/tmp/ipse-accepted-retention-{build,format,compile,ci,demo,help}-final-20261101.log`;
the earlier successful pre-help build/check logs remain separate. The unchanged
helper SHA256 is `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.
The available host is Linux `7.2.11-arch1-1` with tmpfs test storage; this does
not establish Btrfs on that kernel, macOS, OS confinement or reboot durability.

Documentation validation passed **1,011 Markdown files, 8,395 local links,
0 errors**, `/tmp/ipse-accepted-retention-docs-final-20261101.log`. Existing
permission-denied warnings for private unrelated ledger directories remain;
those directories were not inspected or changed.

The exclusively created post-run inventory is
`/tmp/ipse-accepted-retention-inventory-20261101.json`, SHA256
`980ed5282b9a1438252b1f7da71c908ff8a0171141480618ce2e78877ec96417`.
It hashes **32 selected source/helper/manual/build/dependency inputs, 37 logs,
and 128 retained synthetic fixture/journal/child-log files across seven final
roots**. It is not a pre-launch freeze, full-runtime inventory or whole-source
acceptance. The final documentation-only receipt amendment and its separate
commit-time checker log follow that inventory.

No real inference, downloads, package or external review occurred. Native/PTY
cohorts run serially. General turnover/compaction, accepted replacement/history,
expiry/retention-specific loss and installed combinations, full-source acceptance,
independent quality and final audit remain open. The last completed full-source
aggregate remains **3,538 passed, 60 failed, 109 skipped, 112 excluded** at
`e86b1b8`; focused passes do not replace it.
