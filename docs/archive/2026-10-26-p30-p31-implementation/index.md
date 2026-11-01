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
settled service reservations and valid idle resume. Local usage is now 4 of 1,000,
996 remaining. Download success establishes neither quality
nor resource/offline qualification. No daemon configuration or existing model was changed.

## P31A contracts and evidence

- [Nested native/MCP result continuation](nested-result-input-20261101.md) replaces the redundant result gate only for pinned exports using the actual managed input fence. Explicit-allow positives and post-effect root/revocation controls retain known effects, uncertain delivery and inert recovery; document and other unqualified purposes stay gated.
- [Unsupported private Worker input refusals](private-worker-input-refusals-20261101.md) preserve ordinary and metadata delivery while closing managed presentation, notification, tool-feed and selected text entry; required registered text retains its original producer and acknowledgment checks.
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
- [Current local follow-up](current-local-followup-20261031.md) records the integrated build/demo, 99 focused regressions, 79 P30 checks and fresh current-runtime two-source decision controls, with an exact runtime/test manifest.
- [Bounded DOCX table styles](docx-table-style-20261031.md) records the reproduced nonhidden-style refusal, reuse of the existing style graph, recipe v12 and source/separate-artifact refusal controls; full Word fidelity remains open.
- [Matching alternate DOCX style graphs](docx-matching-effects-20261031.md) records original public Word fixtures, recipe v13's exact graph agreement, native acquisition and separate source/installed artifact checks; differing graphs still refuse and rendered-Word fidelity remains open.
- [Broader Word ingestion investigation](word-ingestion-gap-20261031.md) separates format/version evidence from parser compatibility and reproduces the many-paragraph source-transfer refusal; complete bounded acquisition is the next Word implementation target.
- [V14 block packing](word-block-packing-20261031.md) implements the mixed paragraph/table geometry without raising limits and records actual original-file acquisition, both native storage profiles and independent installed-artifact citation checks.
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
