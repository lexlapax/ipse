# Protected notes publication — original-requirement and source review

Read-only direction, 2026-10-29. The [plan](../../plan.md) owns acceptance.
This audits new `/remember` statements and automatic note/proposal publication,
not retention changes, correction/supersession, inference, or protected delivery
of existing notes. No gate/code edits, runtime tests or effects were performed.
The 28 relevant source/context owners are retained in a
[source-only snapshot](notes-publication-restoration-review/source.tar), with
[file hashes](notes-publication-restoration-review/source.sha256),
[manifest](notes-publication-restoration-review/manifest.sha256) SHA-256
`b2e04f3726606c80d8c344913f6b268ca07e486993010fc65f10449a39a5e5f9`
and [freeze result](notes-publication-restoration-review/freeze-source.log).
This is not an executable cohort or a whole-current-source safety review.

Disposition: a narrow notes restoration is supported by the original contract
using existing owners and native `switch_before`. The blanket refusal does not
prove that a new physical-expiry primitive is required. Restoration still needs
the source/policy/clock composition and focused actual controls below; this
direction is not permission to relabel current safe refusal as working capture.

## Required contract and the stronger promise

The [baseline](baseline.md) requires host-authenticated exact sources, exclusions,
current scoped consent, finite reservations and final revalidation under the
publication lock. Its permission section requires retained native locks and
atomic ordering with explicit revocation: initial reservation is not a later
publication grant. Its retention section says reads never renew TTL and expired
support invalidates use. Native role labels, copied receipts and worker JSON
cannot create operator testimony. The original
[contracts](contracts.md#consent-commit-order-and-process-coordination) require
intent before effects, durable reservation, control → storage ordering, immutable
staging/root publication, settlement and no replay after uncertainty.

Those obligations require a final **locked admission decision** against the
applicable clocks, not physical rename completion within the sampled wall-clock
millisecond. The [expiry requirements audit](expiry-requirements-audit.md)
finds no universal physical-completion promise in the original notes baseline;
the earlier P26 decision explicitly disclaims such clock-atomic syscalls. The
[actual interposition](strict-deadline-interposition.md) remains valid evidence:
a native process stopped after its clock comparison can rename after expiry.
It disproves physical expiry, not a documented live final-decision contract.
Its containment gate must be replaced explicitly, rather than calling the same
helper a newly enforceable physical deadline.

Use the existing actual-owner `Transaction.switch_before`: complete staging,
sync, fixed staged-inode checks and blocking validation precede its authoritative
UTC comparison immediately before the one fixed root rename. Equality refuses.
The staged name is consumed by rename; it is not a reusable grant. Retain native
Identity/Consent/Collection ownership through the fixed operation, sync and
receipt handling. Revocation/another writer cannot acknowledge past a surviving
old writer. Scheduling suspension after a live decision is one in-flight attempt.
It does not authorize another mutation or renew any stored clock.

Unlike native Review's separate live-success rule, ordinary saved-consent
capture has no original requirement that every confirmed late completion be
called unknown solely because time passed after the live final decision. A
confirmed committed result can describe that admitted attempt; current-use
eligibility is checked again later. Loss, failed sync/settlement, unconfirmed
owner cleanup or receipt failure still withholds known success. Original expiry
and lineage remain intact even if materialization completes late, so the result
cannot revive an expired note or authorize active recall under expired consent.

## Existing path and smallest restoration

The present blanket gates are distinct: Invocation refuses all mutating
`collection.call`/`collection.managed` after publication prerequisites; Collection
refuses the trusted deadline callback; notes timed profile entry refuses; and
`switch_pointer` accepts a deadline only for documents. `/remember` additionally
discards its genuine prompt ticket in `Session.prepare_assertion` before rendering.
None of those current refusals is evidence that publication occurred.

Restore first the existing **v3 `collection.managed` new literal/proposal path**,
which is what the current knowledge worker emits. Keep legacy arbitrary
`collection.call` mutation and metadata-v2 compatibility outside this first
restoration unless deliberately included and tested. Reuse the following owners:

1. **Keep actual source and grant checks.** Preserve Session/Registry/current job
   and action binding, exact outer descriptor/artifact and operator-selected
   recipe/constraints, mode ceilings, durable action intent, current original
   journal origin/source-window proof and unique exact quote. Current-source
   proof resolution runs again inside Consent publication. Retain
   `ManagedToolUse.publication_prerequisites?`: it permits no inherited content,
   only the exact own-publication root observation at the same namespace, policy
   and expected generation. A fresh source B cannot discard an inherited stale A.
   Do not reopen arbitrary managed-derived publication or replace this check with
   a worker-selected snapshot. New original receipts have no invented additional
   source TTL; managed literal dependencies have their real separate validity
   and source-owner requirements and remain outside this narrow path.
2. **Scope the trusted deadline in the actual effect owner.** Restore a named
   final-admission scope for the v3 capture path, reusing the existing
   minimum-preserving process-local mechanism. The authenticated Consent policy
   expiry and any already inherited earlier deadline can only narrow it. Validate
   positive safe-integer deadlines, refuse elapsed entry, and restore prior state
   on all exits. The callback runs once in the tracked file-effect owner, not in
   a worker or a new policy framework. `switch_pointer` must use the existing
   native final check for this notes attempt. Never fall back to an untimed
   switch when a trusted deadline exists.
3. **Include the normalization's real clock.** `ManagedCollectionCall` currently
   scopes only the policy's `expires_at_ms`. Normalizer/V3 also derives
   `valid_until_ms` from the retained lineage anchor and checks it before metadata
   planning/staging. That earlier finite clock must narrow the same final native
   deadline for restored current publication; nil persistence adds no deadline.
   Derive it from the actual trusted normalization/metadata under the lock, never
   a worker field. Keep first-admitted and pending clocks, signed retirement and
   override checks, original public change, recipe binding, 32-unit seal, bounded
   metadata planning and exact generation/revision CAS. Re-reading/retrying the
   same lineage cannot restart its ordinary or seven-day proposal age. An
   intentionally inert late-materialization contract would be separate; do not
   silently substitute it for successful current publication.
4. **Preserve publishing liability and first-domain activation.** Keep one finite
   Consent reserve/admit and durable `publishing` before the fixed attempt.
   Preserve v3 Identity domain authentication and exact first-publication proof;
   prepared domain metadata is not an active collection. Validate actual Core
   binding/accounting and release/finalize Identity before deferred settlement.
   Existing/duplicate operation outcomes are inspected, not reexecuted. Native
   elapsed refusal can leave immutable staging; Collection currently conservatively
   reports uncertainty after staging. No-root-change alone is not proof of zero
   preparation/accounting effects and does not justify clearing liability.
5. **Keep unrelated fences.** No retention/pinning, supersession, managed State/
   service effect, managed document mutation, protected approval/question, nested
   result or retained-note output gate follows from restoring capture. No broad
   `--yes`, headless grant or automatic testimony conversion is introduced.

Do not turn `publication_deadline_admission` into a global predicate returning
bare `:ok`: the current non-document `execute_profile_before` branch returns it
directly and would then report admission without executing the requested operation.
That generic notes timed entry is not needed by `execute_managed_v3`; keep its
explicit refusal unless intentionally routed through the real selected execution
path. Separate any strict-physical support diagnosis from the newly reviewed
notes final-admission scope. Reusing a small existing scope or a narrowly named
trusted helper is sufficient; no general workflow/interpreter is needed.

## `/remember` intake and separate output boundaries

The native Terminal already sends observed `/remember` prompt tickets into
`prepare_assertion`; OperatorAssertion selection/render/receipt and the observed
acceptance path remain. Restore only `parse_command`'s new
`/remember ordinary|preference|current TEXT` intake, with idle/no-active-work
checks, actual same-client/channel ticket submission, original source and input
generations, selected capture recipe and `purpose: nil`. Keep `/correct` and
`/supersede` rejected. Preserve the fresh exact statement/category/workspace/
permission/retention display and volatile confirmation, then journal the genuine
assertion before protected capture. Cancellation, stale code, foreign witness,
scope/epoch/recipe change and explicit mode denial must not become an assertion
or a publication. The reviewed category contract remains exact; this does not
silently implement a different pin/retention choice.

This display is the operator's **new statement**, not active recall of retained
managed content. Its native input attests that statement/category, not truth of
quoted external material or effect permission. It therefore need not wait for a
new existing-note protected-display architecture merely because both paths use
a terminal. Actual current-use recall, worker/history/result publication and
inference still need their own fresh authority and output owners. Keep their
current gates; do not let local storage success bypass them. A withheld worker/
terminal result is not evidence of rollback or a safe replay opportunity.

Readiness/manual wording must distinguish notes final-admission support from
strict physical deadlines and complete capture/recall readiness. The current
`capture_ready_now` combines one publication boolean with activation; reopening a
limited path cannot truthfully advertise every still-fenced output journey as
complete. Whole-chapter/manual reconciliation remains required after actual
caller qualification, rather than accumulating another gate exception list.

## Focused actual qualification needed

Use a fresh matching source/helper/worker cohort and reuse earlier passing
evidence only where those owners match. Do not rerun an aggregate merely to
establish this direction.

- One actual native-terminal `/remember` journey through statement/category
  review, same-journal assertion and action intent, v3 signed root/metadata,
  measured settlement and Saved reconstruction, with zero model admission.
  Cover cancellation, stale/foreign confirmation, mode denial and changed
  permission/selected artifact between review and publication.
- One genuine automatic typed host-outcome save under saved scope, including
  headless without `--yes`; injected argv/stdin/assistant prose must remain
  attributed/pending or refused. A fixture claiming `native_operator_assertion`
  is not a substitute for the genuine-input positive.
- Current finite policy positive; approval/wait and synced-staging expiry before
  the final decision; exact equality; a shorter retained normalization deadline
  while Consent is still live; nested earlier deadline/restoration; expired
  lineage recapture and pending age. Predecision refusal leaves old selection
  intact and never renews clocks. Use trusted short-clock fixtures rather than
  claiming a real 90-day wait.
- Reuse the established post-clock/pre-rename scheduling distinction: an already
  admitted attempt may complete late with original metadata. Record actual root,
  outcome and later-use ineligibility. Do not call it physical expiry or demand
  rollback from a userspace clock comparison.
- Two real owners race revoke/disable, correction/suppression or a competing CAS
  against staging/publication. If the writer wins, acknowledgment waits for its
  fixed native attempt; if revocation wins, the old epoch refuses. Kill/stop the
  actual Session, file-effect peer and native owner at unresolved boundaries;
  verify original journal/source and policy/storage ownership cannot be released
  while an old writer can still publish. An unknown outcome stays inspectable
  with no automatic retry or new operation adopted from the journal.
- Exercise first-domain prepared→active proof, source/recipe/quote mismatch,
  inherited stale A plus current B refusal before intent, duplicate operation,
  result-append/Identity finalization/settlement/release loss, and retained
  retention/supersession/output fences. Inspect actual root and original
  operation when UI/worker delivery is withheld; do not equate that withholding
  with no effect.

These controls can establish the restored local notes slice. They do not close
source acquisition, full capacity/turnover, protected current-use sinks,
decision-model experiments, non-Linux/package or complete P30/P31 acceptance.
