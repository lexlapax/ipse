# Development plan

Ipse is an Apache-2.0-licensed general-purpose local AI harness. Its core stays in
Elixir/OTP, with Rust for small OS helpers; target projects may use any suitable
stack. Prefer extensions, tools and inert skills for domain features, ordinary
OTP for ownership, and reviewed generic core changes for missing host invariants.
No mandatory workflow framework, external service or database. Integrations use
explicit provider/service selections and their documented endpoint policy.

This document owns priorities, scope and acceptance. The
[documentation map](index.md) owns navigation. The [user manual](operator/index.md)
teaches operation; the [contributor manual](developer/index.md) teaches implementation
and verification. Dated test counts, receipts and investigations live in the
[archive](archive/index.md), including the
[verification record](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks)
preserved before the manual rewrite. The
[previous plan and knowledge design](archive/2026-10-17-before-self-hosting-review/index.md)
are preserved with provenance.

## Current priorities and status

The requested whole-repository
[semantic documentation remediation](archive/2026-10-25-prepublication-docs/index.md)
is complete, with local example/archive/installed checks and the full hosted
Linux/macOS matrix at `5daf5d0`. On explicit developer authorization, the stable
tag and unpublished draft were replaced with the audited candidate `341e458`.
Its complete Linux/macOS release workflow and exact re-downloaded assets pass
[verification](archive/2026-10-25-prepublication-docs/release-reconciliation.json).
The developer then explicitly authorized publication. [v0.1.0](https://github.com/lexlapax/ipse/releases/tag/v0.1.0)
was published as the latest release on 2026-10-25, with the same four inspected
assets ([publication receipt](archive/2026-10-25-prepublication-docs/publication.json)).
Qualified readiness retains its recorded human/live limits.

| Milestone or gate | Current state | Next result |
| --- | --- | --- |
| P0–P22 | Complete within [the scopes below](#completed-milestones-p0p22) | Preserve their invariants when extending the host |
| [P23: accounting and budgets](#p23-usage-cost-reporting-and-budget-controls) | Complete within one-shot text/accounting scope | Keep later embedding and provider coverage separately identified |
| [P24: architecture/security readiness](#p24-independent-architecture-validation-and-baseline-security) | Accepted for supervised P25 at `375e607` | Preserve the scoped verdicts and accepted same-user storage limit |
| [P25: comparative self-development](#p25-comparative-research-and-supervised-self-development) | Accepted within declared supervision/assistance at `3307563` | Preserve frozen inputs, failures and bounded comparison claims |
| [P26: memory baseline](#p26-optional-working-and-long-term-memory) | Explicit-note scope accepted at `25f1d8e` | Productize automatic memory under P31 without changing this historical acceptance |
| [P27: research, graph and RAG](#p27-optional-research-graph-and-rag) | Optional-package scope complete; hybrid qualified and selected | Evaluate new workloads independently; retain all seven strategies' original results |
| [P28: operator usability and release](#p28-operator-usability-and-release-readiness) | v0.1.0 published at `341e458` under qualified acceptance after semantic documentation remediation and exact asset inspection | Retain human/live qualifications; evaluate subsequent changes against their own scope |
| [P29: provider registry, OpenRouter and Gemini](#p29-provider-registry-openrouter-and-gemini) | Original scope and repairs accepted for qualified readiness; added Grok routes pass automated checks | Preserve unverified Grok API/OAuth eligibility and Gemini foreign-history live acceptance |
| [P31: usable knowledge and prompt assistance](#p31-usable-knowledge-and-prompt-assistance) | Implementation authorized; local host, permission and capture components in progress | Sustainable metadata, current recall, lifecycle and integrated qualification remain open |
| [P30: decision engines](#p30-advisory-decision-engines) | Typed/protocol and bounded protected-consumer increments in progress; no qualified production strategy | Verify full B baseline; C–E integrate with P31B/E, without waiting for PDF/graph |
| [P32: voice and media](#p32-voice-and-realtime-media) | Deferred; unimplemented; formerly P31 | Select media contracts and device/service validation in a later increment |
| [Apache-2.0 transition](#license-transition) | Complete at `7bb642b` | Preserve runtime, dependency and extension license boundaries |

[Saved-session diagnosis](operator/recovery.md#find-the-original-session) reports
an aggregate count of unknown extension actions and excludes a validated current
pending question. Resume warns about unknown outcomes and withheld managed
questions. Nine focused synthetic controls pass on the combined source; a
managed test attempt on unsupported Btrfs failed during setup and its fixture is
retained. An earlier filtered baseline finished with one native-helper boundary
fixture failure; the final combined-source baseline remains open.
Declined `recall_many`, opt-in native integrated cases and skipped platform
coverage remain unqualified.

### Execution order for P30 and P31

Work in the lanes below can proceed in parallel when their file ownership and
verification resources do not conflict. A dependency says which implementation
must exist before an integrated result is possible; an unrun test or review is an
open evidence gate, not a reason to defer unrelated implementation. Finish a
lane's observable journey and its stated checks before calling that lane done.

The notes journey remains a required acceptance gate, but the operator declined
the proposed retained-notebook recall check. That check and equivalent replacement
consumers remain off limits, as detailed in the notes lane below. Continue the
independent document, decision-consumer and verification work without treating
that refusal as a completed notes test. Do not continue the annual storage-only
calendar as a substitute for the integrated workload: its missing Session turns
and intake/mix evidence remain required.

Close the following concrete results in order within each lane. Independent
lanes can proceed together; the arrows identify actual implementation dependencies.

| Order and owner lane | Current task and subtasks | Closure evidence still needed |
| --- | --- | --- |
| Documents 1 | Complete within bounded source-runtime scope: public saved-result publication, unbound Job creation, vector preparation, explicit input binding, append and finalization. The synthetic public Session journey, focused checks and manual review pass; the earlier fixture assertion failure is preserved | Larger groups, installed use and full capacity have separate gates below |
| Documents 2 → 1 | Complete within bounded source-runtime scope: ordered saved-result assembly, one shared 512-read budget and duplicate refusal. The [eight-source/160-fact public journey](archive/2026-10-26-p30-p31-implementation/document-fact-assembly-public-20261106.md) passes through append/finalization and six closed/idle Sessions | Full capacity, installed use and all maximum-value combinations retain separate gates |
| Documents 3 → 2 | The [initial developer model](archive/2026-10-26-p30-p31-implementation/document-initial-public-model-20261106.md) completed the fixed initial target with mocked replies and an independently reconciled trace. Complete the remaining recipe: declared replacement, retained history, cleanup and migration | Measure actual native journal/allocation peaks and lifecycle controls under unchanged limits; modeled replies do not qualify actual execution or capacity fit |
| Notes | Current recall, one complete populated day, then the declared annual workload with 10,000 mixed changes. The original retained check is declined; populated recall and integrated endurance remain unqualified | Authorized evidence for those gates; preserve all 2,100 original operations and unknown outcomes without replay or a substitute consumer |
| Decisions | The [separate reference/review contract](archive/2026-10-26-p30-p31-implementation/p30-selection-review-v2-20261106.md) and [current-package synthetic v2 lifecycle](archive/2026-10-26-p30-p31-implementation/p30-paired-selection-v2-20261106.md) pass their scoped controls, including actual first rows and later unmeasured review. Keep useful, rejected/no-benefit and unverified outcomes distinct | Current complete baseline and a reviewed disposition for each engine and consumer. Qualifying a strategy or reporting a negative result needs the applicable independent quality labels and matched time/cost; unverified access remains unverified. Synthetic protocol success alone is insufficient; no qualified default or engine/account claim |
| Verification | Repair specific hosted/source/installed failures. Draft child counters now have a separate local pass; native filesystem admission and macOS/installed outcomes remain open | A current complete source baseline, supported platform checks, fresh package and installed journeys; no blanket skips or widened native profile |
| Final → all required gates | Reconcile remaining P31 integration/lifecycle/qualification items, whole operator/developer manuals, adversarial audit and reviewer handoff | Exact candidate checks and an explicit disposition for every remaining acceptance item; no milestone completion from component passes |

The earlier [combined source regression](archive/2026-10-26-p30-p31-implementation/combined-source-regression-20261104.md)
passed all six bounded chat controls but finished with 26 failures and 52 invalid
cases. Fresh [focused controls](archive/2026-10-26-p30-p31-implementation/focused-source-regression-20261104.md)
now pass for all of those failed or blocked cases. A separate actual
[same-ID follow-up](archive/2026-10-26-p30-p31-implementation/chat-same-id-followup-20261104.md)
also completes after current recall while preserving the original tool call and
native continuation. The [terminal 473-file regression](archive/2026-10-26-p30-p31-implementation/source-regression-groups-20261104.md)
ended 4,018/4,019 passed, 128 skipped and 123 excluded, with all eleven integrity
checks passing and no invalid cases reported. Its original owner-loss assertion
remains failed; a [fresh confirmed-native-exit control](archive/2026-10-26-p30-p31-implementation/source-owner-loss-causal-20261104.md)
passes both the corrected causal witness and unchanged native source guard.
These separate outcomes do not form a retroactive all-green aggregate. A newer
[frozen 477-file regression](archive/2026-10-26-p30-p31-implementation/source-regression-477-20261104.md)
against `9b1a4e5e` ends 4,028/4,029 passed, 130 skipped and 123 excluded, with
all 44 group integrity checks passing and no invalid cases. Its sole stale Graph
catalog fixture failure has a separate later focused pass; this aggregate remains
failed. A [later frozen 478-file run](archive/2026-10-26-p30-p31-implementation/source-regression-478-20261104.md)
against `18e3e0b1` ends with 4,048 passed, one failed and one invalid; all 44
integrity checks pass. Separate capacity and Research fixture repairs now pass
their focused controls, without reclassifying that aggregate. Later timer,
fetched-Research and coalesced-reader changes retain their
focused evidence outside that freeze. The committed-runtime retained-cohort
checks remain open before notes acceptance.

The later [517-file frozen regression](archive/2026-10-26-p30-p31-implementation/full-regression-3d409619-20261107.md)
completed with 4,318 passed and one failed, plus 136 skipped and 125 excluded.
The failed small synthetic recall fixture and a companion race pass separately
after the expectation repair; those focused results do not change the aggregate
or qualify later source changes. The operator-declined retained notebook remains
untouched, and its integrated acceptance gate remains open.

The earlier [489-file attempt](archive/2026-10-26-p30-p31-implementation/source-regression-489-20261106.md)
was interrupted before its coordination deadline, with 13 known outer failure
headers and no final test exit or totals. Later immutable-copy and independent
host cleanup checks pass. Separate [Word setup](archive/2026-10-26-p30-p31-implementation/word-cli-recipe-v18-20261106.md)
and [evaluation isolation](archive/2026-10-26-p30-p31-implementation/evaluation-domain-isolation-20261106.md)
controls now pass their focused cases. They do not complete that interrupted
run or establish a current full-source baseline.

The [budget reservation correction](archive/2026-10-26-p30-p31-implementation/budget-reservation-pre-slot-20261106.md)
reserves before inference-service selection and waiting, preserving full liability
when the provider callback does not start. Fifty focused tests and independent
source review pass. Preparation failures before this dispatch path can still
leave unmatched admissions that fail closed; historical ledgers remain unchanged.

The [CI readiness repair](archive/2026-10-26-p30-p31-implementation/ci-runner-formatter-readiness-20261106.md)
restores the canonical Elixir 1.18 formatting check and replaces the retired
macOS runner image. Its local formatter and policy checks pass; a new hosted
full-source baseline and remaining platform/installed checks remain open. The
[Linux package job at `6e5e4bdc`](archive/2026-10-26-p30-p31-implementation/ci-azure-storage-diagnosis-20261106.md)
passes its listed build and synthetic installed checks; it is not the full suite.

The [hosted Azure diagnosis](archive/2026-10-26-p30-p31-implementation/ci-azure-storage-diagnosis-20261106.md)
records an actual `7.0.0-1017-azure` Linux runner rejected by the current native
kernel profile. Filesystem qualification, separate terminal/MCP failures and
the macOS unknown installed Memory action remain open; no profile was widened.
At `6e5e4bdc`, all four hosted Ubuntu source partitions failed with filesystem
refusals and other unresolved failures; macOS jobs remained queued when
inspected.

The [hosted source-test partition change](archive/2026-10-26-p30-p31-implementation/ci-source-partitions-20261106.md)
assigns every default test file to one of four jobs per OS after an unpartitioned
job reached its existing time limit. Platform and installed checks retain their
own job; draft admission requires both complete matrices. Fifteen focused release
controls pass. Hosted execution remains open, with no reduced coverage or longer
job deadlines.

[Bounded native terminal buffering](archive/2026-10-26-p30-p31-implementation/operator-buffered-input-20261106.md)
addresses per-byte polling after hosted macOS input controls timed out. Twenty-two
native and nine existing host/input controls pass on Linux, retaining the same
input ceiling and deadlines. A new hosted macOS result remains required.

A [schema-validator update](archive/2026-10-26-p30-p31-implementation/schema-validator-security-20261104.md)
replaces the newly retired JSONSchex version with 0.11.1 and its required pointer
dependency. The closed schema subset remains unchanged; focused checks and the
normal build pass. Final source/package qualification must use this updated graph.

Separate [P30 current-use controls](archive/2026-10-26-p30-p31-implementation/p30-advice-output-revocation-20261104.md)
pass settled-output revocation and the proposal's own signed seven-day expiry
under a fresh day-eight grant. The old service-alias fixture failure remains
preserved. A [later simultaneous committed-preflight cohort](archive/2026-10-26-p30-p31-implementation/p30-simultaneous-preflight-20261104.md)
reaches both real reserve/fits paths and excludes a second call, but its winner
fails before dispatch and remains unknown. A separate
[simultaneous-entry and quiescent-recovery cohort](archive/2026-10-26-p30-p31-implementation/p30-simultaneous-settlement-20261104.md)
now completes one known settled decision and both confirmed-close/idle/no-replay
paths under a shared one-call allowance. Its loser encounters native-control
contention before a fit check, so this cohort does not establish budget-driven
denial. The earlier fast refusal remains unidentified; current-main integrated
regression and consumer quality remain open.

A [bounded helper-context increment](archive/2026-10-26-p30-p31-implementation/model-context-v4-20261105.md)
now carries complete evidence separately from the question under unchanged SDK
and request limits. Seventeen ModelCall and 91 related host tests pass. Native
current approval and denial pass in a failed four-case run; separate fresh
source-withdrawal and interruption cases pass with retained accounting, source
fences, signed close and idle no replay. The failed aggregate remains separate;
real matched answer/citation quality, installed use and full P30 remain open.

The [evaluation adapters](archive/2026-10-26-p30-p31-implementation/p30-evaluation-adapters-20261105.md)
now supply frozen assessment declarations, an OFF Session materializer and
protected baseline/candidate answer projection. Fifty-nine focused development
checks pass. A later [synthetic paired protocol](archive/2026-10-26-p30-p31-implementation/p30-paired-protected-answers-20261105.md)
qualifies eight eligible protected reads, the actual six-note ordinary baseline
frozen before selection, and a four-note candidate across three main, two helper
and one decision wire. Complete inherited unions, current release/cleanup,
accounting, Saved/close/idle and no replay pass. The adopted version-2 source
passes 61 focused tests and the working integration build. Independent labels,
whole-task time/cost, model quality and standalone evaluation remain open.
The later packaged checkpoint below covers its disclosed synthetic CLI path;
broader installed-user qualification remains open.

The [explicit helper-route CLI increment](archive/2026-10-26-p30-p31-implementation/p30-combined-helper-route-20261105.md)
now supports reviewing a separately admitted answer profile alongside main and
advice before capture. All 58 CLI/Knowledge tests pass, including native save,
new-Session identity pinning and refusal after a configuration change during
review. The earlier fixture assertion failure remains recorded separately.
The [packaged CLI paired checkpoint](archive/2026-11-05-packaged-paired-cli/index.md)
now passes all five synthetic phases on the exact aa1c Linux package: native
review establishes the final helper routes before eight eligible notes produce
the complete six-note baseline and four-note projection. All immutable guards
and independent host cleanup pass. Earlier fixture failures remain distinct.
Independent quality, comparative time/cost, standalone evaluation and broader
installed-user workflows remain open; the helper is a separately supplied test
artifact, and this option supplies no bundled answer extension.

For each active lane, name the next end-to-end result, its owner, required inputs
and observable pass/fail checks. Use focused tests during implementation; preserve
failures and stop repeating a probe when it does not resolve the user journey.
Revisit the design when a boundary or workload makes the current approach
insufficient. Serialize native/Mix/PTY checks until independent build and runtime
isolation is verified; run the long full suite on a stable integration candidate
and again after material repairs, rather than after every small edit. Publish a
checkpoint with completed work, the next gate and remaining uncertainty. Give
time estimates only after measuring the integrated workload and available capacity.

The previous approach produced many useful safeguards but too few completed
user journeys. Repeated large probes and storage-only progress did not establish
that populated recall works or that the annual workload is practical. Apply the
following limits until the end-to-end paths are qualified:

- Keep one owner on the notes journey, one on the bounded pilot/workload, and
  at most one on an independent end-to-end slice. The integration owner closes
  and reviews each result before starting replacement work. Separate source
  ownership does not make native-helper, Mix or terminal tests independent.
- Investigate the populated recall failure with a small disposable fixture and
  phase evidence first. Preserve the unknown outcome and existing source,
  deadline and no-replay checks. Stop repeating a failing probe without a new
  hypothesis; repair and retest the identified boundary before another full day.
- Freeze the pilot-derived or explicitly provisional intake, then measure one
  complete populated day, including turns and effects. Use its real elapsed time
  and resource peaks to assess whether the 30-, 90- and 365-day runs are feasible
  before launching them. If not, redesign the workload execution while preserving
  the specified coverage and real safety boundaries; do not count simulation or
  storage-only segments as completed Session turns.
- A checkpoint is complete only when its actual user journey, failure and recovery
  cases, focused checks, documentation and independent review are complete.
  Keep remaining milestone gates visible rather than treating a passing fixture,
  preflight or source audit as acceptance. No delivery date is established until
  the integrated day has been measured.

1. **Notes journey — P31B/C0/D0/E.** Finish protected capture, current recall and
   their failure/recovery paths, and implement the displayed assistant-proposal
   card and exact in-chat acceptance. The result must exercise the actual Session,
   terminal, source ownership, saved consent and provider request, including stale
   sources, revocation, owner loss and resume without replay. Recall must find
   fitting eligible notes even when earlier indexed notes are unavailable; merely
   raising a fixed candidate limit does not establish that coverage. Any paging
   or discovery design must retain current-source and ownership checks. The notes
   release checkpoint additionally depends on C1a below; a small fixture alone
   does not close it. [Bounded fitting-note selection](archive/2026-10-26-p30-p31-implementation/recall-fitting-selection-20261106.md)
   removes the early stop when accumulated notes exceed the allocation, within
   the existing projection and host limits, and skips value reads below the
   minimum note-item frame. Synthetic mocked controls pass; actual-host and
   integrated workload qualification remain open. A [pending-read containment](archive/2026-10-26-p30-p31-implementation/pending-source-containment-20261103.md)
   now refuses unclassified managed values rather than exposing a proposal after
   loss of its source. It also temporarily refuses generic reads of saved
   overrides and unrelated managed values; a safe compatible path remains open.
   Current native retention review binds one existing note, whereas a saved
   override would apply to future captures for a lineage. The former is not
   approval of the latter: restoring override reads needs an authenticated
   choice for that exact wider scope and matching replay/current-use checks.
   [Recorded generic reads](archive/2026-10-26-p30-p31-implementation/managed-read-replay-containment-20261103.md)
   now apply the same classification during reconstruction, so affected older
   Sessions fail closed rather than using a root-only receipt; receiptless
   historical lineage remains a separate limitation.
2. **Sustainable notes — P31A/C1a.** Complete the pilot evidence within its
   authorized bounds, record unavailable routes, and freeze intake and retention
   mix. Then run the integrated 30-, 90- and 365-day
   workload with actual Session turns and protected lifecycle effects. Include
   two overlapping OS processes, offline/restart and import scenarios,
   representative and maximum values, retained history and suppression, and
   measured resource peaks. The selected requirement is **10,000 mixed
   update/correct/forget changes in addition to normal annual work**. The current
   audited continuation covers three simulated storage-only days, 172 effects and
   82 additional changes; it has executed **zero of 14,600 planned main turns**.
   A separate [seven-note integration smoke](archive/2026-10-26-p30-p31-implementation/integrated-final-smoke-20261102.md)
   completed 40 actual Session turns with four native effects; it does not count
   toward that annual continuation. Neither is annual acceptance. The next
   checkpoint is a fresh 2,000-note cohort and one full integrated day after the
   intake/mix is frozen and its assumptions distinguished from pilot evidence.
   A [separate full-day runner preflight](archive/2026-10-26-p30-p31-implementation/integrated-full-day-preflight-20261102.md)
   checks the provisional calendar and restart guards; it does not establish a
   populated seed, integrated day or representative intake.
   A [fresh populated run](archive/2026-10-26-p30-p31-implementation/integrated-full-day-failure-20261103.md)
   seeded and audited 2,000 notes, then closed 14 ordinary day effects before
   its first turn failed during recall. It completed zero day turns and remains
   a separate incomplete run, not an additional annual-acceptance result.
   A [separate read-only diagnostic](archive/2026-10-26-p30-p31-implementation/retained-probe-20261103.md)
   also stopped before inference with an unknown Worker-input outcome; its
   cause remains unproven and neither failed turn is replayed. A later
   [traced distinct Session](archive/2026-10-26-p30-p31-implementation/retained-worker-trace-20261103.md)
   measured two slow protected observations before another unresolved handoff;
   it did not establish the earlier failures' cause. A subsequent
   [fresh 2,000-record candidate run](archive/2026-10-26-p30-p31-implementation/populated-recall-d739-20261103.md)
   completed its seed and audit but ended with another unknown Worker input
   before inference. The batching candidate therefore has not fixed populated
   recall, and the new uncertain turn is not replayed. A later
   [combined coalescing increment](archive/2026-10-26-p30-p31-implementation/worker-v4-coalescing-bde96-20261103.md)
   passes focused signed-batch, source-owner and P30 compatibility controls;
   a subsequent [real synthetic 33-note Session](archive/2026-10-26-p30-p31-implementation/recall33-one-shot-20261103.md)
   delivered all 37 Worker inputs and recorded 32 included notes with partial
   coverage, but failed before the loopback provider received a request. Its
   failure reason is unknown. A later [generic-use batching candidate](archive/2026-10-26-p30-p31-implementation/generic-v4-batching-dcbb-20261103.md)
   passed smaller controls without raising deadlines but did not make a
   [fresh combined-source 33-note attempt](archive/2026-10-26-p30-p31-implementation/recall33-combined-dcbb-20261103.md)
   succeed; it was withdrawn from current source. The 33-note journey and
   populated recall remain unqualified by those multi-source attempts. A later
   [current canonical positive](archive/2026-10-26-p30-p31-implementation/current-canonical-recall-20261104.md)
   delivers all 33 short notes from one original source Session to a new consumer
   with complete coverage, strict Saved reconstruction and confirmed close.
   A later [strict 33-original control](archive/2026-10-26-p30-p31-implementation/recall33-strict-sources-20261104.md)
   separately passes with one source missing during recall and restored before
   preflight, 32 exact eligible note parts and unchanged original identities.
   The retained-cohort gate remains open.
   A [fresh egress diagnostic](archive/2026-10-26-p30-p31-implementation/egress-diagnostic-dcbb-20261103.md)
   reached managed-current use after a successful gate, but missing terminal
   markers leave its failure cause inconclusive. A [small source-owner comparison](archive/2026-10-26-p30-p31-implementation/source-owner-phase-20261103.md)
   measured cache-inclusive source-index and source-lock costs in one fresh
   eight-note run per case. Different source journals and unobserved cache hits
   limit the comparison; it does not identify the 33-note failure cause. A
   [guarded Saved-window reuse candidate](archive/2026-10-26-p30-p31-implementation/saved-source-window-fold-20261103.md)
   passed focused replay controls but a fresh strict 33-note attempt again failed
   before the loopback fixture read a request. The candidate was not promoted. A
   [local pilot launcher preflight](archive/2026-10-26-p30-p31-implementation/pilot-local-preflight-20261103.md)
   passed 27 synthetic controls without model calls; live results and independent
   semantic labels are still missing. Its first local launch
   [refused before any recorded reservation or inference](archive/2026-10-26-p30-p31-implementation/pilot-local-refusal-20261103.md);
   the observed account-directory mode explains the refusal under the tested
   code, though the generic error did not identify its failing check.
   The [synthetic workload listener repair](archive/2026-10-26-p30-p31-implementation/workload-listener-20261103.md)
   removes a fixture-only idle timeout, with local lifecycle and one unpopulated
   Session compatibility check. It does not resolve the populated recall failure
   or complete an integrated day.
   The [canonical encoding optimization](archive/2026-10-26-p30-p31-implementation/recall-canonical-encoding-20261103.md)
   preserves historical digests and reduces measured retained-source reconstruction
   cost, with current-host strict compilation and 39 focused tests. Its fresh
   33-note control still failed before provider dispatch; the fixture skipped the
   separate error notification. The subsequent [scope-ownership repair](archive/2026-10-26-p30-p31-implementation/recall-owned-cache-20261103.md)
   captures that diagnostic, preserves a single pure reconstruction cache across
   the admitted task, inference-slot and controlled-child scopes, and passes 75
   focused controls. A later [fresh strict 33-original-source control](archive/2026-10-26-p30-p31-implementation/recall33-strict-sources-20261104.md)
   now passes at the unchanged five-second provider limit in 125 seconds, with
   exact full text and committed-read provenance for all 32 eligible notes,
   partial missing/reappearing-source coverage, unchanged original journal/lock
   identities and idle reopen without replay. This closes that fitting-set case;
   earlier failed attempts remain preserved. Next qualify a distinct read against the retained
   2,000-note cohort, then one complete populated day before the annual workload.
   The [retained-cohort recovery pair](archive/2026-11-05-retained-recovery/index.md)
   now closes the stopped request's admission marker and renews permission on
   the frozen committed runtime. Both independent audits pass, preserving all
   2,100 operation records, unknown usage, sources and six inert consumers during
   the lossless control-format upgrade. Four subsequent current-source proofs
   pass separately. A later read was interrupted; its independent preservation
   observation finds unchanged original bytes and no new registered dispatch,
   without qualifying recall. A fresh ordinary read and the measured day remain
   open; no old consumer is resumed. The operator explicitly declined the later
   proposed recall check on this retained notebook. Preserve that refusal and
   the original 2,100 operation records and unknown outcomes; do not run that
   check, renew access for it, or substitute another consumer as a workaround.
   A separate fresh synthetic [rejection follow-up diagnostic](archive/2026-10-26-p30-p31-implementation/rejection-diagnostic-setup-20261106.md)
   stopped during bundle setup before rejection or inference; it did not identify
   the earlier refusal or qualify recapture suppression.
   A [native renewed-recall control](archive/2026-10-26-p30-p31-implementation/authenticated-expired-recall-20261104.md)
   now passes after narrowly classifying authenticated expired ordinary neighbors,
   preserving current permission and original-source gates. Two later retained-cohort reads on c8245f87 remain failed: the first
   has unconfirmed cleanup at its 22nd Worker input; a separate traced read
   confirms cleanup but reaches the unchanged 120-second Host deadline. The
   [paired native reader checkpoint](archive/2026-10-26-p30-p31-implementation/recall-paired-native-reader-20261104.md)
   preserves both outcomes, qualifies bounded root-identity reuse and paired
   storage observations, and records an instrumented private storage improvement.
   A fresh paired-worker check passes on eight original sources. A new ordinary
   retained read on that runtime reaches 30 delivered Worker inputs before a
   protected-share ownership failure; its 31st input remains unknown and no
   provider request occurs. A [separately reproduced stale-timer repair](archive/2026-10-26-p30-p31-implementation/share-stale-timeout-20261104.md)
   prevents a completed share's late timeout from poisoning the next share. It
   does not identify the retained read's trigger. Successful ordinary retained
   recall, a complete populated day, annual throughput and full notes acceptance
   remain open.
   A [coalesced notes observation candidate](archive/2026-10-26-p30-p31-implementation/coalesced-worker-readview-20261104.md)
   now reuses one bounded index per protected pass. Its fresh complete current
   build, 33 backend cases including genuine native capacity fallback, and one
   actual eight-source Worker case pass separately. Ordinary retained recall
   remains open; the component timing sample does not establish annual feasibility.
   A [managed event replay repair](archive/2026-10-26-p30-p31-implementation/managed-event-withdrawal-replay-20261104.md)
   authenticates confirmed withdrawn output as a failed job despite successful
   earlier reads. Six pure controls, 36 integrated cases and in-place reconstruction
   of 207 actual events pass without replay or changes to the originals. The failed
   partial read and quarantined reservation remain unchanged.
   A [separate ordinary final-use repair](archive/2026-10-26-p30-p31-implementation/ordinary-final-coalescing-20261104.md)
   reuses that existing coalesced observer in both independent protected passes.
   A storage-only 32-record comparison reproduces the unchanged five-second
   DomainAuth callback expiry in the per-record route while coalesced succeeds;
   it does not directly trace the earlier Session failure. Forty-three pure
   checks, a fresh actual eight-source delivery/Saved/close/idle case, and separate
   current-main root-withdrawal controls pass. The first idle-mode fixture failure
   remains preserved. These changes do not qualify retained recall; the
   populated-day and annual driver remain OFF.
   A [lossless Consent v3 storage increment](archive/2026-10-26-p30-p31-implementation/consent-v3-storage-20261105.md)
   addresses a separate serialized-capacity failure: the specified 31,052 IDs
   fit the count cap but their old compacted rows exceed the write budget.
   Canonical disk-only digest/status packing preserves all accounting, unknowns
   and current full receipts; 22 focused storage/compaction/budget tests pass.
   The specified full-receipt geometry fits the unchanged maintenance cap.
   No original cohort is migrated by that result, and actual retained recall,
   populated-day resource measurement and annual feasibility remain open.
   Workload tooling can advance alongside the notes journey; the completed
   integrated workload depends on the Session and recall behavior it exercises.
3. **Documents and local retrieval — P31C1b/D1/F.** Independently finish document
   extraction, source-bound citation and installed acquisition/recovery journeys.
   In parallel, complete the document store's populated capacity, publication,
   cleanup and migration work. Final document and local-retrieval qualification
   depends on the applicable C1b storage and model contracts; Word may qualify
   separately from PDF. Word list markers need versioned source-faithful locator
   and storage contracts; generated numbering must not be presented as quoted
   source text. Check source replacement, interrupted work, exact original locators,
   installed artifacts and independent quality, not just parser fixtures.
   The [bounded completed-Collection restore](archive/2026-10-26-p30-p31-implementation/document-result-restore-public-20261106.md)
   now passes an actual 72-command public journey over eleven records in three
   pages: selected-result export/validation, approval denial, same-floor import,
   rollback, abort, checkpoint removal and closed/idle no-replay reconstruction.
   A separate [installed synthetic attempt](archive/2026-10-26-p30-p31-implementation/installed-backup-attempt-20261106.md)
   stopped at project identity admission with an unknown outcome and no public
   command receipts; its actor placed the project on unsupported workspace
   Btrfs. Installed backup remains unqualified and the attempt is preserved.
   Descriptor validation also rejects a rehashed nonempty lineage at floor zero,
   matching the existing restore-plan rule; eleven focused restore tests pass.
   [Partial retirement operation binding](archive/2026-10-26-p30-p31-implementation/document-retirement-operation-20261106.md)
   records a native operation/invocation join on newly admitted heads; a synthetic
   live Session control also joins its exact action and ledger receipt. The
   [live-owner follow-up](archive/2026-10-26-p30-p31-implementation/document-retirement-live-owner-20261107.md)
   refuses partial cleanup adoption by a resumed owner and conservatively limits
   multi-stage legacy cleanup. The current candidate imports live Session, Writer
   and source controls for the final switch; fresh synthetic positive Session and
   two-lock/refusal controls pass. Owner-loss and interrupted recovery remain
   unqualified, so an unconfirmed outcome still refuses automatic continuation.
   Ten host provenance controls, 24 domain/controller cases and the separate
   eight-test native migration file pass. This closes the bounded same-project
   increment, not changed-target recovery, installed migration, larger segmented
   sets, cleanup or full populated capacity. A [source-identity validation repair](archive/2026-10-26-p30-p31-implementation/document-backup-source-binding-20261106.md)
   rejects a rehashed catalog/head mismatch in focused synthetic restore validation
   and in an [installed direct-domain check](archive/2026-10-26-p30-p31-implementation/document-backup-installed-binding-20261106.md). A public native refusal journey for
   that malformed input remains open. Those remain the document
   critical path. Public supplied-fact publication, binding, append and eight-source
   assembly now pass their bounded Session journeys, and the refreshed public
   controller model completed its fixed initial target with modeled replies.
   A [one-source replacement model](archive/2026-10-26-p30-p31-implementation/document-replacement-model-20261106.md)
   passes focused selection, checkpoint and stop controls with modeled replies.
   A separate [synthetic Word Session check](archive/2026-10-26-p30-p31-implementation/document-replacement-session-20261107.md)
   covers one actual replacement, retained old blocks and idle reconstruction.
   The full replacement/history recipe, native journals, physical peaks, cleanup
   and migration remain open.
   Its [authoritative Job input-binding component](archive/2026-10-26-p30-p31-implementation/document-job-input-binding-20261106.md)
   now has closed opt-in formats, actual owner/source/revision guards and a
   native staged bind/append/abort check. Caller-editable continuation hashes
   alone do not freeze a chosen input. The
   [public supplied-result journey](archive/2026-10-26-p30-p31-implementation/document-fact-result-public-20261106.md)
   and [eight-source assembly](archive/2026-10-26-p30-p31-implementation/document-fact-assembly-public-20261106.md)
   qualify those bounded callers without establishing full capacity. Separately,
   [indexed Word row context](archive/2026-10-26-p30-p31-implementation/indexed-word-row-context-20261106.md)
   passes pure and one actual Collection Session control; installed and
   no-token-overlap quality remain open.
4. **Planning and prompt assistance — P31I.** Finish and qualify the existing
   planning and draft operator paths, including crash/resource boundaries and
   cancelled-draft carryover. The [operator-authored deferred decision](archive/2026-10-26-p30-p31-implementation/operator-planning-20261103/index.md)
   already has native review and a separate post-exit save; ordinary exit does
   not publish it. Assistant-proposed provenance and deferred save have bounded
   native controls; broader current-source and permission combinations remain
   open. The terminal work can proceed independently, but
   decision acceptance depends on the relevant P31E path, and retrieve-first
   clarification depends on the notes and document paths it uses. An
   [in-chat acceptance protocol plan](archive/2026-10-26-p30-p31-implementation/chat-acceptance-host-protocol-plan-20261103.md)
   records why the existing standalone management review cannot be reused as
   a Session-owned decision without new owner-bound handoffs. A later
   [architecture reassessment](archive/2026-10-26-p30-p31-implementation/chat-acceptance-reassessment-20261103.md)
   preserves the frozen post-reply requirement and pauses the unproven draft;
   a [reviewed guard design](archive/2026-10-26-p30-p31-implementation/chat-acceptance-session-guard-design-20261103.md)
   sets out the then-proposed owner and recovery checks. An [isolated native primitive](archive/2026-10-26-p30-p31-implementation/session-acceptance-native-primitive-20261103.md)
   has synthetic owner-loss controls. A [real-Session transfer discriminator](archive/2026-10-26-p30-p31-implementation/session-guard-owner-discriminator-20261103.md)
   passes in a test-only prompt-source fixture, but its wrong-recipient control
   remains unproven. The [clock-domain assessment](archive/2026-10-26-p30-p31-implementation/session-acceptance-clock-anchor-assessment-20261103.md)
   records why the native wall cutoff does not yet establish the existing
   BEAM-monotonic Review permit's lifetime through publication. A focused
   [terminal rounding repair](archive/2026-10-26-p30-p31-implementation/leased-terminal-quantization-20261103.md)
   removes a sub-millisecond conversion excess under compatible clocks; clock
   rate and suspend compatibility remain unproven. Those Session-owned native
   transfer proposals are superseded for normal chat by the
   [completed-reply close/review/resume path](archive/2026-10-26-p30-p31-implementation/chat-completed-reply-20261104.md).
   Exact turn-bound nomination, committed-answer capture and protected native
   acceptance now pass four bounded actual controls, including cancellation and
   stale selection. The original conversation closes before existing standalone
   management review, then resumes under the same ID after a confirmed outcome.
   A [fresh explicit-resume review](archive/2026-10-26-p30-p31-implementation/chat-explicit-resume-20261104.md)
   also passes a real cancel/exit/resume/accept journey, with a new code and
   separate accounting before the first ordinary chat prompt. A
   [planning-exit control](archive/2026-10-26-p30-p31-implementation/chat-planning-mode-20261104.md)
   now also passes native acceptance and idle same-ID normal reopening. The
   [first ordinary follow-up](archive/2026-10-26-p30-p31-implementation/chat-same-id-followup-20261104.md)
   now passes with active-source revalidation and an exact authenticated
   capture-to-acceptance historical-root mapping. Complete integrated
   qualification remains open.
   A separate [Anthropic text-only carryover control](archive/2026-10-26-p30-p31-implementation/anthropic-draft-carryover-20261104.md)
   now passes cancellation, an unrelated ordinary request, strict saved-history
   reconstruction and same-ID continuation through the actual synthetic Messages
   adapter. It preserves native history outside the withdrawn interval. The
   current signed-thinking extension passes 11 synthetic projection and request-body
   controls and a [synthetic Session/Saved test](archive/2026-10-26-p30-p31-implementation/anthropic-signed-draft-20261106.md)
   with a synthetic acceptance witness. A follow-up covers bounded opaque
   redacted-thinking blocks in the same no-tool path. It checks shape, not
   signature or opaque-data authenticity. OpenAI API draft withdrawal uses the
   existing stateless Responses isolation and historical selector; focused
   synthetic projection, transport and reconstruction controls pass.
   Anthropic tool-bearing drafts have subsequent synthetic source controls;
   broader provider coverage, installed/native-terminal qualification and
   integrated clarification remain open.
   A [synthetic Ollama tool-assisted control](archive/2026-10-26-p30-p31-implementation/ollama-tool-draft-20261107.md)
   also covers isolated native tool calls and results across cancellation and
   acceptance; live and installed qualification remain open.
   [Synthetic provider carryover controls](archive/2026-10-26-p30-p31-implementation/p31i-provider-draft-carryover-20261107.md)
   cover cancelled Chat Completions and xAI draft tool intervals through ordinary
   continuation and same-ID restoration on isolated loopback fixtures. The
   combined candidates pass eight projection and five Session controls.
   One earlier malformed-fixture setup failed and remains recorded; installed, live
   provider and final integrated qualification remain open.
5. **Decision engines — P30A–E.** Complete the host protocol and protected
   consumer integration independently of document/graph work. Enforce the explicit
   finite allowance across the whole authorized experiment, using the existing
   shared budget and one durable run if sufficient; a per-Session budget alone
   does not prove a cap across separate Sessions. Review the grant and explicit
   artifact/route setup before enabling calls. After the notes journey supplies the required
   consumer, run the frozen bounded experiments and compare them with engine-free
   baselines. Close each with a supported, rejected/no-benefit or explicitly
   unverified disposition as allowed by P30; live account evidence and paid calls
   remain subject to their separate bounds.
6. **Relationships and research — P31G/H.** Once their required note and storage
   contracts are stable, implement source-bound relationships, conflicts and
   evidence transfer with attribution and invalidation. Integrated relationship
   acceptance follows E and uses C1b where graph storage is selected; transfer
   must qualify each store it actually uses rather than assume an optional backend
   is available. Graph currently revalidates stored sources but does not recheck
   acquired workspace files before using their facts or returning citations;
   that current-use path remains open. The [source investigation](archive/2026-10-26-p30-p31-implementation/graph-workspace-and-retirement-boundaries-20261107.md)
   identifies the missing durable Corpus-to-Graph authority and the separate
   extraction and publication decisions. Do not create placeholder implementations
   while those contracts are unsettled.
7. **Final acceptance — P31J and the goal handoff.** On the final integrated
   source, serialize the required native/Mix/PTY verification, full source suite,
   demo, package and installed checks; complete the platform, quality, safety,
   migration and whole-manual checks required below. Conduct the adversarial
   post-implementation audit, repair its findings, and prepare the reviewer
   handoff. Report fixture, live-account, human and platform evidence separately,
   including any scope the existing acceptance rules permit to remain experimental
   or unverified. Publication remains separately authorized.

The [frozen default regression](archive/2026-10-26-p30-p31-implementation/full-source-2a56-regression-20261106.md)
at `2a56c60b` completed all 497 selected files in 9,447.2 seconds with
4,184/4,188 passed, four failures, 136 skipped and 124 excluded. Its immutable
inputs and cleanup checks pass. The four stale fixture expectations have
separate focused repairs; this is still an exit-two historical result, and the
final combined current-source suite remains open. Hosted protected-storage
support, macOS terminal timeouts and installed-memory diagnosis also remain
separate gates; presentation and MCP-verifier repairs do not qualify them.

Acceptance is bounded by the evidence for each milestone. Internal source review,
external critique, static scanning, fixture execution, hosted platform checks and
live accounts establish different claims. P24/P25 acceptance is supervised use in
a trusted, cooperative workspace; partial security scans and withheld independent
verdicts remain partial. P27's versioned held-out comparison is not a universal
engine ranking. No unattended operation or security certification is claimed.
No further broad architecture-review loop or security scan is scheduled.

The [architecture dispositions](archive/2026-10-18-before-manual-rewrite/docs/developer/architecture-review-dispositions.md),
[P25 acceptance](archive/2026-10-18-before-manual-rewrite/docs/developer/p25-evaluation.md#scoped-acceptance-decision),
[P26 remediation](archive/2026-10-19-p26-remediation/index.md),
[P27 comparison](archive/2026-10-23-p27-heldout-comparison/index.md) and
[P28/P29 qualified acceptance](archive/2026-10-24-p28-p29-review2/acceptance.md)
preserve the decisions and original limitations. On 2026-10-26 the developer
inserted knowledge and prompt assistance as P31 and moved voice/media to P32.
Historical media proposals retain their contemporary P24, P28 or P31 numbering;
the [previous scopes](archive/2026-10-26-p30-p31-plan/prior-milestones.md) are preserved.
The [current design](knowledge-design.md) and
[latest audit disposition](archive/2026-10-26-p30-p31-final-handoff/index.md) link source
research, settled user choices and concrete contracts. P31A retains the open pilot
and qualification work; P30A/B can proceed independently.
The [implementation handoff](archive/2026-10-26-p30-p31-final-handoff/implementation.md)
specifies P31A's bounded first work and required evidence.
The developer authorized full P30/P31 implementation on 2026-10-26, with full tests,
an adversarial audit and review handoff. The [implementation record](archive/2026-10-26-p30-p31-implementation/index.md)
preserves the frozen amended baseline, finite live allowance and open evidence.
Publication remains separately authorized.
The developer-selected Grok follow-up extends P29 and keeps API billing separate
from registered-client subscription OAuth.

## Completion rules

For each increment define observable acceptance, preserve original/native history,
explicit provider/billing selection, approvals, owned cancellation, bounded data
and no automatic replay of unknown effects. Instructions and configuration are
never permission grants. Disabled extensions create no worker, store, connection,
indexing job or inference. Core owns mandatory journal/accounting integrity even
when tracing, cost UI or optional memory is disabled.

Evaluate maintained Elixir/OTP and Rust facilities before custom machinery;
inventory selected dependencies and licenses. Dependencies outside Elixir/Rust
require explicit developer approval, including development and security tooling.
Use public interfaces and operator-configured endpoints, with no hidden fallback.

Run meaningful focused tests and the required source/native/demo/package checks for
runtime changes. Distinguish fixtures, live provider/account checks, installed
artifacts, hosted macOS and local macOS evidence. Review affected operator/developer
guides as coherent documents, reconcile entry points and check files/anchors before
calling an increment complete. Commit and push verified focused changes; preserve
unrelated work and never force-push. Detailed procedures are in
[AGENTS.md](../AGENTS.md#finish-a-change) and [testing](developer/testing.md).

## P23: usage, cost reporting and budget controls

**Complete within the selected scope.** The [usage contract](developer/accounting.md) supplies durable
request/attempt/provider/billing/model facts separately from diagnostics. The
[configured cost implementation](developer/accounting.md) and
[operator guide](operator/resources.md) define the available reports:

| Increment | Delivery state and scope |
| --- | --- |
| P23A | Pure versioned rate-card estimator with exact configured identities, fixed-point arithmetic, cache partitions, provenance and explicit unknown/partial values |
| P23B | Separately granted own-session `usage.read`, fixed prefixes, source-bound cached recovery and default-off `builtin:cost-report:1` pages |
| P23C | Finite separately granted full own-session enumeration and default-off `builtin:cost-summary:1`, cumulative request replacement and overflow/legacy handling |
| P23D | Explicit registered-child discovery/reads and default-off `builtin:cost-tree:1`, frozen accounting prefixes, exact origins and visible missing/busy/invalid/legacy/cleanup gaps |
| P23E1 | Explicit supported provider output ceilings, narrowed child/summary caps and saved-policy resume |
| P23E2 | Optional atomic session-tree reservations for main/summary/children, conservative settlement, protected inspection and historical-source validation; local and hosted Linux/macOS source/package/installed checks passed |
| P23F | Explicit one-shot `host.model` text requests, profile-bound approvals/receipts, canonical usage and shared reservations; source/native/package and both independent artifact proofs passed locally and in hosted Linux/macOS checks |

[Provider output ceilings](developer/configuration.md) follow the selected route's
capability contract. ChatGPT subscription refuses the unsupported setting; no
output-token ceiling is invented for that public interface. Verification scope
and limitations are recorded in
[actual evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks).
The [shared budget contract](developer/accounting.md) covers main, summary and local
children and [extension model operations](developer/extension-effects.md#request-bounded-text-inference)
independently of reports. P23F's source and installed proofs passed locally and on
both hosted platforms; the measured coverage remains distinct from live billing.

These reports do not enforce budgets, produce a globally atomic tree balance or
promise an invoice ceiling. Rates are configured; subscription equivalents,
API estimates and local inference resource costs remain distinct. Missing usage
or failed-child cleanup cannot be converted to zero liability.

The [independently built model artifact](../examples/README.md) and
existing seven-artifact compatibility lab passed against unchanged extracted
packages. Acceptance includes real parallel child inference, nested approvals,
owner-loss cancellation, refusal/overdraw, source-bound cached cost recovery and
inert resume. Exact revisions, archive digests and terminal hosted conclusions
are recorded in testing. P23 delivered one-shot text; P27 subsequently added the
separate native embedding contract. Audio remains unsupported pending separate
contracts. In-flight input/money estimation
and arbitrary trusted out-of-band calls cannot establish an invoice ceiling.

## P24: independent architecture validation and baseline security

**Complete for the scoped supervised P25 trial at `375e607`; not a security certification.**

The independent critiques challenged ownership, effects, privacy, recovery,
extension authority, accounting and native confinement. Their reports remain
partial source reviews with the verdicts they actually returned. The interrupted
2026-10-18 focused pass did not provide its requested final report. Following the
operator's scan-first decision, the one-time Security Cloud baseline at `8b4f706`
reported complete whole-tree static coverage, without executing tests or native
enforcement. Its findings and the interrupted pass's concerns were triaged
separately rather than treating either output as automatic acceptance.

Applicable helper-integrity, aggregate-call, JWT and CI-pin findings were repaired
at `bfce156`. Additional controlled probes corrected credential staging under a
shared Mac grant, a retiring optional consumer rejecting the next turn, and a
large launch frame leaving the first protocol write backpressured. Exact-source
local and hosted verification passed at `375e607`, including actual macOS native
environment/stdin handling, signed sandbox enforcement and both installed proofs.
The [readiness decision](archive/2026-10-18-before-manual-rewrite/docs/developer/architecture-review-dispositions.md#p24-scoped-readiness-decision)
records the evidence chain and selected acceptance scope. Historical failures and
unconfirmed intermittent causes remain in [testing](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks).

Accepted limits remain explicit: trusted user-permission code; non-atomic host
file checks under hostile concurrent workspace changes; same-user journal/storage
rewriting; Mac shared-container and detached-descendant boundaries; unknown remote
effects and unconfirmed cleanup; journal growth/startup cost at that revision
(reopened by P25's final scan and addressed by its verified bounded-journal repair); fixed
reservations, fail-closed tree overdraw and torn-ledger continuation. Immutable
host evidence is not a memory-erasure interface. These limits constrain the
supervised trial and future contracts; they are not claims that attacks or defects
are impossible. There is no unresolved applicable Critical/High finding in this
review set, but no independent post-fix architecture verdict or second security
scan is claimed.

The implementation author's final changed-path review plus actual execution
supports proceeding under supervision; the old independent reviewers' withheld
verdicts are not rewritten. P25 must preserve the frozen runner and approvals,
record interventions and revalidate changed surfaces. Its final architecture
delta/security review remains a separate gate. The
[preserved operator checkpoint](archive/2026-10-18-before-manual-rewrite/docs/operator/architecture-review.md)
links the actual scan; the
[preserved evaluation protocol](archive/2026-10-18-before-manual-rewrite/docs/developer/self-hosting-evaluation.md)
owns that trial's controls.

## P25: comparative research and supervised self-development

**Complete as a scoped supervised evaluation at `3307563`, with recorded assistance and accepted limits.** Replace P25's production-engine delivery
with a large supervised evaluation using those engines as a research/planning
problem. Track A uses Codex; Track B uses stable installed Ipse. Both research
working/long-term memory, configurable research providers, graph and RAG, including
Zero-Mem and alternatives, then propose implementable P26/P27 designs. Each works
independently before comparison, with common requirements and recorded resource,
provider/model, retrieval and assistance differences.

The [preserved evaluation protocol](archive/2026-10-18-before-manual-rewrite/docs/developer/self-hosting-evaluation.md) owns the rubric,
artifact manifest, proposed round limits, held-out cases and review process.
The [frozen common brief](archive/2026-10-18-before-manual-rewrite/docs/developer/p25-common-brief.md) pins the initial research
controls and identical source manifest before scored execution.
The [preserved knowledge design](archive/2026-10-18-before-manual-rewrite/docs/developer/knowledge-extensions.md)
owns that study's domain questions and selection gates. New evaluation work follows
the [contributor training](developer/testing.md). Existing P14 tools/skills/ledger and P22 SDK are available; engine
installation or production implementation is not required by this milestone.

Execution readiness requires a passing frozen runner, reviewed task/resource
limits, usable explicit research access for both tracks and P24's architecture
dispositions and triaged baseline audit. Brief preparation and service-access
checks can proceed earlier. Live audio (now P32) is not a prerequisite. Scope the trial
as several reviewable work packages with retained intermediate artifacts, so
research, long-task recovery and actual self-development have separate evidence.

| Phase | Deliverable and gate |
| --- | --- |
| A — freeze and verify readiness | Pin task/rubric, source packet, runner/candidate, profiles, tools and resource limits; confirm P24 architecture/security coverage matches the actual baseline and refresh affected reviews if it changed |
| B — independent research | Frozen A/B reports, primary-source/claim ledgers, alternatives, architecture, dependency/license review and implementation proposals; common-packet and live-research comparisons |
| C — evidence-based comparison | Codex reviews both reports against the sources and common rubric; record material discrepancies, root-cause hypotheses, uncertainty and supervisor assistance |
| D — Ipse-authored repairs | Stable Ipse develops meaningful harness/extension/skill fixes with regressions and documentation in a separate candidate; Codex independently reviews and verifies |
| E — fresh reruns | Clean same-input and held-out evaluations after fixes; real behavior change, context pressure, operator question, interruption/resume and independent review, plus source/native/package/platform checks |
| F — final architecture, security and acceptance | Completed partial OpenAI security scans, affected delta reviews, reproduced repairs and exact corrected-source platform/installed checks; scoped supervisor acceptance, sanitized evidence and researched P26/P27 proposal. Scan revisions and later corrective patches remain distinct |

Research acceptance means source-supported correctness, required coverage and a
useful implementation plan at comparable declared limits. Codex's report is a
reviewed reference, not unquestionable truth or a wording template. Both tracks
must satisfy minimum criteria; justified alternative decisions can pass. Proposed
bounds are three repair rounds and two independent final Ipse runs, with no material
factual/citation errors, unresolved applicable critical/high findings or foundational
correctness gaps. Pin actual limits before execution; exhausted limits produce a
residual-gap report, not an unbounded attempt to force agreement.

Self-development acceptance additionally requires at least one meaningful
Ipse-authored behavior change and independently verified regression tests. Record
supervisor-authored repairs and manual interventions honestly. A report comparison
alone, copied Codex conclusions or a synthetic extension lab cannot close this gate.
Promote a new frozen runner only after independent review and checks; preserve old
reports/runtimes and validate held-out cases rather than tuning a single answer.

Use P24's external architectural challenge and OpenAI Codex Security baseline as
separate inputs; repeat architecture review for material design changes and
security review on the final candidate. The hosted security route is
preferred to adding local tooling, subject to actual account/repository access
and revision coverage. Scan status and coverage are separate; findings need
triage and fixes need regression evidence. Raw findings stay private. P24's baseline
scan completed; all applicable repairs and composition follow-ups passed their
source/platform gates. Preparation is not scored P25 execution. No recurring
monitoring is enabled and no new dependency is approved by this plan. See
[architecture validation](archive/2026-10-18-before-manual-rewrite/docs/developer/self-hosting-evaluation.md#independent-adversarial-architecture-validation)
and [security execution constraints](archive/2026-10-18-before-manual-rewrite/docs/developer/self-hosting-evaluation.md#security-review-before-and-after-the-trial).

## P26: optional working and long-term memory

**Complete within the explicit-note scope at `25f1d8e`.** The
[2026-10-19 review](archive/2026-10-19-p26-remediation/index.md) found model
inspection outside expiry/dependency filtering, lossy backup/restore, a missing-source
collection crash and an admission/test gap. These and the internal findings were
reproduced and repaired without weakening suppression or approval. A generic locked
write deadline refuses approvals crossing the existing note's expiry. The
[second external review](archive/2026-10-19-p26-remediation/review-2.md) accepts the
P26 code scope, identifies one low-severity failed-receipt validation gap, and
confirms that the run failed in inherited P27 60-second fixtures. The receipt
correction and all 60 focused tests pass with an explicit 60,000-ms deadline.
After measuring the accumulated work, the independent suppression Session cases
and CLI refusal checks now have separate fixture units; the full seven-variant
current-source integration case remains. A fresh three-reviewer adversarial
review of the entire P26 milestone found no actionable defect. Refreshed full,
native, installed and manual-example checks pass. Exact-source hosted
[run 39309132023](https://github.com/lexlapax/ipse/actions/runs/39309132023)
passes both Ubuntu and macOS with Elixir 1.18.5 / OTP 27, including package and
installed proofs. A forced Linux staging delay also confirms refusal before
publication. The user authorized this internal review and repair followed by P27;
no further external dispatch or CI waiver was required. The remediation record
owns the complete receipts and limits.

Implementation `108aa86` and diagnostic-worker cleanup repair `fb4627e` retain
their applicable source/native/package and exact-source hosted evidence. Local causal reproduction and controlled
before/after regressions explain the strict cleanup failure; the original failed
attempts and unchanged rerun remain in the [verification record](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#macos-diagnostic-cleanup-repair-2026-10-18).
Independently selectable default-off session/task and persistent project/operator
memory ship as bundled extensions.
Explicit recall/remember/forget/export tools and commands provide bounded task
cards/facts and lexical recall. Source suppression, TTL/conflicts, derivative
inventory/collection and approved migration/import preserve lifecycle integrity.
Automatic recall/capture is now scoped under [P31](#p31-usable-knowledge-and-prompt-assistance);
it is not enabled by this baseline. Zero-Mem is inspiration, not a selected package or
reproduced benchmark result. The [knowledge design](archive/2026-10-18-before-manual-rewrite/docs/developer/knowledge-extensions.md#research-handoff-and-deferred-production-acceptance)
owns the researched selection and deferred engine comparisons.

Acceptance: default-off parity; explicit namespace/project/operator scopes;
stable logical identity with explicit export/migration/collection across artifact
and configuration-source versions; provenance, retention/TTL and conflicts;
approved bounded writes; concurrent forget without resurrection; derivative
deletion/export and distinct history-access/redaction, journal/backup and erasure
limits; cancellation and unchanged resumed recall. No mandatory store, embedding
model, remote service or silent promotion. Keep core conversation/recovery intact
when optional memory is off. Measure quality and resources separately from
protocol correctness; document actual dependency, configuration and recovery.

The implementation follows the researched explicit-notes baseline, with no external
service, embedding model or database dependency. Domain behavior belongs in
independently selectable bundled extensions. Necessary generic host changes must
preserve legacy identities and grants; they are reviewed and tested separately.

| Increment | Deliverable | Status |
| --- | --- | --- |
| P26H1 | Operator-only, versioned logical state bindings across reviewed artifact/configuration versions; legacy namespace compatibility and scope ceilings | Complete; source/native/installed and exact-source hosted gates pass |
| P26H2 | Bounded value scans and explicit read-work allowance for useful lexical recall, with strict receipt/recovery validation | Complete; byte pages, forged/ungranted/over-limit actions and extended real-worker receipt chain pass |
| P26H3 | Generic optional State write deadline, selected by the extension and enforced under the existing CAS lock without interpreting note schemas | Original final-locked-decision contract restored through the actual native owner; [current State/Memory controls](archive/2026-10-26-p30-p31-implementation/state-restoration.md) and [scoped independent review](archive/2026-10-26-p30-p31-implementation/state-restoration-independent-review.md) cover live/delayed approvals, expired backup and managed timed denial. Historical gate receipts remain valid. Coherent source/package qualification remains pending; physical completion by the deadline is not promised |
| P26A | Separate default-off working and persistent memory, explicit remember/recall/forget/export, provenance, bounded lexical ranking and approvals | Complete; admission, exact backups and real CLI examples pass; external findings repaired and full milestone internally reviewed |
| P26B | Durable source suppression, TTL/conflicts, derivative inventory/collection, schema migration/import, stale-work and cached-context recovery policy | Complete; visibility, legacy migration and delayed-expiry checks pass; fresh-session recovery and retained-history limits remain part of the contract |
| P26 verification | Deterministic authority/concurrency/restart/import cases, measured retrieval/resources, source/native/installed/platform checks and coherent operator/developer guidance | Complete; 60 focused and 1,167 full tests pass locally; exact-source hosted Ubuntu/macOS source and installed gates pass; prior Linux native-enabled evidence retained with its source identity |

Stable logical storage is an explicit operator grant, never a namespace chosen by
project text or extension code. Existing journals and provider-visible history are
retained; memory deletion must state its separate recall/suppression and cached
context limits. See the [knowledge development manual](developer/knowledge-extensions.md)
for current placement and design guidance.
The [operator guide](operator/memory.md) owns configuration/retention/recovery;
the [extension contract](developer/extension-state.md) owns suppression and measurement limits.

## P27: optional research, graph and RAG

**Complete within the optional Research, Graph and Corpus scope.**
The first private GPU comparison at `7bffee0` retained 350 first outcomes but
failed measurement and audit. Its context and streaming corrections passed
verification and hosted CI at `1d40eee`. A fresh comparison at that source then
exhausted its first cell's 100-minute service allowance. It retained 22 outcomes
before the remaining owned work was stopped. Neither attempt qualifies a strategy.
The duration correction at `817ab84` passed local verification and exact-source
hosted CI. Its fresh comparison completed all 350 first outcomes, including six
failures, and passed the joined execution/resource audit before reference release.
Two independent model assessments, separate adjudication and one explicit human
resolution supply complete review of all 350 outcomes and 635 citations. The
owner-resolved rerank case uses a frozen `independent: true` compatibility flag
to close the scorer's global completeness gate. It is not an independent final
judgment and changes neither hybrid nor any strategy's qualification; the
[comparison disclosure](archive/2026-10-23-p27-heldout-comparison/index.md#result-and-remaining-acceptance)
records that accepted method extension. The
original scorer passes the frozen per-strategy qualification policy. Hybrid is
the sole eligible strategy, with 92% answer support and 95.18% citation support,
and is selected as the reference configuration. The
[complete comparison record](archive/2026-10-23-p27-heldout-comparison/index.md)
publishes all outcomes, all seven strategies, original judgments and matched
resources. All four final-code source/installed CPU/GPU synthetic measurement
controls pass, along with platform/package checks and the whole-manual review.
The [requirement-by-requirement audit](archive/2026-10-23-p27-heldout-comparison/acceptance-audit.md)
records the complete acceptance and its limits.
The
[first terminal record](archive/2026-10-22-p27-private-comparison/index.md) and
[duration-repair record](archive/2026-10-22-p27-duration-repair/index.md) preserve
the separate failures and their corrections. The
[previous plan](archive/2026-10-22-p27-private-comparison/previous-plan.md)
preserves earlier increment history.

P27 supplies independently configurable Corpus, Graph and Research extensions.
Memory remains independent. Enabling one package does not enable another or
create an undeclared worker, connection, store, index or model call. Lexical
retrieval works without embeddings. Search, fetch, store, retrieval, embedding
and rerank services use named operator-selected profiles. No framework, database,
provider, external endpoint or measurement backend is mandatory.

### Acceptance criteria

The complete milestone requires all of the following:

- Preserve attributable source, chunk, generation, typed version, hash and citation
  identities through bounded ingestion, extraction, traversal and retrieval.
- Propagate deletion and suppression. Refuse stale projections and honor
  historical and as-of eligibility, including delayed work and import recovery.
- Handle contradictory, stale, negative-only and weak evidence without inventing
  support. Compatible positive requirements remain compatible.
- Preserve approvals, selected profiles, accounting, finite budgets, cancellation,
  owner-loss cleanup, partial failures and inert recovery. Never automatically
  replay an interrupted or unknown effect.
- Require zero authority, isolation, replay and resurrection failures in the
  applicable corrected-source deterministic, native and installed controls.
  Preserve historical failures and declared platform limits; this gate adds no
  unverified sandbox guarantee.
- Deliver generic host contracts before domain consumers. Keep legacy grants and
  SDK bounds unchanged unless the operator explicitly selects a new contract.
- Evaluate seven strategies on fifty independently authored held-out questions
  across two projects. Publish every one of the 350 first outcomes, including
  failures, partial results and unavailable measurements.
- Freeze predictions and verify the full execution and resource audit before
  releasing reference answers. Obtain independent semantic judgments for every
  applicable answer, claim and citation. Recompute literal citation integrity
  against hash-verified corpus bytes through the scorer.
- Select a strategy that individually reaches at least 90% answer support and
  95% citation support. Reject strategies below either target for selection.
  Aggregate results and synthetic fixtures cannot qualify a strategy.
- Compare retrieval quality, classification, latency, request and budget usage,
  retained storage and exact workload-charged RAM. Justify the engine choice with
  those results and their limits.
- Complete whole-codebase consolidation, coherent operator and developer manuals,
  platform and installed-package checks, and independent architecture and
  implementation review. Integrate the final decision into the manuals before
  closing the milestone.

### Implementation and verification

| Increment | Implemented behavior | Acceptance state |
| --- | --- | --- |
| P27H1 | Source-bound result pages, explicit mixed read/effect allowance and pure saved-source validation | Protocol checks complete |
| P27H2 | Approved configured MCP actions, pinned descriptors, child denial, owned cancellation and unknown-outcome recovery | Protocol checks complete |
| P27H3 | Selected-profile native embeddings, exact egress and operation-aware accounting and budgets | Protocol checks complete |
| P27H4 | Opt-in complete results, historical receipt reads and strict source closure within ordinary SDK bounds | Protocol checks complete |
| P27H5 | Explicit schema-bound inference and independently selected extraction and rerank contracts | Compatibility and protocol checks complete; held-out judgments complete |
| P27A | Independent Research and lexical Corpus packages with cited evidence, explicit limits, partial failures and suppression | Implementation/review checks and held-out comparison complete; both strategies rejected for the reference choice |
| P27B | Independent Graph, optional extraction, dense/hybrid retrieval and reranking | Implementation/review checks and matched comparison complete; hybrid selected, weaker strategies rejected |
| Structural readiness | Whole-codebase/manual consolidation reviewed at c9a2d80; its sole Daybreak P2 inventory finding repaired at b81f68f | Complete; local/hosted/native-inclusive suites, package checks and all four source/installed CPU/GPU measured controls pass |
| Comparison audit repair | Stream merged execution against closed cell inventories without materializing the raw aggregate | Reviewed; platform suites and all four source/installed CPU/GPU measured proofs pass |
| Explicit context repair | Bind portable and local context; verify loaded completion context while allowing separate embedding windows | Reviewed; platform/floor checks, 31-case service proofs, all four measured proofs and eight exposed GPU requests pass |
| Duration composition repair | Compose fourteen legal service lifetimes within one finite measured-root ceiling; preserve existing request and service limits | Reviews, platform and supported-toolchain checks, native controls, package checks, all four source/installed CPU/GPU measured proofs and exact-source hosted CI pass at `817ab84` |
| Final acceptance | Frozen outcomes, semantic judgments with the disclosed owner-resolution extension, all-strategy publication, exact resources and hybrid reference choice | Complete within that accepted extension; whole-manual/requirements audit passes; earlier failed attempts retain their verdicts |

The [external whole-P27 review and dispositions](archive/2026-10-20-p27-external-review-r1/index.md)
retain all twelve code and five documentation findings, their repairs and
follow-up coverage. The [readiness repair record](archive/2026-10-21-p27-readiness-repair/index.md)
retains the subsequent whole-milestone and Daybreak review, six further repairs
and their checks. The [structural implementation](archive/2026-10-20-p27-structure-implementation/index.md)
and [whole-manual editorial review](archive/2026-10-21-p27-manual-consolidation/editorial-review.md)
record the earlier changes. Those records do not establish acceptance of the
whole-codebase consolidation.

Structural acceptance is complete. Host runtime follows the standard Elixir layout
with matching feature folders under `lib/ipse/` and `test/ipse/`. Generic extension
host and SDK code is under `lib/ipse/extension/`; bundled and optional feature
implementations share one `extensions/` tree. Small, tightly coupled modules and
one-caller wrappers were merged while justified process/public-contract ownership
remains separate. Developer commands retain separate entry points with shared
implementation grouped under `dev/`. Individual historical files remain intact.

Session retains the conversation process. Its turn and extension-invocation
implementations run synchronously in that process, with caller/reference/phase
admission and resource completion retained by Session. A source split must not
introduce another conversation owner.

The [current consolidation review](archive/2026-10-22-p27-structural-review/index.md)
records the independent findings and their causal checks. At that consolidation,
the manuals had 14 operator and 22 developer chapters. Corrected-source hosted Ubuntu/macOS,
native-inclusive Linux, package and installed-package checks pass at `b81f68f`.
All four source/installed CPU/GPU measured controls pass. Their
[final receipts](archive/2026-10-23-p27-heldout-comparison/final-platforms.json)
retain exact source/archive identities, commands, audit results and exclusions.
File-count reductions alone do not establish
deletion of unnecessary interfaces or lower implementation complexity. The earlier
broad default checkpoint passed with 1,459 passed, one skipped and 36 excluded.
The supported-toolchain loading correction passes 161 integrated caller tests and
77 focused floor tests. The clean floor snapshot also passes packaging, installed
package/model-service checks, all fifteen Knowledge builds and ten source plus ten
installed Knowledge routes. These use synthetic services, not actual model quality
or Linux native enforcement evidence.
Hosted run `39895104182` passed Ubuntu. macOS passed those source/native/package
and Knowledge steps, then failed compilation of the final experimental App Sandbox
verifier. Its stale helper capture is repaired with a causal compile regression,
supported-toolchain compile check and passing real local App Sandbox probe. The
original run remains failed. The correction at `c9a2d80` passed
[run 39899526393](https://github.com/lexlapax/ipse/actions/runs/39899526393) on both
platforms, including all installed proofs and the final experimental macOS
verifier. Its [receipt](archive/2026-10-22-p27-structural-review/hosted-c9a2d80.json)
records exact source and exclusions. The subsequent verification-record update
changes documentation only; actual-model quality and final Linux native-inclusive
checks were separate gates at that stage, with later acceptance recorded above.

The consolidation covers runtime code, extension packages, tests, developer
tooling, examples, shipped resources and both current manuals. The structural
record distinguishes deletions/merges from moves and records caller, packaging
and documented-usage checks against the resulting structure. The completed
comparison retains its original frozen source and provenance throughout this work.
The developer accepted that comparison at
`817ab84944c347f76e297efaad313b1ec841ee91` as explicitly versioned evidence,
alongside correctness and platform checks on the final consolidated code. A new
350-answer comparison is not required solely because of structural consolidation.
Quality qualification and publication still require the full outcomes, joined
resource audit and independent semantic review.

The [preceding launch-verification record](archive/2026-10-21-p27-gpu-policy/index.md#preserve-the-first-private-preparation-refusal)
binds the canonical command correction, actual fresh-VM regression, macOS and
native-enabled Linux suites, supported toolchain checks, source and installed
synthetic comparisons, packaging and hosted CI to the corrected runtime. Those
checks establish implementation and execution behavior for that earlier source.
They do not verify the later corrective increment. Its
[corrective record](archive/2026-10-22-p27-private-comparison/index.md#verify-the-corrective-increment)
retains passing macOS and native-enabled Linux suites, the supported toolchain,
package/installed checks, source comparisons and exposed context diagnostic.
All four source/installed CPU/GPU measured comparisons and final source-identity
checks pass. Exact hosted run `39737181313` is green on Ubuntu and macOS for
`1d40eee`. That result verifies the context and streaming corrections. The new
duration-composition repair has separate completed verification in its
[record](archive/2026-10-22-p27-duration-repair/index.md#verification-and-remaining-acceptance).
Exact hosted run `39764314254` is green on Ubuntu and macOS for `817ab84`.
All four measured fixture proofs complete 350 outcomes and the joined audits.
These checks verified execution behavior at that increment; the separately
versioned [held-out result](archive/2026-10-23-p27-heldout-comparison/index.md)
now supplies semantic qualification and the reference choice.

### Completion and subsequent work

All P27 acceptance tasks are complete. The selected reference uses existing
State Corpus hybrid retrieval with BM25, native 768-dimensional embeddings,
reciprocal rank fusion at 60, no graph or reranker, and explicit missing-embedding
refusal. This is an operator-selected configuration, not a mandatory service or
automatic provider switch. The answer-quality result applies to the frozen 9B
answer policy and workload; the other strategies remain available but are rejected
for this reference choice.

Preserve the published outcomes, raw assessments, human resolution, final scores,
matched resources and all earlier failures. The released workload is now exposed;
future quality acceptance requires independently authored data. Later engine,
corpus, provider or model changes need their own scoped evaluation rather than
upgrading this historical result or replaying consumed seals. P31 adds a separately
qualified ordinary-user knowledge experience; voice/media remains deferred as P32.

The [independent review of `a7f4982`](archive/2026-10-23-p27-independent-review/index.md)
confirms acceptance within this scope. The later
[remediation record](archive/2026-10-23-p27-review-remediation/index.md) closes both
P2 findings: dispatched MCP errors now retain a distinct diagnostic outcome,
and non-regular skill files refuse while explicit prompt expansion runs outside
the owner. It also closes deadline-edge accounting and patches PlugCrypto.
The comparison discloses adjudication sensitivity and the owner-resolution method
extension; frozen predictions and scores remain unchanged. Subsequent
[maintenance and fingerprint compatibility](archive/2026-10-23-p27-maintenance/index.md)
consolidates equivalent primitives and pure feature policy, removes the unused
HTTP backend, and versions new MCP sessions while preserving old journal rules.
Verification remains versioned: `4171fb4` had a Linux setup failure followed by
focused correction; `dd0a130` had one harness failure in each initial full suite
and hosted formatting failures; `ca5838b` passed its bounded follow-up checks.
The [final independent review](archive/2026-10-23-p27-final-review/index.md)
then verified `ca5838b` with 1532 native-inclusive Linux tests, its exact package
and installed proof, and green Ubuntu/macOS hosted run 40014715937. It confirms
acceptance and independently recomputes all published evidence. Its remaining P3
MCP corners and documentation/record gaps are addressed in the accompanying
follow-up at `89151b6`, with separate verification in that record. The subsequent
[internal whole-P27 adversarial audit](archive/2026-10-23-p27-final-review/internal-audit.md)
also repairs shared MCP output admission and legacy public-argument/hash agreement.
Its individual reviews, causal probes and final platform/package checks are
recorded separately. Frozen outcomes and scores are unchanged.

### Final comparison policy

The independently authored private workload has fifty questions, two projects
and 22 documents. The earlier exposed workload is tuning material and cannot
establish final acceptance. Preserve every historical attempt and its original
verdict; never upgrade or replay an incomplete comparison.

The [recorded semantic-review method](archive/2026-10-22-p27-semantic-review-policy/index.md)
requires two fresh blinded assessments of every case and citation, followed by
separate adjudication of disagreements. Preserve both raw assessments and the
adjudications. Unresolved judgments leave review completeness open. This method
is recorded before reference release and changes neither qualification target.

The selected inference policy uses the existing `qwen3.5:9b` model with reasoning
for final answers only. Extraction and reranking retain SDK-2's two-minute limit
and disabled reasoning. The explicit SDK-1 version-three answer allowance is
600 seconds and 8192 output tokens. The declared one-NVIDIA-device policy permits
partial CPU/GPU residency. It does not establish physical exclusivity.

The exact memory quantity is `linux_memcg_charged_peak_bytes_v1`, workload-charged
RAM including cache and kernel charges within each declared subject. Report the
whole-lifetime peak, each fresh stage's lifetime peak and the whole population's
peak during each stage separately. RSS samples,
summed process peaks and device memory do not substitute for those measurements.
The optional Linux backend uses the approved existing systemd user-service tools.
Ordinary Ipse operation does not require that backend. Host paths, device UUIDs
and runtime identities belong to execution provenance; Serenity is a verification
host rather than a required product configuration.

The [developer evaluation manual](developer/knowledge-evaluation.md) owns the
runnable declaration, sealing, execution, audit, independent-review and scoring
procedures. The acceptance rule requires the complete frozen audit, independent
semantic judgments, all-strategy publication, an individual qualifying strategy,
the engine decision and whole-document editorial integration.

## P28: operator usability and release readiness

**v0.1.0 published on explicit developer authorization on 2026-10-25 at `341e458`, under the qualified readiness accepted on 2026-10-24. Semantic documentation remediation, full platform verification and exact asset inspection pass; the recorded human/live qualifications remain.**
P0–P27 established correctness, recovery and evidence for a
supervised developer. This milestone makes the same harness usable by an operator
who did not build it, without weakening approvals, explicit provider selection or
fail-closed behavior. It adds no provider, model service or dependency by default.
The [P28 implementation brief](archive/2026-10-23-p28-p29-design/p28.md) breaks
this scope into ordered work packages with files, tests and decisions.
The developer accepted its recommended decisions on 2026-10-23. A missing
configuration keeps the built-in `chatgpt` default, and interactive starts print
a notice that names it and points to `ipse setup`. The first stable version is `v0.1.0`. The
release workflow drafts releases with the runner-provided `gh` CLI and the default
token, as recorded in the dependency inventory.
The [implementation record](archive/2026-10-23-p28-p29-implementation/index.md)
tracks the ordered work packages, actual checks and auditor handoff requirements.
Version/build identity is complete at `b4788b4`, with local source and
installed-archive checks and exact-source hosted Ubuntu/macOS verification.
Actionable errors pass full local and hosted checks at `6818000`. Offline doctor passes
the native-inclusive suite at `a89fce7`. Private setup passes focused and installed
first-run checks. Release checksums, symlink handling, draft workflow and lifecycle
manuals are implemented; the local installed upgrade proof passes. Whole-manual
review and installed examples pass. The original `9c5eb6a` native-inclusive baseline,
isolated demo, installed proof and complete hosted Ubuntu/macOS matrix pass.
RC1's workflow and both platform archives/checksums pass, including re-download
and runtime-notice inspection ([receipts](archive/2026-10-23-p28-p29-implementation/rc-assets.json)).
The developer reports a successful existing-account Linux walkthrough, including
ChatGPT sign-in, doctor/demo and follow-up confirmation of the real task,
individual approvals, output inspection and resume. The
[observation record](archive/2026-10-24-p28-walkthrough/index.md) distinguishes
terminal evidence from operator attestations. A subsequent fresh Linux account
run used Demo and Ollama `qwen3.5:9b`; the developer accepts the run and reports
excessive individual approval prompts. Account setup and product-navigation help
are recorded, so this is not labelled an entirely unassisted manual-only pass.
Human upgrade was skipped because only one version was available; automated
upgrade evidence remains separate. The requested
[approval UX research](archive/2026-10-24-p28-approval-ux/index.md) compares existing
agents and proposes modes plus reusable consent. The developer explicitly selected
implementing this follow-up before external audit, extending the brief's original
approval-semantics exclusion. Native workspace edit consent and exact shell-call
session grants are implemented in the
[new candidate](archive/2026-10-24-approval-implementation/index.md), with inspect/revoke,
fresh proposal binding and no inherited/resumed grants. The combined `622a2c8`
runtime passes full local native, installed and hosted Ubuntu/macOS checks;
the older baseline retains its narrower scope.
The developer also requested [machine identification during sign-in](archive/2026-10-24-sign-in-host-label/index.md).
New registrations now use a short `ipse@HOST` display-name hint to prefill the
browser's editable name. Returning authorization preserves registration identity
and omits that hint. The earlier terminal-only guidance is superseded; combined
verification includes browser-prefill request construction, without claiming a
new real browser authorization.
The inspected RC draft was deleted on explicit developer authorization after all
four exact assets and inspection metadata were retained locally; its RC tag remains.
The developer subsequently [accepted the repaired candidate with its documented
qualifications](archive/2026-10-24-p28-p29-review2/acceptance.md), including the
assisted walkthrough and missing human macOS/upgrade checks. This is a qualified
readiness decision, not an unassisted pass or a fresh independent verdict.
The developer subsequently authorized stable tagging and draft preparation.
The initial tag/draft used `1617657`; its
[workflow](https://github.com/lexlapax/ipse/actions/runs/40169083307) completed
successfully before the documentation remediation. After that remediation, the
developer explicitly authorized replacing the tag/draft with `341e458`, retaining
the original tag object and four assets locally. Tag `v0.1.0` now points to
`341e458`; its [release workflow](https://github.com/lexlapax/ipse/actions/runs/40202117315)
passes both platforms, every installed proof, complete asset admission and draft
re-download. Independent inspection verifies all four hosted digests/checksums,
both compiled identities, bundled manuals and runtime notices in the
[reconciliation receipt](archive/2026-10-25-prepublication-docs/release-reconciliation.json).
The final main check's first macOS attempt failed one cleanup fixture; its
unchanged retry and the fresh release checks pass. The failure remains recorded
with its cause unestablished. After inspecting those results, the developer
explicitly authorized publication on 2026-10-25. The
[published release](https://github.com/lexlapax/ipse/releases/tag/v0.1.0) is latest;
its [publication receipt](archive/2026-10-25-prepublication-docs/publication.json)
verifies the same four pre-inspected asset IDs, sizes and digests, unchanged notes
and the approved tag/source. This closes publication under the existing qualified
acceptance without claiming new human walkthroughs or live inference checks.

Scope:

1. A guided first-run path that writes an owner-only operator configuration after
   showing it: provider and billing choice, credential source, workspace defaults
   and optional extensions. It never selects a provider or paid mode implicitly and
   never prints or copies credentials.
2. An `ipse doctor` diagnosis of toolchain, runtime identity, configuration
   resolution, credential presence (not values), provider reachability on explicit
   request, native policy availability, MCP and extension selection, and session
   store permissions/bounded headers without acquiring locks. Every finding names
   the documented recovery step.
3. An audit of operator-visible refusals and errors from `ipse chat`, `run`,
   `config`, resume and extension/MCP paths. Each states the cause, what did or
   might have happened and the next command, matching
   [recovery](operator/recovery.md).
4. A versioned release: tagged source, Linux and macOS archives from the existing
   [packaging](developer/testing.md) path, checksums, release notes and
   install/upgrade/uninstall instructions. Upgrades preserve saved sessions or
   refuse them with a documented handoff, as the license transition did.
5. A whole-document review of the operator manual as a new user's path from
   install to a first real task, including accepted limits stated where they apply.

Acceptance: fixture tests for setup output, configuration resolution and each
doctor finding; no network traffic without an explicit request; installed-archive
first-run and upgrade checks on Linux; hosted macOS package checks; and a recorded
unassisted walkthrough by a fresh operator account. The developer's recorded
readiness decision accepts the walkthrough qualifications for v0.1.0 without
claiming that original human criterion was met. Signing, notarization and
distribution channels such as package managers need separate approval as release
dependencies.

## P29: provider registry, OpenRouter and Gemini

**Original P29 scope completed at `9c5eb6a`; repaired candidate accepted for v0.1.0 readiness with documented qualifications on 2026-10-24. Live xAI access and registration remain unverified.** The central
[`provider registry`](../lib/ipse/provider/registry.ex) supplies configuration,
profiles, credentials, billing, accounting, capabilities, setup and diagnosis.
Independent pre-refactor fixtures from `dd510a7` retain existing manifests,
destinations, usage, costs and saved-session behavior. Shared conformance covers
the existing adapters, pinned OpenRouter, explicit loopback-compatible servers
and native Gemini. Session/child/SDK, compaction, privacy, budgets and recovery
controls pass. Guided setup saves explicit route profiles while preserving
existing configuration. Native embeddings remain limited to OpenAI/Ollama.

Original-scope verification at `9c5eb6a` passes the Linux native-inclusive suite (1713 passed,
19 excluded), isolated demo, complete installed proof and the exact-source
[Ubuntu/macOS matrix](archive/2026-10-23-p28-p29-implementation/final-hosted.json),
including all independent proofs. Whole-manual review and installed examples pass.
Separate [live Gemini and pinned OpenRouter text/tool checks](archive/2026-10-23-p28-p29-implementation/p29-live-final.json)
pass at `492d091`. Later error, endpoint and Gemini history-conversion repairs
have fixture coverage; those live checks do not verify the new paths. Live
Gemini foreign-history acceptance remains unverified. Missing Gemini counters
remain partial. The
[combined receipt](archive/2026-10-23-p28-p29-implementation/combined-verification.json)
preserves exact revisions, exclusions and earlier failures. The developer supplied
an [independent completeness audit](archive/2026-10-24-p28-p29-audit-repair/index.md).
Its findings are repaired and verified at `aee0ad8`; the approved artifact handoff
passes at `dc70463`, which has the same runtime source. The follow-up record retains
earlier failed/canceled runs and the separate hosted scopes. Independent re-review
remains distinct from implementation checks. Earlier receipts cover their exact
source; P28's human walkthrough qualifications and publication status remain distinct.
The [second independent review and corrections](archive/2026-10-24-p28-p29-review2/index.md)
supersede acceptance of the first repair: its slash filter masked legitimate
configuration, skill and provider causes despite green automated checks. Those
causes now survive actual CLI rendering. Strict setup diagnosis, exact release
admission and numeric stream diagnostics pass local and hosted checks at
`5d9650e`. The requested author adversarial review also repairs a cross-toolchain
verifier compiler defect; 33 verifier tests, installed checks for both toolchains
and the complete hosted rehearsal pass at `45cae30`. Host code, native helpers and
the release workflow are unchanged in that follow-up. The record retains failed iterations and
superseded/canceled runs. The pre-existing short private MCP-value collision
remains documented, without weakening privacy. The
[release-readiness handoff](archive/2026-10-24-p28-p29-review2/release-readiness.md)
prepares v0.1.0. The developer's [qualified acceptance](archive/2026-10-24-p28-p29-review2/acceptance.md)
closes the readiness decision without a fresh independent verdict or new live
provider checks. Documentation remediation and the authorized tag/draft rebuild
are complete, including exact asset inspection. The developer subsequently
authorized v0.1.0 publication; the existing human/live qualifications remain open.
The [P29 implementation brief](archive/2026-10-23-p28-p29-design/p29.md) breaks
this scope into ordered work packages with files, tests and decisions.
The developer accepted its recommended decisions on 2026-10-23. Gemini, then
OpenRouter, follow the existing four providers in the implemented priority order
recorded in [AGENTS.md](../AGENTS.md#product-and-scope).
An `openai_compatible` provider serves loopback servers only, with local billing.
OpenRouter profiles send `data_collection: "deny"` unless they explicitly allow
collection.

1. **Registry, no behavior change.** Each provider declares its adapter, default
   endpoint, credential source, billing mode, reasoning/profile validation, usage
   normalization, pricing source and destination facts in one place. Existing
   journals, profiles, cost reports and destination digests stay identical; old
   sessions resume unchanged.
2. **OpenAI-compatible Chat Completions adapter.** The current OpenAI adapter uses
   the Responses API only. A separate Chat Completions adapter serves OpenRouter as
   a named provider and, with explicit base URLs, local servers that implement the
   same interface. OpenRouter can route to different upstream hosts or fall back to
   other models. Ipse must pin the requested model and upstream order, disable
   fallbacks, record the upstream that actually served each response and refuse a
   mismatch, so no provider or model changes silently.
3. **Native Gemini adapter.** Use the Gemini API rather than its OpenAI-compatible
   endpoint, so thought signatures and function-call state are preserved as
   provider continuation data. This increment supports AI Studio API keys;
   Vertex credentials and OAuth are unsupported. Billing is recorded as API,
   without inferring the account's free/paid tier. Gemini embeddings may
   follow under the existing versioned embedding contract with its own evaluation.

Acceptance: registry equivalence tests over existing fixtures and saved sessions;
loopback fixture servers for streaming, tool calls, truncation, errors, usage and
continuation round trips for each new adapter; budget and cost reporting with
unknown prices kept unpriced; destination and egress facts; and separately
recorded opt-in live account checks. The accepted implementation includes
OpenRouter and Gemini in the provider priority order in [AGENTS.md](../AGENTS.md).

### P29 follow-up: Grok API and subscription OAuth

**Implemented and automatically verified before external audit, 2026-10-24;
live API/subscription eligibility remains unverified.**
The [primary-source research and work packages](archive/2026-10-24-xai-provider-research/index.md)
cover xAI/SpaceXAI's Grok API, its officially supported Hermes subscription
integration, device authorization, native Responses, continuation, billing and
retention. This extends the accepted P29 scope; the earlier registry/Gemini/
OpenRouter verification does not prove Grok compatibility.

Add separate explicit `xai` API-key and `xai_oauth` subscription routes, with no
automatic credential/billing fallback and an explicit model. Prefer native
Responses with local history and `store: false`; preserve opaque continuation in
an xAI-specific namespace, and retain Ipse approval/journal authority over tools.
Use existing bounded Elixir transport, private storage and OS locks, with no new
language runtime or mandatory service. Integrate profiles, roles, accounting,
setup, offline doctor, SDK/children, compaction and resume. Keep xAI hosted search,
execution, MCP, media and multi-agent features outside this text/tool increment.

The developer has no Ipse OAuth registration yet. Public discovery supports
device authorization but advertises no registration endpoint; the official
Hermes announcement does not grant Ipse its client identity. Require an approved
Ipse client ID, and refuse missing registration before network access. Do not
borrow another app's ID or saved tokens. Document registration and entitlement
as open external gates; fixture success cannot establish subscriber eligibility.

The working implementation adds both routes, provider-bound Responses, minimal
registered-client device authorization with locked rotating credentials, private
setup/doctor, explicit billing and native-replay isolation. xAI's public OpenAPI
schema clarifies that the output cap excludes reasoning and function calls; total-
output reservations therefore refuse. Reported legacy totals disambiguate whether
completion includes reasoning, counting it once; missing evidence stays partial
and mixed dialects/contradictions are invalid.
Reported USD ticks remain separate from aggregate rate-card estimates. Focused
source/integration checks and the `622a2c8` installed proof pass. Its full Linux
native-inclusive suite passes 1760 tests, 19 excluded, followed by an isolated demo;
its complete Ubuntu/macOS matrix passes, including all independent proofs and
experimental macOS checks. The later live-driver candidate exposed two macOS
fixture assumptions: cancellation before command-handler startup and an undersized
eight-client listener queue. Controlled reproductions and 26 focused checks support
test-only repairs. Repaired candidate `288a6a2` passes its complete Ubuntu/macOS
matrix, including all independent and experimental macOS proofs; the
[final receipt](archive/2026-10-24-xai-provider-research/final-hosted.json) preserves
the exact run. Product deadlines and frozen evaluator implementation are unchanged.
The authorized live API check found a project key
but received HTTP 403 on its first `grok-4.7` request and stopped without retry.
API inference remains unverified pending team billing/model permissions; no OAuth
account check has run. The [receipt](archive/2026-10-24-xai-provider-research/verification.json)
keeps these scopes and candidates separate.

Acceptance: unchanged existing-provider golden fixtures; Grok Responses
conformance and native replay/privacy; device/refresh/expiry/denial/rotation and
unsafe-file tests; explicit billing and accurate partial usage/costs; real Session
integration; whole-manual review; full source/native/demo and installed checks;
hosted Linux/macOS. Record API-key and OAuth live checks separately when their
credentials/registration are available. The external-auditor handoff must name
any remaining registration or live-account limits explicitly.

## P30: advisory decision engines

A [native in-flight cross-process control](archive/2026-10-26-p30-p31-implementation/p30-inflight-native-eof-20261103.md)
verifies refusal while a first call remains admitted. The later
[simultaneous settlement control](archive/2026-10-26-p30-p31-implementation/p30-simultaneous-settlement-20261104.md)
observes one known settled winner and both idle/no-replay paths; its loser meets
native-control contention, not demonstrated budget denial. Earlier failed
[preflight cohorts](archive/2026-10-26-p30-p31-implementation/p30-simultaneous-preflight-20261104.md)
remain failed. The [protected selection and assessment increment](archive/2026-10-26-p30-p31-implementation/protected-selection-assessment-20261105.md)
qualifies a full six-note greedy baseline versus a four-note advised pack, then
assessment of an actual main-tool pending proposal: nine main/two decision
requests and two known settled calls under one unchanged finite grant. The
failed original pipeline, separate saved-output qualification and fresh
assessment-only continuation retain their distinct chronology. Synthetic
protocol evidence establishes no model-quality benefit or default strategy.
The later [packaged paired checkpoint](archive/2026-11-05-packaged-paired-cli/index.md)
qualifies its disclosed synthetic installed protocol; broader installed use,
matched evaluation and the whole milestone remain open. The [local disposition
crosswalk](archive/2026-10-26-p30-p31-implementation/p30-local-disposition-20261105.md)
keeps the two consumers and engine-access limits distinct.
The [assessment materializer checkpoint](archive/2026-10-26-p30-p31-implementation/candidate-assessment-materializer-20261106.md)
also qualifies its fresh synthetic prepare/run, authenticated row, Saved/close/idle
and first-row freeze path: seven main requests, one settled decision and explicit
scorer rejection after loading non-independent synthetic labels. Earlier failures
remain separate; accepted scoring, independent quality and matched whole-task
time/cost remain open or null.

The [paired critical selection observation](archive/2026-10-26-p30-p31-implementation/p30-selection-paired-critical-20261106.md)
reports known case-level membership losses even when aggregate recall is unchanged.
Its 28 pure source controls include legacy and current scoring; labels, independence,
the hard gate and the overall experiment disposition remain unverified.

The [critical-recall follow-up](archive/2026-10-26-p30-p31-implementation/p30-critical-unmeasured-20261107.md)
reports an arm's critical count as unmeasured when a critical prediction is not
successful, and withholds the aggregate comparison. Thirty-one synthetic controls
pass; real-input quality and the overall experiment remain unverified.

The [bounded cost-total follow-up](archive/2026-10-26-p30-p31-implementation/p30-cost-safe-sums-20261107.md)
keeps out-of-range sums unmeasured rather than reporting an invalid or understated
cost. Thirty-three pure controls pass; real costs and integrated qualification remain open.

The [assessment route-binding follow-up](archive/2026-10-26-p30-p31-implementation/p30-assessment-route-binding-20261107.md)
checks the frozen public decision profile and selected main-route controls before
new Session work, and checks recorded decision execution before projecting a known
result. Version-1 studies remain readable and scoreable. Thirty-seven direct
synthetic controls and one fresh synthetic native Session assessment pass against
the built runtime; a full baseline on the integrated source remains open. Declared
source/runtime digests and pre-dispatch rubric binding are not established by this
increment, and quality remains unqualified.

**Authorized; typed/protocol and admitted-operation increments in progress.** P31 is the active delivery
path. P30A/B can proceed independently; later
P30 work consumes the first usable notes journey, not the entire P31 milestone.
The [current design](knowledge-design.md#p30-interfaces-and-useful-consumers)
owns detailed contracts. The [final audit disposition](archive/2026-10-26-p30-p31-final-handoff/index.md)
records repairs; the [former plan](archive/2026-10-26-p30-p31-final-handoff/prior-plan.md)
preserves the replaced scope.

Target OpenAI Decisions, TypeSafe's hosted System One API for **Jev**, and a
separately configured loopback SystemOne-compatible endpoint. The developer
confirmed that “Zev” meant Jev; the unrelated `zev-rs` project is not selected.
No local engine, SDK, new dependency or live account eligibility is established.

The [2026-10-31 local follow-up](archive/2026-10-26-p30-p31-implementation/current-local-followup-20261031.md)
has current typed/Session regressions and protected shadow controls over eight
native-reviewed notes from two original Sessions. It does not qualify a
production consumer or replace the separate whole-source baseline.
The [prior-Session shadow assessment](archive/2026-10-26-p30-p31-implementation/decision-shadow-prior-session-20261102.md)
adds an explicitly reviewed, finite numeric-loopback experiment and passes
synthetic bundled approval, denial, expiry and revoked-grant controls. The
same-Session post-write case still refuses; held-out experiments, quality and
final integrated qualification remain open.
The [saved-note shadow result](archive/2026-10-26-p30-p31-implementation/saved-note-shadow-result-20261103.md)
now returns bounded experimental advice or an abstention reason. Synthetic
Session controls cover separate approval, settled accounting, unchanged notes,
source withdrawal at output release and idle reopen without a new request.
This does not assess a pending main-tool candidate or qualify a strategy.
The subsequent [pending-candidate shadow increment](archive/2026-10-26-p30-p31-implementation/p30-pending-assessment-20261103.md)
assesses an actual main-tool-created bundled proposal under a separate finite
grant, with source-loss and replay controls. Its synthetic advice is not a
qualified production strategy, and historical v3 compatible-resume behavior
remains under investigation. An [installed prior-Session control](archive/2026-10-26-p30-p31-implementation/p30-pending-installed-20261103.md)
also passes approved, denied, source-loss and charged-unknown synthetic cases;
it does not establish live decision quality or same-Session assessment. A
[deferred-candidate fixture](archive/2026-10-26-p30-p31-implementation/p30-defer-candidate-20261103.md)
also exercised the non-default advice with an unchanged pending record. An
initial scratch selector exited nonzero after unexpectedly running all eleven
passing cases; a separate fresh targeted case then passed with exit zero.
The [cross-Session experiment controls](archive/2026-10-26-p30-p31-implementation/p30-cross-session-allowance-20261103.md)
observe two settled one-call reservations and no third dispatch, plus a new
Session quarantined after an unknown call. The settled case's third failure is
generic; a separate [timestamp-correlated synthetic trace](archive/2026-10-26-p30-p31-implementation/p30-allowance-interval-20261103.md)
demonstrates the two-call limit caused refusal in that instrumented run.
An [independent cross-process control](archive/2026-10-26-p30-p31-implementation/p30-cross-process-allowance-20261103.md)
also observes that refusal in a new OS process using the same protected ledger,
with no third dispatch. A later [in-flight attempt](archive/2026-10-26-p30-p31-implementation/p30-inflight-allowance-20261103.md)
failed at the second operator channel before its approval or allowance check;
that attempt qualifies neither path. The later native in-flight control above
passes separately; the later simultaneous settlement above does not reclassify
that failed cohort or establish budget-driven exclusion.
The later [exact Linux package proof](archive/2026-10-26-p30-p31-implementation/package-idle-resume-20261031.md#passing-final-package)
passes generic installed checks and the independent synthetic decision/document
artifacts; full-source, consumer-quality and installed knowledge qualification
remain open.

The earlier [complete frozen-source baseline](archive/2026-10-26-p30-p31-implementation/full-suite-546869c8-20261106.md)
at `546869c8` exited 0: 4,288 passed, 136 skipped and 124 excluded, with
matching source, build and toolchain inventories and independently confirmed
cleanup. The later [98267afd regression](archive/2026-10-26-p30-p31-implementation/full-regression-98267afd-20261106.md)
passed 4,294 tests with 136 skipped and 124 excluded. Neither run covers later
commits. The `0cdc36fa` regression completed with 4,305 of 4,309 tests passing,
four failures, 136 skipped and 124 excluded. The failures were hybrid-fixture,
Corpus wrapper isolation, package-fixture and artifact-time-context failures. Their separately repaired
[nine-case](archive/2026-10-26-p30-p31-implementation/domain-hybrid-regression-repair-20261106.md),
[16-case, 33-case and artifact](archive/2026-10-26-p30-p31-implementation/corpus-namespace-test-isolation-20261106.md)
controls pass without changing that run's result. The later isolated
[`6e5e4bdc` regression](archive/2026-10-26-p30-p31-implementation/full-regression-6e5e4bdc-20261106.md)
passed 4,313 tests, with 136 skipped and 124 excluded, matching input checks and
independently confirmed cleanup. It predates the current changes and does not
qualify those exclusions, hosted platforms or the integrated milestones. The earlier
[complete `9f1707c` baseline](archive/2026-10-26-p30-p31-implementation/full-suite-cancel-repair-20261102.md)
followed the [controlled cancellation repair](archive/2026-10-26-p30-p31-implementation/worker-input-cancel-20261102.md).
The earlier [failed `39c8043` execution](archive/2026-10-26-p30-p31-implementation/full-suite-20261102.md)
and `f44b63c` baseline remain preserved.
Required positive integration, lifecycle and fault controls remain open; focused
passes never alter a historical aggregate.

A [later current-source run](archive/2026-10-26-p30-p31-implementation/full-suite-interrupted-20261106.md)
was stopped after three failures, including temporary quota exhaustion and a
nested-test completion-marker defect. The marker repair passes its separate
focused native control and the later frozen baseline above. A complete baseline
on the final current source remains open.
The [saved-result verifier repair](archive/2026-10-26-p30-p31-implementation/saved-result-release-verifier-20261106.md)
passes fresh synthetic source and Linux installed checks while preserving the
earlier failed CI result and the separate macOS uncertainty.
The [knowledge-complete verifier repair](archive/2026-10-26-p30-p31-implementation/knowledge-complete-release-verifier-20261106.md)
also passes fresh synthetic source and installed checks on the frozen 546869c8
runtime. Later source and the separate macOS Memory failure remain unqualified.
The later [consent and close controls](archive/2026-10-26-p30-p31-implementation/consent-and-close-controls-20261107.md)
record 11 failures in a separate broad regression, followed by focused synthetic
passes. The consent workload passed close to its timeout; the Collection close
controls do not establish the cause of its unconfirmed cleanup. A passing final
integrated baseline remains open.

The [synthetic exact-action materializer](archive/2026-10-26-p30-p31-implementation/p30-exact-action-materializer-20261107.md)
checks a frozen rubric and exact parent/request fence through one native terminal
assessment and Saved reconstruction. A changed rubric refused in preflight, and
synthetic labels remained unqualified. An independent audit checked retained
journals, receipts and observed resource closure. An earlier materializer failed
after its synthetic action, and an earlier cleanup removed lock identities for
two fixtures with unmatched invocation intents; neither outcome may be replayed
or inferred. On a combined-source candidate, fourteen focused fence, assessment
and policy checks and seven synthetic Session approval and owner-loss checks pass.
The synthetic materializer also passes with its observed source and runtime
inventories checked against the frozen declaration before execution. These are
point-in-time disk checks; they do not attest loaded code or prevent transient
changes between checks.
This evidence is limited to the fixed synthetic routes and does not
establish general Session egress, live model quality, installed behavior or P30
completion. The broader integrated baseline remains open.

| Package | Output and prerequisites |
| --- | --- |
| P30A | Versioned neutral text contract and pure OpenAI/System One wire subsets implemented; synthetic fixtures and finite experiment/benefit criteria prepared; fixed foundation baseline and incremental audit pass. [Developer contract](developer/decisions.md) |
| P30B | In progress: operator-only profiles, bounded owned HTTP, `host.decision`, Session/replay bindings, v3 usage/prices and shared budgets implemented; [current-source synthetic controls](archive/2026-10-26-p30-p31-implementation/p30-current-decision-followup.md) cover zero-egress refusal, hosted/compatible wire, tampering, owner loss, inert resume and child approvals. A separately built decision artifact and the exact generic Linux package pass synthetic installed checks; the frozen 546869c8 full-source baseline passes, while subsequent changes and live account access remain unverified. No qualified consumer is implied |
| P30C | In progress: [pure Knowledge planners and zero-call controls](archive/2026-10-26-p30-p31-implementation/p30c-pure-policy.md) have an [independent pure-scope audit and reporting correction](archive/2026-10-26-p30-p31-implementation/p30c-pure-policy-audit.md). A later [coverage-gap repair](archive/2026-10-26-p30-p31-implementation/p30c-coverage-followup.md) has a [separate pure-scope review and adversarial grid](archive/2026-10-26-p30-p31-implementation/p30c-coverage-independent-audit.md). A [synthetic planner-to-Session fixture](archive/2026-10-26-p30-p31-implementation/p30-current-decision-followup.md#synthetic-planner-to-session-shadow-control) covers approval and advice mapping; bounded protected selection and pending assessment are implemented and exercised. Qualified consumer selection remains open |
| P30D | Bounded implementation and synthetic protected journey qualified: explicit over-budget note selection retains the complete ordinary greedy baseline, followed by assessment of a real main-tool-created pending proposal under one finite two-call grant. Exact source/get/release, accounting, Saved/close/idle and no-replay checks pass with failed pipelines separately preserved. The [packaged checkpoint](archive/2026-11-05-packaged-paired-cli/index.md) covers the disclosed synthetic selection and answer protocol; broader workloads and installed-user qualification remain open |
| P30E | Synthetic lifecycle qualified: frozen declarations/scoring and protected answer projection retain complete baseline reprojection, inherited provenance, citation byte joins and null timing/cost. The [current-package v2 journey](archive/2026-10-26-p30-p31-implementation/p30-paired-selection-v2-20261106.md) passes actual 8→6→4 projection, physical reference freeze before App, first-row freeze and later unmeasured review/report readback through close/idle. The separate assessment materializer qualifies actual row/freeze and rejection of non-independent synthetic labels, with pending-only versus observed-durable strata preserved. Independent quality, accepted matched real-input/label scoring, whole-task time/cost, current whole-source baseline, broader standalone evaluation and installed-user workflows remain open. Retain useful, rejected/no-benefit and unverified dispositions, unverified engine access and separate live/model evidence; no qualified default. Document/graph routing needs later independent qualification |

Acceptance requires exact result count/type/range/distribution validation, valid
per-question refusal handling, uncertainty and malformed-output distinctions,
permission/reservation/journal admission before egress, cancellation during actual
work and zero dispatch on denial. Decisions choose within saved authority; they
never create evidence, establish truth, grant permission or silently switch a
model provider/paid service. Consent displays operation-specific pricing, endpoint,
processing/storage region, cache retention and verified/unknown account controls.
Freeze per-consumer quality, abstention, latency and cost bars before evaluation.
Hard protocol/integration gates must pass; completed negative experiments can close
D/E and P30 with **no qualified default consumer**. Unavailable engines and
accounts stay unverified and their consumers stay unqualified; that external
unavailability alone does not block a qualified completion of the locally
verified scope. Incomplete local protocol or integration evidence remains open.
Only useful, qualified strategies become selectable; fitting note sets bypass retrieval decisions
without an extra call. Protocol success is not model quality.

The [current signed-note shadow follow-up](archive/2026-10-26-p30-p31-implementation/p30-signed-withdrawal-20261102.md)
passes an eight-note synthetic decision positive and its source-withdrawal
control. The latter checks no decision dispatch, partial accounting, unknown
Worker input, original-source restoration and idle recovery. Earlier failed
fixture expectations are retained in that record. This is scoped P30C
integration evidence; consumer selection, live engines and quality remain open.

## P31: usable knowledge and prompt assistance

The Research worker now checks captured-source time transitions before proposing
a rerank and before constructing its result; [controlled-clock source tests](archive/2026-10-26-p30-p31-implementation/research-time-boundary-20261107.md)
pass. Actual Host dispatch, later Session delivery and the final integrated
baseline remain separate unqualified boundaries.

The [v19 literal-bullet increment](archive/2026-10-26-p30-p31-implementation/word-bullet-v19-20261107.md)
passes 51 focused extraction/citation tests and a synthetic Collection Session
journey using the newly built artifact. General Word fidelity, installed use,
PDF verification and the final integrated baseline remain open.

The [public backup identity control](archive/2026-10-26-p30-p31-implementation/public-backup-identity-20261107.md)
now exercises origin-pinned page and plan results across inactive Sessions and
refuses a rehashed catalog/head mismatch in a seeded synthetic Collection. Its
initial same-Session attempt remains failed; broader backup and migration remain open.

The [v18 document verifier repair](archive/2026-10-26-p30-p31-implementation/document-verifier-v18-20261106.md)
passes fresh synthetic source and installed `fff77fbe` DOCX/PDF proofs after a
stale v16 expectation failed CI. The later planning runtime still needs its own
final package qualification.

The [initial document controller model](archive/2026-10-26-p30-p31-implementation/document-initial-public-model-20261106.md)
returns a selected synthetic generation for 1,000 sources and 10,000 chunks,
with an independently reconciled trace and approximately 3.59 GB of minimum
modeled action-journal bytes. Native Session handoffs, physical peaks, capacity
fit and the complete recipe remain unqualified.

The [Graph query fence candidate](archive/2026-10-26-p30-p31-implementation/graph-query-fences-20261106.md)
has synthetic source and built-artifact controls for captured-snapshot time and
generation changes. A [worker result-time follow-up](archive/2026-10-26-p30-p31-implementation/graph-result-time-20261107.md)
also checks eligibility after result preparation in fake-State and fake-MCP
fixtures. A separate State Session journey passes on the earlier
host SDK, without injecting those query races. Current-host native race tests,
real MCP, installed and full integrated qualification remain open.

The [exact query-prefix candidate](archive/2026-10-26-p30-p31-implementation/query-prefix-double-20261106.md)
has synthetic State, MCP and Collection refusal controls and fresh State and
Collection artifact controls. A bounded synthetic Collection Session also passes;
installed and full integrated verification remain open.

The [Corpus State/MCP namespace-fence candidate](archive/2026-10-26-p30-p31-implementation/corpus-namespace-fence-20261106.md)
has synthetic source and wrapper controls for concurrent insertion, empty
snapshots, batched tokens and a simulated document current-use callback.
Separate fixture controls cover 32 fetched sources and 32 selectors; Collection
checks cover routing only. Two [State Session controls](archive/2026-10-26-p30-p31-implementation/focused-session-20261106.md)
now cover a concurrent root insertion and source expiry during a workspace check.
Native Collection and broader real MCP race coverage remain open. A separate [full-snapshot time candidate](archive/2026-10-26-p30-p31-implementation/corpus-query-time-20261106.md)
has 14 private synthetic controls for source/fact boundaries, explicit history,
pre-rerank proposal and a simulated workspace callback. The integrated wrapper
also passed by owner report, without a retained raw log; real transport remains
unverified. A separately reviewed synthetic source candidate extends the check
to hydrated remote-selected sources; omitted sources remain outside its coverage.
Collection namespace and explicitly selected queries have a separately reviewed
source-time candidate with synthetic closed-host controls, including an empty
namespace and a simulated workspace callback. Selected semantic fact checks use
controlled continuations. The [isolated wrapper repair](archive/2026-10-26-p30-p31-implementation/completed-backup-wrapper-repair-20261106.md)
preserves a failed combined run, a separately passing 19-case wrapper and a
later three-wrapper pass. Real
Collection Session, shared-generation semantic hydration, approval-to-dispatch
timing and delivery leases remain open. The synthetic MCP verifier passes
separate [source](archive/2026-10-26-p30-p31-implementation/knowledge-mcp-source-verifier-20261106.md)
and [installed](archive/2026-10-26-p30-p31-implementation/knowledge-mcp-installed-verifier-20261106.md)
checks; their retained unknown outcomes and cleanup scope remain explicit.

The [expected-forget target control](archive/2026-10-26-p30-p31-implementation/expected-forget-target-20261106.md)
adds an opt-in internal exact-target and control-ledger constraint with a fresh
synthetic native journey. It does not qualify other lifecycle operations, annual
turnover or recovery from an active-effect owner loss.

**Active implementation track; P31A qualification and P31B host primitives in progress.**
An [actual helper interposition](archive/2026-10-26-p30-p31-implementation/strict-deadline-interposition.md)
confirmed that the current userspace deadline check can precede expiry while the
following root rename occurs after it.
Narrow new-v3 capture and public reviewed forgetting have scoped native controls
and independent reviews. Reviewed retention and session-only choices also have
scoped native controls. Interactive literal correction and supersession now have
[source-owned native review and publication controls](archive/2026-10-26-p30-p31-implementation/managed-supersession-native-20261031.md);
accepted-decision targets and headless replacement remain closed.
The [independent gate review](archive/2026-10-26-p30-p31-implementation/strict-deadline-gate-independent-review.md)
also identified reviewed-forget and State-backed draft timing boundaries. Actual
controls reproduced late effects in both; [focused interim gates](archive/2026-10-26-p30-p31-implementation/strict-gate-lifetime-followup.md)
initially refused those operations while ordinary no-deadline State writes remained
available. A subsequent [requirements audit](archive/2026-10-26-p30-p31-implementation/expiry-requirements-audit.md)
recovered the original State contract: the final locked publication decision,
after staging, is the linearization point; physical rename completion within
the same millisecond was explicitly excluded. The reviewed
[State restoration design](archive/2026-10-26-p30-p31-implementation/state-deadline-restoration-design.md)
also requires the actual native lock owner to perform every State replacement.
That backend has [focused controls](archive/2026-10-26-p30-p31-implementation/state-native-owner.md)
and an [independent backend review](archive/2026-10-26-p30-p31-implementation/state-native-owner-independent-review.md).
State-only timed execution has [actual Memory/Session controls and independent integration review](archive/2026-10-26-p30-p31-implementation/state-restoration-independent-review.md).
Ordinary document staging also has a separate
[scoped restoration and controls](archive/2026-10-26-p30-p31-implementation/document-decision-restoration.md)
and [independent implementation review](archive/2026-10-26-p30-p31-implementation/document-decision-restoration-implementation-review.md).
It uses the final locked decision and adds explicit host refusals for managed
document mutations. These changes do not open notes/capture, managed document,
retention, Review or managed-output gates, weaken later-use source eligibility
or permit revocation acknowledgment to overtake an admitted native owner.
Actual contention controls also exposed legacy fresh-header and subsequent
journal mutations outside their surviving native lock owner. Native-owned
[header](archive/2026-10-29-native-shared-lease/session-header-native.md) and
[journal append/repair](archive/2026-10-29-native-shared-lease/native-journal-owner.md)
repairs have focused controls and scoped independent review; whole-source and
installed qualification remain pending.
Earlier positive publication controls below identify historical cohorts; they
do not qualify the post-gate behavior or prove atomic expiry fencing.
Standalone native permission review and literal capture have component controls;
automatic capture, current recall and lifecycle management remain open. P30 numbering does not imply it
must finish first. P26/P27 retain
their completed original scopes, P20 remains completed and voice/media stays P32.
Implementation is authorized; release publication is not.

The selected outcome is automatic useful-fact/decision capture with visible changes,
permission remembered across sessions, retrieval before material clarification,
automatic routing only among enabled knowledge sources, and PDF/Word ingestion.
The audit follow-up adds these explicit choices: enablement takes effect in the
next new session; saved knowledge consent also applies to headless `run` without
`--yes`; graph/PDF may remain experimental/off under qualified completion; a narrow
Rust PDF-parser exception is allowed when maintained Elixir/Erlang options are
unsuitable. Workspace/shell/MCP/delegation authority remains separate.

The [current design](knowledge-design.md) is the single
detailed contract specification: proposed command vocabulary, main-model capture,
source intake, retention, worktree sharing, headless admission, process coordination,
document extraction, prompt editing and release qualification. This ledger owns
delivery status/dependencies and gates; do not duplicate its lifecycle prose here.
The developer's subsequent [local Ollama request](archive/2026-10-26-ollama-local-rag/index.md)
adds an optional embedding/RAG route: Qwen3-Embedding 0.6B and Qwen3.5 4B are the
primary qualification targets, with a smaller EmbeddingGemma 2 text challenger
and an available Qwen3.5 9B comparison. Model details and contracts live in the
[design](knowledge-design.md#optional-local-embeddings-and-rag), not this ledger.

The [bounded v16 Word numbering increment](archive/2026-10-26-p30-p31-implementation/word-numbering-20261102.md)
records direct single-level decimal labels as locator metadata, with focused
extraction and native Session checks. A [PDF-free synthetic Linux package](archive/2026-10-26-p30-p31-implementation/word-numbering-installed-20261103.md)
also passes acquisition, cited retrieval, changed-file refusal and resume in
both State and Collection. A [40-block packed-numbering fixture](archive/2026-10-26-p30-p31-implementation/word-packed-numbering-installed-20261103.md)
also passes those paths in both profiles, with a separate pure forged-label
control. The [default PDF-enabled Linux package](archive/2026-10-26-p30-p31-implementation/default-pdf-package-20261103.md)
also passes synthetic installed document and packed Word setup controls in both
profiles. A [subsequent installed recovery control](archive/2026-10-26-p30-p31-implementation/word-disappearance-installed-20261103.md)
checks missing-original refusal across Session reopen and the same citation after
restoring the original file in both profiles, without acquisition replay.
The [larger Collection Word checkpoint](archive/2026-10-26-p30-p31-implementation/word-collection-larger-20261103.md)
adds bounded snapshot acquisition, current-file checks at publication and a
36,251-byte installed synthetic document journey. State retains its 32 KiB
original limit. That historical registration-cancellation result remained cleanup-unconfirmed.
The [current source bound/cancellation checkpoint](archive/2026-10-26-p30-p31-implementation/word-capacity-cancel-20261104.md)
now confirms unstarted cleanup and the bounded 1-MiB acquisition/citation/recovery
journey. The [exact installed Collection ceiling control](archive/2026-10-26-p30-p31-implementation/word-installed-capacity-20261104.md)
now passes that bound, three independent overflow dimensions, file recovery and
final Saved/idle no replay in the 6adb7aca package. Independent file fidelity remains open.
Broader document capacity, independent Word and PDF quality, other
platforms and the broader P31F requirements remain open.

An [independent frozen Word cohort](archive/2026-10-26-p30-p31-implementation/word-independent-extraction-20261104.md)
returned twelve v16 refusals. A separate frozen v17 repair candidate produced
twelve partial extractions/payloads and passed 62 bounded support checks. The
[integrated Research/Word checkpoint](archive/2026-10-26-p30-p31-implementation/research-word-integration-20261104.md)
now passes strict host/artifact builds, 63 focused tests and two fresh v17
Collection capacity/citation/recovery controls. Full locator mapping,
semantic/rendering, other installed profile/package combinations and final
combined qualification remain open; the exact Collection ceiling is qualified
separately above.

A later [independent logical oracle and v18 repair](archive/2026-10-26-p30-p31-implementation/word-logical-oracle-20261105/index.md)
freezes complete text, visibility and source coordinates before candidate
inspection. The existing v17 artifact failed all twelve complete comparisons
because it emitted footnote layout separators. V18 excludes declared layout
entries while retaining ordinary notes and original paragraph ordinals. All
twelve originals, 144 blocks and both payload profiles now agree with that
oracle; fifty focused regression tests pass. Every document remains partial
with its body-formatting warning. These exposed remediation inputs do not
establish fresh held-out quality, installed citation joins or full P31F acceptance.

The [bounded table-row context increment](archive/2026-11-05-word-row-context/index.md)
addresses a returned label cell whose adjacent value had no query terms. Direct
BM25 snapshots retain lexical hits first and add source-exact sibling-cell context
within the existing result limit, with separate provenance and explicit scope.
The source-runtime checks pass, including both storage profiles and changed-file
refusal. The [fresh installed 24-case run](archive/2026-11-05-word-installed-row-context/index.md)
matched all 24 document manifest commitments and 20 applicable raw revision
ancestry joins, but failed its frozen citation target at 122 of 124 support slots.
Both misses were the same no-token-overlap query under the two profiles. Indexed
namespace parity, multi-block expansion, explicit returned revision fields and
broader Word/model quality remain open; the failed run is not retroactively passed.

A separate [supplied-Word comparison](archive/2026-10-26-p30-p31-implementation/word-semantic-supplied-comparison-20261106.md)
now completes 152 within-document State results and twelve close/idle journeys
under a fresh pinned local runtime. Independently frozen scoring finds matching
support and citation bytes/locators in 61/62 lexical and 62/62 dense support slots.
Its 148 embedding requests are accounted. This does not qualify installed
acquisition, current-file use, precision, answers or general Word coverage; all
results retain their partial-coverage warning.

The [operator-authored planning-decision increment](archive/2026-10-26-p30-p31-implementation/operator-planning-20261103/index.md)
adds a separate native acceptance and explicit post-exit save with linked original
provenance. Its synthetic verification passed 11 native journeys and 95 focused
regressions. A later [assistant-proposed increment](archive/2026-10-26-p30-p31-implementation/assistant-planning-decision-20261106.md)
adds exact-quote acceptance, post-exit staging and independent review, with scoped
native stale/source/permission/unknown controls. Wider source combinations,
independent-human qualification, and the rest of P31I remain open.

An [installed synthetic operator-decision check](archive/2026-10-26-p30-p31-implementation/planning-decision-installed-20261107.md)
passes save and revoked-consent scenarios against a pinned PDF-free package. A
separate [installed assistant-decision check](archive/2026-10-26-p30-p31-implementation/assistant-planning-installed-20261107.md)
passes six synthetic positive and failure journeys against that same package.
Broader source combinations, independent-human use, other platforms and the
default package remain unqualified.

The [Anthropic tool-assisted draft increment](archive/2026-10-26-p30-p31-implementation/anthropic-tool-draft-20261107.md)
adds bounded withdrawal for matched, isolated tool groups. Seven focused
validation tests and 25 synthetic Session tests pass on an isolated source copy;
native-terminal, installed, live and final integrated qualification remain open.

The [Ollama draft recovery increment](archive/2026-10-26-p30-p31-implementation/ollama-draft-recovery-20261103.md)
supports cancellation or acceptance of a plain-text draft while preserving unrelated
native continuation on later turns and resume. A [no-tool thinking follow-up](archive/2026-10-26-p30-p31-implementation/ollama-draft-thinking-20261103.md)
also withdraws a bounded native thinking field with the draft, with synthetic
Session and terminal acceptance/cancellation controls. A [packaged synthetic
follow-up](archive/2026-10-26-p30-p31-implementation/ollama-draft-installed-20261103.md)
passes acceptance and cancellation via release eval. Tool-assisted drafts,
public installed chat, live-model and full integrated checks remain open.

A [current direct-client control](archive/2026-10-26-p30-p31-implementation/assistant-proposal-current-20261102.md)
now saves a synthetic completed assistant reply as signed pending material with
its original source attribution. A synthetic main model can select that reply
on an explicitly requested later turn; a fabricated quotation is refused, and
separate native review preserves that attribution on acceptance. A fresh-session
synthetic recall includes the accepted decision and withholds it when the original
source is missing. That earlier control used a fresh Session to recover from
stale protected history in the original conversation.
A [completed-reply assistant-proposal operation](archive/2026-10-26-p30-p31-implementation/chat-completed-reply-20261104.md)
now binds an exact main-model nomination to protected capture, native review and
same-ID chat resume. Four bounded actual controls cover normal-start accept,
cancel and stale selections. A separate
[explicit-resume control](archive/2026-10-26-p30-p31-implementation/chat-explicit-resume-20261104.md)
passes fresh review after known cancellation without recapture. A subsequent
[same-ID next-prompt control](archive/2026-10-26-p30-p31-implementation/chat-same-id-followup-20261104.md)
passes current recall and provider dispatch while preserving the original
nomination tool call and native continuation. Broader source combinations and
complete integrated qualification remain open. Planning-start/exit has the bounded
actual control linked above.
The baseline does not require blanket extraction from final replies.
The [chat-card consistency check](archive/2026-10-26-p30-p31-implementation/pending-chat-journal-binding-20261102.md)
now refuses different Session and journal IDs before review and rejects a source
check using another Session's pinned admission; it does not create an in-chat
review or effect path. A source-owner adapter now distinguishes inactive leases
from an active Session that still needs its real Session/Writer share.
The [33-note native recall diagnostic](archive/2026-10-26-p30-p31-implementation/recall-many-native-20261102.md)
found an unconfirmed worker-input handoff before provider dispatch on both the
original 32-note worker and an attempted larger candidate limit. A later pure
projection found that its original 33 texts exceeded the context envelope. An
[isolated paged-recall candidate](archive/2026-10-26-p30-p31-implementation/recall-paging-20261102.md)
passed a shorter 33-fitting-note fixture, a missing-original case and a
reappearance case using a 15-second synthetic provider timeout. Those controls
also pass on the later combined P30 candidate. Arbitrary sparse coverage,
final-use absence revalidation and full-source qualification remain open.
[Bounded replay computation](archive/2026-10-26-p30-p31-implementation/recall-replay-capacity-20261102.md)
reduces repeated pure encoding and hashing without caching source authority.
An exploratory [batched-read prototype](archive/2026-10-26-p30-p31-implementation/recall-batched-read-20261102.md)
also failed the native control and was not retained. A later [task-scoped source
replay](archive/2026-10-26-p30-p31-implementation/task-source-replay-20261102.md)
passes the existing 32-note native control with a 15-second synthetic provider
timeout. A later [owned-cache repair](archive/2026-10-26-p30-p31-implementation/recall-owned-cache-20261103.md)
passes its focused ownership controls. A later [strict current 33-original-source
control](archive/2026-10-26-p30-p31-implementation/recall33-strict-sources-20261104.md) passes in
125 seconds at the unchanged five-second provider limit, including exact complete
text and committed-read provenance for all 32 eligible notes, missing/reappearing
original partial coverage, unchanged source identities and idle reopen without
replay. The 2,000-note cohort, integrated day,
annual workload and complete recall qualification remain open.

| Package | Output and prerequisites |
| --- | --- |
| P31A | In progress: amended baseline archived; host ownership/contracts, nonpublishing interaction/pilot probes, storage/parser evaluation and human journeys prepared. The [candidate-audit pilot](archive/2026-10-26-p30-p31-implementation/pilot-usage-privacy.md) remains an incomplete 96-response-record run. [Exact label coverage and provisional intake freeze](archive/2026-10-26-p30-p31-implementation/pilot-label-intake-freeze-20261104.md) confirm the existing independent-agent labels cover all 57 observed initial turns and 39 candidates; the unchanged 57-effect/40-turn day has reviewed assumptions and private declaration-pin refusal controls. This supplies no representative, human or quality ratification. A [direct native statement maximum](archive/2026-10-26-p30-p31-implementation/native-statement-maximum-20261104.md) now passes one fresh ordinary 4062-byte value with proof/source overflow and idle no-replay; other record-shape maxima remain open. [Generic saved-policy accounting](archive/2026-10-26-p30-p31-implementation/saved-policy-budget-metadata-20261104.md) passes ten focused native/worker controls. The [pending-proposal burst](archive/2026-10-26-p30-p31-implementation/native-burst-320-20261105.md) qualifies 40 turns/320 raw proposals, queue/budget advice, 100 known settled operations, current pins/sources and four idle checks through immutable audit and separate tails; the original 30-minute aggregate and first tail remain failed. This is no annual, resource-feasibility or quality qualification. Integrated intake/workload ratification and human/platform evidence remain open. See [record](archive/2026-10-26-p30-p31-implementation/index.md) |
| P31B | In progress: native input, actual-owner transactions, protected identity/control, managed Collection SDK and registered inference dispatch have local controls and scoped audits. [Allocation recovery](archive/2026-10-26-p30-p31-implementation/sol-recovery.md) settles retained stages before counting and refuses sync errors. [Owned native inference send and result release](archive/2026-10-26-p30-p31-implementation/owned-send-integration.md) now have actual-adapter local HTTP/TLS controls. Standalone permission review, next-session readiness, headless save, revocation and [reviewed management](archive/2026-10-26-p30-p31-implementation/managed-forget.md) have native controls. [Fresh/resumed release-claim integration and independent review](archive/2026-10-29-native-shared-lease/release-receipt-integration-independent-review.md) identified a real post-helper-loss journal ownership race and a journal-size mismatch. [Native-owned append/repair and independent review](archive/2026-10-29-native-shared-lease/native-journal-owner-independent-review.md) now cover the repaired actual-owner boundary; actual CLI EOF/death/unlock-response controls also cover the stronger cleanup caller. [Retained native close and private Session lock sharing](archive/2026-10-29-native-shared-lease/session-share-candidate-independent-review.md) have scoped independent review. Private operation sealing and [actual Session/Host control wiring](archive/2026-10-29-native-shared-lease/session-control-wiring-independent-review.md) are independently reviewed. The [synthetic tty repair and additive review](archive/2026-10-29-native-shared-lease/terminal-display-synthetic-independent-review.md#additive-v7-repair-disposition) close reproduced incomplete-lease and post-readiness deadline defects; actual caller/Review integration and production tty delivery remain open. The [retained exact management snapshot](archive/2026-10-26-p30-p31-implementation/management-snapshot-read-independent-review.md) has scoped acceptance, while [continuous Collection reads](archive/2026-10-26-p30-p31-implementation/collection-held-read.md) have25affected controls and [independent token-seal repair acceptance](archive/2026-10-26-p30-p31-implementation/collection-held-read-independent-review.md#additive-v2-repair-disposition), preserving the original post-publication known-refusal counterexample. The [held signed-target adapter](archive/2026-10-26-p30-p31-implementation/management-held-target-independent-review.md) has four selected actual domain/native controls and scoped independent acceptance. The [private actual Session/Host tty bridge](archive/2026-10-29-native-shared-lease/tty-session-bridge-independent-review.md) and [original management journal/control prerequisite](archive/2026-10-26-p30-p31-implementation/management-share-controls-independent-review.md) are separately accepted within their inactive scopes. The [full private management display and deadline repair](archive/2026-10-26-p30-p31-implementation/management-display-deadline-repair.md) and [genuine-input no-mutation review](archive/2026-10-26-p30-p31-implementation/management-review-input-independent-review.md) have scoped acceptance. A [forget-only Core fence change](archive/2026-10-26-p30-p31-implementation/reviewed-forget-core.md) retains retention/supersession and strict-deadline fences; the [private genuine-input journaled effect](archive/2026-10-26-p30-p31-implementation/management-forget-effect-independent-review.md) is independently accepted for actual mutation, late-commit unknown and scoped loss controls. [Changed-target/root/recipe and post-dispatch owner-loss qualification](archive/2026-10-26-p30-p31-implementation/management-forget-qualification.md), [public caller restoration](archive/2026-10-26-p30-p31-implementation/management-forget-public.md), and [fresh full-host/current-artifact integration](archive/2026-10-26-p30-p31-implementation/management-forget-current-source.md) now have scoped independent acceptance. Public forgetting and reviewed retention are restored within their scoped native controls. Interactive literal replacement now has [source-owned native review/publication and loss controls](archive/2026-10-26-p30-p31-implementation/managed-supersession-native-20261031.md); generic unreviewed APIs remain closed. [Standalone management journal ownership](archive/2026-10-26-p30-p31-implementation/management-journal-owner.md) now uses the native header/append owner; its initial review found a serialized metadata-key bypass, with a [focused repair independently accepted](archive/2026-10-26-p30-p31-implementation/management-journal-owner-independent-review.md). Full source/package/platform and endpoint-recovery qualification remain open. The [exact available-kernel tmpfs profile](archive/2026-10-28-native-profile/index.md) has native qualification; newer-kernel Btrfs remains unsupported |
| P31C0 | In progress: [original journal identity](archive/2026-10-26-p30-p31-implementation/sol-source-origin.md), [protected source reads](archive/2026-10-26-p30-p31-implementation/current-source-read.md), [durable read unions](archive/2026-10-26-p30-p31-implementation/managed-read-receipts.md), producer inheritance and causal replay have focused controls. [Batched preflight/expiry](archive/2026-10-26-p30-p31-implementation/managed-use-preflight.md) and [actual native inference send/result release](archive/2026-10-26-p30-p31-implementation/owned-send-integration.md) are locally verified; preflight repairs have scoped independent review. [Direct extension-result final release](archive/2026-10-26-p30-p31-implementation/managed-output-integration.md) has focused controls; subsequent cleanup repairs and their independent review remain scoped to that boundary. The [source-lock reserve](archive/2026-10-28-source-lock-reserve/index.md) has focused 128-lock and owner-loss controls, not a complete 128-note recall qualification. [Managed MCP start/send](archive/2026-10-26-p30-p31-implementation/managed-mcp-integration.md) has actual Session controls. [Managed verified-HTTPS peer-loss controls](archive/2026-10-29-managed-http-peer-loss/index.md) and [independent evidence review](archive/2026-10-29-managed-http-peer-loss/independent-review.md) cover explicit-allow nested Session/transport/discovery loss, post-effect disconnect and untrusted certificates without replay. A separate [bulk discovery repair and review](archive/2026-10-29-mcp-discovery-outcome/independent-review.md) preserve the typed unknown outcome; the separate [extension discovery adapter repair](archive/2026-10-29-mcp-discovery-outcome/extension-independent-review.md) also preserves typed unknown. Broader HTTP faults and approval shapes outside the scoped native model-tool path remain open; managed worker-result delivery has the bounded export controls below. [Managed MCP discovery and held-binding document publication](archive/2026-10-26-p30-p31-implementation/managed-actions-document.md) have focused current/stale and deadline Session controls on the recorded earlier approval cohort; ordinary model approval now has the scoped native display controls below; other unqualified shapes still refuse. The [nested-result input follow-up](archive/2026-10-26-p30-p31-implementation/nested-result-input-20261101.md) now permits known native/MCP outcomes through the pinned export fence; managed document results remain gated. The [retained native stdin component](archive/2026-10-26-p30-p31-implementation/worker-stdin-ownership-20261031.md) lends the actual supervisor pipe to the existing protected transaction owner. [Pending Worker reservation and sealed native bytes](archive/2026-10-26-p30-p31-implementation/worker-input-frame-20261101.md) bind the actual artifact/frame, buffer early responses and remove the unrelated 256-handoff ceiling; The [Session export-input adapter](archive/2026-10-26-p30-p31-implementation/worker-input-session-20261101.md) binds versions 3–5, and the [accepted-input follow-up](archive/2026-10-26-p30-p31-implementation/accepted-worker-input-20261101.md) adds original management-journal ownership for version 6; other Worker purposes have the explicit refusals below and retain separate qualification. [Managed tool progress, approval and special host operations](archive/2026-10-26-p30-p31-implementation/managed-host-display-refusal.md) currently refuse when the required current-use output or effect fence is unavailable. An [independent review](archive/2026-10-26-p30-p31-implementation/managed-host-display-independent-review.md) found legacy pending-question disclosure, unfenced managed State/service operations and a two-source publication bypass. [Focused repairs](archive/2026-10-26-p30-p31-implementation/managed-audit-repairs.md) now refuse these paths and preserve ordinary capture; [Focused follow-up](archive/2026-10-26-p30-p31-implementation/managed-publication-deadline-followup.md) covers policy-deadline propagation, exact question-parent binding and stopped-helper controls. Its [independent review](archive/2026-10-26-p30-p31-implementation/managed-publication-deadline-independent-review.md) identified a check-to-rename race, since [reproduced on the actual helper](archive/2026-10-26-p30-p31-implementation/strict-deadline-interposition.md); the later [original-contract review](archive/2026-10-26-p30-p31-implementation/notes-publication-restoration-independent-review.md) distinguishes final locked admission from physical rename completion, and the [new single-v3 capture scope](archive/2026-10-26-p30-p31-implementation/notes-publication-admission.md) has focused native controls and independent implementation review. Generic strict legacy APIs remain closed. The [literal-source upgrade control](archive/2026-10-26-p30-p31-implementation/literal-v4-source-union.md) now proves stale original A plus fresh B refuses before a managed publication intent on the verified current prerequisite code; it does not qualify publication or all output sinks. Other approval-delayed tool integration, complete withdrawal/recall journeys, proposal review, retention integration, export and final integrated qualification remain open. Unsupported projections refuse. Internal only; follows A/B |
| P31C1a | In progress: versioned storage, worktree admission, pure temporal policy, reclamation/import and measured import headroom have component controls. The old [V2 fixed-shard failure](archive/2026-10-26-p30-p31-implementation/managed-storage-continuation.md) is preserved. An [actual V3 run](archive/2026-10-26-p30-p31-implementation/capacity-available-host.md) reached 4,000 notes with complete receipt reconciliation and peak accounted allocation below 64 MiB. [Native-reviewed literal forgetting](archive/2026-10-26-p30-p31-implementation/managed-forget.md) integrates signed suppression, disabled-capture management and measured settlement; its [public current-source caller](archive/2026-10-26-p30-p31-implementation/management-forget-current-source.md) is now restored and independently reviewed. [Typed retention Core](archive/2026-10-28-managed-retention/index.md) and [actual CLI choices](archive/2026-10-26-p30-p31-implementation/retention-cli.md) have focused controls; [native final-switch expiry fencing](archive/2026-10-28-retention-publication-deadline/index.md) has delayed-publication controls; the [new-helper CLI journey](archive/2026-10-26-p30-p31-implementation/retention-cli.md#added-cli-integration-with-the-final-switch-helper) also passed. [Signed expiry reclamation](archive/2026-10-28-managed-expiry/index.md) and its [actual standalone CLI journey](archive/2026-10-26-p30-p31-implementation/expiry-cli.md) have focused controls and a scoped independent caller review. [Correction and temporal supersession](archive/2026-10-28-managed-supersession/index.md) have native component controls, including a forced eight-sidecar publication; Earlier [Session and terminal controls](archive/2026-10-28-managed-supersession-session/index.md) cover a superseded cohort. The current interactive literal handoff now has [actual native display/publication and owner-loss controls](archive/2026-10-26-p30-p31-implementation/managed-supersession-native-20261031.md), including cross-session sources and post-switch idle recovery without replay. Generic unreviewed supersession and accepted-decision replacement remain closed. [Native accepted-decision forgetting](archive/2026-10-26-p30-p31-implementation/accepted-decision-forget-20261101.md) has source controls after disabled capture and unavailable original source, preserving the immutable link, peer and authenticated suppression. A [post-effect native-owner-loss control](archive/2026-10-26-p30-p31-implementation/accepted-decision-forget-loss-20261101.md) verifies durable removal, unconfirmed journal/publishing liability and nonreplaying read-only inspection; whole-source qualification remains open. [Accepted-decision expiry](archive/2026-10-26-p30-p31-implementation/accepted-decision-expiry-20261101.md) adds signed finite-deadline reclamation through the existing reducing management path, preserving original clocks and immutable links; [Native accepted retention](archive/2026-10-26-p30-p31-implementation/accepted-decision-retention-20261101.md) adds explicit pin, automatic and duration choices through metadata-only publication, preserving the public record/link and binding current read witnesses; accepted replacement and complete qualification remain open. [Historical observation and expiry](archive/2026-10-28-managed-history/index.md) have focused controls; the [current native history-expiry journey](archive/2026-10-26-p30-p31-implementation/history-expiry-session-20261101.md) now uses an actual Session correction/source and elapsed signed deadline, with the successor and original journal preserved. [Shared-evidence and historical-use component controls](archive/2026-10-26-p30-p31-implementation/literal-lifecycle-launchers-20261031.md) now pass on the genuine relation path; full integrated qualification remains open. A [test-process clock fixture](archive/2026-10-26-p30-p31-implementation/process-clock-20261102.md) verifies fresh VM/Rust coherence; the [actual native clocked component](archive/2026-10-26-p30-p31-implementation/native-clock-lifecycle-20261102.md) adds a signed day-30 pin and day-91/day-366 reclamation across fresh processes, preserving the original source and settled receipts. It does not execute the full annual workload. A [late first-supersession control](archive/2026-10-26-p30-p31-implementation/native-clock-late-supersession-20261102.md) uses a disclosed private stdio-clock host for a day-100 relation and retention through days 366/464 before day-466 reclamation. Compaction and actual 30/90-day/annual turnover remain; follows C0, **required before E release** |
| P31D0 | In progress: native capture artifact/build catalog, standalone permission review/status/revocation and next-new-session activation have local source controls. [Readiness reporting](archive/2026-10-26-p30-p31-implementation/knowledge-readiness.md) distinguishes a saved activation match from broad publication support; the plain notice also describes the narrower reviewed-statement path. Its permission/status control does not itself enable capture. Installed retention acceptance, separate local embedding/answer choices and installed notes acceptance remain; installed packaging depends on C1a. Optional local preset follows D1/F |
| P31E | Main-model capture, explicit proposal acceptance, stable-prefix turn-local recall/source paging and quality remediation; follows B/C1a/D0; **interim notes release checkpoint**. [Native statement/category review](archive/2026-10-26-p30-p31-implementation/native-assertion.md) drives protected `/remember` capture without inference; plain/generated inputs stay pending and workers cannot promote reviewed categories. The [narrow new-v3 publication scope and prerequisite repair](archive/2026-10-26-p30-p31-implementation/notes-publication-implementation-independent-review.md) now have independent implementation acceptance; [genuine Session publication](archive/2026-10-26-p30-p31-implementation/remember-publication-absence-integration.md) and [top-level Terminal controls](archive/2026-10-26-p30-p31-implementation/remember-terminal-headless-controls.md) pass. Actual headless typed-outcome controls expose causal-root/source-tool gaps; their [reviewed repair direction](archive/2026-10-26-p30-p31-implementation/causal-root-and-source-tools-direction-independent-review.md) preserves the whole authenticated union and native output boundary. The [causal-root cache](archive/2026-10-26-p30-p31-implementation/causal-root-cache.md) now implements chronological classification and a direct-client saved-consent headless positive without --yes; [All-selected-source preflight](archive/2026-10-26-p30-p31-implementation/managed-source-tool-preflight-independent-review.md) and [own-write historical-root continuation](archive/2026-10-26-p30-p31-implementation/own-root-transition-independent-review.md) now have scoped independent acceptance. The final synthetic-model journey captures, performs later source list/read and completes the turn successfully with settlement, Saved and confirmed close. Repeated capture, current-record output, broader provider/loss cases and complete capture/recall qualification remain open. [Reviewed forgetting](archive/2026-10-26-p30-p31-implementation/managed-forget.md) has an actual native CLI journey. [Automatic turn-local recall/source paging](archive/2026-10-26-p30-p31-implementation/recall-integration.md) has focused actual Session controls; the [pure pending projection and contract review](archive/2026-10-26-p30-p31-implementation/pending-projection-independent-review.md) supplies structural parsing only. Standalone [pending review](archive/2026-10-26-p30-p31-implementation/pending-review-cli-20261031.md) supports signed revision/hash-bound acceptance with a linked event and original provenance, as well as separately reviewed correction. [Completed-reply native chat review](archive/2026-10-26-p30-p31-implementation/chat-completed-reply-20261104.md) passes bounded normal-start accept/cancel/stale controls with confirmed close and same-ID resume. [Explicit-resume review](archive/2026-10-26-p30-p31-implementation/chat-explicit-resume-20261104.md) also passes known-cancel/fresh-code acceptance without recapture. [Planning-exit acceptance](archive/2026-10-26-p30-p31-implementation/chat-planning-mode-20261104.md) passes with idle reopening. The first ordinary same-ID follow-up now passes current recall and provider dispatch while preserving its original tool call and native continuation. Safe legacy treatment and integrated intake/cache/latency/quality remain open |
| P31C1b | In progress: the [internal document epoch fence](archive/2026-10-26-p30-p31-implementation/document-maintenance-epoch-20261105.md) has native lifecycle, SDK stale-stage/fresh-publication and selected migration compatibility controls; [Source and lexical Index epoch integration](archive/2026-10-26-p30-p31-implementation/document-continuation-epoch-20261106.md) has separate limited native/Session and public workspace/retirement controls. A later [progress-provenance review](archive/2026-10-26-p30-p31-implementation/document-progress-provenance-gap-20261106.md) found that Source counters and their public digest can be rewritten without a native opening anchor. [Shared-generation Jobs](archive/2026-10-26-p30-p31-implementation/shared-job-epoch-20261106.md) have durable predecessor and retirement controls. [Native Source/Projection progress](archive/2026-10-26-p30-p31-implementation/document-native-progress-20261106.md) adds bounded owner/epoch/unit heads, real immutable verification, reserved cleanup capacity and focused native/Session controls, including partial and unknown outcomes. [Same-owner draft abort](archive/2026-10-26-p30-p31-implementation/document-draft-abort-20261106.md) now exposes bounded Source/Projection stage retirement, preserving published values and unknown outcomes. General producer qualification, maintenance, GC, migration and full populated qualification remain open. The [document profile/staged-block boundary](archive/2026-10-26-p30-p31-implementation/document-store-boundary.md) and expired-draft repairs have focused controls and independent source/evidence review. A [packed adapter/paged catalog/selected hydration increment](archive/2026-10-26-p30-p31-implementation/document-store-adapter.md), [public Collection Corpus routes](archive/2026-10-26-p30-p31-implementation/corpus-collection-documents.md), [lossless per-source lexical runs](archive/2026-10-26-p30-p31-implementation/source-lexical-runs.md), and a [namespace lexical index](archive/2026-10-26-p30-p31-implementation/namespace-lexical-index.md) have focused Session controls. A [versioned larger-chunk recipe](archive/2026-10-26-p30-p31-implementation/collection-chunking.md) has focused legacy and new-source controls; [Inline publication](archive/2026-10-26-p30-p31-implementation/inline-document-publication.md), source-local [packed vectors](archive/2026-10-26-p30-p31-implementation/packed-vector-projections.md) and [cited facts](archive/2026-10-26-p30-p31-implementation/packed-fact-projections.md) have focused controls. The original dry preflight calculated at least 36,000 initial mutations against the unchanged 32,768 limit. [Fused writes](archive/2026-10-26-p30-p31-implementation/fused-document-writes.md) reduce the measured initial recipe, but the per-source layout still exceeds the 8,192 live-key ceiling before global graph or rebuild overlap. A [shared projection codec](archive/2026-10-26-p30-p31-implementation/shared-projection-codec.md) has read-only Session and dry geometry controls; [independent review](archive/2026-10-26-p30-p31-implementation/shared-projection-codec-independent-review.md) found a noncanonical fact-version round-trip defect; the [shared-boundary repair](archive/2026-10-26-p30-p31-implementation/shared-projection-canonical-fact.md) has a focused read-only control and an [independent repair review](archive/2026-10-26-p30-p31-implementation/shared-projection-canonical-independent-review.md) with no additional concrete defect in that scope. [Shared generation finalization](archive/2026-10-26-p30-p31-implementation/shared-generation-finalization.md) and [independent review](archive/2026-10-26-p30-p31-implementation/shared-generation-finalization-independent-review.md) cover durable streamed manifests/entity merge/digests and three-stage selection at the protocol/artifact level. [Small ordinary native/public finalization](archive/2026-10-26-p30-p31-implementation/shared-finalization-native.md) and [independent review](archive/2026-10-26-p30-p31-implementation/shared-finalization-native-independent-review.md) cover programmatic full approvals, old-root preservation, final selection, stale approval and post-publication unknown without replay, with trusted pending/group setup and immutable reuse explicitly limited. [Measured wide-metadata failures](archive/2026-10-26-p30-p31-implementation/shared-metadata-geometry.md) motivated an [explicit paged directory v2 design and independent review](archive/2026-10-26-p30-p31-implementation/shared-directory-v2-design-independent-review.md). Its [frozen Root2/Job3 implementation](archive/2026-10-26-p30-p31-implementation/shared-directory-v2-implementation.md) and [independent review](archive/2026-10-26-p30-p31-implementation/shared-directory-v2-implementation-independent-review.md) include the complete final-call protocol model, phase/resume controls and small actual Session controls. The [public descriptor inventory](archive/2026-10-26-p30-p31-implementation/document-descriptor-inventory.md) and [read-only original packed-layout adapter](archive/2026-10-26-p30-p31-implementation/document-packed-layout-independent-review.md) are separately reviewed; neither implements faithful export/import. The [terminal initial/rebuild recipe ledger](archive/2026-10-26-p30-p31-implementation/document-whole-recipe-ledger.md) models28,258mutations/6,910retained records/707,516actionevents before public inference-producer costs; per-value migration exceeds the unchanged32,768operation-ID cap. [Explicit compact generation responses and independent review](archive/2026-10-26-p30-p31-implementation/generation-compact-progress-independent-review.md) include actual Session finalization and a committed stage-free fresh-Session handoff. The [compact-only finalization model](archive/2026-10-26-p30-p31-implementation/document-compact-finalization-ledger.md) reduces public output to907,489Bwith0pagedslots but still104,036actionevents/161,950,045B, beyond one Session. The [first public shared-vector page](archive/2026-10-26-p30-p31-implementation/shared-producer-first-page.md) has focused registered synthetic-provider controls; [independent review holds source freshness before inference](archive/2026-10-26-p30-p31-implementation/shared-producer-first-page-independent-review.md). The [worker eligibility repair](archive/2026-10-26-p30-p31-implementation/shared-producer-worker-policy-repair.md) checks current sources before claim and each batch. The original source/transport hold is superseded for the bounded first page by the actual guarded controls and public adoption below. A separately [implemented selection bootstrap and optional v2 pin](archive/2026-10-26-p30-p31-implementation/embedding-selection-bootstrap.md) has focused pure/actual Session controls; [implementation review](archive/2026-10-26-p30-p31-implementation/embedding-selection-bootstrap-implementation-independent-review.md) is accepted, and [producer adoption](archive/2026-10-26-p30-p31-implementation/shared-producer-selection-adoption.md) has focused actual Session controls. [V3 range claims](archive/2026-10-26-p30-p31-implementation/shared-producer-range-claim.md) include reverse-insertion and segmented-DOCX fixtures. The [retained document reader](archive/2026-10-26-p30-p31-implementation/document-held-reader-independent-review.md) and [complete logical value reader](archive/2026-10-26-p30-p31-implementation/document-held-value-independent-review.md) are independently reviewed. The [Host byte/time relation](archive/2026-10-26-p30-p31-implementation/document-source-use.md) has focused and actual native read controls. Its [initial wiring](archive/2026-10-26-p30-p31-implementation/document-source-admission-initial.md) and [reader-return repair](archive/2026-10-26-p30-p31-implementation/document-source-admission-return.md) have scoped implementation review. Actual registered Session controls pass [four-batch positive and approval-expiry cases](archive/2026-10-26-p30-p31-implementation/shared-producer-guard-session-independent-review.md), plus a separate [finite-TTL positive](archive/2026-10-26-p30-p31-implementation/shared-producer-finite-guard-session-independent-review.md). [Public first-page adoption](archive/2026-10-26-p30-p31-implementation/shared-producer-public-adoption-independent-review.md) is independently reviewed with explicit bindingv2 and registered-route configuration; canonical artifact promotion has strict build/protocol/configuration evidence, not a repeated native run. [V4 progression direction](archive/2026-10-26-p30-p31-implementation/shared-producer-v4-progression-independent-direction.md) releases worker implementation subject to the [actual-old-ready/live-inline Host amendment](archive/2026-10-26-p30-p31-implementation/document-inline-v4.md); A [synthetic public two-page Session](archive/2026-10-26-p30-p31-implementation/shared-producer-v4-public-session.md) passes with an empty old root. A subsequent [selected-root immutable-reuse repair](archive/2026-10-26-p30-p31-implementation/shared-producer-v4-selected-reuse.md) has protocol-model controls, a strict build and a [native synthetic selected-root reuse control](archive/2026-10-26-p30-p31-implementation/checkpoint-pending-acceptance-20261029.md), with trusted fixture seeding and public fact production still open at that checkpoint; [Source-bound 256-chunk model geometry](archive/2026-10-26-p30-p31-implementation/shared-producer-v4-bound-geometry.md) and the [pinned-read follow-up](archive/2026-10-26-p30-p31-implementation/shared-producer-v4-pinned-read.md) complete private one-fact-per-source append at a maximum 506 reads across 37 invocations; a [256-short-fact model](archive/2026-10-26-p30-p31-implementation/shared-producer-v4-full-facts.md) and [batched citation follow-up](archive/2026-10-26-p30-p31-implementation/shared-producer-v4-batched-spans.md) complete the same bounded group, while native controls cover two pages only. [Packed page and split-append controls](archive/2026-10-26-p30-p31-implementation/shared-producer-v4-split-append.md) complete a 256-wide-fact synthetic group; the subsequent [final root fence](archive/2026-10-26-p30-p31-implementation/shared-producer-v4-final-root-fence.md) passes native interposition and a 464-read model. Reservation proof, native wide append, Session handoffs and full producer qualification remain open. The [producer egress epoch increment](archive/2026-10-26-p30-p31-implementation/producer-egress-epoch-20261106.md) joins live claims and stored Jobs to the current idle epoch, with synthetic pre-approval, fresh-Job and in-flight controls. The [reviewed short-lock direction](archive/2026-10-26-p30-p31-implementation/document-producer-source-egress-independent-review.md) preserves admitted in-flight uncertainty without requiring locks through socket close. Complete producer progression, post-approval source policy, full native journal/physical peak, GC and migration remain open. The [corrected cleanup/migration design](archive/2026-10-26-p30-p31-implementation/document-collection-maintenance-v2-design.md) and [opening-epoch/ID clarification](archive/2026-10-26-p30-p31-implementation/document-maintenance-epoch-clarification.md) require separate publication fencing, preserved checkpoints/physical representation, explicit deletion authority and exact operation reservations. The bounded completed-Collection restore now has a public Session journey and native checkpoint controls; general cleanup, larger migration, complete acquisition/build and populated peak remain open. Ordinary document staging has a separately reviewed final-decision restoration; managed document mutations remain gated; narrow new notes capture has separate scoped admission and genuine Terminal controls, with complete notes qualification still open. Remaining scope includes document/graph collections, model/recipe-bound vectors, durable work references where needed, later-use source authority and safe P26/P27/released-notes migration; after C1a, prototype alongside E |
| P31D1 | In progress: [packaged lexical document selection](archive/2026-10-26-p30-p31-implementation/documents-setup-20261031.md) ships separate inert State/Collection Corpus artifacts; native setup/acquisition/citation/resume/disable and refusal controls pass in source and the [extracted package](archive/2026-10-26-p30-p31-implementation/documents-setup-installed-20261031.md). [Read-only model inspection](archive/2026-10-26-p30-p31-implementation/local-model-inspection-20261031.md) has source and installed controls plus real primary-model metadata observations, without loaded-context or inference qualification. [Explicit query formatting](archive/2026-10-26-p30-p31-implementation/query-prefix-20261031.md) has public-source and built-artifact controls; [Selected Collection cosine/hybrid queries](archive/2026-10-26-p30-p31-implementation/collection-selected-semantic-20261031.md) have public-artifact native controls with encoder pinning and final generation/expiry checks; namespace-wide dense retrieval remains open. [Manual inference reconciliation](archive/2026-10-26-p30-p31-implementation/inference-reconciliation-cli-20261031.md) has native source controls over the existing protected API and [exact-package inspection/reconciliation controls](archive/2026-10-26-p30-p31-implementation/inference-reconciliation-installed-20261031.md); real daemon quiescence remains an operator prerequisite. Remaining artifacts/catalog composition, optional provisioning, protected job/model identity and context checks, owned-daemon recovery and installed upgrades remain; follows applicable B/C1b/F/G contracts; weights remain unbundled |
| P31F | In progress: bounded DOCX extraction ([v14 compact block maps](archive/2026-10-26-p30-p31-implementation/word-block-packing-20261031.md) and [v15 annotation coverage](archive/2026-10-26-p30-p31-implementation/word-annotation-completeness-20261102.md)), [supplied-byte cited storage](archive/2026-10-26-p30-p31-implementation/word-source-bridge.md) and [paged native acquisition/staged text](archive/2026-10-26-p30-p31-implementation/word-staged-acquisition.md) have focused actual Session/native/CAS controls. State acquisition retains its 32 KiB original limit. [Source byte-bound and cancellation controls](archive/2026-10-26-p30-p31-implementation/word-capacity-cancel-20261104.md) now pass for the Collection path at 1 MiB original bytes, 64 KiB UTF-8 text and 32 chunks, including exact citations, original-file loss/restoration, no replay and one-byte-over refusal with the old head preserved. The synthetic thumbnail retains a partial-coverage warning; this is not general Word fidelity. Registration cancellation confirms unstarted cleanup. A subsequent [exact installed Collection control](archive/2026-10-26-p30-p31-implementation/word-installed-capacity-20261104.md) passes the 1-MiB/64-KiB/32-chunk ceiling, independent original/text/chunk overflow guards, final close and Saved/idle no replay in the 6adb7aca archive. Its partial thumbnail warning and earlier two failed fixtures remain explicit; this does not qualify other installed profiles or general fidelity. [Paged locator metadata](archive/2026-10-26-p30-p31-implementation/word-locator-manifest.md) has actual Session controls; expired queued writes refuse before publication. [On-use workspace checks](archive/2026-10-26-p30-p31-implementation/document-current-use-20261031.md) withhold returned evidence/claims after original-file replacement, rename or deletion, then revalidate storage; this is no watcher or complete producer/later-use authority. Unsupported relationships, numbering outside the v16 subset and unresolved annotation coverage remain partial. A clean v15 [exact package](archive/2026-10-26-p30-p31-implementation/word-annotation-installed-20261102.md) passes generic and same-artifact document checks. Real Word fidelity, full C1b capacity, complete file lifecycle/current-use qualification, installed journeys, no-extra-service quality and optional Ollama hybrid/local-answer qualification remain; follows C1b/D1. Word can qualify independently of PDF |
| P31G | In progress: [main-tool stored-source capture](archive/2026-10-26-p30-p31-implementation/graph-main-capture-20261104.md) preserves exact citations and ordinary approvals without a secondary model. The [ordinary State identity increment](archive/2026-10-26-p30-p31-implementation/graph-identity-lifecycle-20261105.md) adds explicit alias/merge/latest undo over immutable facts, source/State CAS revalidation and old-reader refusal. Its 26 protocol controls include the earlier ten; three inert matching reader artifacts and one fresh explicit-command State approval/denial/stale-revision/Saved/idle journey pass, with zero model calls. Actual identity-write expiry/interruption, mixed-package live coexistence, original-source/managed-note graph admission, automatic identity inference, full lifecycle/quality, C1b capacity and installed use remain open. Graph stays optional/experimental; qualifies separately from F |
| P31H | In progress: [provided-only Research transfer](archive/2026-10-26-p30-p31-implementation/research-word-integration-20261104.md) shares attributed unverified text with an ordinary State Corpus under explicit approval and preserves same-body forgetting across caller aliases. A [bounded mixed-note coexistence control](archive/2026-10-26-p30-p31-implementation/research-managed-coexistence-20261104.md) passes explicit user retention under ordinary State approval, real native-approved model-selected Corpus query/full note lineage and same-ID idle no replay. A separate model-selected retain under `--yes` ends with error, zero unknown Worker inputs and zero State mutations. The [fetched-State main integration](archive/2026-10-26-p30-p31-implementation/research-fetched-state-20261104.md) passes actual selected MCP fetch, ordinary State approval, exact Corpus citations, same-body forgetting and interrupted-write/Saved/idle no replay, with a current-host strict build and separate compatibility checks; installed and full combined qualification remain open. A [fetched-version lifecycle control](archive/2026-10-26-p30-p31-implementation/research-fetch-origin-lifecycle-20261104.md) now passes immutable changed-body versions, local host-revision selection and explicit selector-only recovery under ordinary MCP/State approval, with strict Saved and idle no replay. Derivative/cross-store lineage, installed qualification and managed-derived State writes remain open. Integrates each available E/F/G store without requiring unqualified optional backends |
| P31I | In progress: static ceilings deny durable research writes; the [CLI can select a persisted planning ceiling](archive/2026-10-26-p30-p31-implementation/planning-cli-followup.md) at startup. Witnessed idle-terminal `/plan` entry and local `/plan exit`, including newly recorded CLI selections, have [Session, replay and PTY controls](archive/2026-10-26-p30-p31-implementation/planning-transition-design-followup.md); a [native-terminal Session-death control](archive/2026-10-26-p30-p31-implementation/planning-transition-design-followup.md#controlled-session-death-at-journal-boundaries) passed at four entry/exit receipt boundaries and two declared-MCP epoch boundaries; [actual live-stdio MCP controls](archive/2026-10-26-p30-p31-implementation/planning-live-mcp-resources.md) additionally cover busy transition refusal, fresh entry/exit after read cleanup and real Session-death/no-replay resource cleanup in a mixed runtime. Broader crash-boundary and resource qualification remain open. Version-2 same-owner resume checkpoints preserve active and enclosing ceilings separately, while legacy collapsed provenance stays ambiguous; neither authorizes an exit by itself. The [main-Session enhancement integration](archive/2026-10-26-p30-p31-implementation/enhance-integration.md) adds experimental `/enhance`, native witnessed editing/acceptance, cancellation/source isolation, bounded questions and MCP catalog revalidation from the independently reviewed private prototype. Inline replacement has local replay and PTY controls. [Declared planning MCP reads](archive/2026-10-26-p30-p31-implementation/planning-mcp-live-read-followup.md) have synthetic Session and terminal acceptance coverage; whole-source/platform qualification, provider carryover and broader deferred-decision source combinations remain open. Integrated knowledge/document clarification still needs E/F; this is not P31I completion |
| P31J | Integrated safety, quality, resource, installed-user, migration and whole-manual acceptance; records supported, experimental and unverified slices explicitly |

P31C1a now has a [frozen native initial-population runner](archive/2026-10-26-p30-p31-implementation/native-notes-seed-20261102.md),
using actual Session statement/category capture and native pin review. Its full
plan counts 2,000 captures plus 100 pin publications across 21 seed days without
changing the existing 100-operation daily limit. The two-day smoke verifies seven
1,024-byte-source notes, one pin, fresh-process clock coherence, actual public
values, signed metadata, settled resource records and unchanged prior journals.
The [read-only population auditor](archive/2026-10-26-p30-p31-implementation/native-notes-audit-20261102.md)
also passes the closed seven-note store: every signed target/category/clock,
exact root/control state and original-source reconstruction remain unchanged,
with separate per-note evidence and component allocation. Active/incomplete
cohorts and output reuse refuse before audit output. This is a smoke-sized
audit, not a full initial-population result.
The [full initial population](archive/2026-10-26-p30-p31-implementation/native-initial-population-20261102.md)
has closed with 2,000 captures and 100 pin publications. Its separate
[whole-population audit](archive/2026-10-26-p30-p31-implementation/native-full-population-audit-20261102.md)
passes signed categories, clocks, public values and unchanged root/control and
373 original source files. Maximum payload and annual normal-use plus 10,000
mixed changes remain open. Source Session allocations are reported alongside
Collection/control costs. Initial population alone is not endurance acceptance.
The separate [seven-effect native turnover pilot](archive/2026-10-26-p30-p31-implementation/native-turnover-pilot-20261102.md)
continues a seven-note smoke through capture, correction, forgetting, supersession
and elapsed reclamation, then verifies signed final records and saved Sessions.
It executes no main turns and does not qualify the annual workload.
The [locked continuation follow-up](archive/2026-10-26-p30-p31-implementation/native-turnover-lock-20261102.md)
preserves an initial management-owner conflict and verifies a separate-worker
repair plus post-effect interruption/refusal on fresh smoke stores. Active-effect
loss, concurrency, scalable recovery and annual qualification remain open.
The [batched smoke continuation](archive/2026-10-26-p30-p31-implementation/native-turnover-batch-20261102.md)
checks grouped effects, clean restart and reuse of a compensated same-day clock
anchor on separate small stores. A [calendar-runner smoke](archive/2026-10-26-p30-p31-implementation/native-calendar-runner-20261102.md)
adds frozen-source validation, UTC-aligned windows, native renewal and refusal
controls. Neither executes main turns or qualifies the annual calendar; active
effect loss, concurrent restart and power loss remain unverified.
The [first large-seed calendar day](archive/2026-10-26-p30-p31-implementation/native-calendar-first-day-20261102.md)
closed and independently checked 57 effects. A [second day](archive/2026-10-26-p30-p31-implementation/native-calendar-two-day-20261102.md)
brings the checked total to 114 effects. A separately audited
[third day](archive/2026-10-26-p30-p31-implementation/native-calendar-third-day-20261102.md)
brings it to 172 effects, including 82 of the additional 10,000 changes. The
other 362 days and all main-model turns remain open.

P31D1 now has optional [cooperative model checks around registered Ollama jobs](archive/2026-10-26-p30-p31-implementation/ollama-model-pin-jobs-20261031.md).
Named operator text/embedding profiles bind expected metadata and minimum loaded
context into saved execution; embedding selection also binds the pin and requested
context. Synthetic main/SDK/controlled-child checks cover successful publication,
preflight refusal, withheld text/tools/vectors and retained measured charges.
The first [actual primary-pair Session controls](archive/2026-10-26-p30-p31-implementation/local-pinned-jobs-20261031.md)
pass public embedding reconstruction, ordinary main completion, reported 8,192-token context,
service settlement and Saved/idle resume. Immutable per-request weights, offline
execution, long-input/context-fit/quality and installed
qualification remain open; these checks do not close D1 or F.

P31C0 ordinary model-tool approval now uses a
[Session-owned native display adapter](archive/2026-10-26-p30-p31-implementation/managed-approval-native-20261031.md)
on top of the [retained source/policy-owner prerequisite](archive/2026-10-26-p30-p31-implementation/managed-display-owners-20261031.md).
The adapter binds the pending call, full payload, original Session/Writer and
source/policy owners, settles display, releases those locks before input and
retains fresh effect admission afterward. Scoped synthetic-route native controls
cover fresh/active/resumed writes, denial/stale code, cancellation/exit, delayed input,
changed source, revocation and Session loss. The
[actual-note shell follow-up](archive/2026-10-26-p30-p31-implementation/native-shell-approval-20261101.md)
adds native approval, a physical command effect, owned cleanup and buffered stdout
delivery, plus changed-source refusal before spawn. Broader actual-note shell
loss/expiry qualification remains open. The
[actual-note stdio MCP journey](archive/2026-10-26-p30-p31-implementation/native-mcp-approval-20261101.md)
also covers native approval, separately admitted start/send, one service call,
current result delivery and pre-dispatch source withdrawal. Root-only approval
positives now have a separate
[native caller migration](archive/2026-10-26-p30-p31-implementation/root-native-approval-20261101.md)
that preserves the original snapshot, policy, provider sequence and effect
assertions, including strict idle recovery. The
[root-only waiting-fault migration](archive/2026-10-26-p30-p31-implementation/root-native-faults-20261101.md)
also preserves root-change, revocation, actual expiry and consumer-loss controls
for write/shell/MCP through that native caller, with no effect or replay.
[Running-shell revocation and owner-loss controls](archive/2026-10-26-p30-p31-implementation/root-native-running-shell-20261101.md)
now preserve the original delayed command under native approval, withheld stdout
after revocation and actual process-group exit after consumer loss, followed by
strict idle recovery. The
[root-only MCP start/send controls](archive/2026-10-26-p30-p31-implementation/root-native-mcp-start-20261101.md)
pair native allowed stdio/HTTP calls with revocation after admitted start and
before send, confirmed cleanup, withheld delivery and strict idle recovery.
[HTTP pre-start and pinned-helper controls](archive/2026-10-26-p30-p31-implementation/root-native-prestart-pinned-20261101.md)
also preserve zero additional connections after native-input revocation/expiry
and successful stdio dispatch despite an unpinned helper override. The
[lost-initialization and held-owner-loss controls](archive/2026-10-26-p30-p31-implementation/root-native-mcp-loss-20261101.md)
now preserve actual startup uncertainty, held HTTP socket/stdio server cleanup,
the complete original root dependencies and inert recovery. Missing effect
cleanup keeps lineage unavailable rather than authorizing reuse. The
[prior complete frozen managed-collection module](archive/2026-10-26-p30-p31-implementation/managed-collection-module-current-20261102.md)
at clean isolated `2f628a9` has 170 passed, 5 failed and 15 skipped, with unchanged
pre/post source/build/helper inventories. A subsequent focused legacy-question
synchronization passes both original cases without replacing that aggregate.
The later [complete source run](archive/2026-10-26-p30-p31-implementation/full-suite-20261102.md)
at `39c8043` retains one protected-outer cancellation failure in this module;
its 3,747 passing cases do not establish confirmed cleanup at that boundary.
The [preceding V3 module](archive/2026-10-26-p30-p31-implementation/managed-collection-module-v3-20261101.md)
and the
[earlier module result](archive/2026-10-26-p30-p31-implementation/managed-collection-module-20261101.md)
is retained. A [shared loss-lineage assertion follow-up](archive/2026-10-26-p30-p31-implementation/native-loss-lineage-shared-20261101.md)
now compares exact retained approval sources and journal-derived reconstruction
availability for shell and MCP, preserving unavailable lineage after unconfirmed
cleanup. A [paired helper-input follow-up](archive/2026-10-26-p30-p31-implementation/stale-helper-boundary-20261101.md)
now distinguishes zero helper egress plus unknown unfinished-Worker input from
completed-Worker withdrawal and successful later-main continuation, retaining
current-helper positives, accounting and inert recovery. These focused controls
do not replace the failed module aggregate or close full C0, installed/platform
or actual-note quality qualification. The
[accepted-decision approval extension](archive/2026-10-26-p30-p31-implementation/accepted-approval-20261101.md)
additionally retains original management journals at that same native sink,
with Session/Writer-authenticated manifest counts/inodes. Native controls cover
approval, denial, actual descriptor ownership and journal loss before display,
including stopped-consumer inert recovery. A [nested native-approval adapter](archive/2026-10-26-p30-p31-implementation/nested-native-approval-20261101.md)
now binds an extension's original parent/action and full source union to that same
terminal, with root-derived MCP, native-file, text, embedding and decision
approval/denial/source-change controls, preserved MCP cancellation/loss cases and
strict idle recovery. The combined frozen cohort's wire-assertion failure and its
focused correction remain separately recorded. Source-content, installed and
whole-source qualification remain open.
Delegation and managed question displays remain closed. This is component progress;
full C0, installed/platform and independent quality acceptance remain open.
The same record's [read-only export follow-up](archive/2026-10-26-p30-p31-implementation/nested-native-approval-20261101.md#read-only-export-permission-control)
restores the current V3 permission-denial fixture while preserving output/replay
negatives and unchanged accounting/storage assertions; it supplies no new
complete-module or suite aggregate.
The [paired source-origin controls](archive/2026-10-26-p30-p31-implementation/legacy-origin-boundary-20261101.md)
also reach the actual missing-origin publication refusal without first attempting
unsupported legacy protected-input delivery, alongside a current V3 publication,
accounting and idle-recovery positive. Full C0 and whole-source acceptance remain
open.
The [current V3 accounting/fault controls](archive/2026-10-26-p30-p31-implementation/managed-collection-module-20261101.md#current-v3-accounting-and-publication-fault-controls)
restore conservative conflict settlement, measured successive-save refunds,
native normalization loss, post-admission Session loss and foreign-caller
negatives on the supported path. Their focused result remains separate from
the failed complete-module baseline.
The [current V3 binding follow-up](archive/2026-10-26-p30-p31-implementation/managed-collection-module-20261101.md#current-v3-binding-follow-up)
also preserves the headless publication positive and its outer/policy/inner
tamper controls using actual V3 page metadata and registered continuation.
The [new complete module and subsequent focused repair](archive/2026-10-26-p30-p31-implementation/managed-collection-module-v3-20261101.md#focused-text-delivery-and-deadline-follow-up)
retain all seven failures at `7e9f533`, then separately verify optional text
callback synchronization and successful registered deadline continuation.
Neither focused pass establishes a new complete-module or whole-suite aggregate.
The [late A/B publication follow-up](archive/2026-10-26-p30-p31-implementation/managed-collection-module-v3-20261101.md#late-ab-publication-boundary)
now retains the actual earlier root-bound read and delivered B quote at the
publication guard, with independent registered seed/winner positives and inert
recovery. It is distinct from the earlier Worker-input source-withdrawal control
and does not qualify full current-source publication.
A [separate genuine-current-literal positive probe](archive/2026-10-26-p30-p31-implementation/managed-collection-module-v3-20261101.md#open-positive-capture-after-a-current-literal-read)
confirmed an implementation gap at `1560cb7`: A is eligible and unchanged,
B is quoted successfully, but the root-only prerequisite gate refuses capture
before publication intent. The [source-dependent capture integration](archive/2026-10-26-p30-p31-implementation/current-source-capture-publication-20261102.md)
now retains the whole union and actual original-source owners through the native
publication decision. A genuine current literal plus new pending B completes;
source/policy withdrawal and original-owner loss retain refusal/unknown semantics,
accounting and inert recovery. Four new controls join a passing 14-case focused
cohort, and six complete component modules pass 89 tests. These results do not
replace the failed complete-module/suite aggregates. Historical/accepted-note
combinations, maximum unions, broader expiry/loss and full C0 remain open.

The [shipped recall/capture follow-up](archive/2026-10-26-p30-p31-implementation/shipped-recall-capture-20261102.md)
addresses the actual native artifact's nonempty index plus current-literal union.
Main-model source lookup, new pending publication and historical-metadata
continuation now have a complete synthetic local-provider positive. Original
literal dependencies remain attached; source withdrawal and revocation after
publication withhold the next Worker input while retaining settled storage and
inert resume. Replay-tamper controls remain separate from live source checks.
This is author-run component integration, not independent model quality,
installed qualification or a replacement complete-suite/module aggregate.

The [managed export-input adapter](archive/2026-10-26-p30-p31-implementation/worker-input-session-20261101.md)
now binds actual initial calls, committed action continuations and output-page
requests to their complete Session-derived dependencies and immutable Worker
frames. Consuming/original Session locks, Writer/Session controls and current
policy owners reach the same native stdin writer and settle before buffered
compute is released. Strict Saved reconstruction preserves unknown inputs without
replay, and the narrow authenticated own-write metadata transition preserves
allowed captures. The subsequent [accepted-input increment](archive/2026-10-26-p30-p31-implementation/accepted-worker-input-20261101.md)
extends that adapter to version 6 by retaining original management journals at
the same native sink. Genuine single/two-decision source controls also preserve
the model historical notice after two captures across resume. Accepted-decision
terminal approval uses its separate native adapter above; other Worker entry
points and integrated/installed qualification remain open. This does not close
C0 or change effect permission.

The [nested native/MCP result follow-up](archive/2026-10-26-p30-p31-implementation/nested-result-input-20261101.md)
now lets known outcomes continue through that pinned export input fence, with
status-only previews. Actual explicit-allow effects and post-effect root-change/
revocation controls preserve known writes, withheld callbacks, typed unknown
delivery and inert recovery. Effect permission is unchanged; managed document
results and other unqualified purposes remain gated. These root-metadata source
controls do not close full C0 or installed/domain qualification.

The [private Worker input follow-up](archive/2026-10-26-p30-p31-implementation/private-worker-input-refusals-20261101.md)
now refuses unsupported managed presentation before startup, private notifications
as known unstarted, private tool feeds before queue admission and selected text
consumers before the dependent model request. Ordinary/required callbacks and
managed metadata retain focused actual-artifact controls. Required registered
text checks its original producer without granting the provider child broker
authority. Broader inherited-source, capacity and integrated C0 qualification
remain open.

The [current native A/B input controls](archive/2026-10-26-p30-p31-implementation/worker-inherited-union-20261101.md)
now exercise the complete inherited union at the actual next Worker frame after
a fresh quote commits. Losing original A withholds the frame and preserves known
B/unknown input; an independent B-only Session still captures and completes while
A is unavailable. Both use fresh current-runtime native source seeds. This
qualifies that source boundary; capacity and full C0 acceptance remain open.

The [page-input reservation follow-up](archive/2026-10-26-p30-p31-implementation/worker-input-reservation-20261101.md)
now includes managed page input records in the existing output token. Actual
byte/event contention controls complete publication, and insufficient full
capacity refuses before source begin without leaking reservations. Source-byte
quotas, native ownership and deadlines are unchanged. Maximum managed output,
whole-producer capacity and integrated C0 qualification remain open.

Interactive literal correction and supersession now have a
[Session-owned native review and publication adapter](archive/2026-10-26-p30-p31-implementation/managed-supersession-native-20261031.md).
Two separate fresh choices endorse the new statement and exact old/new relation.
Actual source/policy owners protect display, and Session/Writer/source controls
reach the final native root decision under a claimed one-use review. Focused
ordinary/temporal, cross-session, cancellation, revoked/missing source, shared
lifecycle and owner-loss controls include idle recovery after a physical switch
without replay. Headless replacement and replacement of accepted decisions remain closed;
complete lifecycle/capacity, installed and
independent qualification remain open. This does not close C0 or P31.
The [history-use and interrupted-compaction follow-ups](archive/2026-10-26-p30-p31-implementation/literal-lifecycle-launchers-20261031.md)
now reuse this genuine publication and release-owner setup while preserving
their separate history, revocation and unknown-liability assertions; this is
component verification, not complete lifecycle acceptance.
The [genuine pinned-history control](archive/2026-10-26-p30-p31-implementation/pinned-history-session-20261031.md)
also covers public pin, temporal replacement and successor forgetting without
removing signed persistent history; its pure future as-of check is not annual
native turnover qualification.
The [default lifecycle test migration](archive/2026-10-26-p30-p31-implementation/genuine-lifecycle-default-20261031.md)
now exercises all six native modes through actual Session-reviewed sources,
including eight-sidecar publication and a native elapsed root decision. Its
explicit future as-of component and synthetic page geometry remain distinct
from annual/full-capacity or independent quality acceptance.

Public session-only retention uses the same full-facts native review, journal
and reducing effect as explicit forgetting. Public pin, automatic and duration
use the guarded retention effect; native-terminal success and cancellation
controls cover those choices on synthetic stores. Independent review, installed
packages and the complete lifecycle remain open.

P30 malformed-response handling now retains a bounded `decision_response`
diagnostic through the owned Session path without settling an uncertain service
reservation. Synthetic two-source and ordinary Session controls pass; replay
does not independently verify a discarded malformed body. Full P30 integration,
cross-boundary audit and acceptance remain open.

P31E has a synthetic main-model Session capture followed by private native
acceptance, with exact source proof and selected-root checks. A separate
temporary-runtime control now uses the freshly built Knowledge artifact. The
[pending-review boundary correction](archive/2026-10-26-p30-p31-implementation/pending-review-boundary-20261031.md)
uses retained signed historical data for display, then freshly verifies the
original source, active consent and target before publication. Fresh-artifact
synthetic Session/native controls pass for acceptance, cancellation, duplicate
refusal, revocation during input and unavailable-source publication refusal.
The earlier pathname-replacement display assertion tested a stronger guarantee
than the baseline requires; its failure remains recorded. The
[experimental public single-card CLI](archive/2026-10-26-p30-p31-implementation/pending-review-cli-20261031.md)
now lists bounded historical metadata and uses native review plus protected
resource reservation/settlement for one selected candidate. Synthetic Session
and actual CLI controls cover wrong code, cancellation, duplicate refusal,
quota, expiry, revocation, input-owner death and operation inspection. A
[current accepted-decision recall control](archive/2026-10-26-p30-p31-implementation/accepted-recall-20261031.md)
reaches a fresh Session's registered synthetic Ollama request with explicit
decision attribution and version-6 dependencies; missing original sources and
altered acceptance events withhold the text. The
[single-candidate rejection increment](archive/2026-10-26-p30-p31-implementation/pending-rejection-20261102.md)
adds native review after capture revocation, candidate-specific suppression and
shared-source preservation. A fresh-artifact synthetic-model Session reaches
actual public cancellation, native disable and rejection with its original
source unavailable, preserving journals/peer/anchor and refusing old-backup
restoration. The [native pending-text correction](archive/2026-10-26-p30-p31-implementation/pending-correction-20261102.md)
replaces one candidate while preserving its original source and signed clocks;
fresh-artifact Session controls cover separate later acceptance, source loss,
revocation and actual consent expiry after staging with retained unknown liability.
The [explicit review-later command](archive/2026-10-26-p30-p31-implementation/pending-deferral-20261102.md)
reads the signed pending candidate without changing its expiry, reserving an
operation or creating acceptance authority, including after revocation and expiry.
The [immutable selected batch path](archive/2026-10-26-p30-p31-implementation/pending-batch-20261102.md)
freezes at most eight items/8 KiB and uses separate fresh native acceptance for
each candidate. Actual Session-produced two/eight-item and second-item cancellation
controls preserve original attribution, per-item settlement and partial results;
manifest identity is retained in events and operation inspection. These local
controls establish no workload capacity. Broader batch geometry/effect-loss
boundaries, installed/provider and
whole-source qualification remain open.

The legacy protected Collection SDK also has an isolated final-admission
[restoration control](archive/2026-10-26-p30-p31-implementation/legacy-sdk-admission-20261031.md).
Its unmanaged publisher reuses the existing native final-decision scope after
current source, mode, mapping and Consent checks; strict APIs and unsupported
managed mutations retain their gates. Focused Session and post-staging expiry
controls pass, with whole-source qualification still pending.

P31C1b dense Corpus finalization now offers an explicit current-source guard for
the selected producer binding. Synthetic Session controls cover a supplied
one-source public finalization and two-group private selection, including source
change and expiry during approval. The public producer also exposes guarded
group append from ready vector pages and stored explicit facts. Synthetic
journeys reach guarded selection for six sources across two vector pages and
nine sources across two groups, with confirmed stage-free Session handoffs;
a single Session hit the lineage producer limit. Host-level group-read interposition,
maximum-scale build and publication cost, wider public production and integrated qualification remain open.
A separate [result-backed supplied-fact caller](archive/2026-10-26-p30-p31-implementation/document-fact-result-public-20261106.md)
has a one-source, one-fact public Session check with a synthetic registered
embedding, explicit result binding and same-owner continuation. The separate
[bounded assembly journey](archive/2026-10-26-p30-p31-implementation/document-fact-assembly-public-20261106.md)
now covers eight inputs, eight sources and 160 supplied facts through final
selection, with actual catalog-order inspection and an unbound Session handoff.
Installed qualification and the full P31 capacity target remain open.
A separate [producer egress epoch increment](archive/2026-10-26-p30-p31-implementation/producer-egress-epoch-20261106.md)
fences staged and inline claims against the held reader's current idle epoch.
Synthetic Session controls cover both pre-approval fences, a fresh post-fence
Job and an already-sent request; they do not qualify populated capacity or
external provider behavior.
A directly seeded native fixture checks 1,000 synthetic sources and 125 groups
with 20,480,000 text bytes, including a staged switch and changed-generation
refusal. It excludes normal ingestion, domain-valid projection payloads and peak
allocation. See the
[checkpoint](archive/2026-10-26-p30-p31-implementation/checkpoint-pending-acceptance-20261029.md).

P31I enhancement now asks the model to check available context before material
questions, with versioned replay preserving the original draft instruction.
Focused Session and replay controls pass; the instruction itself establishes no
model quality. A later [real native ChatGPT control and Responses repair](archive/2026-10-26-p30-p31-implementation/responses-optional-tools-20261031.md)
obtained workspace context before one missing-choice question, but its final
draft exceeded the unchanged response-byte bound and remained uncommitted.
A later [response-budget repair](archive/2026-10-26-p30-p31-implementation/draft-response-budgets-20261031.md)
preserves the selected route's bounded transport instead of adding a 64-KiB
draft-only wire cap. Synthetic Session controls distinguish SSE framing from
proposal size, preserve tighter configured bounds and refuse oversized final
proposals explicitly. A separate [fresh native main-route control](archive/2026-10-26-p30-p31-implementation/enhance-complete-native-20261031.md)
completed read, missing-choice clarification, final proposal, cancellation and
unrelated exact continuation within four known-final requests. This is exposed
development evidence; independent quality, acceptance, installed drafts and
integrated knowledge clarification remain open. New native question
batches also refuse duplicate prompts, kinds and ordered option labels and
descriptions even if wire IDs or recommendations differ. A matching answered
question in the current visible turn is returned to the model before another
operator wait. Reworded questions and earlier turns are not deduplicated. A
draft that cannot accept another question reports that limit separately from
unavailable interactive input.

Named operator Ollama text profiles can now request a bounded context window
through the existing native adapter. Synthetic native-wire, delegated Session and
legacy helper-snapshot controls cover explicit selection, summary preservation
and project refusal. This configures requested context only; job-level model
identity, effective-context verification and optional local-pair qualification
remain open. See the [scoped implementation evidence](archive/2026-10-26-p30-p31-implementation/ollama-context-profile-20261031.md).

The private P31B Session/terminal bridge now binds close preparation to the
PID selected for its Session owner-control transfer. This narrows port
substitution, but the synthetic bridge still lacks independently authenticated
completion and is not enabled for protected-content delivery.
An experimental native v2 owner-control channel can report one authenticated,
operation-bound peer notice. A private Session starts the fixed-marker synthetic
terminal mode and requires its notice, post-release final exchange and terminal
exit before thaw. This synthetic path has focused PTY and premature-close
controls; binding real protected content and authority, broader loss qualification
and protected delivery remain open. A controlled stop reproduced a native
final notice after wall expiry; the synthetic Session now checks its own wall
deadline and compares it with the authenticated peer notice. An isolated
test-hook Session control stops the synthetic recipient across expiry and
observes a poisoned share; Session also refuses to start the synthetic terminal
after its selected deadline. Full race qualification remains open.

P31E search now reports partial coverage for a request that starts at a later
cursor, even when that request reaches the last page, and refuses a query with
no lexical terms before reading the collection. Source and freshly built
worker-artifact fixtures cover these distinctions; the broader recall journey
and capacity qualification remain open. Index traversal now refuses empty,
repeated or cycling continuations and duplicate keys, with source and built-worker
controls; it also bounds pages and checks that full traversal accounts for a
stable visible count. When a later index request fails, automatic recall discards
earlier page keys and reports unavailable coverage with an unknown count. Reads
also match indexed value hash and byte count as well as key and revision. Recall
generation checks withhold a pass on observed change, including a final bounded
index check after reads; the [current native Session fixture](archive/2026-10-26-p30-p31-implementation/checkpoint-pending-acceptance-20261029.md)
passes with reviewed notes and a synthetic local provider. A controlled change
after the final check withheld the old note texts at that provider. This does not
lock the collection through publication or establish retrieval quality. The SDK
context-size estimate runs without host Session modules, using the same Reference
framing as the host;
minimal-artifact and saved-Reference controls cover that boundary.
Pending-proposal capacity is checked by the host under the Collection lock;
the worker no longer reads existing proposal values to count the queue. Scans
remain outside the root-only prerequisite classification. A synthetic
model-selected headless Session saved two distinct proposals across close and
resume. The [registered repeated-capture control](archive/2026-10-26-p30-p31-implementation/repeated-v3-capture-20261101.md)
extends initial additions across 27 Sessions and a nonzero live-page split fence,
with actual adapter continuations, settlement and idle recovery. This is not
retention endurance or annual turnover. A subsequent
[same-owner domain selection repair](archive/2026-10-26-p30-p31-implementation/domain-selection-20261101.md)
removes a preliminary-verifier race in competing V3 publication while preserving
prepared-state refusal and existing one-use authorization order. Focused Identity,
actual competing-publication and repeated-capture controls pass; integrated and
whole-source qualification remain open. The
[registered lifecycle/queue follow-up](archive/2026-10-26-p30-p31-implementation/capture-lifecycle-20261101.md)
also preserves first-use activation, later publication, settled full-queue refusal
and idle recovery. The [compatibility follow-up](archive/2026-10-26-p30-p31-implementation/managed-compatibility-boundaries-20261102.md)
keeps unsupported V2 managed publication refused before intent/reservation while
retaining actual V3 queue, competing-last-slot and registered late-Identity-loss
controls. It separately verifies the current source-withdrawal boundary against a
fresh genuine historical-runtime literal, without copying its original journal.
These are focused controls, not a replacement complete module/suite aggregate.
[Actual headless CLI argv/stdin controls](archive/2026-10-26-p30-p31-implementation/headless-cli-pending-20261101.md)
now require a completed turn and one attributed pending save under native saved
consent without `--yes`, while ordinary write/shell effects stay denied. Broader
source, loss, installed and quality qualification remain open.

The evaluation source snapshot now admits up to 16,384 files and 4 MiB for
declarations and frozen manifests. A synthetic checkout with more than 8,193
files and manifests over 1 MiB passed declaration, sealing and verification;
16,385 files refused before output. This is a capacity control, not a full
evaluation or qualification of every larger path distribution.

The [native operation-budget preflight](archive/2026-10-26-p30-p31-implementation/native-workload-budget-20261102.md)
now separates the primitive driver's generic churn from authenticated lifecycle
cycles. At the unchanged initial annual floor, the current single-new-record
route needs at least 23,080 IDs for 10,000 mixed operations or 43,080 for 10,000
complete update/correct/forget cycles, including 100 separate initial pin
reviews and before expiry/import/compaction costs. The
[pin-accounting follow-up](archive/2026-10-26-p30-p31-implementation/native-pin-budget-20261102.md)
ties the initial 2,100 effects to the actual population plan.
The developer [selected 10,000 mixed changes total](archive/2026-10-26-p30-p31-implementation/workload-change-count-20261102.md),
additional to the simulated year's normal work. Its 23,080-ID lower bound is
below the unchanged 32,768-ID limit; complete effect overhead and pilot-derived
intake remain unverified. This pure preflight qualifies no native workload and
does not authorize resetting IDs or omitting required coverage.
The [corrected annual action calendar](archive/2026-10-26-p30-p31-implementation/native-calendar-correction-deadline-20261102.md)
models the 20-item floor with a balanced working split of the selected 10,000
changes. Corrected replacements inherit the earlier deadline, matching the native
publisher. It schedules 7,972 expiry publications and 31,052 initial-plus-year
publications, with no required daily operation overflow. Its 6,903 public-note
peak implies at least 7,326 Collection records, below the 8,192 limit; this is a
lower bound, not proof of fit. All-values-at-ceiling logical bytes exceed 24 MiB.
The prior calendar's contrary record-count conclusion and associated same-shape
data-overflow claim are withdrawn. This pure fixture is unratified and executes
zero turns/effects. Actual page packing, remaining effect overhead and pilot-derived
mix/intake remain open.
The [segment preflight](archive/2026-10-26-p30-p31-implementation/native-calendar-segments-20261102.md)
preserves the working calendar in bounded day-local batches; it executes neither
effects nor turns. A scalable continuation with authenticated targets, durable
closure and nonreplaying recovery remains to be built.
The [compensated fixture-clock preflight](archive/2026-10-26-p30-p31-implementation/native-calendar-clock-anchor-20261102.md)
accounts for real elapsed time between simulated days and refuses a backward or
overflowed day. Its [quota-aligned correction](archive/2026-10-26-p30-p31-implementation/native-calendar-quota-clock-20261102.md)
ends the workday at the actual UTC quota reset and has a protected-consent
boundary control. Persistence and actual long-running clock behavior remain open.
The [seed recorded-time audit](archive/2026-10-26-p30-p31-implementation/native-seed-recorded-times-20261102.md)
adds selected journal-field maxima to the signed audit; its smoke and subsequent
[2,000-note audit](archive/2026-10-26-p30-p31-implementation/native-seed-full-recorded-times-20261102.md)
pass with unchanged source, root and control.
Those fields alone are not a physical-completion or clock-monotonicity bound.
The [native consent-renewal control](archive/2026-10-26-p30-p31-implementation/native-consent-renewal-20261102.md)
checks expired-policy refusal and a later native capture after fresh review,
preserving the original signed stored note and saved source. The follow-up
[renewed recall and source-loss control](archive/2026-10-26-p30-p31-implementation/native-renewal-recall-20261102.md)
checks fresh-Session delivery to a synthetic loopback provider and withholding
after source loss. Existing-Session behavior and full annual continuity remain open.
The [retained-receipt geometry probe](archive/2026-10-26-p30-p31-implementation/native-receipt-geometry-20261102.md)
also measures 8,639,325 canonical packed bytes for 42,980 managed receipts and
2,000 public record descriptors, above the unchanged 8-MiB ceiling before domain
sidecars. That retained three-action comparison makes an ID-only increase
insufficient for its scenario. The selected mixed workload still needs actual
composition/allocation evidence; any required storage repair needs explicit review.

F and D1 develop together: parser/acquisition code can run in source fixtures
before packaging; F's installed acceptance requires D1's relevant artifacts.
Do not turn this integration relationship into a sequential implementation deadlock.
The early notes release waits for C1a's sustainable capacity, but not C1b, parsers,
automatic graph or P30. Safe exhaustion of the old State store is not release
acceptance. Publication still requires separate authorization. Core notes/recall
quality cannot borrow P27's result or the optional graph/PDF experimental allowance.

Acceptance gates:

- Ordinary installed users enable knowledge without manual builds/JSON/MCP, see
  accurate next-session status, use normal conversations and later recall, correct,
  forget and disable. Covered effects cause zero repeat permission prompts in chat
  or `run`; prove an eligible headless save while generated prose remains attributed
  or pending review and shell/workspace edits remain denied.
- Default capture uses host-validated tools on the selected main route, with all
  adapter protocols covered and live/model quality distinguished. No mandatory
  secondary extractor or new embedding account. Qualify small notes and larger
  document retrieval separately, including paraphrases and citation support. Decision
  cards require explicit `accept CODE`; bare yes never accepts them in the first
  release. Models supply exact quotes, not offsets. Standalone review preserves origin.
- The optional local route qualifies at least one explicit embedding/answer pair
  on frozen quality/resource gates, with guided setup, versioned preprocessing,
  unchanged-tag/weight-change handling, bounded atomic reindex, endpoint-wide
  contention and offline inference evidence. Distinguish local retrieval with a
  remote main model from fully local answers. No automatic model substitution,
  hidden downloads or mandatory embedding dependency. E does not wait for this F
  slice; failure leaves the local slice open pending repair or explicit scope
  acceptance, not covered by graph/PDF's experimental allowance.
- Preserve authority, evidence and lifecycle under secret/poisoned inputs, concurrent
  processes, revocation, cancellation, queued work, forged worktree membership, divergence, stale context,
  disabled-store forgetting and old-backup migration. Experimental labels waive
  none of these gates. Unknown effects never replay.
- Freeze and measure pilot-derived capture intake, history/compaction overhead,
  serialized prefix stability, cache partitions and TTFT, shared budgets, visible
  retention/category corrections, temporal history, multi-day use, turnover, parser
  fidelity and storage capacity. Verify enhancement on the default main ChatGPT route
  with dispatch-enforced draft effects, stable tools, cancelled-intent tests and
  preserved history. Run source/package/installed checks and user journeys on
  the environments and accounts actually available. Record unavailable Linux
  profiles, macOS, accounts and human journeys as unverified, and do not claim
  support for them or count unrun journeys as passes. Their absence alone does
  not block a qualified completion of the tested scope. The available host's
  storage, authority and safety boundaries must still be demonstrated before
  their affected capabilities can be enabled or described as supported.
- PDF/Word and graph remain in delivery scope. The developer permits qualified
  P31 completion with graph/PDF quality failures retained as experimental/off,
  precisely documented with follow-up work. Core notes/recall, Word and safety gates
  remain required. Rewrite manuals for the actual shipped scope at each checkpoint.

Deferred: voice/media, universal historical-chat mining, unattended daemons,
team/cloud synchronization, unrestricted provider routing, live in-session artifact
activation, lossless context erasure and a general workflow framework.

## P32: voice and realtime media

**Deferred; unimplemented. Previously P31; older archives call it P28 or P24.**
Keep the requested scope for a future delivery; it is no longer ahead of
architecture/security review or self-development.
Build on the owned text/provider and P23 accounting foundation. Start with a
chained STT → admitted text agent → TTS extension/client; then add a versioned
realtime provider/session capability for bidirectional transport, interruption,
turn control, playback acknowledgment and reconciliation of generated versus
played history.

Voice choice, STT/TTS/device adapters and UI belong in extensions/clients. Core
owns resource lifetime, admission, approvals, cancellation, flow control and
provider continuation integrity. Use a separate media data plane, ephemeral raw
audio by default, canonical transcripts/usage and explicit endpoint/device/billing
choices. Text subscription authentication does not establish audio eligibility.

Acceptance: synthetic split/slow/disconnected media, revised interim transcripts,
barge-in, stale/unplayed frames, owner death, approval waits and no-replay recovery;
source/package checks and separately recorded opt-in live account/device checks.
Evaluate maintained Elixir/Rust/OS facilities and approve/inventory external
dependencies before adoption. No codec, frontend runtime or service is selected.
See [media boundaries](archive/2026-10-18-before-manual-rewrite/docs/developer/runtime-capabilities.md#text-and-media-are-distinct-from-diagnostics).

## License transition

The operator-requested MIT → Apache-2.0 transition follows the completed P22–P25
campaign, before the separately deferred P26–P27 features and voice (now P32).
Root and bundled extension licenses now carry Apache-2.0 with the original copyright. Current contributor,
dependency, operator and developer guidance uses that license; upstream dependency
licenses, prior artifacts and historical evidence retain their own provenance.

The bundled license is part of built-in artifact identity. Older selected sessions
need their preserved runner or reviewed explicit handoff; the transition does not
rewrite saved journals or imported artifacts. The synthetic recovery boundary,
local source/native/package checks, both packaged license copies and old compiled
compatibility proofs pass. Exact `7bb642b` Linux/macOS source/native/package and
installed checks also pass after correcting a proof-fixture preparation timer;
production code and request/assertion deadlines are unchanged. This separate
transition is complete. The [verification record](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks)
owns actual receipts. No new runtime capability, dependency or service is added.

## Completed milestones P0–P22

These entries retain stable references and explain what each completed scope
established. They are historical summaries, not new implementation instructions.
Exact commands, dated failures, counts and live limitations stay in the linked
verification records. P2 originally named two milestones; they are distinguished
below as P2a and P2b without renumbering later milestones.

## P0: verify the current release path

Complete for the tested Arch host/account: source/demo/package validation,
subscription browser sign-in, natural-expiry refresh/token rotation, streamed
inference, approved tools, idle resume and logout. A permission-off error was
observed; allowance exhaustion and ineligible accounts remain unverified. Broader
host/model/account portability is not implied. See the
[P0 closure](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p0-closure-on-serenity-2026-10-15).

## P1: make everyday use clearer

Complete: line-oriented running/waiting/cancelled/finished states, EOF/queued-input
and unknown-effect recovery checks. Skills remain explicit, bounded and inert.
See [verification](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md) and [operator usage](operator/usage.md).

### Runtime identity and extension boundaries

Implemented allowlisted application/configured-provider/requested-model facts for
`/info` and model turns, with reported model identity retained separately. Aliases
and model self-descriptions cannot establish backend revisions. No keyword answer
interception or credential exposure. The historical extension proposal was
subsequently implemented within P22's documented boundaries; see
[runtime facts](../lib/ipse/session/context.ex) and [extension architecture](developer/extensions.md).

## P2a: automatic context compaction

Complete: validated durable checkpoints preserve user intent, host approval/action
metadata and native continuation while retaining original journals; unsafe
reduction stops explicitly. P13/P19/P21 added bounded long-turn recovery and
handoff capabilities. See [compaction](developer/workspace-context.md#plan-a-reduction-at-the-model-boundary) and
[P2 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p2-context-compaction-2026-10-15).

## P2b: define an OS sandbox boundary

Complete for the optional Linux native profile's tested filesystem/network/process/
resource boundary. Trusted execution remains the default; requested native policy
fails closed. Mac enforcement and best-effort descendant lifetime have distinct
limits. See [sandbox contract](developer/sandbox.md),
[Linux evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p2-native-linux-sandbox-2026-10-15) and
[Mac boundary](developer/sandbox.md#understand-the-macos-workspace-profile).

## P3: workspace context from any directory

Complete: launch/explicit working directory, bounded scoped instruction snapshots,
provenance and deterministic resume/refresh, with coding and non-coding trials.
Shell target scope can remain unknown; instruction path checks are not an OS
sandbox. See [contract](developer/workspace-context.md) and
[evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p3-workspace-context-2026-10-15).

## P4: packaging and protocols

Complete within Linux/macOS source/archive verification and separate MCP/delegation
protocol design scope. Packages identify OS/architecture/libc and include notices;
fresh extraction checks do not establish all architectures or signing/notarization.
Windows and adversarial detached-descendant termination on Mac remain outside scope.
See [evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p4-release-verification-and-protocol-proposal-2026-10-15).

## P5: local MCP tools

Complete: explicit stdio tools, bounded descriptors/allowlists, schema validation,
full approvals, durable intent and owned transport/no-replay recovery using reused
MCP/schema packages. Source, extracted and scoped live checks are recorded in
[P5 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p5-local-mcp-2026-10-15); arbitrary servers are
not certified by the demo. See [MCP contract](developer/mcp.md).

## P6: local subagent delegation

Complete: opt-in serial local children, separate journals/approvals, bounded
context/results, parent ownership and no recursive delegation/child MCP. See
[delegation contract](developer/architecture.md) and
[P6 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p6-local-delegation-2026-10-15).

## P7: expanded MCP capability

Complete within bounded local resources/prompts and pinned independent-server
interoperability. Ordinary stdio cleanup repairs do not remove the documented Mac
detached-child limit. See [P7 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p7-expanded-local-mcp-2026-10-15)
and [second-server coverage](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#second-independent-local-mcp-server-2026-10-15).

## P8: bounded skill resources

Complete: explicit source-bound `load_skill_resource`, bounds, provenance and
inert resume; loading does not run scripts or install dependencies. See
[P8 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p8-skill-resources-2026-10-15).

## P9: parallel local subagents

Complete: opt-in two-child groups, separate approval routing, bounded scheduling,
results and cancellation. Serial remains default; P23 separately adds atomic shared
token/cost reservations. See
[P9 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p9-parallel-local-delegation-2026-10-15).

## P10: network MCP

Complete: explicitly configured MCP Streamable HTTP POST with JSON/finite SSE,
verified TLS, server-specific credentials, limits, exact approvals and no replay.
Redirects/retries, OAuth negotiation, GET subscriptions and reconnection are not
implemented. Remote cancellation is best effort. See
[contract](archive/2026-10-18-before-manual-rewrite/docs/developer/mcp.md#streamable-http-boundary) and
[P10 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p10-streamable-http-mcp-2026-10-15).

## P11: live dotsetup trial

Complete within read-only project/next-step assessment and selected Ipse follow-ups:
Bash descriptor compatibility, sandbox visibility facts and project-orientation/Git
skill guidance. Existing dotsetup edits were preserved; no dotsetup coding/deployment
or GitHub adapter trial was performed. Multi-repository read roots remain separate.
See [comparison](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p11-live-project-assessment-2026-10-15) and
[repairs](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#native-bash-and-visibility-repair-2026-10-15).

## P12: task tracker coding trial

Complete in a separate app workspace: forms/SQLite CRUD, validation, persistence,
independent review and layout checks. Elixir was imposed by the test operator, so
this did not prove neutral stack selection. Long-turn limitations led to P13.
See [P12 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p12-task-tracker-coding-trial-2026-10-15).

## P13: long-turn compaction and general-purpose trials

Complete: safe long-turn checkpoints/diagnostics, a neutral-stack task tracker
(Ipse chose Python/Flask) and a source-backed non-coding task. Ipse's implementation
language does not constrain target workloads. These are bounded trials, not
unrestricted task coverage. See [compaction](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p13-long-turn-compaction-2026-10-16),
[coding](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p13-neutral-stack-coding-trial-2026-10-16) and
[non-coding](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p13-non-coding-document-trial-2026-10-16) evidence.

### First supervised self-development trial

Complete: frozen installed Ipse authored shared operator skill discovery in a
separate candidate, with independent checks, approved effects and idle resume.
The trial exposed and repaired bundled launcher environment contamination of
system Mix. See [integration evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#shared-skills-questions-configuration-and-profiles-integration-2026-10-16).
Later P18/P21/P22 trials broadened this supervised evidence; P25 proposes a larger
comparative evaluation without claiming unattended self-development.

## P14: bounded deep research

Complete: inert research skill, configured provider-agnostic MCP retrieval and
bounded durable source/claim ledger/export, plus an independently checked live
primary-source trial. No mandatory search service, recursive research engine or
production knowledge backend. See [research contract](developer/knowledge-extensions.md) and
[five-stage evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P15: scoped configuration and shared operator skills

Complete: bounded versioned JSON/provenance and trusted scoped selections;
project > Ipse user > shared operator `~/.agents/skills` > bundled precedence.
Instructions and skills cannot enable executable extensions, change billing or
grant effects. Explicitly trusted project configuration may select a provider and
billing route under the configuration rules; that trust grants no effect approval.
See [operator configuration](operator/configuration.md),
[developer contract](developer/configuration.md) and
[integrated evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P16: explicit model profiles and task routing

Complete: named profiles and main/routine/review roles, supported provider settings,
explicit child selection and credential/native-payload isolation. A stronger
subscription main/local Ollama child trial passed; no hidden billing/provider
fallback or automatic summary routing is claimed. See
[profiles](operator/configuration.md#reuse-a-named-model-profile) and
[integrated evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P17: structured operator questions

Complete: validated single-choice, multiple-choice and text answers, explicit
submission, durable waiting/resume, cancellation/EOF/headless behavior and separate
approval authority. Child questions and MCP elicitation remain unsupported.
See [contract](developer/architecture.md) and
[integrated evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P18: supervised self-development on the operator's Mac

Complete: frozen-runner `sessions --json` change, structured clarification,
independent local Mac/native/package checks, bounded review and hosted Linux/Mac
verification before PR #1 merged. Review budget exhaustion, supervisor assistance
and safe context refusal remain recorded. See the
[Mac runbook](operator/development-workflows.md) and
[local evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p18-macos-supervised-self-development-evidence).

## P19: long-session diagnosis and recovery

Complete: content-free context/timing diagnostics and explicit reviewed handoff
without silently trimming native continuation or intent. Synthetic fixtures
reproduce the failure shape, not a private original Mac transcript. See
[observability contract](developer/lifecycle-events.md),
[operator recovery](operator/recovery.md) and
[P19 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p19-diagnosis-and-explicit-recovery).

## P20: repeatable supervised self-development

Complete: inert bundled self-development skill/resources, credential-free real
Session fixture and supervised live use. Existing approvals, profiles and journals
supply the boundaries; there is no mandatory workflow engine. See
[P20 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p20-reusable-self-development-skill).

## P21: larger self-development trial on Serenity

Complete: Ipse-authored fresh-chat handoff import from a frozen P20 runner,
independent Linux/package checks, separate bounded live review and hosted Linux/Mac
checks. Repeated orientation needed supervisor narrowing; a reviewed manual handoff
and unchanged idle resume were exercised. See
[P21 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p21-supervised-serenity-trial-and-independent-checks).

## P22: extension scaffold and lifecycle hooks

Complete within the SDK contract at `de073ba`: immutable artifacts, explicit scoped
trust/selection, independent workers, typed hooks/invocations/host calls, state,
context/evidence, services, questions, approved actions, owned jobs, source-bound
history/events/feeds and private visible-text channels. Diagnostics have independent
off/local/export controls, bounded retention and synthetic developer tracing.
Two shipped prompt/presentation examples are default-off.

The [architecture/comparison](developer/extensions.md),
[adoption scenarios](developer/testing.md#learn-a-complete-workflow-through-the-compatibility-lab) and
[lifecycle coverage audit](archive/2026-10-18-before-manual-rewrite/docs/developer/lifecycle-events.md#supported-lifecycle-coverage)
define supported and unsupported seams. Hooks share lifecycle occurrence identity
with notifications/feeds/jobs while retaining distinct private-view, ordering and
effect authority. Remote event bridges, nested effectful services, automatic
installers/builders and idle hot activation remain explicit future enhancements.

The separate [memory/workflow lab](developer/testing.md#learn-a-complete-workflow-through-the-compatibility-lab) passed 41 synthetic
source/installed assertions against frozen core `3b0ef78`, without core edits or
rebuilding the installed archive. A separately reviewed live extension-only change
and hosted Linux/Mac checks closed P22's gates. This proves the exercised SDK
contracts, not production graph/retrieval quality; later core changes require
fresh compatibility evidence. See
[completion evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#supervised-extension-only-trial-2026-10-17).
