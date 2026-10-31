# Managed question recovery and host publication repairs

The [independent repair review](managed-audit-repairs-independent-review.md)
found a remaining ordinary-publication deadline gap and additional question and
test-evidence limits. Its findings are open until the follow-up is implemented
and verified.

Historical scoped receipt, 2026-10-29. This records repairs to the findings in
[the independent host-display review](managed-host-display-independent-review.md)
and supersedes the open-findings status in
[the earlier refusal receipt](managed-host-display-refusal.md). Existing frozen
cohorts remain historical. Current milestone status belongs to
[the plan](../../plan.md); this is not P31C0 acceptance.

Saved reconstruction now classifies a pending native question from its original
tool-call dependency union. Extension questions additionally require an actually
present invocation with a matching parent ID and the union of inherited and
host-observed reads. A missing producer is not proof of empty dependencies.
Nonempty or unavailable lineage withholds the question before live state is
constructed, marks lineage unavailable, and exposes only the argument-free
`managed_question_withheld` recovery disposition. Subscriber replay, `Session.info`
and `/answer` therefore cannot release or resume that question. Original journal
records remain inspectable and no question continuation is replayed.

Managed `state.put`, `state.delete` and `service.call` now refuse before action
admission, including under `--yes`. They require real final publication or worker
start/send fences before managed inputs can use them. Ordinary untainted calls
retain their existing behavior.

The actual two-source probe reproduced a publication defect: a worker scanned
managed namespace root A, waited while a separate genuine capture advanced that
root, then successfully published while citing a fresh original source B. Its
host union still contained the stale A observation. The probe's proposal records
produce v3 root dependencies, not v4 literal dependencies; no literal-v4 result
is claimed here. The failed safety assertion is retained in 46862, including
`MANAGED_AB_WRITE_STATUSES=["ok"]`.

Collection publication now refuses inherited managed content or extra observed
dependencies. Its sole narrow exception is the exact host-produced snapshot
precondition for that publication: same invocation, no inherited input, matching
namespace/pin/epoch, exact snapshot request/result hashes, and generation equal
to the request's `expected_generation` consumed by the existing final native CAS.
Workers do not classify or remove reads. Scan observations, literal dependencies,
old roots, missing snapshots, foreign bindings and inherited inputs refuse.
The repaired probe in 46865 observed no successful candidate publication result;
the fixture did not directly assert absence of its intent. Both ordinary captures
within that same control still succeed.

Focused checks:

- 46854: nine actual Session controls passed in 23.2 seconds. Each managed State
  mutation and service call refused after revocation and expiry under `--yes`;
  all three ordinary counterparts succeeded. The service's cross-worker marker
  appeared only on its ordinary path.
- 46859: two actual interruption/resume controls passed in 7.9 seconds after
  revoke/expiry. A test-only historical tracking omission was applied before
  real Session request/usage/question emission. The legacy journal removes the
  tracking marker and substitutes inert observations while preserving original
  source byte ranges and line ordinals. No question notification, info arguments,
  answer, closure or continuation was emitted on resume; the prefix stayed intact.
- 46863: ordinary interrupted question recovery passed in 1.2 seconds, displayed
  its full arguments and accepted exactly one answer.
- 46865: the repaired root-A/current-B probe passed in 3.2 seconds, with ordinary
  capture compatibility and Saved replay checked in the same scenario.
- 46867: three focused pure controls passed, covering native/extension question
  classification and publication prerequisite binding/tamper/inheritance cases.
- Strict compilation passed for the initial three modules in 46853 and all four
  production modules in 46864. Final formatting and strict compilation in 46868/69
  changed only formatting/line metadata after those behavioral checks; no
  aggregate suite was repeated.

Retained fixture failures distinguish discovery from repairs: 46855 appended an
unmetered assistant event and correctly failed usage validation; 46856 closed the
question before interruption; 46857 rewrote byte positions and correctly failed
source validation. The final legacy fixture preserves both genuine producer
records and source ranges. Probe 46858 used an invalid nil scan generation;
46860/46861 incorrectly expected a literal dependency from a proposal recipe.
46862 is the actual reproduced root-union defect. In 46866 two pure controls
passed and the third hit a test-only struct Access error; only the new focused
selection was rerun after that fixture correction.

The [manifest](managed-audit-repairs/manifest.json) retains source, scripts, logs
and the final runtime inventory. The runtime uses the previous matched a51c2d
helper and dependencies; no helper/native protocol was changed. The final
post-format runtime inventory is compilation evidence, not a repeated behavioral
run. No terminal PTY, paid service or aggregate suite was used.

The scoped whitespace check initially found duplicate trailing newlines from the
formatting wrapper. Removing only those extra newlines was followed by the final
strict compile46869 and a clean scoped `git diff --check`.

Remaining boundaries include a wired literal-v4 A/B negative, leased full approval
and question display, fenced managed State/service execution, managed delegation,
nested worker-result release and shared native source/effect owner-death ordering.
Those managed paths remain refused or withheld. Supersession relation display
remains separately disabled. Manuals, integration reconciliation and milestone
acceptance remain separate work.
