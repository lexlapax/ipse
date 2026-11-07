# P30/P31 implementation record

Dated **2026-10-26**. Implementation was authorized against clean source
`fbb207d` on branch `codex/p30-p31`. This is a dated engineering record, not a
current-behavior manual. The [plan](../../plan.md) owns package status;
the [operator manual](../../operator/index.md) owns shipped procedures.

The [complete amended proposal](baseline.md) is frozen from
`docs/knowledge-design.md` at `fbb207d`. Its body is unchanged except relative-link
rebasing; a historical notice was prepended. The [provenance manifest](manual-provenance.json)
records source and snapshot hashes. The former live design is now a pointer with
preserved section targets. Later decisions below amend this baseline explicitly.

## Authorization and external evidence

The implementation task covers both milestones, full tests, an adversarial
post-implementation audit and a review handoff. It does not authorize publication.
The developer selected these finite qualification limits in this conversation:

- Up to **300** calls on Ipse's configured ChatGPT subscription route.
- Up to **1,000** local Ollama calls.
- Up to **12 GiB** of model downloads for the primary Qwen embedding/4B answer pair.
- Prepare human journeys; actual independent human and macOS use remain pending.

The configured main route is ChatGPT, requested model `gpt-6.1-sol`. Only Ipse's
own documented authentication is used. No Codex credentials or private transcripts
are imported. Paid API/hosted P30 engines have no selected account/spending cap;
leave their live qualification open. The allowance is a ceiling, not a target.
Do not repeat failed requests automatically. Track consumed calls in this record.

