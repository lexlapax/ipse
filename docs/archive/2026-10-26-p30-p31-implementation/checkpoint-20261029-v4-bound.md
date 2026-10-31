# Resume checkpoint: v4 source-bound geometry — 2026-10-29

This advances the [previous checkpoint](checkpoint-20261029-v4-public-resume.md);
the [plan](../../plan.md) owns full P30/P31 scope. All commands from this
continuation are terminal. Preserve the extensive dirty worktree, all retained
stores and failed evidence; never replay unknown effects or stage everything.

The [selected-root model](shared-producer-v4-selected-reuse.md) found and fixed
an immutable-page reuse response mismatch after inference. The later
[source-bound geometry work](shared-producer-v4-bound-geometry.md) records the
read-budget failure, its cache/revision-bound reader changes and provisional
append reservation, plus current model and native controls. Its exact source,
artifact and 90-row manifest are frozen. The 256-chunk synthetic append used
up to 509 of 512 reads across 37 invocations. A fresh actual two-page Session
passed on artifact `fd1be1c6d6f4354a1f90b7fe42322c83782f6992f251054d7fab3ced852c70a9`;
it does not establish native group append, populated-root reuse or capacity.

Next, review the provisional append reservation against every token and
worst-case page/fact/stage geometry, and verify the new source-head and
revision-bound read paths under actual concurrent mutation/owner-loss controls.
Do not assume the 16-read overhead or one-fact model is a universal proof.
The 37 expensive invocations also require measured stage-free Session handoffs
and journal limits. A model extractor may return no facts, while the current
group codec requires one per source; text inference has no equivalent of the
embedding source guard. Design and implement those missing contracts, not a
fabricated fact or an unguarded call. Independent review, full source
acquisition and native populated selection, GC/migration, end-to-end capacity,
quality, P30 integration, baseline/package checks, adversarial audit and
reviewer handoff remain open. No live model/account call or quota change ran.

Later [pinned anchor reads](shared-producer-v4-pinned-read.md) retain the original
generation and raise the provisional control-read reservation to 24. The same
wide one-fact model completed at 506 maximum reads; a 32-fact-per-source model
reached only its first known continuation. A fresh native two-page run passed on
artifact `ff8273cef5d12713308336fd18e5a4c5b54affb4fe69a335d79ce25277bae02b`.
Its 77-row evidence manifest is frozen. All handles are terminal. The same
remaining review, race, full-fact, handoff and completion gates apply.

Subsequent [native stale-read controls](pinned-native-stale.md) passed at the
DocumentStage boundary after intervening commits; Session owner loss remains
unqualified. A [256-fact private model](shared-producer-v4-full-facts.md)
completed over 37 invocations at 506 maximum reads. A later
[batched citation-validation change](shared-producer-v4-batched-spans.md)
passed its focused, source and artifact checks and the same full model. Its
single callback timing sample was 3.35 seconds, not a production deadline proof.
The Word-ingestion source loader was repaired after exposing missing Collection
modules. All these handles are terminal; the new dense artifact has not had a
fresh native Session run. Full escaped-fact geometry, read reservation proof,
native append/owner loss, stage-free Session handoffs and the broader goal remain.

The [packed-shape diagnosis](shared-producer-v4-packed-shape.md) found an
escaped fact page exceeding its native wrapper limit; packing now splits using
the physical bound. Its full escaped group initially refused four reads short.
[Split append metadata staging](shared-producer-v4-split-append.md) then passed
the synthetic 256-chunk/256-wide-fact group across 44 invocations, at 463
maximum reads, and a small direct native atomic-switch control. A fresh
two-page Session passed on artifact
`6dee1907b46aa2bc83c73044a927231f8f6bc4828e8cd90b73879f42545da18d`.
The new stages are same-Session continuations, not handoff points. All handles
are terminal. Review the reservation and staging changes independently; native
large-group, interruption/owner loss, public fact production, real Session
handoffs and the full P30/P31 gates remain open.

