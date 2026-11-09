# Proposed: P30 qualified completion for the local scope

**Draft for operator sign-off; not yet accepted.** This record proposes a
disposition for P30's locally verified scope. It does not complete P30. An
independent reviewer approved the draft with required changes, which are
applied here. The operator decides acceptance and the open clauses below. Until
then the [plan](../../plan.md#p30-advisory-decision-engines) remains the
authority for P30 status; this draft becomes historical evidence once
superseded. Current behavior belongs to the
[developer chapter](../../developer/decisions.md) and the
[operator shadow procedure](../../operator/knowledge-permissions.md#try-a-local-shadow-assessment).

| Provenance | Value |
| --- | --- |
| Prepared | 2026-11-09 (US/Pacific), on `codex/p30-p31` at `f4e20277`; documentation only, no tests run for this draft |
| CI-parity source baseline | `b6df1b11`, Arch Linux kernel 7.2.11, Elixir 1.18.5 / OTP 27.3.4: 4,665 tests, 0 failures ([record](../2026-11-08-whole-source-baseline/index.md)) |
| Latest full Linux suite | Tested `7833160d` plus the then-uncommitted 7.2.14 selector, test-gate and manual changes. Arch Linux `7.2.14-arch1-1`, Elixir 1.20.4 / OTP 29. `IPSE_TEST_NATIVE_STORAGE=1 mix test`: 4,399 passed, 0 failures, 136 skipped, 132 excluded ([record](../2026-11-09-kernel-7214-tmpfs-profile/index.md)). Commit `f4e20277` also contains `7736b5db` (`dev/package.sh` and two tests), which that run did not test |
| Hosted CI | Run 42663715255 at `72ee4e63`: every Ubuntu and macOS source partition and both platform jobs passed, with `:native_storage` tests excluded ([plan Verification row](../../plan.md#execution-order-for-p30-and-p31)) |
| Local macOS | One full suite at `7833160d` (Darwin, OTP 29): 3,327 of 3,329. One load timeout in `test/ipse/provider/ollama_context_test.exs` (passes alone) and one AppleDouble archive defect in `test/dev/release_test.exs`, repaired in `7736b5db`. Recorded only in the plan and `P30_P31_HANDOFF.md`; no complete macOS rerun is recorded. Neither failure is in a P30 file, but the P30D Session files are tagged `:native_storage` and did not run here |
| Where the P30D Session files ran | `test/extensions/knowledge/shadow_*_session_test.exs` carry `@moduletag :native_storage`. They ran only in the two Linux full runs above, not in hosted CI or on macOS |
| P30 evidence crosswalk | [Local disposition crosswalk, 2026-11-05](../2026-10-26-p30-p31-implementation/p30-local-disposition-20261105.md) |
| Replacement | [Current plan, P30](../../plan.md#p30-advisory-decision-engines) |

## Plan rules applied

The plan's acceptance paragraph supplies the closure rules this draft applies:

> Hard protocol/integration gates must pass; completed negative experiments can close
> D/E and P30 with **no qualified default consumer**. Unavailable engines and
> accounts stay unverified and their consumers stay unqualified; that external
> unavailability alone does not block a qualified completion of the locally
> verified scope. Incomplete local protocol or integration evidence remains open.

The Decisions lane requires "Baseline plus a reviewed disposition for every
engine and consumer; no qualified default." The plan also states: "No local
engine, SDK, new dependency or live account eligibility is established," and
"Live engine access and model quality stay unverified until an operator
supplies accounts and labels."

A gate is **met for the local scope** only when the cited evidence covers it.
It is **qualified** when the remaining gap depends only on engines, accounts or
operator-supplied labels. It is **open** when the gap could be closed with
local resources. Some open clauses need an operator decision on what the
requirement means before they can be closed.

## Package dispositions

| Package | Plan requirement | Evidence | Disposition |
| --- | --- | --- | --- |
| P30A | A versioned neutral text contract with pure OpenAI/System One wire subsets. Results need exact count/type/range/distribution validation, valid per-question refusal handling, and uncertainty kept distinct from malformed output | `lib/ipse/decision.ex`, `lib/ipse/provider/decision.ex`; `test/ipse/decision_test.exs` (count, order, option coverage, probability sum, per-question refusal, independent corruption), `test/ipse/provider/decision_test.exs` (OpenAI refusal distinct from malformed output, System One identities and score legend, exact usage, no cross-engine coercion), `test/fixtures/decisions/`. Uncertainty versus malformed output: `test/ipse/extension/decision_session_test.exs:1010` (low-probability advice keeps the baseline) against `:1266` and `:1310` (malformed distributions and responses fail without advice) | **Met for the local scope.** Synthetic wire fixtures only. `Decision.select` returns the same `{:defer, :unusable_advice}` for low-probability and unusable results (`lib/ipse/decision.ex:59,63`). The distinction lives in result validation and the Session tests, not in `select` |
| P30B | Operator-only profiles, bounded owned HTTP, `host.decision`, Session/replay bindings, usage/prices and shared budgets. Admission requires "permission/reservation/journal admission before egress, cancellation during actual work and zero dispatch on denial." "Consent displays operation-specific pricing, endpoint, processing/storage region, cache retention and verified/unknown account controls" | `test/ipse/extension/decision_session_test.exs` (approval before egress, zero dispatch on denial, cancellation of a dispatched request, malformed/disconnected liability, inert resume, child approval, one shared reservation under concurrency, hosted wire subsets with explicit keys); `test/ipse/provider/decision_transport_test.exs`, `test/ipse/extension/decision_call_test.exs`, `test/ipse/extension/decision_capability_test.exs`, `test/ipse/extension/decision_outer_test.exs`, `test/ipse/usage/decision_test.exs`, `test/ipse/config/decisions_test.exs`, `test/ipse/config/decision_loading_test.exs`; cross-Session and cross-process controls in `test/extensions/knowledge/shadow_cross_session_test.exs` and `shadow_cross_process_session_test.exs`; the baselines above. Older installed evidence: the `decision` scenario (`dev/verification/decision_installed.exs`, listed in `dev/verification/scenarios.exs`). It passed on 2026-10-27 against archive `3be5ea3d…`, built from a private tree with no reviewed commit, using an example extension, not Knowledge ([record](../2026-10-26-p30-p31-implementation/p30-current-decision-followup.md#synthetic-installed-decision-session)) | **Met for the local scope, with the consent clause accepted as a limitation by the operator on 2026-11-09.** `lib/ipse/config/decisions.ex:218-223` accepts each of the five disclosures as nil or a 1–1024 byte string. The only test (`test/ipse/config/decisions_test.exs:39`) asserts that all five are nil. `test/ipse/extension/decision_call_test.exs:68` binds `execution` only. No test shows non-null pricing, region or retention reaching the approval display. No verified-versus-unknown account-control state exists. Other limits: hosted wires use synthetic keys only; the CI-parity and native-storage runs used different commits and toolchains; the installed scenario has not been rerun on current source |
| P30C | Pure Knowledge planners and zero-call controls with independent audits, planner-to-Session shadow mapping, and "fitting note sets bypass retrieval decisions without an extra call" | `extensions/knowledge/src/knowledge/decision_policy.ex`; `test/extensions/knowledge/decision_policy_test.exs`, `test/extensions/knowledge/selection_shadow_test.exs` with `selection_shadow_cases.exs`; [pure-policy audit](../2026-10-26-p30-p31-implementation/p30c-pure-policy-audit.md); Session mapping in `decision_session_test.exs` ("synthetic shadow selection exercises the Knowledge planner through Session approval") | **Met for the local scope.** No production strategy calls the planner automatically |
| P30D | Two bounded consumers with source/get/release, accounting, Saved/close/idle and no-replay controls. Remaining plan gate: "Broader installed-user workflows" | [Protected selection and assessment](../2026-10-26-p30-p31-implementation/protected-selection-assessment-20261105.md) (source runtime, both consumers). Installed synthetic Linux checks of both consumers on older archives: selection in the [packaged paired CLI checkpoint](../2026-11-05-packaged-paired-cli/index.md) (archive `f0274bb5…`, commit `aa1c7695`; five phases scripted through `bin/ipse eval` with a separately supplied answer artifact), and pending-proposal assessment in the [installed prior-Session assessment](../2026-10-26-p30-p31-implementation/p30-pending-installed-20261103.md) (`dev/verification/pending_shadow_installed.exs`, archive `678b446a…`, reported commit `e0daa811`). Its five scenarios: approved assessment, native denial, source absent before dispatch, source absent before output, invalid response with reopen and no extra call. Also `test/extensions/knowledge/shadow_experiment_session_test.exs`, `shadow_pending_candidate_session_test.exs`, `shadow_allowance_trace_session_test.exs`, and `test/dev/evaluation/candidate_assessment_session_test.exs` | **Open.** On 2026-11-09 the operator decided that closing P30D means the same scripted synthetic journeys on current source: port the selection checkpoint into a current `dev/verification` verifier, and rerun it and `pending_shadow_installed.exs` on a Linux package built from the accepted source. Both consumers have source integration and installed synthetic Linux checks. Both installed runs used archives built from much older source (2026-11-03 and 2026-11-05). The assessment verifier is current and could be rerun on a new package. The five-phase selection checkpoint has no current runnable verifier: its record calls its sources "historical source references, not permission to run either fixture". It also calls itself "not an out-of-box answer extension or a standalone public evaluation command". This work is local, so the external-unavailability rule does not cover it. macOS installed coverage is not required (see below) |
| P30E | Frozen declarations and scoring, protected answer projection, an exact-action materializer, and "Freeze per-consumer quality, abstention, latency and cost bars before evaluation." Remaining plan gate: "Independent labels, matched real-input experiments and whole-task time/cost" | `test/dev/evaluation/freeze_test.exs`, `score_test.exs`, `decision_metrics_test.exs`, `protected_answer_test.exs`, `candidate_assessment_test.exs`, `candidate_expected_decision_policy_test.exs`, `selection_critical_pairs_test.exs`, `test/dev/selection_experiment_test.exs`. The freeze mechanism is tested at `candidate_assessment_test.exs:120` and `test/dev/selection_experiment_test.exs:373`. The [pending-assessment materializer](../2026-10-26-p30-p31-implementation/candidate-assessment-materializer-20261106.md) rejects non-independent labels | **Qualified for the experiment.** The draft found the bars incomplete: selection had no abstention bar and assessment had only `finite_cost_cap`. On the operator's 2026-11-09 decision both were added: selection fails when the candidate abstains on more than five percentage points more cases than the baseline, and assessment fails when whole-task cost (baseline plus decision call) exceeds the baseline by more than a fifth; missing or zero baseline cost leaves it unverified (`dev/evaluation/decision_metrics.exs`, tested in `test/dev/evaluation/decision_metrics_test.exs`). Assessment abstention stays report-only because abstaining keeps the baseline. For the experiment itself, the engine is the binding external dependency. No real engine is available: the loopback is a synthetic fixture and no account was supplied. Labels and whole-task time/cost only matter once an engine run exists. No experiment completed, so benefit and no-benefit are both unestablished |

### Platform reading for P30D

The plan asks that evidence "Distinguish fixtures, live provider/account checks,
installed artifacts, hosted macOS and local macOS evidence". It does not require
every platform. Both consumers operate on native notes. The
[operator manual](../../operator/knowledge-permissions.md) admits those writes
only on the reviewed Linux protected-storage profiles; "other kernels and macOS
remain unsupported". This draft therefore reads macOS installed decision
coverage as not required for P30's local scope, and records it as unverified.

The installed planning-decision verifiers
(`dev/verification/planning_decision_installed.exs` and
`assistant_planning_decision_installed.exs`, with the
[assistant planning record](../2026-10-26-p30-p31-implementation/assistant-planning-installed-20261107.md))
cover P31 operator and assistant planning decisions. They make no decision-engine
call, so this draft does not count them as P30D evidence.

## Engine and consumer disposition

Every cell is **no qualified default**. No consumer becomes selectable.

| Consumer | OpenAI Decisions | TypeSafe System One / Jev | Explicit compatible loopback |
| --- | --- | --- | --- |
| Bounded note-pack selection | No qualified default. Verified: request/response wire subset with synthetic keys. Unverified: account access, eligibility, quality, matched time and cost | No qualified default. Verified: request/response wire subset with synthetic keys. Unverified: account access, eligibility, quality, matched time and cost | No qualified default. Verified: synthetic protocol in source and in an older scripted Linux package (`f0274bb5…`). Unverified: current-source installed runtime, any real engine, quality, matched time and cost |
| Pending-proposal assessment | No qualified default. Verified: wire subset, including per-question refusal, with synthetic keys. Unverified: account access, eligibility, quality, matched time and cost | No qualified default. Verified: wire subset with synthetic keys. Unverified: account access, eligibility, quality, matched time and cost | No qualified default. Verified: protected synthetic protocol in source and in an older Linux package (`678b446a…`). Unverified: current-source installed runtime, any real engine, quality, matched time and cost |

## What this does not establish

- Model quality, usefulness, calibration of abstention, or advice correctness
  for any engine. Protocol success is not model quality.
- Benefit or lack of benefit. Scripted fixtures establish neither.
- Account access, eligibility, live billing, pricing accuracy or regional
  processing for OpenAI Decisions or TypeSafe System One / Jev.
- That operator-entered pricing, region, retention or account-control
  disclosures reach the approval display.
- The existence or behavior of a real local SystemOne-compatible engine.
- Comparative latency or whole-task cost, which remain null rather than zero.
- A default, automatic or selectable decision strategy for any consumer.
- Installed behavior of the current source, installed use by an independent
  person, or any macOS installed or native-storage behavior.
- P31 completion, or the 2,000-note cohort and other opt-in workloads, which
  were excluded from every baseline.

## Remaining before acceptance

1. Independent review of this draft against the plan and cited evidence. The
   first review approved it with the required changes applied here.
2. P30B consent clause: accepted by the operator as a limitation
   (2026-11-09). Disclosures remain optional operator strings, only the empty
   state is tested and no verified account-control state exists.
3. P30D installed workflows (open). Write a current runnable selection
   verifier, then rerun it and `dev/verification/pending_shadow_installed.exs`
   on a Linux package built from the accepted source. The operator should also
   confirm the platform reading above.
4. P30E bars: added on the operator's decision (2026-11-09). The operator
   should confirm that the engine is the binding external dependency for the
   experiment.
5. Checks on the source being accepted: the full baseline, `./bin/ipse demo`
   and `./dev/package.sh`. The latest full Linux suite did not include
   `7736b5db`.
6. Operator sign-off. After that, the plan's P30 status and next result are
   updated, and this record's draft marking is replaced by the accepted
   disposition.