The [later accounting checkpoint](live-call-accounting.md) reconciles the102-call
pilot and four subsequent draft calls to106of300 before the new audit run.
That run was initially rejected before launch, then explicitly approved and
started once with at most120calls. It ended without a final receipt after96
completed responses. The ledger conservatively charges the120-call reservation:
226of300charged,74remaining; exact attempted calls and termination cause unknown.
Subsequent [native enhancement controls](responses-optional-tools-20261031.md)
used eight additional requests, including a retained partial failure: the
conservative total at that checkpoint was234of300,66remaining. A later
[complete native draft](enhance-complete-native-20261031.md) used four known-final
requests, bringing the current total to238of300,62remaining. The detailed
[accounting ledger](live-call-accounting.md#complete-native-draft-control-2026-10-31)
retains all three bounded native Sessions and the earlier unknown liability without replay.

Ollama **0.40.5** is already installed. Resident tags include `qwen3.5:9b` and
`llama3.2:3b`; neither silently substitutes for the primary embedding/answer pair.
Mutable tags and abbreviated list IDs are discovery data, not immutable model proof.
No model download or local inference had run at the initial inventory checkpoint.
Later, the explicitly selected primary pair was pulled to
`http://127.0.0.1:11434`. The [provisioning receipt](ollama-provisioning.json)
records full reported digests, sizes, metadata and runtime. Summed artifact size
is **3,963,324,792 bytes**, below the 12-GiB allowance; this is an upper bound on
new artifact payload before shared-blob reuse, not measured network transfer.
No local inference ran during provisioning. A later [two-request adapter smoke](local-primary-smoke-20261031.md)
charges2of1000local calls, leaving998; its loaded contexts were4096tokens and its
direct chat witness remained false. Later [pinned registered Session jobs](local-pinned-jobs-20261031.md)
used two further calls, both completed/final, with reported 8,192 context tokens,
settled service reservations and valid idle resume. A later
[stopped Word comparison](word-semantic-03-failure-20261106.md) adds one
conservatively charged admitted attempt, bringing that checkpoint to 5 of 1,000.
The later [supplied-Word comparison](word-semantic-supplied-comparison-20261106.md)
completed 148 additional embedding requests, bringing local usage to 153 of 1,000,
847 remaining. Download success establishes neither quality
nor resource/offline qualification. No daemon configuration or existing model was changed.

## P31I planning and acceptance

- [Installed Ollama draft controls](ollama-draft-installed-20261103.md) pass synthetic packaged acceptance and cancellation through release eval, with live and public-chat limits.
- [Ollama no-tool draft thinking](ollama-draft-thinking-20261103.md) records synthetic Session and terminal acceptance/cancellation checks while retaining stricter managed-source admission.
- [Ollama draft recovery](ollama-draft-recovery-20261103.md) records focused synthetic cancellation, acceptance and resume controls, with full-suite and installed qualification still open.
- [Leased terminal deadline rounding](leased-terminal-quantization-20261103.md) repairs a bounded conversion excess and records focused review controls; cross-clock rate and suspend assumptions remain open.
- [Acceptance clock-domain assessment](session-acceptance-clock-anchor-assessment-20261103.md) records why the native wall cutoff does not establish the BEAM Review lifetime and compares unimplemented alternatives; it also identifies an existing terminal-conversion qualification.
- [Synthetic Session-owner discriminator](session-guard-owner-discriminator-20261103.md) records a successful test-only transfer and failed wrong-recipient diagnostics; production acceptance and recipient refusal remain unproven.
- [Same-reply proposal and card map](same-reply-proposal-card-map-20261103.md) identifies the missing nomination, answer and display-owner bindings; implementation and end-to-end verification remain open.
- [Session acceptance native primitive](session-acceptance-native-primitive-20261103.md) records an isolated one-shot guard and owner-loss controls using synthetic helper owners; actual Session binding and the same-reply journey remain open.
- [Proposed Session-owned acceptance guard](chat-acceptance-session-guard-design-20261103.md) sets out the reviewed same-reply owner, review, replay and interruption requirements; implementation and qualification remain open.
- [Chat acceptance architectural reassessment](chat-acceptance-reassessment-20261103.md) compares the frozen post-reply contract with the paused Session-owned draft and an unproven separate-owner alternative.
- [Chat acceptance host-protocol plan](chat-acceptance-host-protocol-plan-20261103.md) records the ownership and later-use gaps for a proposed single-card journey; no implementation or test is claimed.

## Protected decision experiments — 2026-11-05

- [Protected selection and assessment](protected-selection-assessment-20261105.md) retains the full six-note greedy baseline versus a four-note advised pack, then assesses an actual main-tool proposal under the same finite grant: nine main/two decision requests, two known settled calls and Saved/idle no replay. The failed pipeline, exact historical result materialization and fresh assessment-only continuation remain distinct; real quality and installed/full combined qualification stay open.
- [Separate bounded helper context](model-context-v4-20261105.md) preserves complete evidence in version-four model calls under unchanged SDK and request limits. Current approval and denial pass in the failed four-case run; separate fresh source-withdrawal/interruption cases pass with conservative accounting and idle no replay. Real matched quality and installed qualification remain open.
- [Frozen assessment and protected-answer adapters](p30-evaluation-adapters-20261105.md) records 59 focused development checks, complete baseline freeze/reprojection, inherited provenance and exact citation byte joins. Genuine paired execution, independent labels, time/cost and model quality remain open.
- [P30 local acceptance and disposition crosswalk](p30-local-disposition-20261105.md) joins both bounded consumers to source and packaged synthetic evidence. The current full-source baseline and real-engine quality, matched time/cost and default qualification remain open.
- [Synthetic paired protected answers](p30-paired-protected-answers-20261105.md) later qualifies the actual eight-read, six-note baseline and four-note candidate protocol with three main, two helper and one decision wire. It preserves the failed 02 extractor aggregate and separate read-only materialization. Independent quality, time/cost and standalone/installed CLI qualification remain open.
- [Explicit combined helper-route review](p30-combined-helper-route-20261105.md) adds the optional native CLI route before capture, with 58 passing CLI/Knowledge tests and the earlier fixture assertion failure preserved. CLI-to-paired and installed journeys remain open.

## Consent storage checkpoint — 2026-11-05

- [Lossless Consent v3](consent-v3-storage-20261105.md) preserves logical rows and liabilities under unchanged caps; specified 31,052-ID/full-receipt geometry and 22 focused checks pass. Original retained state, populated-day and annual qualification remain separate.

## Regression closure and fixture qualification — 2026-11-06

- [Hosted Azure storage diagnosis](ci-azure-storage-diagnosis-20261106.md) identifies an unadmitted hosted Linux kernel and preserves the other unresolved failures separately.
- [Domain hybrid fixture repair](domain-hybrid-regression-repair-20261106.md) records the active regression failure and separately passing nine-case control; the full aggregate remains pending.
- [Corpus namespace test isolation](corpus-namespace-test-isolation-20261106.md) records a second active regression failure and a separately passing contaminated-parent control; the full aggregate remains pending.
- [Full regression at 98267afd](full-regression-98267afd-20261106.md) passed 4,294 tests with 136 skipped and 124 excluded; later candidate changes are outside its scope.
- [Focused State document and signed-draft Sessions](focused-session-20261106.md) records three passing synthetic Session controls and their limits.
- [Completed-backup wrapper repair](completed-backup-wrapper-repair-20261106.md) preserves a failed combined run and separately passing repaired wrapper.
- [Knowledge MCP source](knowledge-mcp-source-verifier-20261106.md) and [installed](knowledge-mcp-installed-verifier-20261106.md) verifiers passed with separately retained evidence and scoped cleanup.
- [Document backup source binding](document-backup-source-binding-20261106.md) records the reproduced catalog/head mismatch, focused validation repair and remaining native and installed checks.
- [Installed backup source binding](document-backup-installed-binding-20261106.md) checks the valid and malformed synthetic fixtures in the package's domain code; public restore remains separate.
- [Corpus namespace-fence candidate](corpus-namespace-fence-20261106.md) records synthetic State/MCP generation checks, batch compatibility and their remaining native and transport limits.
- [Knowledge MCP verifier retention candidate](knowledge-mcp-retention-20261106.md) records the earlier synthetic compatibility controls and their then-outstanding native proofs.
- [Rejection follow-up diagnostic setup](rejection-diagnostic-setup-20261106.md) preserves a failed fresh-synthetic bundle setup; it did not reach the rejection or diagnose the earlier refusal.
- [Corpus full-snapshot time candidate](corpus-query-time-20261106.md) records 14 synthetic controls and the pre-proposal, remote-selection and delivery limits.
- [Indexed Word row context](indexed-word-row-context-20261106.md) brings bounded same-row context to already hydrated positive namespace hits. Pure containment/citation controls and one actual Collection Session case pass, including original-file replacement refusal; installed and no-token-overlap quality remain open.
- [Knowledge preset verifier export identities](ci-knowledge-preset-verifier-20261106.md) repairs stale Graph command/tool counts and checks exact exports and catalog identities. The pure fixture and all fifteen separately built presets pass; the earlier hosted failure and temporary-checkout quota failure remain separate. macOS and the whole-source aggregate remain open.
- [Candidate MCP and embedding source/installed checks](candidate-9b0a-mcp-embedding-20261106.md) pass all twelve existing checks in each of four modes on the frozen 9b0a package. The [managed selected-result refusal](managed-fact-result-refusal-20261106.md) separately checks the new synthetic cohort's protected-data boundary without delivering bytes or making a model request. These do not establish hosted-platform or full-milestone acceptance.
- [Public-controller document model](document-public-controller-model-20261106.md) follows publication, assembly, producer and append controllers with explicit mocked storage/inference. Focused controls and reducer checks pass; the first full-target attempt timed out after twelve groups. Full target, actual Session journals, physical peaks and capacity remain open.
- [Current-package paired selection v2 lifecycle](p30-paired-selection-v2-20261106.md) completes all five synthetic phases on package9b0a with eight reads, a six-note baseline, four-note candidate and six scripted wires. Physical pre-App references, first-row freeze, later unmeasured review and exact post-idle report checks pass with immutable/independent cleanup. Preparation's first warning remains separate; quality, task time/cost and the current full baseline remain open.
- [Separate selection references and semantic reviews](p30-selection-review-v2-20261106.md) preserves historical scoring and adds an explicit version-2 reference commitment plus post-prediction opaque-ID review envelope. Sixteen outer controls pass with twenty protected-answer children enforced separately; the first compile failure is preserved. A fresh paired v2 lifecycle, independent quality and whole-task time/cost remain open.
- [Document Job input-binding component](document-job-input-binding-20261106.md) binds selected-reference/body digests to an actual stored Job, source group, owner and pre-bind revision. Twenty-one pure controls and one selected native component pass; public caller, consent/read-provenance integration and capacity remain open.
- [Safe memory-verifier failure diagnostics](ci-memory-failure-diagnostic-20261106.md) preserves fixed phase/event/status fields and allowlisted Core codes before fixture cleanup. Two pure redaction/bounds controls pass; the macOS failure's cause and a current installed run remain open.
- [Frozen full default regression](full-source-2a56-regression-20261106.md) completes the unchanged 497-file run at `2a56c60b`: 4,184/4,188 passed, four failures, 136 skipped and 124 excluded. Integrity and cleanup checks pass; separate focused fixture repairs do not turn that failed historical result into a current-source pass.
- [Version-independent child-result counters](ci-child-result-counters-20261106.md) replaces prose parsing with exact ExUnit counters, zero child exit and one control marker. Separate representative checks cover both assigned source groups; unsupported or unrun native/terminal scopes remain explicit.
- [Witnessed-draft child counters](ci-draft-result-counters-20261106.md) repairs the two remaining MCP/extension draft summary assertions. Both existing synthetic PTY controls pass locally with exact counters; hosted native-storage and installed qualification remain open.
- [MCP resume-verifier correction](ci-mcp-resume-verifier-20261106.md) permits only the exact release-owner marker on idle reopen and preserves conservative descriptor-drift uncertainty. All twelve source-proof checks pass; a fresh installed proof remains open.
- [Embedding resume-verifier correction](embedding-idle-resume-20261106.md) checks that same narrow owner suffix, strict Saved reconstruction and unchanged budget/transport. One focused suffix test and all twelve synthetic source-proof checks pass; installed and hosted qualification remain open.
- [Bounded public document Collection restore](document-result-restore-public-20261106.md) records 72 confirmed commands across 24 closed/idle Sessions, eleven records in three pages, same-floor import/rollback/abort/checkpoint removal and separate eight-test native coverage. Changed-target recovery, larger sets and installed migration remain open.
- [Bounded public supplied-fact result](document-fact-result-public-20261106.md) records one source and fact through a captured saved result, guarded binding and final selection in 37 confirmed commands, with three closed/idle Sessions and one synthetic registered embedding. That check does not establish larger groups or full capacity.
- [Bounded public supplied-fact assembly](document-fact-assembly-public-20261106.md) records eight inputs and 160 supplied facts through assembly, binding and final selection in 110 commands and six closed/idle Sessions. The preserved first fixture refused a wrong catalog order before any write; full capacity and quality remain open.
- [Frozen 9b0a Linux package](package-9b0a-generic-20261106.md) builds the exact candidate with PDF included and passes the generic installed verifier, including 100 explicit-memory records/queries. The first protected-workspace fixture failure is preserved; whole-source, platform and full P31 qualification remain separate.
- [Conservative budget reservation fixtures](budget-reservation-fixtures-20261106.md) correct stale no-booking assumptions while retaining fixed one/two-request policies and unstarted liabilities. Both nine-test files pass separately; the frozen full regression remains a distinct outcome.
- [Inactive original result lease](stored-result-lease-20261106.md) records eight actual synthetic controls for same-project committed input, original native ownership, complete dependency unions and checked release. Caller approval, document restore and full-capacity acceptance remain separate.
- [Exact result-reference SDK helpers](sdk-result-reference-helpers-20261106.md) adds explicit small paged output and bounded canonical object digests through the existing protocol. Thirteen publication controls pass, including a real small-output Worker and stage refusals; document restore and integrated qualification remain separate.
- [Supplied-Word retrieval comparison](word-semantic-supplied-comparison-20261106.md) records all 152 results, 148 completed local embedding requests, twelve closed/idle Sessions and independently frozen scoring: 61/62 lexical versus 62/62 dense expected support slots with byte/locator fidelity. Installed acquisition, precision, answers and current-file qualification remain separate.
- [Bounded terminal input buffering](operator-buffered-input-20261106.md) retains 1-MiB limits and deadlines while reducing per-byte polling; 22 native and nine existing host/input controls pass on Linux. Hosted macOS remains unqualified.
- [Complete source CI partitions](ci-source-partitions-20261106.md) replaces the timed-out single hosted suite with four complete file partitions per OS while preserving platform/installed gates and release dependencies. Fifteen focused release controls pass; hosted execution remains unqualified.
- [Installed synthetic backup attempt](installed-backup-attempt-20261106.md) preserves the failed project-identity admission and unknown outcome; the actor placed its project on Btrfs, so installed backup remains unqualified.
- [Bounded fitting-note selection](recall-fitting-selection-20261106.md) considers later small notes within existing host bounds; 32 synthetic mocked controls pass, while actual-host and populated-workload qualification remain open.
- [Full regression at `6e5e4bdc`](full-regression-6e5e4bdc-20261106.md) passed 4,313 tests with 136 skipped and 124 excluded; its isolated input checks and host cleanup passed, and later source changes are not covered.
- [Synthetic document replacement model](document-replacement-model-20261106.md) passes two focused controller/model controls after a recorded timezone-fixture repair; native lifecycle and capacity remain unqualified.
- [Synthetic Word replacement Session check](document-replacement-session-20261107.md) covers one public replacement and retained old records; crash recovery, capacity and the complete lifecycle remain open.
- [Synthetic Ollama tool-assisted draft withdrawal](ollama-tool-draft-20261107.md) covers bounded native call isolation and Session carryover; live and installed qualification remain open.
- [Graph workspace and retirement recovery boundaries](graph-workspace-and-retirement-boundaries-20261107.md) identifies the missing cross-store provenance and owner-release joins; neither is implemented by that investigation.
- [Partial retirement operation binding](document-retirement-operation-20261106.md) joins new heads to their local native operation and invocation; legacy cleanup remains separate and interrupted recovery still refuses.
- [Stopped local Word comparison](word-semantic-03-failure-20261106.md) preserves the known failed embedding attempt, all 152 undispatched result slots and failed idle check. Separate filesystem probes support a tmpfs requirement; no retrieval or quality pass is claimed.
- [Budget reservation before service selection](budget-reservation-pre-slot-20261106.md) closes the observed post-admission service-slot failure gap, with 50 passing focused tests and an independent source review. Earlier preparation failures can still leave an unmatched admission that fails closed; broader regression and model qualification remain open.
- [Interrupted 489-file source regression](source-regression-489-20261106.md) retains 13 known outer failure headers and two separate nested failures, with no final exit or totals. Later immutable-copy and independent host-neutral checks pass; the complete baseline remains unqualified.
- [CI runner and formatter readiness](ci-runner-formatter-readiness-20261106.md) records the retired macOS image, canonical Elixir 1.18 source adoption and clean local formatter/policy checks; hosted tests and installed gates remain unqualified.
- [Word CLI recipe fixture](word-cli-recipe-v18-20261106.md) passes the selected native setup/new-Session/disable case for both State and Collection after updating its stale v17 expectation to v18. Its runtime/source guards and independent cleanup pass; PDF, quality and the whole suite remain separate.
- [Evaluation domain isolation](evaluation-domain-isolation-20261106.md) passes 13 combined outer tests, including the nine earlier victims and both repaired isolation wrappers. Nested controls remain separate; the interrupted aggregate is unchanged.

## Source checkpoint evidence — 2026-11-04

- [Schema-validator security update](schema-validator-security-20261104.md) adopts maintained JSONSchex 0.11.1 and its existing Elixir pointer dependency after upstream retirement, preserving Ipse's closed schema gate; focused tests and normal build pass, final integration remains separate.

- [Frozen 478-file source regression](source-regression-478-20261104.md) remains failed with 4,048 passed, one failed and one invalid, despite all 44 integrity checks passing. Separate capacity and Research fixture repairs pass their focused checks; no new whole-suite pass is implied.

- [Ordinary final-use coalescing](ordinary-final-coalescing-20261104.md) reuses the existing observer in both protected passes after a concrete storage-only five-second expiry reproduction; fresh eight-source delivery/Saved/close/idle and separate root-withdrawal controls pass. The first fixture failure, quarantined retained request and day/annual gates remain separate.
- [Fetched-body selection and explicit recovery](research-fetch-origin-lifecycle-20261104.md) passes one fresh ordinary MCP/State lifecycle with known-body/denied-selector recovery, immutable citations, competing revisions and Saved/idle no replay. Paired format-2 compatibility and pure boundaries stay distinct from installed, quality and cross-store qualification.

- [Confirmed withdrawn event replay](managed-event-withdrawal-replay-20261104.md) authenticates exact managed completion during Saved reconstruction, with six pure controls, 36 integrated cases and an unchanged 207-event in-place replay. The actual partial read remains failed and quarantined; live final use and retained recall stay open.

- [Direct native statement maximum](native-statement-maximum-20261104.md) passes one fresh 4062-byte ordinary record, 2048-byte proof and 999-byte source, proof/source overflow refusals, unchanged accounting and idle no-replay; two earlier fixture failures, other record maxima, burst and annual limits remain explicit.

- [Anthropic cancelled-draft carryover](anthropic-draft-carryover-20261104.md) repairs live and saved text-only projection, preserves native outside history and passes a fresh four-wire synthetic cancellation/ordinary/same-ID journey. The first saved-policy failure and broader provider/installed/quality limits remain explicit.

- [Paired critical selection observations](p30-selection-paired-critical-20261106.md) reports known per-case membership losses without changing the unverified gate or disposition; 28 pure compatibility controls pass, with accepted real-input scoring still open.

- [Anthropic signed-thinking draft withdrawal](anthropic-signed-draft-20261106.md) adds bounded no-tool projection and pure request-body controls. A later synthetic Session/Saved fixture passed; native-terminal, installed and live qualification remain open.

- [Simultaneous decision entry and quiescent recovery](p30-simultaneous-settlement-20261104.md) complete one synthetic settled winner, both normal closes and sequential idle/no-replay paths in one fresh cohort. The loser encounters native-control contention, not observed budget denial; earlier failures and consumer quality remain open.

- [Native pending-proposal burst](native-burst-320-20261105.md) records 40 turns/320 proposals, 100 known settled units, queue/budget advice, authenticated root chains and separate current-pin/source/four-idle qualification. Original aggregate/tail failures and timing/baseline limits remain explicit; annual, quality and broader maximum-shape gates remain open.

- [Pilot label coverage and provisional intake freeze](pilot-label-intake-freeze-20261104.md) verify all 57 observed turn rows and 39 candidates already have independent-agent labels, preserve the partial run, and pin the unchanged 57-effect/40-turn assumptions in a private developer adapter; no actual day or quality acceptance.

- [Coalesced notes Worker-input observations](coalesced-worker-readview-20261104.md) record a fresh complete current build, 33 backend passes, one eight-source Worker pass, genuine native index/slot fallback and unchanged authority bounds; ordinary retained recall remains open.
- [Fetched Research to State Corpus](research-fetched-state-20261104.md) records current-main ordinary MCP/State transfer, exact source attribution, same-body suppression, interrupted-write/no-replay and unchanged old presets; broader lineage and installed qualification remain open.
- [Research retention beside managed recall](research-managed-coexistence-20261104.md) passes one complete fresh native coexistence case with explicit user State approval, same-ID Corpus query/citations and a refused model-selected State write; earlier fixture failures and broader transfer gaps remain explicit.
- [Completed-share timeout isolation](share-stale-timeout-20261104.md) reproduces and repairs a late-generation timer poisoning the next share, while preserving the separately failed retained read and its unresolved trigger.

- [Paired native literal reader](recall-paired-native-reader-20261104.md) distinguishes the failed cleanup-unknown and later traced deadline reads, records paired Worker/component and complete main-build controls plus an instrumented populated storage comparison, and keeps ordinary retained recall and annual gates open.
- [Simultaneous committed-preflight refusal](p30-simultaneous-preflight-20261104.md) preserves partial real pool exclusion followed by pre-service failure/unknown reservation, failed idle reopen and read-only fast-refusal/source-union discrimination. It is not a simultaneous settlement or liveness pass.
- [Installed Collection Word ceiling](word-installed-capacity-20261104.md) qualifies the exact 6adb7aca archive at 1 MiB original bytes, 64 KiB UTF-8 and 32 chunks, with three independent overflow guards, file recovery and final Saved/idle no replay. The two failed attempts and partial thumbnail warning remain preserved; broader capacity and fidelity are separate.
- [Main-tool Graph capture](graph-main-capture-20261104.md) records the existing-State-source tool, exact citations and ordinary approvals, ten protocol controls and four actual scripted main-tool/StateSession cases. That record predates the ordinary State choices below; its first fixture failures remain retained, and managed graph, original current-use, capacity, installed and quality gates remain open.
- [Ordinary State Graph identity](graph-identity-lifecycle-20261105.md) adds explicit alias/merge/latest undo with immutable facts, current citations and State CAS. Its 26 protocol tests include the earlier ten, three inert artifacts share 25 exact helper BEAMs, and one fresh ordinary State approval/denial/stale/Saved/idle journey passes with zero model calls. Actual expiry/interrupted identity writes and broader Graph qualification remain open.
- [Integrated Research transfer and Word v17](research-word-integration-20261104.md) records the complete strict build, four verified bundles, 63 focused passes and two fresh Word capacity/recovery passes; broader lineage, fidelity, installed and final combined gates remain open.
- [Frozen 477-file regression](source-regression-477-20261104.md) records `9b1a4e5e` at 4,028/4,029 passed, 130 skipped and 123 excluded, all 44 integrity checks passing and no invalid cases; the stale Graph catalog fixture failure and its later focused repair stay separate.
- [Frozen regression groups](source-regression-groups-20261104.md) preserve all 473 files' terminal 4,018/4,019 result, eleven passing integrity checks, the original owner-loss failure and locale RED/GREEN evidence. A separately passing [confirmed-native-exit control](source-owner-loss-causal-20261104.md) strengthens the causal witness; the old aggregate remains failed.
- [Current canonical short-note recall](current-canonical-recall-20261104.md) delivers all 33 short notes from one original source Session to a fresh consumer with complete coverage. Earlier multi-source failures and retained-cohort qualification remain separate.
- [Retained revision-ledger prevalidation](retained-revision-ledger-20261104.md) reconciles 373 original journals to 2,000 publication revisions with all 4,890 original objects unchanged; it performs no renewal or consumer recall.
- [Independent Word extraction outcomes](word-independent-extraction-20261104.md) preserve twelve first v16 refusals and a separate v17 candidate reevaluation: twelve partial extractions/payloads and bounded support checks, with full locator, semantic, rendering and installed qualification open.
- [Independent Word logical oracle and v18 repair](word-logical-oracle-20261105/index.md) preserve the complete v17 0/12 failure and qualify all twelve v18 logical-text/locator comparisons against a separately frozen reference, both payload profiles and fifty focused regressions. All documents remain partial; installed citation joins, broader fidelity and model quality remain open.
- [Pending advice current-use controls](p30-advice-output-revocation-20261104.md) withholds settled advice after revocation while preserving its charge; a separate fresh day-eight grant cannot extend the proposal's signed seven-day deadline. The original service-alias failure remains preserved; no simultaneous-reservation or broad quality pass is claimed.

## P31A contracts and evidence

- [Read-only saved-policy accounting](saved-policy-budget-metadata-20261104.md) records ten focused native/worker cases, exact existing-owner metadata, unchanged accounting and preserved fixture failures; queue display, the 320-proposal burst and annual qualification remain open.

- [Authenticated expired-neighbor recall](authenticated-expired-recall-20261104.md) records a narrow typed expiry refusal, complete host/worker rebuild, and a passing genuine native renewal recall control; retained-cohort, complete-day and annual qualification remain open.
- [Synthetic workload listener repair](workload-listener-20261103.md) records real loopback lifecycle controls and an unpopulated Session smoke; the populated recall failure and integrated day remain open.
- [Saved source-window reuse candidate](saved-source-window-fold-20261103.md) records passing focused replay controls and a separate failed strict 33-note attempt; the candidate was not promoted.
- [Source-owner phase comparison](source-owner-phase-20261103.md) records two fresh eight-note Sessions with one or eight original owners; its cache-inclusive timings are directional and do not establish the 33-note failure cause.
- [Synthetic egress diagnostic](egress-diagnostic-dcbb-20261103.md) records a validated small marker control and an inconclusive fresh 33-note failure during managed-current use.
- [Combined-source 33-note failure](recall33-combined-dcbb-20261103.md) preserves the fresh attempt, its unchanged source identities and the unknown pre-request failure.
- [Generic current-use v4 batching](generic-v4-batching-dcbb-20261103.md) records focused controls and the candidate's withdrawal after another failed 33-note attempt; populated recall remains open.
- [Recorded managed-read replay containment](managed-read-replay-containment-20261103.md) checks a genuine old synthetic receipt against the baseline and repaired reconstruction paths, with an intentional fail-closed compatibility change.
- [Strict 33-note recall attempt](recall33-one-shot-20261103.md) delivered all recorded Worker inputs and proposed 32 available notes, but failed before the loopback provider received a request; the cause remains unknown.
- [Current strict 33-original recall](recall33-strict-sources-20261104.md) passes one fresh missing/reappearing-source case in 125 seconds: 32 exact committed reads and structured note parts, partial coverage, unchanged original identities, strict Saved and idle reopen without replay; retained-cohort qualification remains open.
- [Combined Worker v4 coalescing](worker-v4-coalescing-bde96-20261103.md) records focused v4 batching and v7 compatibility controls, not a completed populated recall journey.
- [Historical pending replay control](pending-legacy-resume-control-20261103.md) records two startup refusals after genuine old-runtime pending disclosure, with compatible-resume and network-observation limits still open.
- [Fresh populated recall candidate](populated-recall-d739-20261103.md) records a completed 2,000-record seed and audit, followed by an unknown Worker input in a distinct Session before inference; the candidate did not pass populated recall.
- [Traced retained-cohort handoff](retained-worker-trace-20261103.md) records two slow protected observations in a distinct unresolved synthetic Session; the timeout handler did not establish the initiating cause, and original evidence was preserved.
- [Same-source recapture preflight refusal](same-source-recapture-refusal-20261103.md) records a post-rejection turn stopped before inference; its exact failed predicate and recapture outcome remain unknown.
- [Native recapture controls after containment](native-recapture-after-containment-20261103.md) verifies signed forget and rejection at the native publication boundary with trusted synthetic sources; bundled-worker and legacy override behavior remain separate.
- [Eight-owner handoff attempt](worker-handoff-eight-owner-20261103.md) seeded eight separate source owners but stopped on a disposable tracer syntax error before measuring a handoff; no scaling conclusion follows.
- [Pending proposal generic-read containment](pending-source-containment-20261103.md) records the admitted-worker disclosure, fail-closed repair and deliberate override/custom-value availability limit; compatibility restoration remains open.
- [Local-pilot pre-reservation refusal](pilot-local-refusal-20261103.md) records the pinned zero-inference inspection, empty attempt files and observed account-directory permission mismatch; the pilot was not retried and no reservation is recorded.
- [Small worker-handoff diagnostic](worker-handoff-small-20261103.md) records a passing eight-note control and a failing trace-wrapper count guard; neither establishes the cause of the populated-cohort failure.
- [Explicit sparse-paging fixture timeout](explicit-sparse-paging-timeout-20261103.md) preserves the first 33-note setup's terminal deadline and absence of a paging result.
- [Committed local-pilot synthetic gate](pilot-local-integrated-20261103.md) repeats the clean offline build and 27 focused controls on the integrated committed source; it does not include a live model call or semantic labels.
- [Retained-cohort diagnostic](retained-probe-20261103.md) preserves a separate read-only Session failure before inference, unchanged prior files and an unknown Worker-input outcome; the cause remains unproven.
- [Local pilot synthetic preflight](pilot-local-preflight-20261103.md) records a fixed-route one-shot launcher, 27 focused controls and no live calls; semantic labels and workload qualification remain open.
- [Populated integrated-day failure](integrated-full-day-failure-20261103.md) preserves a separately audited 2,000-note seed, 14 completed day effects and a first turn stopped during recall; the turn remains unresolved and the day is incomplete.
- [Full-cohort integrated-day preflight](integrated-full-day-preflight-20261102.md) records the provisional 57-effect schedule, restart guards and bounded calendar size check; the populated initializer and day were not run in that preflight.
- [Bounded paged recall and missing-original classification](recall-paging-20261102.md) records isolated paging, inode-swap and actual Session controls; reappearance, host limits and final integrated verification remain open.
- [Integrated synthetic Session smoke](integrated-final-smoke-20261102.md) records 40 actual turns interleaved with four native effects, a read-only audit and replay refusal, with retained synthetic receipts; it is not a 2,000-note or annual qualification.
- [Frozen native population seed runner](native-notes-seed-20261102.md) preserves actual statement/category/pin input, 100 operations/day, fresh-process clocks, original sources and separate control/journal costs; its two-day smoke precedes the full 2,000-record population and annual workload.
- [Closed native initial population](native-initial-population-20261102.md) records 2,000 captures and 100 pin publications with component allocation and original-Session costs; its full signed-record audit and annual qualification were still pending at that checkpoint.
- [Full initial-population audit](native-full-population-audit-20261102.md) authenticates all 2,000 signed records and retains exact root, control and 373 original source files; maximum payload and annual qualification remain open.
- [Signed-note decision withdrawal](p30-signed-withdrawal-20261102.md) repairs the current eight-note P30 control to require source-loss refusal, unknown Worker input and inert recovery; live-engine and consumer quality remain open.
- [Read-only native population audit](native-notes-audit-20261102.md) checks every signed record and original source against a closed root/control state, retaining per-note metadata and actual component allocations; the verified seven-note smoke supplies no full initial or annual result.
- [Immutable selected pending batches](pending-batch-20261102.md) bind up to eight candidates/8 KiB to separate native acceptance events and per-item publications; actual Session-produced complete/eight-item and partial-cancellation controls preserve provenance and stopped work without replay.
- [Explicit pending deferral](pending-deferral-20261102.md) reports an exact signed candidate as pending or expired without renewal, storage effects or acceptance authority; batch review and broader qualification remain open.
- [Native pending-text correction](pending-correction-20261102.md) preserves original attribution and expiry, creates a new pending identity and requires separate fresh acceptance; actual source withdrawal, revocation and staged-deadline controls retain their distinct outcomes and liabilities. Batch/defer, broader loss, installed and annual workload gates remain open.
- [Native single-candidate rejection](pending-rejection-20261102.md) preserves shared source anchors, rejects exact recapture and keeps reducing management available after capture revocation; a fresh-artifact synthetic-model Session covers actual public cancellation/rejection and old-backup refusal. Batch/correction, installed and annual workload qualification remain open.
- [Annual change-count clarification](workload-change-count-20261102.md) records the developer's selection of 10,000 mixed changes total in addition to normal annual work; pilot intake, complete native costs and endurance remain open.
- [Initial native pin accounting](native-pin-budget-20261102.md) includes the population plan's 100 separate pin reviews in the selected 23,080-operation minimum; expiry, imports, cleanup and derived intake remain unaccounted.
- [Native annual action calendar](native-annual-calendar-20261102.md) and [notes layout assessment](notes-layout-assessment-20261102.md) retain the original flawed expiry assumption and its withdrawn projections.
- [Corrected annual calendar](native-calendar-correction-deadline-20261102.md) preserves the original correction deadline, reassesses record and data bounds, and leaves actual annual qualification open.
- [Native calendar segments](native-calendar-segments-20261102.md) preserves all scheduled effects in bounded day-local batches and reports dependent-target and quota boundaries; it performs no effects or turns.
- [Native calendar clock anchors](native-calendar-clock-anchor-20261102.md) compensate for elapsed real time and check fresh BEAM/Rust fixture offsets; durable driver integration and long-running behavior remain open.
- [Quota-aligned clock correction](native-calendar-quota-clock-20261102.md) ends each simulated workday at the UTC consent reset, with a protected quota boundary control; annual execution remains open.
- [Two large-seed calendar days](native-calendar-two-day-20261102.md) records 114 native effects and a read-only signed-record audit; annual execution and model turns remain open.
- [Third large-seed calendar day](native-calendar-third-day-20261102.md) extends the audited continuation to 172 native effects; annual execution and model turns remain open.
- [Multi-page native recall diagnostic](recall-many-native-20261102.md) preserves the pre-dispatch worker-input failure and corrects the original 33-note fixture's mistaken fitting-set assumption.
- [Bounded replay computation](recall-replay-capacity-20261102.md) records scoped size/hash reuse, an exact synthetic reconstruction comparison and the still-failing native control.
- [Task-scoped source replay](task-source-replay-20261102.md) retains exact reconstructed indexes without caching source authority; the 32-note native control passes with a 15-second synthetic provider timeout while fitting-set recall remains open.
- [Batched-read probe](recall-batched-read-20261102.md) records a passing synthetic worker suite and a native pre-dispatch failure; the runtime prototype was not retained.
- [Seed recorded times](native-seed-recorded-times-20261102.md) adds selected journal timestamp maxima to the seed audit; its [full signed audit](native-seed-full-recorded-times-20261102.md) passes on all 2,000 notes. Those maxima are not a physical-completion bound.
- [Native consent renewal](native-consent-renewal-20261102.md) exercises expired-policy refusal and a later native capture after renewed review; [renewed recall](native-renewal-recall-20261102.md) adds a synthetic request and source-loss control. Annual continuity remains open.
- [Native turnover pilot](native-turnover-pilot-20261102.md) continues a separate seven-note seed through seven native lifecycle effects and a signed final-state audit; it does not execute the annual calendar.
- [Turnover lock and interruption](native-turnover-lock-20261102.md) retains the initial management-owner conflict, checks a separate-worker pilot and verifies post-effect replay refusal; active-effect loss remains open.
- [Batched turnover smoke](native-turnover-batch-20261102.md) checks grouped native effects, clean restart and reuse of a compensated same-day anchor; annual and active-effect qualification remain open.
- [Native workload operation-budget preflight](native-workload-budget-20261102.md) distinguishes mixed operations from complete lifecycle cycles, preserves the initial annual floor and exposes a complete-cycle lower bound above the unchanged ID limit. Pure tests and CLI arithmetic establish no actual endurance or semantic acceptance.
- [Retained receipt geometry](native-receipt-geometry-20261102.md) measures managed/unbound receipts with zero/2,000 public descriptors; the 42,980-managed-receipt scenario also exceeds the canonical-state byte ceiling. It changes no limit and qualifies no native workload.
- [Complete cancellation-repair baseline](full-suite-cancel-repair-20261102.md) records 3,753 passed, zero failed, 118 skipped and 112 excluded at frozen `9f1707c`, with unchanged source/build/private assets/helper. Later Word/clock drafts and broader acceptance remain separate.
- [Worker-input cancellation completion boundary](worker-input-cancel-20261102.md) records a controlled pre-repair cleanup failure and the focused interruptible-completion repair, actual native exit, mismatched-identifier refusal and inert recovery; its later complete source baseline passes separately.
- [Actual native clocked lifecycle](native-clock-lifecycle-20261102.md) advances one genuine store across fresh day-30/day-91/day-366 processes, with a signed native pin review, elapsed ordinary/history reclamation, unchanged original source and nonmutating receipt inspection. This establishes the instrumented native path, not annual workload or capacity acceptance.
- [Late first temporal supersession](native-clock-late-supersession-20261102.md) uses a disclosed private stdio-clock adapter to publish at day 100, retain signed history through days 366/464 and reclaim it on day 466; the original failed clock-propagation boundary remains preserved. Full annual workload remains open.
- [Earlier complete frozen-source baseline](full-suite-20261102.md) preserves 3,747 passed, one failed, 118 skipped and 112 excluded at isolated `39c8043`, with matching pre/post inventories. Its failure and original diagnosis status remain historical evidence beside the later repair and fresh complete pass.
- [Test-process clock for lifecycle workloads](process-clock-20261102.md) verifies coherent plain-VM/Rust wall clocks at fixed process offsets, unchanged monotonic timers and malformed-setting refusal without starting Ipse or rebuilding its helper. Actual protected turnover and lifecycle qualification remain open.
- [Managed compatibility and historical-source boundaries](managed-compatibility-boundaries-20261102.md) distinguishes explicit unsupported V2 refusal from actual registered V3 queue/concurrency/late-loss controls, corrects the refusal diagnostic and verifies current source withdrawal against a fresh genuine old-runtime literal. Complete-suite and independent acceptance remain separate.
- [Shipped recall followed by capture](shipped-recall-capture-20261102.md) preserves the actual native artifact's full metadata/literal union through source lookup, pending publication and historical-root continuation. Actual post-publication source withdrawal and revocation preserve the known save and withhold Worker input; replay tampering refuses. This remains author-run synthetic component evidence.
- [Complete source-dependent capture module](managed-collection-module-current-20261102.md) records 170 passed, five failed and 15 skipped at clean isolated `2f628a9`, with unchanged source/build/helper inventories and every parent failure. A subsequent two-case legacy-question synchronization pass remains separate from the failed complete aggregate.
- [Source-dependent new-v3 capture](current-source-capture-publication-20261102.md) carries the full inherited union and original source owners through the actual native publication, with a genuine current-literal/pending-proposal positive, withdrawal and original-owner-loss controls, conservative settlement and inert recovery. Broader combinations and complete C0 qualification remain open.
- [Nested native extension approval](nested-native-approval-20261101.md) binds the original Host task, parent/action and inherited union to the existing native display, preserving discovery before approval and separate effect/Worker-input fences. Follow-up controls cover all five operation types on root metadata, with unchanged frozen source/build inventories, the retained combined wire-assertion failure and a focused correction. Whole-source/content/installed qualification remains open.
- [Paired stale-helper input boundaries](stale-helper-boundary-20261101.md) distinguish zero helper egress and unknown unfinished-Worker input from successful completed-output withdrawal, preserving both current-helper positives, exact accounting and inert recovery. This is a focused test repair, not a new complete baseline.
- [Shared native loss-lineage assertions](native-loss-lineage-shared-20261101.md) preserve the exact approval/reference union and journal-derived reconstruction fence for both shell and MCP, including idle recovery. Five focused native controls pass; the complete module aggregate remains separate.
- [Complete frozen managed-collection module](managed-collection-module-20261101.md) records 130 passed, 22 failed and 15 skipped at clean `098559f`, with all parent failures and unchanged pre/post source, test-build and helper inventories. This is a failed module baseline, not a complete-suite result.
- [Original lost-initialization and held-owner-loss controls](root-native-mcp-loss-20261101.md) retain native approval before the actual HTTP/stdio fault, observed socket/server exit, exact original source union and no replay; missing cleanup keeps the recovery lineage unavailable. Combined-module and broader C0 qualification remain open.
- [Original HTTP pre-start and pinned-helper controls](root-native-prestart-pinned-20261101.md) preserve genuine input, the exact signed expiry, no further connection after pre-start refusal, and successful stdio dispatch despite an unpinned helper override. Strict Saved and inert recovery retain exact traffic/effect counts; startup/held-owner loss remains open.
- [Original root-only MCP start/send controls](root-native-mcp-start-20261101.md) pair native allowed stdio/HTTP effects with actual post-start revocation before send, confirmed cleanup, withdrawn delivery and strict idle recovery; HTTP additionally checks unchanged complete connection traffic after settled close. Broader fault migrations remain open.
- [Original root-only running shell controls](root-native-running-shell-20261101.md) preserve genuine approval before revocation or consumer loss, exact completed/absent effects, withdrawn stdout, actual native group exit and strict nonreplaying recovery. MCP start/send and HTTP migrations remain open.
- [Original root-only native approval waiting faults](root-native-faults-20261101.md) retain all twelve write/shell/MCP root-change, revocation, actual-expiry and consumer-loss cases through the native terminal caller, with strict Saved and inert recovery. Running-operation and HTTP boundaries remain open.
- [Original root-only native approval positives](root-native-approval-20261101.md) preserve the SDK/policy/snapshot and exact write/shell/MCP effects through actual terminal approval, completed result delivery and idle recovery. This is distinct from signed-note contents; the later waiting-fault migration above has its own evidence.
- [Actual-note native MCP approval](native-mcp-approval-20261101.md) covers explicitly configured stdio start/send, one physical service call, current result delivery and source withdrawal before dispatch, plus idle recovery. Distinct root-only positives are separately qualified above.
- [Actual-note native shell approval](native-shell-approval-20261101.md) reuses genuine statement capture and native review for physical shell effects, buffered result delivery and source withdrawal before spawn; legacy subscriber-shaped shell fault controls retain their separate qualification.
- [Registered V3 lifecycle and queue controls](capture-lifecycle-20261101.md) preserve actual activation, second-publication success, full-queue refusal, settlement and idle recovery through the registered adapter; the distinct legacy publication failure remains open.
- [Same-owner first-use domain selection](domain-selection-20261101.md) removes a preliminary-verifier race in concurrent V3 capture, preserves legacy authorizer ordering and prepared-state refusal, and records focused Identity, actual competing-publication and repeated-capture controls. Full-source and integrated qualification remain open.
- [Complete clean-source baseline](full-suite-20261101.md) records the terminal f44b63c result: 3,653 passed, 54 failed, 116 skipped and 112 excluded, with all top-level failures, exact source/helper identity and explicit post-run inventory limits. Later repairs and drafts are excluded from that result.
- [Accepted-decision native approval](accepted-approval-20261101.md) binds original management-journal locks through Session/Writer validation to the actual native display, with approval/denial, descriptor ownership and pre-display peer-loss controls; separate source regressions and broader acceptance retain their own scope.
- [Native accepted-decision forgetting](accepted-decision-forget-20261101.md) adds a distinct signed destructive target to the existing public native review and measured management path; cancellation and disabled/source-unavailable removal preserve the immutable link, peer, journals and authenticated suppression. Current-use delivery and other accepted lifecycle choices retain separate gates.
- [Accepted-decision post-effect loss](accepted-decision-forget-loss-20261101.md) kills the actual native owner after durable removal, preserving the unconfirmed journal/publishing liability and read-only nonreplaying inspection. A separate current-source 15-test lifecycle cohort passes; it does not replace the failed complete-suite aggregate.
- [Accepted-decision expiry](accepted-decision-expiry-20261101.md) reclaims a signed finite accepted deadline through existing reducing management, preserving anchor clocks, immutable link and original journals. The genuine journey waits for actual expiry after native acceptance, with capture disabled and the original source unavailable; annual turnover remains separate.
- [Native accepted retention](accepted-decision-retention-20261101.md) preserves immutable public acceptance while updating signed choices through the owned native management path, with compact current-read witnesses and generic-entry refusal controls. Full lifecycle, loss, installed and turnover qualification remain separate.
- [Headless CLI pending saves](headless-cli-pending-20261101.md) use actual native setup followed by separate argv/stdin CLI processes; strict positive controls require one attributed pending record, completed requests, settled consent and denied workspace/shell effects. This supersedes the old empty-store diagnostic only for its current-source path.
- [Registered repeated V3 capture](repeated-v3-capture-20261101.md) preserves successful publication expectations through the actual adapter, with a nonzero live split fence, distinct original sources, settled accounting and idle recovery; legacy reader access still refuses. Retention endurance and full-source acceptance remain open.
- [Nested native/MCP result continuation](nested-result-input-20261101.md) replaces the redundant result gate only for pinned exports using the actual managed input fence. Explicit-allow positives and post-effect root/revocation controls retain known effects, uncertain delivery and inert recovery; document and other unqualified purposes stay gated.
- [Unsupported private Worker input refusals](private-worker-input-refusals-20261101.md) preserve ordinary and metadata delivery while closing managed presentation, notification, tool-feed and selected text entry; required registered text retains its original producer and acknowledgment checks.
- [Current native A/B Worker input controls](worker-inherited-union-20261101.md) retain a genuine inherited source at the next fresh quote frame and complete an independent-B capture with A unavailable; each case creates its own current-runtime native seed.
- [Managed page-input reservation](worker-input-reservation-20261101.md) funds input intents, possible root transitions and results from the actual output token; live byte/event contention completes, while insufficient full capacity refuses before source begin.
- [Accepted-decision Worker input](accepted-worker-input-20261101.md) carries original management journals to the same native stdin writer, with genuine single/two-decision source inspection and strict settlement. Model-history composition after a settled Worker root transition preserves the original union and historical notice; qualification remains scoped.
- [Actual Session-managed export input](worker-input-session-20261101.md) binds committed requests and complete dependencies to the same native Worker stdin owner, with strict unknown/no-replay restoration. Its genuine literal-source observer is disclosed; accepted-decision and other Worker purposes remain open.
- [Retained native stdin through the existing transaction owner](worker-stdin-ownership-20261031.md) has actual pipe and owner-loss controls; exact Session/frame authority and managed SDK delivery remain open.
- [Actual pending Worker input and sealed native frame](worker-input-frame-20261101.md) adds opaque reservation, early-response buffering and more than 256 successive handoffs. A retained substitution counterexample led to exact native byte binding; Session source authority and SDK adoption remain open.

- [Ordinary model-tool approval through the actual native sink](managed-approval-native-20261031.md) binds Session/purpose/full payload and current source/policy owners, releases display locks before input and rechecks effects; accepted decisions and other unqualified shapes remain closed.
- [Interactive literal correction and supersession through actual native owners](managed-supersession-native-20261031.md) binds two fresh reviews, exact normalized publication and active/inactive sources; native loss controls preserve unknown effects without replay.
- [Lifecycle launchers reuse that genuine journey](literal-lifecycle-launchers-20261031.md) and retain distinct signed-history use and interrupted-compaction checks; obsolete zero-append resume assertions are removed.
- [Actual history expiry after native Session correction](history-expiry-session-20261101.md) replaces an obsolete trusted-successor fixture while preserving its signed deadline, retained successor and unchanged original-journal checks.
- [Pinned history through public native management and replacement](pinned-history-session-20261031.md) preserves signed persistent history after successor forgetting; future as-of classification remains distinct from annual native qualification.
- [All default lifecycle modes now use genuine Session sources](genuine-lifecycle-default-20261031.md), including eight-sidecar publication, a native elapsed root decision and explicitly separate future as-of turnover; controlled-host faults and synthetic geometry retain their scope limits.
- [Strict display preparation with retained actual source/policy owners](managed-display-owners-20261031.md) preserves its earlier prerequisite-only evidence and loss/deadline controls.
- [Cooperative Ollama model/context checks around registered text and embedding jobs](ollama-model-pin-jobs-20261031.md) retain saved-profile identity, private output release and measured charges; physical request attestation and live qualification remain separate.
- [Actual pinned primary-pair Session jobs](local-pinned-jobs-20261031.md) cover public embedding reconstruction, ordinary main completion, reported context and service/Saved settlement without quality or installed claims.
- [Installed idle-resume verifier repair](package-idle-resume-20261031.md) preserves the exact failed archive, native ownership/release assertions and source checks; a replacement archive still requires installed verification.
- [Full-source regression result](full-suite-20261031.md) retains the unchanged-source run's 71 failures and complete top-level failure extract; selected later controls do not replace this failed baseline.
- [Completed c7cb484 default baseline](full-suite-c7cb484-20261031.md): 3518 passed,58 failed, with unchanged1057-file source; later isolated increments remain outside its scope.
- [Running e86b1b8 concurrency limitation](full-suite-e86b1b8-concurrency-20261031.md) records overlapping author native-terminal work and the shared per-user input lock; no final aggregate or clean-environment qualification is implied.
- [Completed e86b1b8 run](full-suite-e86b1b8-20261031.md) retains3538passed60failed109skipped112excluded, the verified7,760-file inventory with after-launch timing, and a separate same-source eight-pass isolated native cohort; the concurrency caveat remains.
- [Canonical root-prerequisite fixture repair](root-prerequisite-fixture-20261101.md) preserves the first failure from the clean f44b63c baseline, fixes its noncanonical trusted input without changing runtime validation, and records the separate pure controls.
- [Registered competing V3 positive-fixture repair](registered-competing-fixture-20261031.md), preserving the original failed baseline.
- [Current registered capture controls](registered-capture-controls-20261031.md) cover paged output, worker-entry revocation and ambiguous permissions without changing runtime gates.
- [Installed inference inspection and reconciliation](inference-reconciliation-installed-20261031.md) records the exact clean package, generic installed proof and five synthetic native-terminal scenarios.
- [Selected Collection cosine/hybrid retrieval](collection-selected-semantic-20261031.md) records public-artifact native controls, encoder preflight/pinning and final source/Collection revalidation; namespace dense retrieval remains open.
- [On-use acquired document checks](document-current-use-20261031.md) records native State/Collection file replacement, rename, deletion, redirect and concurrent-revision controls; producer/later-use qualification remains open.
- [Responses optional-argument repair](responses-optional-tools-20261031.md) records the failed real enhancement reader, explicit schema mapping, native context-before-question follow-up and retained final-response bound failure.
- [Draft response budgets](draft-response-budgets-20261031.md) separates proposal size from SSE framing, preserves tighter route limits and records explicit invalid-final refusal with synthetic Session accounting controls; live completion remains open.
- [Complete native main-route draft](enhance-complete-native-20261031.md) records a later fresh read/question/proposal/cancel/unrelated journey, four known-final requests and unchanged source/runtime/workspace, without independent quality or installed acceptance.
- [Clean 78d1555 installed candidate](candidate-78d1555-installed-20261031.md) passes the generic package baseline, retains the additional draft proof's production endpoint refusal and corrects pending-draft recovery text without qualifying installed draft completion.
- [Optional Ollama text context](ollama-context-profile-20261031.md) records operator-only selection, exact native wire, delegated Saved history and legacy helper compatibility; effective context and job-level identity remain unqualified.
- [Storage fixture mount selection](storage-profile-fixture-root-20261031.md) preserves the clean tmpfs clone failure, real Btrfs refusal and an explicit wrong-mount failure without changing production admission.
- [Prior-Session shadow assessment](decision-shadow-prior-session-20261102.md) records a finite numeric-loopback grant, protected bundled decision controls and the unresolved same-Session post-write case. Its [saved-note result follow-up](saved-note-shadow-result-20261103.md) returns bounded experimental advice with a source-withdrawal control; a [pending-candidate increment](p30-pending-assessment-20261103.md) assesses an actual main-tool proposal under a separate finite grant. [Cross-Session controls](p30-cross-session-allowance-20261103.md) record two settled calls, a generic third refusal and a separate unknown-service quarantine. A [timestamp-correlated trace](p30-allowance-interval-20261103.md) demonstrates limit-driven refusal in a distinct synthetic run; a [cross-process control](p30-cross-process-allowance-20261103.md) verifies the same limit in a separate OS process. Concurrent reservations, model quality and P30 remain open.
- [In-flight allowance attempt](p30-inflight-allowance-20261103.md) failed at the second operator channel before its allowance check; it provides no result on overlapping reservations.
- [Native EOF in-flight control](p30-inflight-native-eof-20261103.md) releases the first idle prompt through normal native EOF, then verifies the second process's native-approved allowance refusal while the first call remains admitted. The winner settles and both Sessions reopen without replay; simultaneous reservation entry and full P30 acceptance remain open.
- [Canonical encoding reconstruction cost](recall-canonical-encoding-20261103.md) preserves historical digests while reducing repeated encoder work. Retained-source timings, complete current-host strict compilation and 39 focused tests pass; a successful populated recall turn remains a separate gate.
- [Owned reconstruction cache across inference scopes](recall-owned-cache-20261103.md) records the actual duplicate-cache boundary, 75 focused controls and a fresh untraced 33-source recall pass with exact eligible text, partial missing-source coverage and idle reopen without replay. The 2,000-note read, populated day and annual workload remain open.
- [Completed-reply decision review](chat-completed-reply-20261104.md) records exact nomination and source binding, protected capture, confirmed chat closure, native acceptance and idle same-ID resume. Four actual normal-chat controls pass across accept, cancel and stale selections. The separate explicit-resume and planning records below retain their own qualification; a usable first same-ID follow-up and complete P31 acceptance remain open.
- [Planning exit through decision review](chat-planning-mode-20261104.md) records live-mode projection and chronological ToolLifecycle replay, with actual planning-exit acceptance and idle same-ID reopening. A usable first follow-up in the original conversation and final whole-source checks remain separate gates.
- [Explicit-resume decision review](chat-explicit-resume-20261104.md) follows that baseline with one actual known-cancel then explicit-resume journey: a fresh native code accepts the same pending candidate without recapture, same-ID reopening ends session grants, and a fresh chat retrieves it through a current protected read. Startup runs before the first ordinary input prompt; unknown prior reservations remain blocked. Planning-start/exit and final integrated/package/platform qualification stay separate.
- [Installed prior-Session pending assessment](p30-pending-installed-20261103.md) records five passing synthetic packaged-worker cases, including denial, source loss and charged-unknown reopen.
- [Deferred pending-candidate fixture](p30-defer-candidate-20261103.md) records the non-default advice path, unchanged pending record, initial selector failure and a separate passing targeted run.
- [Current local follow-up](current-local-followup-20261031.md) records the integrated build/demo, 99 focused regressions, 79 P30 checks and fresh current-runtime two-source decision controls, with an exact runtime/test manifest.
- [Bounded DOCX table styles](docx-table-style-20261031.md) records the reproduced nonhidden-style refusal, reuse of the existing style graph, recipe v12 and source/separate-artifact refusal controls; full Word fidelity remains open.
- [Matching alternate DOCX style graphs](docx-matching-effects-20261031.md) records original public Word fixtures, recipe v13's exact graph agreement, native acquisition and separate source/installed artifact checks; differing graphs still refuse and rendered-Word fidelity remains open.
- [Broader Word ingestion investigation](word-ingestion-gap-20261031.md) separates format/version evidence from parser compatibility and reproduces the many-paragraph source-transfer refusal; complete bounded acquisition is the next Word implementation target.
- [V14 block packing](word-block-packing-20261031.md) implements the mixed paragraph/table geometry without raising limits and records actual original-file acquisition, both native storage profiles and independent installed-artifact citation checks.
- [V15 annotation completeness](word-annotation-completeness-20261102.md) has passing pure extraction/evidence and two-profile native acquisition/citation/resume checks with retained v14 compatibility. Its exact package is verified separately; independent Word quality remains open and P31F is incomplete.
- [V15 exact package](word-annotation-installed-20261102.md) passes the generic installed proof and all nine document checks using the same independent artifact as source verification, at clean committed `23d9949`; full installed knowledge and Word quality remain open.
- [V16 bounded numbering locators](word-numbering-20261102.md) records derived single-level decimal labels separately from literal quotation, scoped review and focused Session controls; a PDF-free synthetic Linux package passes both installed storage profiles for [two paragraphs](word-numbering-installed-20261103.md) and [40 packed blocks](word-packed-numbering-installed-20261103.md). A [default PDF-enabled package](default-pdf-package-20261103.md) passes synthetic installed document and packed Word setup controls. General Word fidelity and final integration remain open.
- [Combined source regression](combined-source-regression-20261104.md) preserves the failed integration run, six passing chat controls and unchanged frozen inputs. [Focused repairs](focused-source-regression-20261104.md) close its 26 failures and 52 invalid cases across distinct source freezes; the later [473-file terminal regression and separate causal correction](source-regression-groups-20261104.md) retain their distinct results.
- [Ordinary same-ID follow-up](chat-same-id-followup-20261104.md) passes actual native acceptance, reopening, current accepted-note recall and the next provider request while preserving the original tool call and continuation. It records the earlier main-preflight refusal and the bounded historical-root repair separately.
- [Dense Corpus manifest boundary](dense-corpus-manifest-20261104.md) records a setup-only 13-byte manifest excess and an equivalent wording candidate that passes the unchanged bound, actual inert import and lookup; the affected final-source Session journeys remain unqualified.
- [Word byte bounds and dormant cancellation](word-capacity-cancel-20261104.md) qualifies source-tree native cancellation and the existing 1 MiB/64 KiB/32-chunk limits with exact citations, failure/recovery and over-limit controls. It preserves the earlier failed fixtures and the source-producer bookkeeping fault; broad fidelity, installed capacity and final regression remain open.
- [Larger Collection Word acquisition](word-collection-larger-20261103.md) records the earlier bounded snapshot path, source-tree and installed synthetic checks, and the cancellation uncertainty superseded by the newer control above.
- [Installed Word disappearance recovery](word-disappearance-installed-20261103.md) checks missing-original refusal across reopen and same-file citation recovery in both profiles without replaying acquisition.
- [Native literal result expiry](output-expiry-fixture-20261031.md) isolates the actual read/release boundary and checks the safe withdrawal stub in a real continuation request, preserving the original failed fixture result.
- [Legacy SDK final admission](legacy-sdk-admission-20261031.md) records isolated actual Session controls for source/policy-bound unmanaged publication while strict APIs and unsupported managed mutations remain gated. The [prior Knowledge training manual](knowledge-manual-before-editorial-20261031.md) preserves the full pre-consolidation body, with source hash and mechanically rebased relative links; its replacement is the [current feature guide](../../developer/knowledge-extensions.md).
- [Public accepted-decision recall](accepted-recall-20261031.md) records the distinct current-use dependency, actual registered-provider request, unavailable-source and altered-event controls. It follows public single-card review without qualifying the complete notes lifecycle.
- [Latest resume checkpoint](checkpoint-20261029-v4-bound.md) records source-bound geometry, its provisional reservation and next producer gaps. The [public-page checkpoint](checkpoint-20261029-v4-public-resume.md) records the earlier documentation repair; the [restart](checkpoint-20261029-restart.md) preserves the stop request and its then-current handles.
- [Latest public-producer/notes checkpoint](checkpoint-20261029-public-producer.md) supersedes the earlier [source-admission checkpoint](checkpoint-20261029-source-admission.md) where status differs; neither replaces milestone acceptance.
- [Initial wired document admission](document-source-admission-initial.md), [reader-return repair](document-source-admission-return.md) and [amended source review](document-source-admission-initial-implementation-independent-review.md) precede the actual [positive/expiry controls](shared-producer-guard-session-independent-review.md), [finite-TTL positive](shared-producer-finite-guard-session-independent-review.md) and [public first-page adoption](shared-producer-public-adoption-independent-review.md). [Guarded worker wire](shared-producer-guarded-wire.md) remains separate protocol evidence.
- [V4 producer progression proposal](shared-producer-v4-progression-design.md) and [independent direction](shared-producer-v4-progression-independent-direction.md) release bounded implementation. [V4 source authentication](document-source-use-v4.md) and [actual-old-ready/live-inline admission](document-inline-v4.md) have [scoped independent implementation acceptance](document-inline-v4-independent-review.md). A [public two-page synthetic Session](shared-producer-v4-public-session.md) passes with an empty old root; full producer qualification remains open.
- [Selected-root immutable reuse repair](shared-producer-v4-selected-reuse.md) fixes a response-shape failure after inference and has focused protocol-model controls; native selected-root reuse remains unqualified.
- [V4 source-bound group geometry](shared-producer-v4-bound-geometry.md) records a 256-chunk synthetic append with 509 maximum reads, prior staged-budget failures and a fresh two-page native control; complete capacity and reservation proof remain open.
- [Pinned anchor reads](shared-producer-v4-pinned-read.md) reduce that model's append peak to 506 reads, widen its provisional reserve and include another native two-page control; worst-case reservation proof remains open.
- [Intervening native commits](pinned-native-stale.md) exercise stale pinned anchor and multipart reads directly against DocumentStage; Session ownership-loss qualification remains separate.
- [Maximum-count fact append model](shared-producer-v4-full-facts.md) completes 256 short synthetic facts and 256 vectors over 37 private invocations; real Session timing, journal handoffs and wider fact geometry remain open.
- [Batched citation validation](shared-producer-v4-batched-spans.md) records scoped compatibility, Word-source/artifact controls, callback samples and the corrected document test loader; production deadline and independent review remain open.
- [Packed page geometry](shared-producer-v4-packed-shape.md) records an escaped-value physical bound failure and the repaired page split. [Split metadata staging](shared-producer-v4-split-append.md) reduces a full escaped-group model to 463 maximum reads and has small direct native controls; wide native and Session-owner qualification remain open.
- [Final root fence](shared-producer-v4-final-root-fence.md) adds a pinned root check before append commit, with direct native interposition and a 464-read escaped-group model; independent review remains open.
- [Combined Host/full knowledge control](combined-notes-current.md) records a fresh full artifact, successful capture-and-continue turn and native read-only receipt/settlement/release inspection. The [minimal-artifact diagnostic](combined-notes-artifact-diagnostic.md) preserves the distinct earlier failed run. Explicit pending acceptance is being implemented from its [typed proposal](pending-acceptance-proposed-contract.md), not enabled by the existing parser.
- [All-source selected-provenance preflight](managed-source-tool-preflight.md) and [independent review](managed-source-tool-preflight-independent-review.md) preserve the initial settled-but-failed turns. The later [own-write transition](own-root-transition.md) and [independent implementation review](own-root-transition-independent-review.md) cover an exact successful synthetic-model capture-and-continue turn. [Untrusted-source controls](headless-untrusted-controls.md) retain their separate refusal limits.
- [Current new-capture final-admission implementation](notes-publication-admission.md), [own-read prerequisite repair](notes-publication-prerequisites.md) and [independent implementation review](notes-publication-implementation-independent-review.md), followed by [genuine Session publication](remember-publication-absence-integration.md) and [actual Terminal/headless controls](remember-terminal-headless-controls.md). The Terminal journey passes; headless causal-root/source-tool gaps remain separate.
- [Public native forgetting](management-forget-public.md), [current-source integration](management-forget-current-source.md) and [independent current-source review](management-forget-current-source-independent-review.md) supersede the earlier private-only admission status below. Retention/session-only/supersession remain gated.
- [Retained document reader](document-held-reader.md), [independent reader review](document-held-reader-independent-review.md), [complete logical value reader](document-held-value.md) and [independent value review](document-held-value-independent-review.md) support the [source-use relation](document-source-use.md) and its [scoped implementation review](document-source-use-independent-review.md). Later live admission and public first-page controls are linked above.
- [Reviewed short source-dispatch direction](document-producer-source-egress-independent-review.md), [public containment gate](shared-producer-public-gate.md), [selection adoption](shared-producer-selection-adoption.md) and [v3 range claims/compatibility seeds](shared-producer-range-claim.md) separate implemented prerequisites from the still-gated complete producer. Locks need not remain held through a remote request's lifetime.
- [Causal-root and source-tool repair direction](causal-root-and-source-tools-direction-independent-review.md) preserves authentic inherited observations and identifies the separate terminal preview boundary; it does not open either route by itself.
- [Causal-root classification cache](causal-root-cache.md) and [independent implementation review](causal-root-cache-independent-review.md) cover authenticated chronological replay and the earlier direct-client headless positive. Later source-tool and own-root controls are distinct reviewed increments linked above; shell/workspace authority remains separate.
- [Selection adoption review](shared-producer-selection-adoption-independent-review.md) and [private v3 range review](shared-producer-range-claim-independent-review.md) accept their frozen scopes without reopening public page production.
- [Task-by-task execution checkpoint](status-20261029-current.md), with [exact resumption state](handoff-20261028-sol-retention.md); these dated snapshots do not replace the plan's acceptance ledger.
- [Explicit compact generation progress](generation-compact-progress.md), [independent review](generation-compact-progress-independent-review.md) and [actual stage-free Session handoff](generation-compact-handoff.md); the [new finalization ledger](document-compact-finalization-ledger.md) still exceeds one Session despite reduced public output.
- [Terminal initial/rebuild recipe ledger](document-whole-recipe-ledger.md) accounts for retained operation IDs and physical-layout alternatives; native peak, public producer and migration remain incomplete.
- [First public shared-vector page](shared-producer-first-page.md) and [producer contract](shared-producer-v1-design.md) retain their intermediate scope and original source hold; later v3 admission/adoption is linked above. Later pages and the complete budget remain open.
- [Private complete management display](management-full-facts-display.md), [deadline repair](management-display-deadline-repair.md) and [genuine input review](management-review-input-independent-review.md) precede the [forget-only Core change](reviewed-forget-core.md); public admission and final effect qualification remain separate.
- [Private journaled forget effect](management-forget-effect.md) and [independent effect review](management-forget-effect-independent-review.md) cover the earlier reducing-mutation and late-commit unknown stage; the later public restoration is linked above.
- [Embedding selection bootstrap/pin implementation](embedding-selection-bootstrap.md) follows the [accepted SDK gap](embedding-selection-bootstrap-independent-review.md); later actual source-policy admission has its own evidence above.
- [Worker source-policy repair](shared-producer-worker-policy-repair.md) and [source-only Host egress gap investigation](document-producer-source-egress-gap.md) preserve the original gap and interim hold, superseded for the bounded v3 first page by the reviewed live controls above.
- [Read-only physical document layout](document-packed-layout.md) and [independent review](document-packed-layout-independent-review.md) preserve original part geometry and separate logical from physical hashes; complete export/import is not implemented.
- [Actual private Session/Host tty bridge](../2026-10-29-native-shared-lease/tty-session-bridge.md) and [independent review](../2026-10-29-native-shared-lease/tty-session-bridge-independent-review.md), followed by [original management journal and real owner controls](management-share-controls.md) and [their review](management-share-controls-independent-review.md); management facts, full display/closure, Review and production admission remain separate.
- [Pure pending-proposal projection](pending-projection/receipt.md), [independent review](pending-projection-independent-review.md) and [remaining acceptance contract](pending-proposal-contract-gap-review.md); structural parsing supplies no source, clock or acceptance authority.
- [2026-10-31 pending-review boundary correction](pending-review-boundary-20261031.md) separates signed historical display from fresh publication authority, superseding the later checkpoint's source-path display blocker while preserving its failed controls.
- [2026-10-31 public pending-review CLI](pending-review-cli-20261031.md) records bounded metadata discovery, single-card native acceptance, consent accounting and input-owner-loss controls; complete accepted-note journeys remain open.
- [Exact retained management-snapshot read](management-snapshot-read.md) and [independent review](management-snapshot-read-independent-review.md), followed by [continuous Collection reads](collection-held-read.md) and [independent token-seal repair review](collection-held-read-independent-review.md#additive-v2-repair-disposition). The [held signed-target adapter](management-held-target.md) and [its independent review](management-held-target-independent-review.md) cover historical metadata checks with that owner; complete production display integration remains separate.
- [Extension discovery's unknown outcome](../2026-10-29-mcp-discovery-outcome/extension-discovery.md) has a separate [independent review](../2026-10-29-mcp-discovery-outcome/extension-independent-review.md). The [synthetic active terminal candidate](../2026-10-29-native-shared-lease/terminal-display-synthetic.md) was held for its reproduced lease-count failure and post-readiness monotonic deadline check; the [repair](../2026-10-29-native-shared-lease/terminal-display-repair.md) has [additive independent acceptance](../2026-10-29-native-shared-lease/terminal-display-synthetic-independent-review.md#additive-v7-repair-disposition), without enabling production output.
- [Explicit Root2/Job3 implementation and exact protocol/native cohorts](shared-directory-v2-implementation.md), with [independent review](shared-directory-v2-implementation-independent-review.md); [read-only descriptor inventory](document-descriptor-inventory.md) and its [independent read/design review](document-inventory-v2-independent-review.md) are separate host slices. The [corrected maintenance proposal](document-collection-maintenance-v2-design.md) and [required epoch/ID clarification](document-maintenance-epoch-clarification.md) do not implement deletion or migration.
- [Standalone management's native journal design](management-journal-owner-design.md), [focused implementation and serialized-marker repair](management-journal-owner.md) and [independent review preserving the original finding](management-journal-owner-independent-review.md); this repairs header/append ownership without enabling still-gated management publication or output.
- [Managed HTTPS peer-loss controls](../2026-10-29-managed-http-peer-loss/index.md) and [independent evidence review](../2026-10-29-managed-http-peer-loss/independent-review.md), followed by [bulk discovery's preserved unknown outcome](../2026-10-29-mcp-discovery-outcome/index.md) and [independent repair review](../2026-10-29-mcp-discovery-outcome/independent-review.md); explicit-allow nested effects and bulk discovery have distinct scopes.
- [Retained native close infrastructure and review](../2026-10-29-native-shared-lease/retained-close-independent-review.md), followed by [Session lock-sharing candidate](../2026-10-29-native-shared-lease/session-share-candidate.md) and [independent review](../2026-10-29-native-shared-lease/session-share-candidate-independent-review.md), [owner-control primitive review](../2026-10-29-native-shared-lease/owner-controls-independent-review.md) and [private Session/Host caller wiring review](../2026-10-29-native-shared-lease/session-control-wiring-independent-review.md); production consumers and actual tty/all-copy closure remain separate requirements.
- [Measured metadata geometry failure](shared-metadata-geometry.md), [explicit shared-directory v2 design](shared-directory-v2-design.md), [complete metadata sizing](shared-directory-v2-sizing.md) and [independent design review](shared-directory-v2-design-independent-review.md); v1 remains unchanged while the paged v2 implementation is qualified. The [document maintenance and migration proposal](document-collection-maintenance-design.md) and [independent review](document-collection-maintenance-design-independent-review.md) identify checkpoint/floor, physical export and operation-budget issues that must be resolved before destructive implementation.
- [Reviewed forgetting restoration direction](reviewed-forget-restoration-direction.md), [exact local management-display scope](management-display-scope.md) and its [independent review](management-display-scope-independent-review.md), with the [guarded terminal integration design and review](../2026-10-29-native-shared-lease/guarded-terminal-integration-independent-review.md); these are implementation contracts, not an enabled sink or management journey.
- [Original expiry requirements and publication decisions](expiry-requirements-audit.md), [reviewed State restoration design](state-deadline-restoration-design.md), [native-owned State backend](state-native-owner.md) and its [independent review](state-native-owner-independent-review.md), followed by [actual State/Memory restoration controls](state-restoration.md) and [integration review](state-restoration-independent-review.md). The original final locked decision does not promise physical syscall completion before expiry; other gated paths require separate disposition.
- [Scoped document-stage restoration design](document-decision-restoration-design.md), [independent scope review](document-decision-restoration-independent-review.md), [implementation controls](document-decision-restoration.md) and [implementation review](document-decision-restoration-implementation-review.md); ordinary document deadline decisions are separate from managed document effects and the later narrow notes restoration linked above.
- [Shared generation directory and selected hydration/controller](shared-generation-controller-read.md), [canonical citation-origin repair](shared-citation-origin-canonical.md), [job prerequisite repair](shared-job-prerequisites.md), [independent checkpoint review](shared-generation-controller-read-independent-review.md), [streamed finalization](shared-generation-finalization.md) and its [independent review](shared-generation-finalization-independent-review.md), followed by [small native/public finalization](shared-finalization-native.md) and [its review](shared-finalization-native-independent-review.md); complete acquisition/build, cleanup, migration and populated capacity remain separate requirements.
- [Native-owned journal append/repair](../2026-10-29-native-shared-lease/native-journal-owner.md) and [independent review](../2026-10-29-native-shared-lease/native-journal-owner-independent-review.md), with the [stronger CLI cleanup caller](../2026-10-29-native-shared-lease/release-receipt-integration-independent-review.md#subsequent-cli-caller-repair) and [actual live-MCP planning resources](planning-live-mcp-resources.md).
- [Saved activation matching versus unavailable capture](knowledge-readiness.md), with [independent source/receipt review](knowledge-readiness-independent-review.md); genuine native permission/status control, no positive capture qualification.
- [Optional private synthetic-candidate audit and public-progress leak repair](pilot-candidate-audit.md), with [independent review](pilot-candidate-audit-independent-review.md); no new live model run or semantic qualification.
- [Current literal-v4 source-union upgrade control](literal-v4-source-union.md), including the preserved stale-runtime cohort error and verified current prerequisite refusal.
- [Strict publication-deadline race and containment](strict-deadline-interposition.md), [Review/State lifetime follow-up](strict-gate-lifetime-followup.md) and [current receipt-test reconciliation](lifetime-receipt-test-reconciliation.md); earlier positive write cohorts do not override these gates.
- [Shared projection codec](shared-projection-codec.md), its [independent review](shared-projection-codec-independent-review.md), [canonical fact repair](shared-projection-canonical-fact.md) and [independent repair review](shared-projection-canonical-independent-review.md); publication and complete populated capacity remain open.
- [Native lock-owned fresh headers and framed close](../2026-10-29-native-shared-lease/session-header-native.md), with [pure signed release claims](../2026-10-29-native-shared-lease/release-receipt-contract.md) and their [v6 independent review](../2026-10-29-native-shared-lease/release-receipt-v6-independent-review.md); production receipt integration remains open.
- [Host-owned contracts and package mapping](contracts.md).
- [Storage/parser evaluation and selected implementation direction](selection.md).
- [Qualification protocol and provisional workloads](qualification.md).
- [Independent fresh-user journeys](journeys.md), prepared but not executed by a person.
- [Independent frozen qualification inputs and private-answer provenance](independent-data.md).
- [Incremental adversarial foundation audit and repairs](foundation-audit.md).
- [Internal protected control ledger audit and repairs](control-audit.md).
- [Control compaction, maintenance headroom and boundary repair](control-compaction.md).
- [Actual-owner transactions and protected project identity](transaction-identity-component.md).
- [Serialized migration retry and owned staging inventory recovery](sol-recovery.md).
- [Actual journal-origin binding and legacy publication refusal](sol-source-origin.md).
- [Native statement/category review and pending treatment of plain messages](native-assertion.md).
- [Original-source validation in protected managed reads](current-source-read.md).
- [Host-owned read receipts and complete invocation read unions](managed-read-receipts.md).
- [Final observation expiry checks and bounded historical preflight](managed-use-preflight.md).
- [Actual owned native send, verified TLS cleanup and final inference-result release](owned-send-integration.md).
- [Standalone reviewed forgetting, management reservations and nonreplaying inspection](managed-forget.md).
- [Typed native retention and authenticated current metadata](../2026-10-28-managed-retention/index.md), with [actual standalone CLI choices and their final-switch deadline gap](retention-cli.md).
- [Native final-switch retention deadline repair and actual delayed-publication controls](../2026-10-28-retention-publication-deadline/index.md).
- [Explicit expired-literal reclamation through the actual standalone owner](expiry-cli.md).
- [Direct worker-result authority, causal replay and final deadline controls](managed-output-integration.md), with [independent-review cleanup repairs](managed-output-cleanup-correction.md).
- [Automatic turn-local recall, source withdrawal and actual native request controls](recall-integration.md).
- [Exact available-kernel tmpfs production-profile qualification and explicit Btrfs refusal](../2026-10-28-native-profile/index.md).
- [Original-source lock reserve and focused capacity and owner-loss controls](../2026-10-28-source-lock-reserve/index.md).
- [Pinned trust-bearing locks and legacy managed-namespace isolation](source-lock-namespace.md), with focused substitution and transition controls.
- [Managed MCP start, request and refusal controls](managed-mcp-integration.md), with peer-loss and full integration still open.
- [Managed shell admission and terminal unknown-cleanup recovery controls](native-shell-unknown-cleanup.md), including retained failures and distinct native cohorts.
- [Independent P30C coverage-gap pure-policy audit](p30c-coverage-independent-audit.md), without a qualified host consumer.
- [Native-reviewed correction and temporal supersession component](../2026-10-28-managed-supersession/index.md), with full Session qualification still open.
- [Session supersession integration and terminal-reader handoff controls](../2026-10-28-managed-supersession-session/index.md), with the earlier conflict retained.
- [Independent signed-choice compaction repair review](../2026-10-28-managed-supersession-session/compaction-repair-independent-review.md), scoped to the recorded source and page-level compatibility.
- [Authenticated history observation and expired-history reclamation controls](../2026-10-28-managed-history/index.md), without a worker-use or Session authority grant.
- [Actual 4,000-publication available-host capacity and complete retained receipt reconciliation](capacity-available-host.md).
- [Supplied Word bytes through extraction, CAS storage and typed citations](word-source-bridge.md).
- [Packaged lexical document setup and source-runtime native journeys](documents-setup-20261031.md).
- [Read-only local model identity and reported-context inspection](local-model-inspection-20261031.md).
- [Native operator inference reconciliation](inference-reconciliation-cli-20261031.md).
- [Explicit domain embedding-query formatting](query-prefix-20261031.md).
- [Extracted-package document setup, cited retrieval, resume/disable and refusal controls](documents-setup-installed-20261031.md).
- [Opt-in native workspace Word acquisition and actual Session controls](word-workspace-acquisition.md).
- [Hash-bound paged acquisition and explicit staged Word text](word-staged-acquisition.md).
- [Paged Word locator manifests and authenticated selective hydration](word-locator-manifest.md).
- [Document storage profile, protected staged blocks and legacy draft expiry repairs](document-store-boundary.md).
- [Internal document maintenance epoch, native admission fence and stale-stage refusal](document-maintenance-epoch-20261105.md).
- [Document Source and lexical Index continuation epoch conditions](document-continuation-epoch-20261106.md), with focused native/Session and explicit retirement controls; general maintenance and GC remain open.
- [Shared-generation Job epoch fencing](shared-job-epoch-20261106.md) adds durable predecessor checks and explicit partial retirement; five ordinary Session controls pass. Producer egress and other controllers remain separate.
- [Producer egress epoch fencing](producer-egress-epoch-20261106.md) joins the live claim and stored Job to the held reader's current idle epoch. Synthetic staged/inline, fresh-Job and in-flight controls pass; wider producer and capacity qualification remain open.
- [Document progress provenance gap](document-progress-provenance-gap-20261106.md) preserves the Source counter-plus-digest rewrite trace. The [native progress increment](document-native-progress-20261106.md) adds bounded native heads, real reuse, epoch/owner/unit joins, capacity reservations and native/Session fault controls; broader producer, GC, migration and populated qualification remain open.
- [Same-owner document draft abort](document-draft-abort-20261106.md) exposes bounded Source/Projection stage retirement with ordinary approvals, exact native receipts and frozen cleanup epochs. Published values remain; the failed public-dispatch cohort and later passing repair are retained separately.
- [Packed document adapter, paged catalog and selected-source Session controls](document-store-adapter.md), with [public Corpus Collection routes](corpus-collection-documents.md), [lossless per-source lexical runs](source-lexical-runs.md) and [namespace lexical indexing](namespace-lexical-index.md); full populated capacity qualification remains open.
- [Versioned Collection chunking with legacy-reader and citation controls](collection-chunking.md); populated capacity still requires further storage and projection work.
- [Private project-domain keys, namespace preparation and bounded page authenticators](project-domain-auth-component.md), with its [independent public-API and native adversarial audit](project-domain-auth-audit.md).
- [Native operator-channel incremental audit and fixture repairs](operator-channel-audit.md).
- [Source-bound guarded native review display and focused PTY controls](guarded-review.md).
- [Fresh native review, one-use host permits and repaired deadline/owner races](native-review-component.md), with its [independent audit and source-bound closure](native-review-audit.md).
- [Session input witness audit and source-boundary repairs](session-input-audit.md).
- [Versioned reference projection audit and replay repairs](reference-audit.md).
- [Sustainable collection storage component and measurement provenance](storage-component.md).
- [Actual 30/90-day primitive turnover and bounded annual continuation controls](storage-workload-endurance.md).
- [Annual storage segment 1: incomplete, unknown termination cause and retained read-only evidence](storage-annual-s1-incomplete.md).
- [First 1,000 actual managed publications, packed metadata and version-5 allocation evidence](managed-storage-capacity.md).
- [Bounded actual continuation: 2,000 established, 4,000 refused at a full live-metadata shard](managed-storage-continuation.md).
- [Pure fence-leaf metadata codec: lossless roundtrips, bounded churn and an annual JSON no-fit result](managed-metadata-proof.md).
- [Separate binary metadata proof: conditional measured size, retained failure controls and open lifecycle/authenticity gates](managed-binary-metadata-proof.md).
- [Adaptive pure codec and local leaf proof, package comparison and retained capacity misses](managed-adaptive-metadata-proof.md), with its [independent Stage 1 audit](managed-adaptive-independent-audit.md).
- [Host-private authenticated managed-page codec and bounded local repair](managed-pages-component.md), with its [independent codec/planner audit](managed-pages-independent-audit.md).
- [Explicit Core-v3 normalization envelope and actual native controls](managed-v3-core-component.md), with its [independent envelope audit](managed-v3-core-audit.md).
- [Restricted authenticated automatic NormalizerV3 and separately bound actual Collection integration](managed-normalizer-v3-component.md), with its [independent interpreter audit](managed-normalizer-v3-audit.md) and [exact results](managed-normalizer-v3-results.json).
- [Frozen full baseline: 2,474 passed, retained stopped dev-BEAM predecessor and exact revision scope](full-baseline-checkpoint.md).
- [Interrupted SDK verification and native-profile refusal after the host kernel changed to 7.2.11](kernel-profile-recovery.md).
- [Declarative collection publication constraints](collection-policy-component.md).
- [Native knowledge capture and precompiled artifact component](native-capture-component.md).
- [Native artifact integration with managed recipes and actual PTY publication](native-managed-capture-component.md).
- [Inert operator-sidecar schemas and declared data inspection](operator-sidecar-component.md).
- [Independent capture/SDK audit and anchored-retention repair](capture-sdk-audit.md).
- [Protected collection SDK, source proofs and replay bindings](collection-sdk-component.md).
- [Pure managed-reference lineage, projection contracts and verification](managed-reference-component.md).
- [Explicit absent/present roots and record/absence subjects in pure managed dependencies v2](managed-reference-v2-component.md), with its [independent adversarial audit](managed-reference-v2-audit.md).
- [Strict raw root observations in pure managed dependencies v3](managed-reference-v3-component.md); Session integration remains open.
- [Same-view collection observation foundation and scoped independent evidence](same-view-observation-component.md); Session lineage and current authority remain open.
- [Pure managed policy recipes, deduplicated grants and activation data](managed-policy-component.md).
- [Atomic managed publication and explicit version-5 receipt binding](managed-collection-component.md).
- [Owner-task Collection read views and protected root revalidation](collection-read-view-component.md), with its [independent adversarial audit](collection-read-view-audit.md).
- [Native-confirmed empty/present read-view v2 and complete Collection regression evidence](collection-empty-read-view-component.md), with its [independent audit](collection-empty-read-view-audit.md).
- [Native-confirmed directory neighbors and shared observation limits](collection-neighbors-component.md), with its [independent adversarial audit](collection-neighbors-audit.md).
- [Native root witnesses and owner-bound directory reads inside managed publication](managed-directory-closure-component.md).
- [Managed source clocks, metadata and independently closed findings](managed-normalizer-component.md).
- [Registered inference admission and completion](inference-dispatch-component.md), with its [independent adversarial audit](inference-dispatch-audit.md).
- [Authentication HTTP isolation in the registered inference completion witness](auth-completion-witness.md).
- [Unused controlled owned-effect foundation, scoped verification and open integration limits](owned-effect-component.md).
- [Private draft-mode prototype checkpoint and open acceptance gaps](p31i-private-draft-checkpoint.md).
- [Deferred operator-authored planning decisions](operator-planning-20261103/index.md) records a witnessed acceptance and separate post-exit save, with synthetic native and replay controls; assistant-proposal acceptance remains open.
- [Main-Session `/enhance` integration, terminal repairs and current verification limits](enhance-integration.md).
- [Model-switch continuation, active full suite and unresolved installed proof](handoff-20261027-enhance.md).
- [Explicit managed SDK publication, reserved metadata and replay boundary](managed-sdk-component.md).
- [Verified managed-publication input charges, unchanged reservations and retained uncertainty](managed-actual-accounting.md), with its [independent audit](managed-actual-accounting-audit.md), later [Identity-finalization finding and independent closure](identity-finalization-finding.md), and [deferred-settlement ordering repair](managed-settlement-ordering-repair.md).
- [Protected fresh/resumed activation, exact route overlays and reciprocal worktree admission](activation-overlay-component.md).
- [Independent activation overlay audit and original pending-reclamation finding](activation-overlay-audit.md).
- [Accepted inspection-reclamation finding, existing-only reader repair and frozen replay evidence](activation-readonly-repair.md).
- [Independent reader repair audit and additional ancillary writer finding](activation-readonly-audit.md).
- [Ancillary writer-lock noncreation repair and unchanged independent probe](activation-writer-repair.md).
- [Independent writer repair closure, preserved exploits and fresh controls](activation-writer-audit.md).
- [Standalone native knowledge review, actual PTY/headless controls and frozen CLI graph](native-knowledge-cli-component.md).
- [Independent native CLI audit and original saved-configuration finding](native-knowledge-cli-audit.md), its [repair](native-knowledge-cli-config-repair.md) and [independent closure](native-knowledge-cli-config-audit.md).
- [Native read ownership and staging-frame ordering](native-read-component.md).
- [Versioned optional native reads and exact missing-file refusal boundaries](native-optional-read-component.md).
- [Buffered-frame transaction repair, original adversarial failures and source-bound closure checks](native-framing-repair.md).
- [Independent native framing closure and preserved diagnostic-only companion](native-framing-audit.md).
- [Admitted decision operation, incremental review and controls](decision-operation-audit.md).
- [Pure decision planners, zero-call controls and independent public-SDK artifact closure](p30c-pure-policy.md), with [independent audit and the preserved test-count correction](p30c-pure-policy-audit.md).
- [Optional document parser, bounded staging and package evidence](document-parsers.md).
- [Fixed-revision source and platform verification receipts](verification.md).
- [Question fixture repair, unchanged-runtime reproduction and exact replay refusals](questions-fixture-repair.md).
- [Reference-aware fixture repair and preserved 44-failure baseline](reference-fixture-repair.md), with its [scoped independent review](reference-fixture-audit.md).
- [Complete repeat with one preserved CLI timeout](reference-fixture-full-repeat.md), its [independently reproduced prompt-ordering defect and narrow fixture repair](cli-pty-fixture-audit.md).
- [Nonpublishing interaction model](../../../dev/knowledge/interaction.exs) and
  [boundary tests](../../../test/dev/knowledge/interaction_test.exs).
- [Finite main-route pilot](../../../dev/knowledge/pilot.exs),
  [explicit runner](../../../dev/pilot-knowledge.exs) and
  [dispatch/cap tests](../../../test/dev/knowledge/pilot_test.exs).

The interaction model exercises next-session activation, explicit displayed
acceptance, stale/cross-client/expired/disabled refusal, original-source provenance,
multiple pending cards, draft replacement, one-use consumption and cancellation.
Its terminal-origin proof is explicitly **simulated**. Passing it establishes a
contract observation, not real terminal attestation or model adherence. It performs
no filesystem publication, model call or task effect.

The pilot uses three 20-turn exposed synthetic sessions on the configured main
route. It declares only the fake capture tool, validates source quotes, returns
nonpublishing receipts, and allows at most one continuation per turn (120 requests
total). It refuses configured shared budgets because direct provider calls cannot
enforce them. It neither selects an alternate route nor caps the unsupported
subscription output-token field. Input/response bytes and provider deadline remain
bounded. Request failures stop the pilot. Missing visible text has null TTFT.

Initial focused verification: `mix test test/dev/knowledge` passed **11 tests**;
the subsequent baseline-preservation test brought that directory to **12 tests**.
After protocol and audit repairs, the combined decision/probe suite passes **35
tests**. The credential-free demo, formatting, strict compilation and documentation
checker passed. The full pre-repair suite passed 1,794 tests with 36 exclusions;
full post-repair verification remains separately recorded.
Mix required loopback permission in this execution environment; TLS/tests were not
weakened. Full source, native, package, model-quality and human checks are separate
gates and have not been inferred from these tests.

### First actual main-route pilot

The [sanitized measured receipt](chatgpt-pilot.json) retains exact probe/data hashes,
per-request numerical metrics and first outcomes, without model text, attribution
IDs, credentials or transcript dumps. The run completed **60 turns, 102 requests,
42 capture continuations and 42 proposed items**, all with uniquely matching source
quotes. It published **zero** records. This consumes **102/300** authorized
subscription calls; **198 remain**. Local calls/download consumption remains zero.

The exposed pilot flagged concrete concerns: all items were assigned persistent
(30) or temporal (12), with **no automatic category**; all three uncertain-statement
cases proposed an item, and repeated facts proposed duplicates. Do not call that
semantic success. The receipt contains counts/size/category rather than generated
claim text, so independent entailment/usefulness assessment is unavailable for this
run. Before integrated qualification, add a private, explicitly retained synthetic
candidate audit record and independent labels; never infer 42 useful unique facts
from 42 exact quotes. No workload ratification follows from this pilot alone.

Request duration p50/p95 was **4.12/6.28 seconds**; first-visible-text p50/p95 was
**2.47/4.36 seconds** over 60 requests. The other 42 requests were tool-only with
null TTFT. These are request-level observations, not user-to-answer timing,
paired knowledge-on/off overhead or cache-isolation evidence. No invoice cost is
inferred for subscription calls. The 20-item/day useful-intake floor and capacity
mix remain provisional pending independently assessed integrated sessions.

- [Combined chat and ordinary-expiry audit](chat-expiry-audit-20261104.md) records an independent read-only review of the exact integrated source packet and live-mode delta, with a 20-file manifest and independent pure recall controls. No concrete blocker was found; final combined native/full-suite qualification remains separate.

## Open readiness items

Pilot usefulness labels are development-authored, not independent held-out labels.
The 2,000-note/20-items-per-day floor remains provisional until useful intake and
class mix are independently assessed. P31B/C0 may proceed from frozen structural
contracts, but C1a/E cannot claim final workload or semantic acceptance from this
prototype. Real verified terminal input, host context projection, consent,
sustainable storage and capture are not implemented by the development model.

Recruitment is an explicit open item: the developer requested prepared journeys,
not a claim that a tester exists. Mac automated/human evidence and P30 live-engine
access remain distinct open items. Record every later qualification at its actual
source revision rather than updating historical success claims.
