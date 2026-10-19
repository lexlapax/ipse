# P26 external re-review request, 2026-10-19

Historical review request, not an acceptance verdict. The [remediation record](index.md)
owns verification receipts and later decisions. Current behavior belongs in the
[operator manual](../../operator/memory.md), [developer memory chapter](../../developer/memory.md)
and [host-call contract](../../developer/extension-host-calls.md).

Copy the following request to the independent reviewer.

---

Review Ipse's P26 architecture and implementation at exactly:

```text
b1dc82094afdae8708cdb45dea16beb6c948f88b
```

Repository: `lexlapax/ipse`. This is the corrected runtime/manual candidate, not
a P26 completion claim. Later receipt-only documentation does not change that
review target. Verify your actual HEAD before reviewing or running checks.

Give an independent verdict on whether P26 meets its documented scope. Look for
new defects as well as regressions in the reported repairs. Do not limit the
review to the diff or assume the internal reviewers' verdict is correct.

## Scope and evidence to read

Read `AGENTS.md`, the P26 acceptance section of `docs/plan.md`, and the complete
operator/developer memory chapters plus `docs/developer/extension-host-calls.md`.
Then read the relevant implementation, callers and tests, especially:

- `lib/ipse/extensions/memory.ex`, `memory/records.ex`, `registry.ex`, `state.ex`;
- the generic Host, Actions, Operation, Worker, identity, Session approval,
  filesystem completion ownership and journal recovery paths;
- `test/extensions_memory_test.exs`, `extensions_memory_session_test.exs`,
  `extensions_state_test.exs`, `extensions_state_binding_test.exs` and
  `extensions_state_scan_test.exs`.

The first external report is preserved at
`docs/archive/2026-10-19-p26-remediation/review-1.md`. It reviewed
`10b9dd66d06ef28718b58530a7e5b01c7c50397a`, before these repairs. Read
`internal-review.md`, `expiry-write-design.md` and `index.md` in that directory
for the corrections, explicit user choices, before/after evidence and limits.
Initial P26 implementation was `108aa8632b4a6e6dde8441f73a19727224280963`;
the earlier diagnostic cleanup repair was
`fb4627e5722f29d9bb62f1f51e781f9087d9be18`. Preserve the distinction between
historical and candidate evidence.

## Settled product choices

Backups preserve stored values, including expired notes and legacy active notes,
with original expiry and dependency links. They do not invent suppression for
blocked records. This is an explicit user choice. Model recall/inspection still
hide ineligible text, title and provenance. Existing suppression remains permanent.

The user also explicitly chose rejection when a prepared update waits for approval
past the existing target's expiry. An ordinary live update may renew a still-live
target. A fresh approved backup import may restore an expired value unchanged.
These are separate cases.

P26 is an explicit-note baseline, with no automatic capture, embedding service,
semantic retrieval claim or secure erasure guarantee. Prior results, journals,
exports and provider transfers can retain plaintext. Fresh-session recovery is
documented rather than retrospective history redaction. Do not require later
P27 research/graph/RAG features as P26 acceptance. P27 remains incomplete and its
private interrupted experiment must not be changed or inspected for this review.

## Required adversarial paths

Independently trace and exercise, where the host permits, these boundaries:

1. Model inspection and recall of expired, suppressed, orphan-derived,
   transitively blocked and unmigrated notes. Include descendants of a valid
   legacy parent, a readable control and recovery after explicit migration.
   Check actual provider-received tool messages, not only handler output.
   Inspection must pin dependency scanning to its initial read generation and
   refuse conflicting pagination without modifying State.
2. Complete generation-pinned export and fresh restore of live/expired v1/v2
   values, blocked children and suppression. Compare exact values and later
   behavior when a missing parent arrives or an approved update removes a
   dependency. Preserve suppression priority, source generations, expiry and
   retention ceilings. Active import over a legacy target must require explicit
   migration. Old or partial backups cannot establish complete forget history.
3. Missing collection with and without `cause_source`, at expected revision zero
   and with a stale nonzero expectation. Expect `not_found` or revision conflict
   respectively, no record reservation, and continued Session usability. Forget
   of an absent ID intentionally creates permanent suppression and consumes quota;
   its typo consequences are documented.