The subsequent [final root fence](shared-producer-v4-final-root-fence.md) checks
the captured selected root at the final append generation after stage inspection.
A protocol control and a direct native interposition refuse a root change before
commit, retaining both stages; an independent fresh native append succeeds.
The full escaped synthetic group passes at 464 maximum reads over 44 append
invocations. Its dense artifact has no new public native Session run after this
fence. The 76-row evidence manifest is frozen; all handles are terminal. Source
authority for facts, native wide append/owner loss, stage-free handoff, independent
audit, full baseline and the rest of the objective remain open.

The working source now represents explicitly supplied empty fact sets through
group packing, both directory reductions and selected reads. A synthetic model
control covers all-empty and mixed groups, both directory formats, missing source
entries and rejection of empty `model_complete` input without a completion
receipt; the nonempty append, selected-root reuse and packed-page controls also
passed. This is private model evidence, not a public extraction or native
qualification. The earlier statement that every group requires facts is now
superseded for explicit inputs only. A trustworthy model-completion binding,
guarded source egress and public fact production remain open, as do the other
qualification and full-objective gates above.

A subsequent current-source direct `DocumentStage` control completed explicit
empty append, paged finalization and selected hydration against native storage.
Its synthetic store is retained at
`/tmp/ipse-split-append-c238bc99f183a8d441401049b6de7434`; this does not test a
Session, guarded model extraction or live service. A separate protocol-model
control merges an empty first group with a populated second group and reads
both. Text `model.complete` currently has no document source-guard binding;
embedding's fixed claim and one-use host admission cannot simply be reused for
text without authenticating the text recipe, inputs and completion. Those
design and implementation gates remain open.

An additional pure reduction control covers 17 groups in two manifest batches:
all facts empty, the first entity run empty, and the second run empty, each for
both directory versions. It compares each result with the canonical directory,
including selected entity rows, manifests and head commitments. The focused
wrapper passed; this is not a Session, native capacity or model-extraction test.

The model extraction adapter now rejects supplied chunks whose complete canonical
records do not belong to the supplied source, including altered text, offsets and
duplicate chunks, before it creates a host call. The independent-VM package suite
passed with authentic large and escaped source fixtures. This is an extension-side
input consistency check only: it does not authenticate a current Collection
snapshot after approval, prove model completion, or enable public fact production.

The private extraction adapter now accepts explicit UTF-8-safe windows of up to
2048 bytes inside a canonical Collection chunk, preserving the whole chunk's
identity and absolute citation offsets. It still checks quote uniqueness across
the whole chunk and labels each window as incomplete source coverage. The
independent-VM package suite passed positive, malformed-boundary and ambiguous
quote controls. This does not yet schedule windows, guarantee boundary-spanning
recall, bind host egress, or expose a public producer. Escaped JSON may require
smaller windows than the raw-byte maximum.

The private adapter now plans overlapping windows for one canonical chunk with
a conservative 3000-byte encoded-input budget. Its result records the maximum
quote length guaranteed to fit wholly in a window, capped at 1024 bytes. The
independent-VM package suite exercised both host request versions with ASCII,
escaped quotes, control characters and UTF-8, checking bounds and overlap. This
planner does not execute requests, aggregate facts, establish completion or
source authority, or qualify capacity and quality.

A current-source adversarial control then exposed a Host range-authentication
gap: a pending embedding claim could shorten a real chunk and recompute all its
range and input hashes, and the old checker accepted it. The reproduced case
still used bytes from the authenticated source; it did not demonstrate foreign
byte egress. The candidate Host repair derives the exact UTF-8 chunk ranges,
including document segment boundaries, from the authenticated bundle and
requires the claimed ordinal and range to match. The focused source-use suite
passed 11 tests, including reverse-order and segmented fixtures and the new
counterexample; the separate Session embedding suite passed 10 tests. Both ran
with the current Host module loaded over the existing local build. Full native
interposition, wide-source timing, frozen artifact review and the baseline remain
open. This embedding repair does not implement guarded text extraction.

