# Accepted decisions through ordinary native tool approval

Dated **2026-11-01**, author implementation on base `75773ac`, following the
[complete failed baseline](full-suite-20261101.md). Historical source verification;
[the plan](../../plan.md) owns milestone acceptance and the
[operator manual](../../operator/knowledge-permissions.md) owns current procedures.
This increment does not complete P31C0, P31 or P30.

## Bind the additional original owner

Accepted current recall and Worker input already retained the original committed
management journal. Ordinary approval still used generic display preparation,
which deliberately refused version 6. A new narrow approval purpose now retains
those authenticated journal owners while leaving generic displays closed.

Session derives the required journal IDs from its exact pending dependency
union. Its Writer snapshots the private journal lock inodes alongside original
Session lock inodes. Session validates the exact combined manifest count and
inode set before supplying its own payload. LeasedTerminal binds each actual
journal token to its immutable link and exports/settles it at the same native
terminal receiver as the source and policy owners. Source groups and management
journals share the unchanged 128-entry bound. No Rust opcode, layout, helper,
dependency, provider choice or product allowance changed.

Writer stays frozen under its Session through display/settlement; Session/Host
controls protect the actual display. Source/policy locks release before input,
and the eventual effect reacquires fresh authority. The exact fresh native
`allow CODE` confirms one attempt, with no reusable grant. Delegation, nested
Worker approvals and generic version-6 displays retain their refusal paths.

## Native journey and preserved counterexamples

The opt-in journey creates two proposals through registered synthetic Ollama
requests, confirms one through public native review, and runs four fresh consumer
Sessions. Unmodified positive and denial cases require respectively one exact
workspace write and no effect. Observed child hosts disclose a pre-display pause,
then verify actual policy/source/Session/acceptance-journal descriptors at the
native sink, both native controls, the sealed frozen Writer snapshot and the
publisher's real journal token/link/operation. The unchanged native send supplies
all successful protocol observations. A separate case kills that exact exported
journal helper before display: no approval payload or tool starts, the poisoned
consumer stops, and strict Saved/idle recovery repeats no work. Original Session
and management journal bytes remain unchanged.

All attempts used fresh synthetic roots. Earlier logs remain separate:

- `baseline`: safe term decoding failed before approval. The fixture handoff now
  uses private JSON and normal entry admission, with no external-term decoder.
- `baseline-json`, old f44b63c host/new launcher: recall reached a version-6
  dependency but approval refused; read-only journal inspection found zero tool
  starts/admissions and no proposed file. This is the missing-feature baseline.
- `native`: the first implementation added a descriptor that Session's original
  source-only manifest check correctly refused. The repair binds the additional
  journal count and inode set through Session/Writer, retaining that check.
- `owned-manifest` and `fresh-admission`: positive/denial passed, but the observed
  child's new host identity required fresh Registry and policy preparation. The
  trusted fixture now uses normal preparation, preserving runtime admission.
- `current-policy`: the observer incorrectly borrowed Worker input's direct
  Writer-control expectation. Source/manual inspection shows display instead
  seals Writer under Session and transfers Session/Host controls. The repaired
  observer verifies that exact frozen snapshot and refuses an attempted append.
- `display-binding`: the ownership positive passed; journal loss stopped the
  poisoned consumer as documented, invalidating the fixture's idle assumption.
  The final case requires CLI status 1 and actual consumer death, then a fresh
  inert resume; it accepts no alternative outcome.