4. Selected scope versus operator binding at initial admission and revalidation.
   Cover required persistent bindings, optional working bindings, compatible
   controls and unbound working memory. Projects cannot grant bindings or broaden
   scopes. Ordinary third-party options named `scope` must not acquire invented
   host semantics.
5. Actual delayed approval for remember and active import. Capture the exact
   approved `state.put.write_before_ms`, derived from the existing target's expiry.
   Approve after that expiry and verify `source_expired`, unchanged value,
   expiry, revision, namespace generation and previous operation ID, a known
   failed receipt, continued Session use and inert idle resume. Include successful
   before-expiry renewal and fresh expired-backup controls.
6. Generic State deadline validation, CAS precedence and receipt integrity.
   The optional scalar belongs only to `state.put`; malformed/null/unknown fields
   refuse. Core must not interpret note fields or grant new authority. Inspect
   the locked initial check and post-sync/chmod check immediately before rename,
   cleanup and preservation of the elapsed result. Verify exact failed summaries
   and recorded timestamps without consulting the recovery-time clock. Ordinary
   unbounded requests retain their old contract. Interruption without a committed
   receipt remains unknown and is never replayed automatically.
7. Default-off behavior, scope isolation, separate full-argument write approval,
   denial/cancellation, concurrent forget/stale continuations, bounded work and
   outputs, legacy namespace compatibility, stable logical identity, no silent
   provider/service changes, and truthful manuals with working examples.

The root did not force a delay inside temporary staging. Its check placement was
source-reviewed, while delayed approval and generic deadline failure were tested.
Do not turn that limit into a claim that a slow-filesystem scenario ran. The
deadline decision is the final clock sample before publication under the lock,
not a hard real-time guarantee about syscall completion or clock rollback.

## Verification discipline

Use an isolated checkout at the target SHA and private synthetic homes/workspaces.
Preserve unrelated work. Run appropriate focused checks, then build, formatting,
strict compilation, full tests, demo and actual native/package checks available
on your host. Follow the repository's documented commands and bounded packaging
procedure. Keep assertions, deadlines, TLS and platform failures intact. Do not
weaken checks or call excluded tests verified. No paid inference, model downloads,
credential borrowing or provider fallback is needed.

The root's macOS full baseline passed 1,160 tests with 32 platform exclusions;
the Serenity Linux baseline at this exact SHA passed 1,177 with 15 exclusions
and native sandbox cases enabled. macOS native and extracted-package checks
also passed. The remediation index records toolchains, commands and limits;
these receipts may postdate the candidate's original pending-status entry.

For additional Elixir 1.18 / OTP 27 compatibility evidence, inspect the exact
candidate's automatically triggered GitHub run and individual steps if available:
<https://github.com/lexlapax/ipse/actions/runs/39295194794>.
This review need not wait for that run. Report the status actually observed;
prior successful jobs do not verify this SHA.
Distinguish an unrelated failing P27 fixture from a P26 regression with actual
evidence; do not silently waive an unexplained failure.

Do not read real credentials, private journals or `.ipse/continuations/`, and do
not inspect private P27 predictions or labels. Do not modify the main checkout,
push changes, send external messages or implement P27. Scratch probes may be
created only in your isolated review workspace; preserve sanitized evidence and
report any cleanup or execution limitation.

## Deliverable

Write `/tmp/ipse-p26-review-r2.md` with:

- A verdict on P26 readiness within its stated scope, with blocking findings first.
- Each concrete finding's severity, exact location, reachable causal path,
  minimal reproducible probe, expected/actual behavior and suggested correction.
- An acceptance matrix distinguishing code inspection, helper/fixture tests,
  public Sessions, actual native enforcement, extracted runtime and hosted steps.
- Exact reviewed SHA, OS/toolchain, commands actually run, passes/failures,
  exclusions and unverified limits. Separate inherited failures from new ones.
- A whole-document assessment of user procedures and contributor training,
  including commands, examples, links and stated limitations.

A green test count or previous review is evidence, not a substitute for tracing
the architecture and authority boundaries. No findings is a valid result when
supported by that investigation. Report gaps rather than changing code silently.