The same candidate subsequently refused a self-consistent shortened claim
committed to native storage and read under the retained document owner; the
positive original claim also passed there. A synthetic in-memory producer test
accepted the first batch of eight version-4-manifest Word sources with 256 total
segments: 29 logical reads and 581,824 assembled bundle bytes, in one 48.5 ms
sample. This timing excludes native I/O and is not a deadline guarantee. The
native control is not an actual Session inference interposition; independent
review and the other qualification gates remain open.

An isolated Host graph copied from `document-inline-v4-complete-sol-20261029`
with the current `DocumentSourceUse` compiled over it, and a freshly built
current Collection artifact, passed the actual public two-page Session control
against a loopback synthetic provider. It retained an empty old selection and a
1,494-event, 4,586,499-byte synthetic journal. The artifact digest was
`d7e89605e80e705c4dc56f483e0042f1ee5a0f7c5c36c4d7bdd890255dbea1fc` and the
overlaid Host BEAM hash was
`a20a770621370b5343e3708e503babf94c9395f12bce4ffee6a0ab39d1f4b329`.
The first launch failed before Session startup because its standalone runner had
not started the application; its fresh home is retained. The successful run used
a separate home. Evidence is under `_build/document-canonical-range-session-20261029`.
This positive Session test does not interpose the forged claim during dispatch,
and the Host graph is not a full current-source build. Full audit, fact egress,
producer progression and the broader objective remain open.