These logs are `/tmp/ipse-accepted-approval-*-20261101.log`. The complete journey
passed **1 test, 14 excluded, 61.9 seconds**, seed 791650:

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_APPROVAL=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_approval --max-cases 1 --seed 791650
```

Its log is `/tmp/ipse-accepted-approval-poisoned-loss-20261101.log`; retained root:
`/tmp/ipse-native-knowledge-session-09e8c33ba39131728dae000aa97f0e15`.

## Restore fixture coverage without changing runtime policy

Default Knowledge positives now use the registered adapter instead of a demo
callback once publication adds managed history. Their synthetic responder selects
only declared literal task inputs and reconstructs result IDs from calls actually
issued on the wire; actual requests retain all reference data. The intentionally
unregistered recall refusal remains. A known refused capture can finish its turn
after returning the failed action; attack controls still require denied commit,
zero effect accounting and an unchanged empty store. Native-answer cases now
also require the final turn record.

The original combined regression had a new assertion syntax error before tests.
After repair it passed **17/20, 11 skipped, 166 excluded, 47.8 seconds**, seed
791652; all 15 Writer barrier controls passed, including eight new inode/bound
cases. The three failures were capture-fixture expectations. The next run passed
all four default Knowledge cases but retained a self-writing fixture failure
(**4/5, 11 skipped, 166 excluded, 48.6 seconds**, seed 791653).

That fixture now selects the supported V3 capture shape and tests the actual
authenticated Worker successor: raw old-root reads and result bytes survive,
the input intent commits the complete old union, and the transition binds the
known action/receipt to the final current dependency. It no longer relies on a
closed V2 publication or expects an erased dependency set. The isolated case
passed **1 test, 166 excluded, 11.6 seconds**, seed 791654, log
`/tmp/ipse-self-writing-successor-20261101.log`. Its intermediate failed
model-notice expectation remains in the prior log; this single capture's old
root was internal to the Worker, so its transition precedes model output. Broader
model historical notices retain separate genuine multi-capture controls.

## Qualification limits

The existing literal native-approval suite passed **11 tests, 12 excluded,
173.6 seconds**, seed 791655:

```sh
mix test test/ipse/session/operator_assertion_integration_test.exs --only managed_approval:true --max-cases 1 --seed 791655
```

Log: `/tmp/ipse-accepted-approval-literal-regression-20261101.log`. It retains
fresh/active/resumed writes, denial/stale input, cancellation/exit, delayed
input, source change, revocation and Session loss on the same shared adapter.

Shared relation, managed-use, Writer barrier, accepted lifecycle consistency and
original-source regressions passed **62 tests, 131.6 seconds**, seed 791656:

```sh
mix test test/ipse/session/managed_supersession_session_test.exs test/ipse/session/managed_use_test.exs test/ipse/session/share_barrier_test.exs test/ipse/session/accepted_decision_lifecycle_test.exs test/ipse/session/stored_sources_test.exs --include native_sandbox --max-cases 1 --seed 791656
```

Log: `/tmp/ipse-accepted-approval-source-relation-regressions-20261101.log`.
All 13 genuine relation modes and all 15 Writer barrier cases ran. Native
inclusion here exercises retained locks/terminal protocols, not shell confinement.

The complete default Knowledge file plus existing accepted recall/forgetting/loss
journey passed **5 tests, 10 skipped, 84.6 seconds**, seed 791657:

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_RECALL=1 mix test test/extensions/knowledge/knowledge_session_test.exs --max-cases 1 --seed 791657
```

Log: `/tmp/ipse-accepted-approval-default-and-recall-20261101.log`; retained root
`/tmp/ipse-native-knowledge-session-82856c1392f021a74630ed328d5a588e`.
The skips are separately opted-in acceptance, expiry, retention and approval
journeys; the new approval journey ran separately above.

The final source build compiled **183 host files** and rebuilt all three inert
bundles. Whole-repository formatting, strict compilation, CI policy and docs
checks passed. The docs checker covered **1,014 Markdown files, 8,409 local
links, zero errors**; pre-existing inaccessible private ledger warnings remain
without inspection or repair. Isolated credential-free demo and CLI help passed.
Logs are `/tmp/ipse-accepted-approval-{build,format,compile,ci,docs}-final-20261101.log`
and `/tmp/ipse-accepted-approval-{demo,help}-utf8-final-20261101.log`.

The first check driver's relative-script launch failed before a build started;
the corrected explicit-shell build passed. Its initial demo collector then
failed to transcode Unicode to its Latin-1 file, so that partial attempt is not
a passing demo result. A fresh private-home CLI run with explicit UTF-8 logging
passed without changing product code or repeating the other passing checks.
The native helper remains
`5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.

After that build, the final test file ran in a fresh standalone ExUnit VM using
only the development SDK/dependency paths and standard isolated test bootstrap.
The same four-mode native journey passed **1 test, 14 excluded, 60.7 seconds**,
seed 791658, `/tmp/ipse-accepted-approval-built-runtime-20261101.log`. Its retained
root is `/tmp/ipse-native-knowledge-session-86078495f79620435872754ac6849b63`.
This matches the rebuilt source runtime and shipped inert bundle catalog;
it remains a synthetic source journey, without installed-package qualification.

The operator knowledge and recovery chapters, developer source and testing
chapters, their audience indexes and the plan were reviewed in their existing
reader-oriented structure. Changes explain the actual native review, original
journals, poisoned-owner recovery, distinct display/input ownership and focused
verification procedures. No dependency, package or live account check is claimed.

The exclusive post-run inventory is
`/tmp/ipse-accepted-approval-inventory-20261101.json`, SHA-256
`afbe3992915f464ac204d05ec11ba2e23f943b1eed7dd799275c580d8e93bde5`.
It hashes 29 selected source/helper/manual/build inputs, 450 development/test SDK
files, 65 bundled-artifact files, 33 logs and 65 named synthetic fixture files.
The record identifies its actual base and tracked runtime/test diff, plus the
two new helpers separately. This is post-run evidence rather than a prelaunch
freeze, complete loaded-runtime/dependency inventory or whole-source proof.
Archive prose and the final commit-time documentation check follow that inventory.

These are automated Linux source/protocol controls with synthetic responses.
They establish no independent human use, live model quality, installed approval,
128-note recall, other platform/storage profile or complete lifecycle. The
whole-source result remains the separately recorded **54-failure f44b63c baseline**;
focused passes do not reduce it. Final integrated tests, capacity/quality work,
adversarial post-implementation audit and reviewer handoff remain open.