The full current Host source compiled with `mix compile --force
--warnings-as-errors` in `_build/p30-p31-current-baseline-20261029`; dependency
warnings were emitted, but the Ipse compilation succeeded. Repository-wide
format checking reported four unformatted pre-existing files. A full `mix test`
run was started in `_build/p30-p31-current-test-20261029`; its log is
`/tmp/ipse-p30-p31-current-suite-20261029.log`. It used the existing stale
`priv/ipse-runner` (SHA-256 `891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`),
while a separate fresh compilation at `/tmp/ipse-p30-p31-current-runner-20261029`
has SHA-256 `40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
The run has multiple failures, including missing test-module loading and native
helper incompatibility; it is not a valid full-build qualification. Its process
was still live as exec session `31634` when this note was written. Poll that same
handle and preserve its log before considering a fresh, correctly built run.

An isolated `/tmp/ipse-current-baseline-snapshot-20261029` copy then completed
`./dev/build.sh`, including the fresh native helper and bundled artifact, without
replacing the workspace's generated binaries. The compact generation-progress
test independently reproduced missing knowledge modules in this clean build.
Its three original checks now run in an isolated VM with an explicit module
compile, avoiding accidental dependence on test order. With that test-only
overlay, the clean snapshot passed 22 focused source-use, Session embedding and
compact-progress tests. The original full-suite handle remained live; neither
that run nor these focused tests establishes the full baseline.

The clean build also reproduced two managed-workload test failures. The synthetic
interactive observation is currently a pending proposal, but the workload had
selected the direct-note policy. It now selects the contract from the actual
record key, and its report identifies the publication kind. Four focused tests
pass. A first native one-operation fixture committed its pending record but its
terminal verifier failed because it recognized only notes; that original store
and failure remain under `/tmp/ipse-managed-workload-current-20261029`. After
adding pending-record verification, a separate fresh fixture committed and
verified one pending record plus its anchor and live metadata. Its report is
under `/tmp/ipse-managed-workload-current-20261029-retry`. This is synthetic
capacity tooling, not a human, consent, Session, model or capacity qualification.
The earlier full-suite handle was still live at this checkpoint.

The clean snapshot also reproduced 11 failures in the older normalizer suite.
Its literal-note fixtures used interactive-input proofs that now produce pending
proposals under the current contract. The synthetic fixtures now use shaped
native-assertion proofs for literal cases and retain interactive-input proofs
for proposals; they attest no terminal input. All 14 focused normalizer tests,
including the existing native storage control, passed in the isolated build.
This is a fixture alignment, not evidence of an operator journey or a change to
the production authorization policy. The stale-helper full suite remains live.

A separate full suite started in the freshly built snapshot with `--max-cases 2`
and log `/tmp/ipse-p30-p31-clean-suite-20261029.log`; its exec session is
`18104`. The first four failures reflected a bootstrap compile order, two stale
knowledge-contract expectations and a retention refusal-code expectation. The
workspace now loads Contracts before Records in the affected development loaders,
and the tests reflect the actual direct-source categories and closed retention
gate. The targeted bootstrap and five contract/management tests passed. The
running snapshot predates those repairs, so retain its output and do not treat
its result as a test of the repaired files. The original stale-helper run is
also still live as session `31634`.

The next two clean-suite failures were caused by the isolated snapshot omitting
`.github/workflows`; after those files were copied into it, all 14 focused
release-configuration tests passed. The credential-free demo also passed from
that build in a separate temporary home, using the installed Mix archive; its
first launch stopped before startup because the empty home lacked Hex. The demo
wrote its expected fixture file in the snapshot while the suite was running.
These mid-run snapshot changes limit that suite's value as a fixed-source
baseline. Both original suite handles were still live at this checkpoint.

A separate recall regression reproduced a zero-budget failure: the Knowledge
worker proposed index and coverage framing even when the host offered no context
bytes. The worker now publishes an empty contribution with partial coverage if
the complete framing cannot fit. Its isolated worker suite passed seven cases,
including zero, one and 128-byte limits. This is not an actual low-budget Session
or broader recall-quality qualification. Both full-suite handles remain live.

The same seven-case recall worker suite subsequently passed both from source and
from a freshly built `knowledge/native` artifact. The artifact-mode loader checks
each Knowledge module's actual BEAM origin; it does not exercise Session context
admission. The artifact is retained under `_build/knowledge-recall-budget-20261029`.

The clean suite exposed a startup ordering defect: release-owner startup repaired
the journal and appended its marker before budget-source validation, so a refused
resume could alter a torn journal. A resumed Session now performs source and
budget validation before release-owner startup and tail repair. The full budget and
release-receipt suites passed 37 tests in a fresh isolated build; native Session
header, loss and journal-fencing controls passed 14 with 12 skipped. A valid idle
resume does append a new owner marker, and the budget tests and demo now verify
that marker while preserving the previous journal prefix. This candidate still
needs focused adversarial review of the changed startup/loss ordering and a full
fixed-source baseline. Both earlier full-suite handles remain live.

Follow-up review found that the first ordering change also moved fresh-session
budget-ledger creation ahead of the release-owner marker. The candidate now
distinguishes fresh startup from resume: fresh startup records its owner before
budget initialization, while resume validates existing budget evidence before
journal mutation. A fresh-start refusal control verifies the marker exists when
budget initialization fails. The full budget/release suites passed 38 tests;
the native Session and journal controls passed 14 with 12 skipped on this host.
The skipped interposition controls and independent startup-loss review remain
open; this is not full P30/P31 qualification.

The original stale-helper full-suite process `31634` subsequently terminated
with exit status 2: 2,049 of 3,386 passed, 1,337 failed, 64 were invalid, 53
skipped and 55 excluded, after 1,393.9 seconds. Its log is retained at
`/tmp/ipse-p30-p31-current-suite-20261029.log`. Many failures reported the old
helper's usage message; other failures need separate diagnosis and cannot all be
attributed to that mismatch. The rebuilt-snapshot suite `18104` was still live
when last polled and predates the later startup and test-fixture repairs.

An additional synthetic owner-loss control holds the budget lock, kills a
resuming Session after its Session lock owner appears, and checks that the torn
journal remains unchanged until a later explicit resume. That resume succeeds
without replaying inference. The full budget and release-receipt suites passed
39 tests in the isolated build. The control does not instrument the exact point
inside budget validation or cover the skipped native interposition cases.

The owner-loss control was then tightened to observe the tracked file peer in
budget-lock acquisition before killing the Session. It verifies that the
Session lock remains unavailable while that peer is alive, waits for both peer
and lock owner to exit, and checks the journal before explicit recovery. The full
budget and release-receipt suites again passed 39 tests. This uses the actual
native lock with a synthetic fixture; it does not cover the separate skipped
header interposition cases or every startup-loss boundary.

The rebuilt-snapshot full suite later exposed additional failures, including
synthetic Rust test harnesses that omitted the transaction module's lease-transfer
dependency. The repaired project-identity harness passed 21 tests; the transaction
and project-authorization harnesses passed 67. Two forged feed-journal controls
passed against the revised startup order. A stale unconfigured-forget gate
expectation was corrected, and its four focused controls passed.

Three ordinary extension-shell controls reproduced a separate defect: the
native admission handshake rejected the absent deadline used for ordinary
effects. The runner now supplies a short grant only for that absent deadline;
managed deadlines remain unchanged. Completion, cancellation and stopped-helper
controls passed, as did four protected-helper tests including an expired-grant
refusal. Five managed-shell Session controls failed earlier, before the expected
approval, and therefore do not establish managed-shell qualification. The full
suite remains an earlier, mutable snapshot and is not a current-source baseline.

The low-budget recall fix now has a synthetic native Session control in an
isolated build with a freshly rebuilt Knowledge artifact. Two independently
admitted context publishers leave at most 128 bytes. The job reads the three
current records, receives the host's actual budget, successfully publishes an
empty contribution after that budget, and completes; the registered loopback
provider receives the competing context without any note text. The same PTY
journey exercises reviewed forgetting and an explicit resume without inference
replay. The test was corrected to wait for the native forget prompt and to
account for owner and close records. This is one constrained synthetic journey,
not full recall-quality, source-loss, or installed-user qualification. The
earlier full suite remained live at the last poll and predates this work.

An additional pending-question control reproduced a second resume refusal that
mutated a torn journal: operator input was checked only after owner startup and
tail repair. Resume now checks the reconstructed pending question against the
effective draft configuration before either operation. The control verifies the
refused journal is byte-for-byte unchanged, then explicitly resumes with input
available and answers without replaying the earlier callback. That control, a
question-corruption control, and the budget/release suites passed 41 tests in
the isolated build. Other post-owner startup checks and loss boundaries are not
thereby qualified.

A missing pending-question source checkpoint exposed another refusal after
tail repair. Resume now resolves both extension-event and subscription question
sources against the locked prefix before owner startup, and repeats the check
after reloading. The missing-checkpoint control asserts the precise refusal and
unchanged torn journal. A valid feed question resumes, records a new owner and
continues only after an explicit answer; both controls passed. The combined
question, budget and release-owner selection passed 42 tests before the final
two-control rerun. A valid extension-event question and the native recall
journey also passed under the new ordering. These checks do not cover every
source or startup failure.

Knowledge search previously reported complete coverage when an indexed record
could not be read and no metadata page remained. It now marks that result
partial while retaining any successfully read matches. The eight-case isolated
worker suite passes against both source and a freshly built native artifact;
it covers all available, all unavailable, mixed availability and additional
metadata pages. This does not establish real-model search quality or an
end-to-end unavailable-source search journey.

The worker now binds each recall/search read to the indexed key and revision.
A mismatched read is omitted and counted unavailable, making coverage partial.
Nine synthetic worker cases passed from source and a freshly rebuilt artifact,
including a revision changed between index and get. The native recall/forget
journey passed against that artifact, but it does not interpose an actual
concurrent replacement; that race and broader retrieval qualification remain open.

The current decision Session/protocol selection initially had one outdated
idle-resume assertion: a valid resumed Session now records a new release-owner
marker. The test checks that exact marker and still requires zero decision
egress on resume. The corrected selection passed 27 tests in the isolated build,
including synthetic loopback approval and decision-policy controls. This does
not establish saved helper consent, protected Knowledge consumer integration,
live account access or the frozen P30 experiments.
