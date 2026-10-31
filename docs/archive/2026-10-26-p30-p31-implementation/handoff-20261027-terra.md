# P30/P31 handoff: inline replacement and installed-package investigation

## Latest resumable checkpoint

**Superseded checkpoint:** resume from the
[2026-10-28 Sol retention/integration handoff](handoff-20261028-sol-retention.md).
The snapshots below remain historical evidence; their running handles and open
items are not current task authority.

**Resumed with Sol at the user's request on 2026-10-28.** The goal is active.
**Latest user steering:** finish coherent implementation sections and use
targeted tests while implementing them. Defer aggregate validation to the section
boundary; do not keep rerunning aggregate suites after small edits.

**Current checkpoint, 2026-10-28; supersedes the earlier snapshots below.**
Root's ManagedUse expiry and batched preflight repairs are implemented, independently
reviewed and focused-verified: 46762 passed5, 46763 passed1/4excluded, and the added
actual mixed eligible/stale verdict batch46764 passed1/4excluded. Evidence and
source/log hashes are in `managed-use-preflight.md`. No root handles remain live.

Actual owned native send and final result release are now wired. Source agent's
final46766 passed3/25excluded and46767 passed13/28excluded, including actual
ChatGPT-adapter verified local TLS, revocation-before-body, changed-root response
withholding, owner loss, policy deadline and shared-budget narrowing. See
`owned-send-integration.md`. This remains available-host diagnostic evidence;
short literal-v4 transport expiry, direct extension-result final release and
final whole-source qualification stay open.

Root added `Review.check/3` and `consumed_receipt/3` plus
`Consent.forget_deferred/8` and `management_sha256/3`. Exact actual native review,
existing control epoch/fingerprint, finite one-op/zero-inference reservation,
durable publishing before callback, consumed receipt/hash matching and deferred
settlement are required. Capture may be expired/revoked. Root run46768 passed33
tests,6.4s, including five actual native management scenarios and existing Consent/
Review regressions; log is `_build/operator-assertion-sol/_build/sol-consent-management-46768.log`.
Capacity independently reviewed this gate and found no concrete scoped defect.
Root wired the standalone `knowledge forget NOTE_KEY` and read-only
`knowledge operation JOURNAL_ID`, with current binding, private owner journal,
intent/reservation before mutation, settlement after Identity release, measured
normalization and checked Writer/lock/scope cleanup. CLI audit found missing mode
ceilings/ignored cleanup; fixed. First actual CLI run46775 exposed an atom/string
origin gate mismatch before review; retained/fixed. Native46776 passed1/5excluded
12.7s; modes46777 passed1; final native+inertinspection46778 passed1/5excluded12.0s.
See `managed-forget.md` and its23-artifact source/log manifest. Root has no live
handles. Recent shared source remains uncommitted, not milestone-complete.

Capacity agent implemented new `Session.ManagedLifecycle.prepare/3` and host-only
`NormalizerV3.forget/3`; actual native Core controls passed2tests/3PTY scenarios6.4s,
and3turnover schedule/clock controls passed. Signed retirement/suppression blocks
same-support recapture and old-floor imports; expired notes can be forgotten.
These Core checks are distinct from root's newer actual CLI/Consent integration.

Word agent's paged original acquisition (<=32KiB, <=4096bytes/reply) and explicit
>8KiB staged text are focused-verified in an isolated host overlay, preserving
SDK/result ceilings. Actual Session7, native11, supplied3, stagedCAS1 and plain64KiB
staging1 passed; failed CAS fixture assumptions were retained and repaired. See
`word-staged-acquisition.md`. Capacity's frozen-source review found a binary result
validator request-grammar mismatch; Word is repairing it. Word now implements
explicit paged typed locator metadata up to16KiB within unchanged SDK limits;
that new section is unverified. FullC1b capacity/current file tracking stay open.

Source agent now implements P31E turn-local recall through an owned blocking
before_request job and fixed Reference tail. Approved host gaps are metadata-only
collection index, context.available and narrow host-derived Reference withdrawal;
all unverified. It owns only effects/2 mapping at bottom CLI.Knowledge, preserving
root run_target above. Root owns Consent/Review/CLI management/docs; Word owns
Tools/Corpus/Documents/Store/Evidence. Capacity is qualifying a narrow exact
7.2.11-arch1-1 x86_64 tmpfs-only production profile; newkernel Btrfs remains
failclosed pending fault evidence. Its build/tests are isolated and still active;
do not call new admission qualified before final native receipt. All3subagents
are explicitly user-authorized.

The plan now records4,000 V3 publications and bounded Word ingestion accurately;
manuals include current staged Word and native forget/recovery procedures. Docs
check679 Markdown/5469links passed0errors after those edits. Whole-manual/final
aggregate/installed/quality/turnover/adversarial acceptance and commits remain open.
Last pushed commit is704bd1d; all recent changes remain dirty. Never add/reset the
unrelated `.serenity-*` evidence. Native profile edits are in-flight/unqualified.

## Earlier checkpoints — superseded historical snapshots

**Newest status checkpoint:** capacity agent finished and independently
reconciled **4,000 actual V3 publications**. See `capacity-available-host.md`;
all handles are closed, production admission unchanged. Word agent completed
bounded4096-byte workspace acquisition, real Session/cited-query/no-replay
controls and opt-in document presets; see `word-workspace-acquisition.md`.
Producer lineage plus async preflight projection/causal replay/historical write
facts passed47 pure/refusal and6 registered HTTP controls (46750/46751).
Root's fresh-consumer ManagedUse test46742 passed1,4excluded,10.1seconds.

The source agent is now implementing actual owned native send/TLS cleanup and
terminal managed-result admission; its task is still live. Root added forwarding
Session `inference_wire_use`/`managed_result_admit` handlers and volatile
`managed_result_seal:nil`, not yet compiled with that transport section.
Root owns two audit repairs in ManagedUse: recheck policy expiry immediately
before use (after final observations), and batch preflight proof checks to avoid
repeated whole-journal scans. StoredSources.snapshot partial statuses + shared
snapshot scan budget and source-reference dedup are in-flight/untested; the
ManagedUse.verdicts batch replacement is **not yet implemented**. Its existing
per-dependency loop still has the reported repeated-scan issue. Do not claim
these two verifier findings fixed or final send/delivery qualified yet.
All current source changes remain uncommitted; final whole-manual integration,
aggregate regression, installed/quality/turnover and final audit remain open.

**Current parallel continuation (all still uncommitted):** the user explicitly
requested specific subagents. `source_audit` owns actual producer lineage in
Session/Turn/Invocation/Saved/Context/ManagedReference and a new ManagedLineage
module; its hooks/accessor are in flight, not yet accepted. Root owns new
`session/managed_use.ex`, the StoredSources phase-bound query/128-proof aggregate
journal budget and InferenceDispatch dependency binding. These latest verifier/
lineage edits are **not yet verified as an integrated section**. They must not
be advertised as an owned-send or delivery barrier. Root's added native fixture
uses a fresh actual consumer Session to test current original sources, unchanged
records at newer roots and stale selection refusal; it has not yet run.

The agreed API is `Session.managed_dependencies(s,phase)` returning a canonical
dependency list, input digest, plan and plan digest; source bindings are trusted
`{:snapshot,phase,sha}` or `{:inference,phase,expected}` values. ManagedUse
revalidates real root/literal dependencies under original-source leases and
current Identity/Consent; InferenceDispatch currently uses it before durable
dispatch intent. **The Finch queue/send race remains open** until actual owned
transport integration retains that authority through its send continuation.
Do not drop pre-write root dependencies from arbitrary worker output: a
separate host-constructed historical write fact must confirm a save safely.

`word_ingestion` completed a supplied-DOCX-payload extraction→CAS→typed citation
bridge, with source and built-artifact controls; see `word-source-bridge.md`.
It is now implementing approved workspace binary acquisition through explicit
new document presets and the existing native read tool, plus actual Session
controls. Larger/staged documents and installed/quality acceptance remain open.
`capacity` is running one frozen V3 available-host diagnostic in
`_build/capacity-sol-20261028-02`, private helper override, production_admitted:false.
Its latest clean checkpoint is **2,000 actual publications**, after the earlier
pre-publication loader failure was preserved in a different graph/store.
Segment 5 is live under handle **86533** (latest progress 2,300); revalidate the
handle or agent before assuming it is still running. No aggregate suite ran.

Last verified receipt section: affected action/invocation/Saved/collection
selection **46716 passed 84**, 38.3 seconds; explicit-marker/receipt **46717
passed 5**. Retention selection was additionally restricted to the exact
standard selected capture recipe (not unused registry entries); unit/native
**46724 passed 8**, four excluded, 8.0 seconds. Writer privacy/origin and
StoredSources native lease-loss fixes have focused evidence below. All these
verified logs predate some in-flight producer/verifier/acquisition changes.

**Latest: read receipts are wired and focused-verified.** New
`session/managed_reads.ex` retains root/literal dependencies. The protected
adapter prepares an exact result receipt through the real active Session action;
commit writes `managed_read_observed` before its successful action result and
unions every committed read for that invocation. Existing `Actions.restore`
owns chronological receipt validation; no duplicate journal parser remains.
`Saved.restore` and actual Session state retain per-output read unions. Fresh
headers pin `managed_reads_v1`; old headers keep historical behavior. Missing,
duplicate, reordered/altered receipts, partial prefixes and omitted literal
dependencies have controls. This is **not yet assistant/reference/summary
inheritance, every-dispatch withdrawal or a final delivery barrier**.

Strict changed-module compilation passed. The first native run46711 failed
because Actions' unknown-record guard refused the new receipt; integrating that
record into the existing owner fixed it. Native46712 passed1, then pure/native
46713 passed8. Receipt/native/origin46714 passed**22 tests**,13.7seconds,exit0;
new literal completeness46715 passed4. Logs are in
`_build/operator-assertion-sol/_build/sol-read-receipts-*`. A focused affected
action/invocation/Saved/collection Session selection46716 is running under
exec handle**(see current tool state; verify before resuming)**, not an aggregate
suite. Do not treat the earlier42-test run as covering these changes.

The user explicitly authorized subagents on2026-10-28, superseding the earlier
single-agent preference. Current bounded tasks: `capacity` repairs stale trusted
V3 workload fixtures/controller and runs one frozen bounded capacity workload;
`word_ingestion` implements explicit-payload DOCX extraction→CAS storage→typed
citations; `source_audit` audits this actual source path and repaired two found
bugs. Writer now rechecks full origin/private parent on cached reads and appends;
its seven added controls are included in46714. StoredSources now monitors/checks
the raw retained lock lease and withholds output after helper loss; its new
`stored_sources_test.exs` passed2 native controls46723. All changes remain
uncommitted. Agent messages/tools are authoritative for active workload handles.

**Latest implementation: [current-source read admission](current-source-read.md).**
`CollectionCall` now preserves `managed_read` recipes; `ManagedRead` authenticates
literal records and current sources before returning get/scan values. New
`Session.StoredSources` resolves the original selected sessions directory, holds
inactive source locks outside Identity/Consent, validates complete Saved history
and original descriptor/project/namespace, and rechecks after use. Current-source
queries use the actual active action lease and Writer. The final protected read
must match its provisional root/value and current recipe/deadline/source policy.
The actual native fixture tests both current and inactive original sources,
tampered stored values and a collection-root race. **42 focused tests passed**
(46709, 22.6 seconds, exit 0); no aggregate run. The later callback-error cleanup
control also passed the save-only fixture (46710, 8.2 seconds). Graph and source-file
list are in the linked record. No test is running at this checkpoint.

All of these changes remain uncommitted in the shared dirty tree. The read guard
checks a normalized dependency but does not yet persist/propagate it. Next:
attach complete host read unions to actual Session producers, reconstruct them
on replay, and revalidate/project before provider egress and final delivery.
Do not treat read-time admission as current authority for later worker/model use.
The section-boundary docs check passed **670 Markdown files and 5,383 local
links**, zero errors, with the existing inaccessible receipt warnings. Final
whole-manual editorial acceptance remains open. The two retained test-log links
were added after that check and point to existing files; no aggregate rerun is
needed merely for those links. All test and docs-check processes are closed.

The [native statement-review section](native-assertion.md) is now implemented in
the shared tree and passes **10 targeted tests** (46705, 8.9 seconds, exit 0).
`/remember CATEGORY TEXT` uses a fresh, exact native confirmation before the
existing protected capture command, without a model call. Receipts bind claim,
category, workspace/project/artifact/policy scope, client/channel/render and
native input. SourceIndex exposes category-specific `input.assertion.*` kinds
and `native_operator_assertion` origin. Both worker and host require the exact
reviewed category for literal notes. Plain interactive messages, including whole
quoted reports, now stay pending; native answers still stay pending. The new
source-page contract admits only the added `assertion_id` and `category`
provenance fields. Planning refuses before review; revocation during review
preserves the endorsed journal statement but permits no capture callback.

The graph is `_build/operator-assertion-sol`, with the inherited test-only native
helper override. Initial strict compilation covered 156 modules; changed modules
and matching inert bundles were rebuilt after fixes. The new test files are
`test/ipse/session/operator_assertion_test.exs` and
`operator_assertion_integration_test.exs`; the actual CLI fixture is
`test/support/operator_assertion.exs`, using an added mode in the existing Rust
PTY driver. No live models or account access were used. The affected capture
section passed 23/25 (46701); after updating the deliberately permissive attack
artifact and matching sidecar, only the affected intake file was rerun and its
three parent tests passed (46702). Earlier failed logs and final retained output
are described in the linked record. All processes from these checks are closed.

These source changes remain uncommitted alongside the previous journal-origin
integration. Other fixtures using `Ipse.Test.ManagedPolicy.proof/0` now receive a
synthetic category-reviewed ordinary proof by default; category-changing tests
must supply their actual reviewed category rather than infer it from raw input.
Some wider tests may need corresponding semantic fixture updates; no aggregate
suite has run for this section. Manuals have been updated for `/remember` and the
source kind. Finish their editorial review and one final docs check at the next
appropriate boundary. Do not claim proposal acceptance by ID, correction/forget,
current recall, source leases through egress, capacity or installed qualification.

Next implementation: use the now-available actual reviewed notes as positive
inputs for current-source read/recall integration. Do not spend another turn
building unused observations or repeatedly validating the aggregate tree.
The native staging-recovery increment is committed and pushed as **`704bd1d`**.
It preserves all unrelated edits and the production profile. The later
[journal-origin integration](sol-source-origin.md) remains uncommitted but now
passes **96 focused tests** (seed 46695, max-cases 1, 109.5 seconds, exit 0),
strict compilation, formatting and an isolated-home scripted demo. Its graph is
`_build/source-origin-sol`; the post-run private source-index tree is
`2c2c406a47c555cf47e2235a7ec448c64d007266`. Its helper is the same diagnostic
override below. All test/build/demo sessions in this continuation are closed.

Fresh Session headers now bind the actual new descriptor and canonical directory.
Locked resume checks this before tail repair; Writer validates its descriptor
and requires a matching SourceWindow origin. Cached source queries recheck file
identity and length before returning. SourceIndex versions incorporate the
recorded origin digest without exposing private paths or changing proof fields.
Legacy versions remain historical. Legacy collection inspection remains possible,
but managed publication and proof-bearing collection requests require a nonnil
Writer-validated origin. The first broad run passed 93/95 because that guard was
too broad; the narrowed guard passed 28 publication tests (46694), then all 96
tests with the final Writer-window match. Keep these failures in the record.

This is actual fresh/resume/publication integration, not current recall or
source authority through egress. No full suite or production-profile build
containing the journal-origin changes has yet run. Do not treat the earlier full
pass as covering them. Source and log hashes are in the linked record.

The working source changes are in `journal/source_origin.ex`, `journal.ex`,
`journal/writer.ex`, `session.ex`, `session/saved.ex`, `session/source_index.ex`,
`session/source_window.ex`, `cli/errors.ex`, the new journal origin test and
additional SourceIndex/managed-Session controls. Manuals now describe the
working origin behavior. Preserve prior changes in the already-dirty files.

The final documentation check covered **668 Markdown files and 5,365 local
links**, with zero errors and the existing inaccessible receipt warnings.
`git diff --check` passed and the root index is empty. No tests are running.
Do not launch another full suite merely to repeat the recovery baseline; first
complete the next coherent source/use integration. The new origin digest can
distinguish a candidate source without a global mutable lookup registry, but
actual cross-Session reads still need the original file, retained ownership,
current semantic checks and revalidation at use. Do not treat that design
observation as an implemented reader or source lease. The independent audits
remain historical; the requested final adversarial audit is still open.
The first check confirmed no competing test or capacity process remained. The
two timed-out migration cases ran alone in the frozen diagnostic graph
`_build/planning-preexit-audit`, seed 46684, max-cases 1.
Both passed in 305.6 seconds (two selected, twelve excluded), with wrapper exit
0; see the [Sol recovery record](sol-recovery.md) for retained output and limits.
The current increment settles retained stages before owned allocation inventory
and refuses on a sync error; nine strict native tests and 22 transaction tests
pass. It leaves production kernel admission unchanged. Full-suite verification should
follow the completed implementation increment, rather than every small edit.
The serial full run finished: `_build/sol-recovery-46691`, seed 46691,
max-cases 2, **2,883 passed, 36 excluded**, 2,027.8 seconds, exit 0.
Session **96243** is closed. Output/status remain `_build/sol-full-46691.log`
and `_build/sol-full-46691.exit` in that graph; the retained log and hash are in
the Sol recovery record. Its test-only source-index tree is
`916b04052a8c142d1c7c9a508148361e46e9a006`; substituting the production
profile yields `cccd73a818b10c66d5046be41e524f16f7c5efea`. All tracked files
except that explicit override, and complete `lib`, `extensions`, `test`, `dev`,
`examples` and `docs` directories matched the working tree before the freeze.
Strict compilation and matching inert bundles passed. Its private helper
SHA-256 is `86d6226c868b7095c6ba7460cc0b42832e98fb70feea0779fb3473ac7bb28a6a`;
catalog SHA-256 is `3a4de68d9ebb038f24102bd2aa6bfb4141ce7efa56a9162875c3087b3c1c1070`.
Its source index was unchanged after completion. This is a diagnostic pass,
not native profile admission or verification of the newer journal-origin work.
The isolated production-profile build in `_build/sol-native-production` passed
141-module strict compilation, inert bundles, 22 transaction tests (46692),
formatting and the final isolated-home demo. That tree is base `668e6a3` plus the
native-recovery increment; it excludes later journal-origin edits. The sandbox
attempt failed only because Mix's required local TCP lock was denied; approved
local access passed. The retained record omits the initial demo output that had
loaded local operator configuration and retains only the fresh-home rerun.

The previous pause remains recorded below. Keep work in one agent unless the user explicitly changes
their earlier choice; their question about subagents was not authorization to
spawn them. They asked whether a more capable model would help; GPT-6 Astra was
recommended for difficult reasoning, while noting it does not remove the test
or platform constraints. The user wants full tests, adversarial review and a
review prompt, with no shortcuts. Release publication is not authorized.

The immediate priority on resume is P31B/C0: current identity, consent and
source authority through actual use/egress; then P31C1a capacity, P31D0/E
installed safe capture/recall/lifecycle, and the P30 qualified consumer and
experiments. Whole-event interactive input now remains pending; the new explicit
statement review supplies category-bound literal authority. New origin-bound source versions and actual resume checks now
distinguish copied/replaced journals, but cross-Session source selection and live
use checks remain unwired. Historical signed-observation guards supply neither
attribution nor current authority.
Do not enable or claim protected recall based on those observations. The
available 7.2.11 host remains unqualified for production protected storage; the
user authorized adapting qualification to available resources, not falsely
claiming an unproved security boundary.

All four full suites started in this continuation were stopped intentionally
after excessive overlap caused or coincided with large migration timeouts.
46681 timed out twice and 46683 once; 46675 and 46678 had no reported test
failures before termination. All four logs end in SIGTERM without an ExUnit
summary; all four wrapper statuses are 0 and **none is a passing full run**.
The prior fixed snapshot seed 46671 finished with 2879 passed and 36 excluded,
but predates the latest reader and planning-test changes. The two migration
retries and the serial full suite have now passed as recorded above; do not
restart the abandoned runs. The prior diagnostic snapshot was
`_build/planning-preexit-audit`, private test
tree `fa5fe8378de268d87b302aa0e5bae53dc074b1aa`; its kernel helper is test-only.
The complete ledger and individual log hashes appear below. Preserve all user
edits and `.serenity-*` evidence; none of the current milestones is complete.

Version-3 managed proposals now check retained `pending.` count and encoded
bytes under the Collection lock, using a bounded metadata-only summary charged
eight of 32 read units. The prior host normalizer accepted a full synthetic
queue (seed 46552). The expanded isolated diagnostic passed 46 tests (seed
46558), including actual Collection count/byte refusal, exact byte boundary,
owner isolation and budget latch. See [the capacity record](pending-capacity-followup.md)
for the concurrency and profile limits. This change postdates the completed full
diagnostic snapshot and is not a completed capacity or lifecycle milestone.
The broader ten-file managed-publication, read-view, Session and capture
selection passed 131 tests (seed 46559) in the earlier test-only-helper graph.
Strict compilation, formatting, documentation links and `git diff --check`
passed on the working tree.
An engineered synthetic proposal requiring anchor repair and live insertion
used exactly the full 32-unit callback budget with the summary (seed 46560).
This single geometry does not prove all page cases or workload capacity.
A subsequent direct Collection control held the lock after reading 63 pending
references and started a competing owned task without the Identity lock. The
competing callback did not enter, and a fresh read after publication saw 64.
The expanded selection passed 48 tests (seed 46563). This uses a synthetic
normalizer and two tasks in one BEAM. A subsequent separate-VM control saw a
busy lock, then a stale-generation conflict, then 64 references on a fresh
request; the expanded selection passed 48 tests (seed 46565). Both use a
test-only helper and synthetic normalizer, not a complete signed-domain race or
production-profile qualification; see the capacity record.
A later two-VM test ran the actual signed-domain callback and version-3
normalizer: the competing VM was refused while Identity was held, a stale
request then conflicted, and a fresh request refused at 64 pending records.
The expanded selection passed 49 tests (seed 46568). Authorization and sources
were synthetic, with no real Consent reservation; the first fixture attempt
failed on truncated child-program options (seed 46566), then passed after
rendering complete options (seed 46567).

A controlled Session-death test now covers a synced planning entry before
acknowledgement. Recovery retained witnessed exit provenance, rejected the old
queued input and allowed one new witnessed exit. The focused control passed
(seed 46547), and the planning/MCP/mode selection passed 40 tests (seed 46548).
It uses synthetic input and a writer proxy; the full diagnostic snapshot
predates this test. See [the transition record](planning-transition-design-followup.md).
The declared-MCP variant now covers the same synced-entry boundary through two
resumes and a new exit; its focused test passed (seed 46549), and the 40-test
planning/MCP/mode selection passed (seed 46550). This is still synthetic input
and a test writer proxy, and also postdates the full diagnostic snapshot.

After the diagnostic snapshot was created, the pure Notes retention receipt
was corrected to flag a potential historical gap when a current temporal claim
is reduced to any non-pin policy. Before the change the new control failed
(seed 46521); the Notes and Records suites passed 18 tests afterward (seed
46522). This conservative flag does not calculate the missing interval, add
the typed operator workflow, or prove shared-evidence handling. The completed full
diagnostic snapshot predates this source change and cannot validate it.
The warning also now covers reductions of pins and enduring preferences, which
can carry persistent or 365-day historical support. A pre-fix control failed
(seed 46545); the Notes and Records suites passed 24 tests after the change
(seed 46546). It remains a conservative flag rather than exact gap computation.
The pure retention operation also now refuses a new choice dated before its
selected note's creation or supersession. The pre-fix control failed (seed
46523); the Notes and Records suites passed 19 tests after the change (seed
46524). Applying an earlier saved override to a later recapture is still
permitted; trusted current time and ordering against earlier choices remain
host responsibilities. This change is also outside the completed snapshot.
The pure `Notes.retention/4` path now refuses pin, ordinary or duration choices
on an already expired note, while still allowing session-only suppression. The
pre-fix expired-note control failed (seed 46525); the Notes and Records suites
passed 20 tests after the change (seed 46526). This does not make direct
`apply_override/2` an eligibility check, authenticate current time or evidence,
or implement the native management workflow; the completed diagnostic predates it.
An ordinary same-lineage correction previously reset its deadline (pre-fix seed
46527). Without an explicit saved override, the pure `Notes.supersede` path now
preserves the earlier finite deadline and refuses persistent promotion or
revival after expiry; a different lineage can create a fresh record but its
new evidence still requires host authentication. Notes and Records passed 20
tests (seed 46528). The completed diagnostic snapshot also predates this change.
The pure constructor additionally refuses applying a same-lineage saved choice
before its recorded time (pre-fix seed 46529). The first combined rerun exposed
a changed error for a foreign lineage (seed 46530); preserving that prior
refusal led to 20 passing Notes and Records tests (seed 46531), including an
explicit saved pin. These checks do not authenticate the supplied choice.
`Records.capture/4` now also refuses a future-dated session-only override before
its suppression branch. The pre-fix control failed (seed 46532); Notes and
Records passed 20 tests after the change (seed 46533). This is a consistency
check, not native-choice authentication; the completed full diagnostic predates it.
Repeated pure retention changes now require a prior override consistent with
the selected overridden note and no later than the new choice; missing or
mismatched prior choices refuse. The pre-fix test exposed acceptance without
prior state (seed 46535); 21 Notes and Records tests passed after the change
(seed 46536). A prior reason is not encoded into the effective note, so even a
matching prior object must be authenticated by the host; the completed full
diagnostic predates this change.
The updated Notes and Records source plus the synthetic capture Session passed
23 tests (seed 46537) in the earlier isolated test-only-helper graph, including
the control demonstrating that a changed prior reason is not authenticated by
pure consistency. This is not the complete typed management path.
The literal reason `operator override` can occur on a fresh note and collide
with the pure model's marker. A caller can now pass `:absent` to represent a
checked absent prior choice (pre-fix seed 46541; 23 Notes and Records tests
passed seed 46542). The marker is only a caller assertion and can be misused:
the actual host must establish and recheck absence under the transaction lock.
No native management route uses it yet; the completed full diagnostic predates it.
The same marker collision affected `Notes.supersede`; it now accepts the same
caller-supplied `:absent` while preserving the finite deadline. The pre-fix
control failed (seed 46543), and 23 Notes and Records tests passed afterward
(seed 46544). The host must check both old and replacement lineage choices as
applicable; this pure atom does not prove either absence.
The current Notes and Records files were also copied into the earlier private
test-only-helper graph with the capture Session test; 22 tests passed (seed
46534), including synthetic PTY capture and a separately built artifact. This
does not qualify native storage or typed retention and is not the full current
working-tree graph.
The pure Notes temporal check now refuses availability before record creation
or historical supersession, and rejects a record whose observation postdates
creation or whose supersession predates creation. The pre-fix control failed
(seed 46538); Notes and Records passed 22 tests after the change (seed 46539).
This is a local chronological constraint, not an authenticated current clock,
event-time inference or current managed eligibility. The full diagnostic
snapshot predates this change. The updated Notes and Records plus synthetic
capture Session selection passed 24 tests (seed 46540) in the earlier
test-only-helper graph; it is not native-profile qualification.

An isolated full functional diagnostic of the earlier working-tree snapshot
finished in `_build/current-diagnostic-dPxI7f4J` (seed 46520, max-cases 2).
It exited 0 after 1,979.2 seconds with 2,837 passed, four skipped and 36
excluded. Its log is `_build/current-diagnostic-dPxI7f4J/_build/full-diagnostic-46520.log`,
SHA-256 `89c260d7b2f59470cc3e1144e597759ef640a399d32801b7c0eccfae7c305403`,
and its private temporary directory is `/var/tmp/ipse-current-functional-ZRDAEtch`.
The copied source's synthetic pre-override tree is
`1a38c17d6098d1a801e608a2e4ec690aea991975`; the diagnostic tree with the sole
test-only `7.2.11-arch1-1` profile override is
`7e98efbf98f51d9d717536334705c34c8d99c74d`. Its helper SHA-256 is
`b7ea344b9b631208e9f766885d781cf3753d8569ed6a55f08fbe610fa28528bb`;
strict test compilation passed. The graph uses the existing shared dependency
source via a symlink and private build outputs. Its two commits are synthetic
fixture history, not release commits. The copied graph's Git status was clean
after the run and the helper hash remained unchanged; the shared dependency
source was not separately inventoried. The skipped cases are optional PDF
parser tests, and the excluded tags cover native/macOS sandbox, macOS filesystem
and memory scope. This diagnostic bypasses profile admission and cannot qualify
production storage or durability. It predates the subsequent retention,
pending-capacity and planning-test changes recorded above.

The two synthetic PDF test files then ran separately in the earlier
test-only-helper graph with an existing parser binary: five passed (seed 46569).
The binary SHA-256 was
`85cde09bd8783ef99427bcd07f5708b33b9e46138e58288d2790eed1544b6556`;
its recorded source graph and current parser `main.rs` both hash to
`ad67c25b4c7fcd9b7781e94fc0ee51e4ca072285fbc93fb7f1fe1276158df21f`.
This is a separate run with an existing binary, not a full-suite rerun or
real-document PDF qualification.
The available Linux `native_sandbox` cases in `sandbox_test.exs` and
`stdio_test.exs` also ran separately on the completed diagnostic snapshot:
17 passed and 22 unrelated cases were excluded (seed 46570). This does not
qualify the separately gated protected-storage profile or macOS behavior.

The current working-tree full suite finished with seed 46519, four cases at a
time, and disk-backed temporary directory `/var/tmp/ipse-p30p31-full-DAamoWm1`.
It exited 2 after 1,386.3 seconds: 2,559 of 2,837 passed, 278 failed, four
skipped and 36 excluded. Output is retained at `_build/p30-p31-full-46519.log`,
SHA-256 `75e670723c180558ac922ac478dd1a9ca21766e10c02ac6e8b23ba198ce8da20`.
Of the 278 top-level failure blocks, 274 include explicit unsupported-filesystem
errors. Two owner-loss tests timed out after their spawned fixtures failed to
seed with `collection_filesystem_unsupported`. Two absent-root observation
tests returned the generic `collection_observation_refused`; a separate empty
store diagnostic using the test's layout returned
`collection_filesystem_unsupported` from `open_view` and the same generic error
from snapshot and record observation. These are first stopping conditions, not
proof of how those tests would behave on an admitted platform. Some tests print
`NOT RUN` while passing the refusal branch. The run is not a frozen source graph
or native-profile qualification. The first diagnostic used an already-created
root and returned `collection_unavailable`; the corrected layout produced the
results above. An earlier full attempt (seed 46518) was interrupted before
completion because shared `/tmp` had only 4.6 GB free, and has no suite result.

A controlled Session-death test now covers a synced planning exit before its
acknowledgement, without declared MCP reads. Recovery retained normal mode,
refused an old queued input and did not duplicate the exit. The focused test
passed (seed 46516), as did 39 planning, MCP and mode tests (seed 46517).
This uses a synthetic observation and test writer proxy, not power-loss or
native-terminal qualification. See [the transition record](planning-transition-design-followup.md).

The internal managed-record reader now refuses any recipe-selected override
record in the same checked view. A synthetic override demonstrated the prior bypass
(seed 46506); the signed-publication, observed-read and view selection passed
56 tests after the fix (seed 46507) in the test-only-helper graph. This is a
fail-closed interim rule, not authenticated retention semantics or Session recall.
See [the observation record](record-observation-followup.md). The user's goal
has resumed; its full P30/P31 implementation and audit remain open. Formatter,
strict compilation, documentation links (663 files, 5,308 links), and
`git diff --check` passed after this change. Next, continue the Session-owned
observation, source-currentness, consent and dispatch integration described below;
do not treat this component as completed recall. A subsequent alternate-prefix
control exposed a fixed-prefix bypass (seed 46509); the reader now requires a
literal recipe matching the signed live-page digest and checks that recipe's
override key. The 56-test selection passed (seed 46510), as did the added
alternate-prefix positive and suppression control (seed 46511), both with the
diagnostic helper. Formatting, strict compilation, documentation links and
`git diff --check` passed on the updated working tree.

An owner-only Writer replay control now closes and reopens the journal, restores
the source window, and revalidates the same exact stored proof under a fresh
window identity. The focused test passed (seed 46508). This establishes neither
cross-session history nor durable managed-observation lineage or current consent.
The integration fixture now also binds a journal-derived synthetic source proof
to an actual managed publication and same-view observation after journal replay.
The combined source, journal and managed-read selection passed 76 tests (seed
46515) in the updated diagnostic graph. This is not a live Session admission or
operator witness; see [the observation record](record-observation-followup.md).

2026-10-27. The developer requested saving state in case this agent is killed.
P30/P31 remain incomplete and the active goal remains unchanged. Keep work in
one agent, preserve all existing dirty files and `.serenity-*` evidence, and do
not publish a release. The plan permits qualified completion for tested scope
when platforms/accounts/human journeys are unavailable, but the available
7.2.11 kernel is still **not** an admitted native-storage profile. Test-only
helper overrides are diagnostics, not production qualification.

The newest in-progress change adds `SourceIndex.revalidate_stored/2` and an
owner-only Journal Writer `{:stored_proof, proof}` query. It reconstructs a
stored exact quote against the current source occurrence, rejects tampering,
ambiguous quotes and redacted versions, and returns the current source/policy
generation. It is not yet connected to managed recall, cross-session source
history, current consent or dispatch authority. The source and writer selection
passed **26 tests** with seed 46505 and local TCP permission. This only checks
the current Session window and owner-only Writer access; a worker-provided
proof does not become publication authority. Formatter, strict compilation,
documentation-link checks and `git diff --check` passed at this checkpoint.
Re-run the applicable checks after further changes. The next integration must
have the Session obtain this owner-only proof for the exact source, bind it to
the managed read and current consent, and journal it before releasing any value;
cross-session source history, replay and the send-time barrier remain open.

The preceding working-tree changes include [fragment intake protection](capture-fragment-followup.md),
[record-only observation and same-view signed metadata](record-observation-followup.md),
the same-root legacy projector compatibility change, and the DOCX v7 recipe.
The internal record-only path now derives a version-4 dependency from checked
metadata and a supplied exact proof, but the caller's proof, time and consent
are not authenticated by that constructor. The SourceIndex change is a step
toward rechecking proofs in the current Session, not a complete source-history
or current-authority solution. Read the linked records before continuing.

All of this work remains **uncommitted**. The last pushed checkpoint was
`668e6a3`; the worktree has extensive unrelated and related edits. No current
full-suite result or final adversarial audit is claimed. Do not mark the goal
or a sub-milestone complete, commit, or push until its required implementation,
verification and whole-manual editorial review actually pass. The
[review prompt](review-prompt-working.md) is provisional and must be updated
against the final implementation.

2026-10-27. Continue P30/P31; neither milestone is complete. The developer chose
**keep work in this agent**: do not spawn review subagents without new explicit
authorization. They are switching to Terra 6.1. Publication is not authorized.
Read [the preceding handoff](handoff-20261027-enhance.md), the plan, and the
repository instructions first. This record supersedes that handoff's status of
the installed permissions timeout and the absence of inline replacement.

Branch `codex/p30-p31` is at the previously pushed checkpoint `668e6a3`. The
original dirty SDK-v3, Mint, egress, inference and capacity experiments and the
`.serenity-*` evidence remain in the worktree; later focused changes to some
experiments are recorded below. Do not sweep them into a commit, clean
retained ledgers or devices, or replay their faults. This turn's changes listed
below are **uncommitted**, have not had the required full editorial review or
independent adversarial audit, and are not a completed sub-milestone.

## Inline replacement

The working tree adds `/enhance replace TEXT` through a witnessed terminal input,
with a version 4 draft replacement record binding the exact command and input
observation; replay checks the parsed text, observation and exact event, and
observation uniqueness includes the new version. `multi` remains reserved for
existing multiline mode. Changed files: `lib/ipse/cli/terminal.ex`,
`lib/ipse/session.ex`, `lib/ipse/session/draft.ex`,
`lib/ipse/session/draft_acceptance.ex`,
`test/ipse/session/draft_acceptance_test.exs`,
`test/support/draft_cli_pty.exs`, and `test/support/operator_cli_pty.rs`.
`mix test test/ipse/session/draft_acceptance_test.exs --seed 20270325
--max-cases 1` passed 7 tests on the dirty working tree. `git diff --check` passed
for those files and the two fixture repairs below. This is not a full regression.
Review the exact changes, add boundary cases if warranted, run focused tests in a
fixed isolated source graph, update the operator and developer manuals and plan,
then perform the required whole-document editorial review and checks before any
focused commit and push. Preserve unrelated dirty files when staging.

## Installed package

The earlier timeout was traced using an isolated synthetic provider: after four
approved effects, a legitimate host reference message became the last input; the
fixture misread that as a new user request and repeated the effects to the step
limit. `dev/verification/package.exs` now excludes reference messages only when
choosing the synthetic response, requires exactly the four expected started IDs,
and reports errors promptly. `priv/demo/extensions.exs` now validates the current
reference selection and preserves it on replay. Both changes are uncommitted.

The fixed archive candidate, source tree `7790db66a9da0c90dbc1a8e5a5dbe2caee9a47b4`,
built successfully with PDF enabled. The installed check passed the permissions,
upgrade, shell, terminal and synthetic 100-record/100-query explicit-memory
fixtures, and the repaired extension demo; it then failed in the parallel
subagent demo at `priv/demo/subagents.exs:302` with a journal match error. Inspect
`_build/enhance-verification-52d8ac809e70/installed-package-candidate.log` and
the actual journal semantics before changing its assertion. It is not a passing
installed-package check or a release candidate: the candidate's synthetic Git
source lacks a commit and its documentation source ref falls back to `v0.1.0`.
Original timeout, tmpfs quota failure, and intermediate package failure logs remain
under the same `_build` directory. No inference was used by these fixtures.
Rebuild and verify a candidate bound to a real reviewed commit after corrections.

## Running baseline and remaining gates

Both full regressions finished with failures; see the subsequent continuation
and [classification](corrected-full-regression-followup.md). Neither session
88188 nor 11421 is still running. Earlier corrected focused tests passed 204;
do not report those as a full pass. The corrected run used the previously
approved outside-repository Btrfs TMPDIR `/var/tmp/ipse-enhance-tests.slGYaYCG`.

Host `7.2.11-arch1-1` remains outside the production native storage profile;
7.2.10 is admitted. The writeback/allocation proof, current-root and inference
send-barrier gaps, protected consent and eligibility, capacity and usable notes,
document ingestion, P30 experiments, platform and human journeys remain open.
Do not claim native qualification or protected publication from refusals. No live
model calls or downloads occurred during this continuation. Preserve prior
allowance accounting and all receipts described in the preceding handoff.

After implementation and required verification, perform an adversarial audit,
review operator and developer documentation as whole documents, run the required
checks, commit and push focused verified changes, and prepare a review prompt.
Do not declare P30/P31 complete while these gates remain open.

## Subsequent continuation

The installed parallel-delegation failure was reproduced against the bundled
runtime. `Session.close/1` appends one confirmed `lifecycle_epoch_closed` record;
the fixture compared the resumed journal to its pre-close state. The uncommitted
`priv/demo/subagents.exs` repair checks the exact prior prefix and the single
confirmed close record, then requires the post-close journal to remain unchanged
on idle resume. The source demo passed against the bundled runtime without a
model service. This does not qualify the rebuilt package by itself.

The isolated draft/source/MCP selection passed 58 tests (seed 20270326). Added
parser boundaries for blank, reserved, 32 KiB, oversized and invalid UTF-8 inputs;
the updated draft acceptance file passed 8 tests (seed 20270327). Operator and
developer manuals now describe inline replacement and its replay binding; the
repository documentation checker passed with 0 errors. These tests do not qualify
P31I or establish whole-milestone completion.

The rebuilt local candidate uses synthetic tree
`38bc6d7677e48092c9c4fc191713f4b3176974db` and includes those changes and the
fixture repairs. Its build exited 0; the installed verification is currently
running under unified-exec session **53032**, logging to
`_build/enhance-verification-52d8ac809e70/installed-package-candidate-repaired.log`.
Poll that handle for terminal status before repeating the check. It is still an
uncommitted synthetic source graph, not a distributable release. Full regression
session **88188** also remained live when this note was written.

The installed verification subsequently completed **exit 0** for that synthetic
candidate. Its archive SHA-256 is
`f9955f4182b1bebcb7ad63a47e8c87fc6799dfc9654ff4429373300c96f7cdc1`.
The full log records all installed scenarios, including the repaired delegation
fixture and 100-record synthetic lexical memory proof. This does not qualify a
semantic model, the native storage profile, a real source-commit identity, a
release, or P30/P31. `mix format --check-formatted` passed for the isolated tree,
and `git diff-files --quiet` confirmed the candidate's tracked bytes matched its
private index. The full regression session 88188 was still running at this point.

A later continuation strengthened the inline replay fixture: it now rejects
changed command bytes even when they trim to the same text, altered proposal,
revision or observation digest, an unexpected event field, and observation reuse
across input and replacement. The isolated updated acceptance suite passed 8
tests (seed 20270328; source tree
`ac0024b652f3253be9ae35c34a1ceab6602c2437`). This tree differs from the
previously verified package candidate only in that test fixture; the reported
archive hash and installed proof above still identify the earlier tree.
The plan records inline replacement as locally controlled, not complete.
The native operator PTY fixture additionally checks that a different process
cannot consume a valid inline replacement ticket, and that a stale revision
refuses and consumes the staged ticket. The updated isolated acceptance suite
passed 8 tests (seed 20270329, source tree
`82d7da1b4174aea371bf125a91b44b6353e1c37b`). The extra changed file is
`test/support/draft_operator_pty.exs`. These remain uncommitted controls.
The PTY driver was then extended by a separate input so the existing next-line
replacement stale-revision check remains exercised with a fresh ticket alongside
the new inline check. All 8 acceptance tests passed again (seed 20270330; tree
`613494cdcb946d5e516c5f603f59355241e50550`).

The later [capacity-controller review](managed-v3-controller-followup.md)
records a fixed false-clean supervisor-exit condition, 18 passing synthetic tests,
and a separate unresolved directory durability concern. The driver and its tests
were already untracked; no native capacity workload was run.

The original regression (session 88188) subsequently ended with exit 2: 2,335 of
2,645 passed, 310 failed, 4 skipped and 36 excluded, in 1,588.7 seconds. Its log
is `full-test.log`; the unsupported native profile and repository-contained TMPDIR
both limit interpretation. A corrected full run is active as unified-exec session
**11421**, seed 20270402 and max-cases 2, logging to `full-test-corrected.log` in
the same verification directory. It uses the approved external Btrfs TMPDIR and
fixed private tree `2e6600e06ae118a431f52e2a70cf18dac57ed0ca`. Poll that handle
before restarting or changing its source graph. This graph excludes the separate
untracked capacity and inference experiments, and native support remains open.

The [Mint text contract follow-up](mint-text-contract-followup.md) records a
local validation-parity change and 21 passing synthetic provider tests. The
experimental inference path remains unwired, and its authority and cleanup
barriers remain open. The shared `lib/ipse/provider.ex` change is also uncommitted.

The [dispatch-admission follow-up](dispatch-admission-followup.md) records a
live/replay consistency guard, its synthetic owner-process positive and negative
controls, and 30 related passing tests. Protected positive dispatch did not run;
this uncommitted source change is outside the active corrected full-run graph.

The [P30C coverage follow-up](p30c-coverage-followup.md) records an uncommitted
pure-policy repair: unavailable or incomplete eligibility no longer returns a
partial candidate pack as an action. An isolated graph passed 56 focused tests
and forced strict compilation; authenticated coverage, integrated consumer and
adversarial review remain open. The active full regression does not include it.

The [managed-reference marker follow-up](managed-reference-marker-followup.md)
records a reproduced malformed reference projection and an uncommitted
fail-closed repair. Both working-tree and isolated runs passed 65 focused tests;
reference-aware withdrawal, live freshness and the full integrated path remain open.

The corrected full regression, session 11421, subsequently exited 2; do not
poll or restart it as an active run. It reported 2,390/2,651 passing and 261
failures, with 36 excluded. The [corrected regression record](corrected-full-regression-followup.md)
retains source identity, first-failure classification and limits. The current
working-tree changes remain outside that frozen graph.

A provisional [review prompt](review-prompt-working.md) is ready for the eventual
handoff. It is not an audit result and must be updated against the final source,
implementation and evidence before the requested post-implementation review.

The managed-reference follow-up now also records reproduced support-set and
expiry-extension gaps and their uncommitted conservative fixes. The updated
isolated graph passed 67 synthetic tests and forced strict compilation; live
receipt authentication and authority remain open.

The latest managed-reference continuation also refuses promotion of an originally
suppressed or unavailable occurrence to eligible by a same-occurrence refresh;
an explicit withdrawal remains possible. The isolated graph passed 68 synthetic
tests and forced strict compilation. See the updated
[managed-reference record](managed-reference-marker-followup.md) for source
identity and the pre-fix reproduction. The capacity-controller follow-up now
includes directory synchronization and 20 synthetic tests; native durability and
the helper path race remain unqualified. The Mint follow-up now records 64
synthetic tests, including an old egress-gate TLS wait race; it remains unwired.

The supported-host question remains pending with the developer. Continue
independent implementation and review without assuming a reply or weakening the
7.2.10 admission rule. The managed observation design identifies the next
integration gap: same-view value and witness, authenticated durable receipt and
result binding, replay and propagation, worker confinement, and current authority
held through the actual send/effect are all required before exposing protected
data. Read [the observation design](observation-lineage-design.md); the private
patches described there are incomplete and must not be promoted as authority.

An uncommitted snapshot observation change replaces the arbitrary public probe
record with a bounded zero-value selector. The directory test passed 11 tests
on the working tree (seed 20270408); the new corruption and root-change native
tests both stopped at initial `collection_filesystem_unsupported` on this host
(seed 20270409), before exercising the change. Run them on an admitted host,
including owner-loss fencing and absent-root cases, before accepting this change.
The working-tree strict compile and documentation checker passed. A subsequent
synthetic sealed-cache ReadView test and the directory suite passed 12 tests
(seed 20270422); this checks selected values, accounting and busy behavior,
but does not execute the native root recheck. It does not wire observation into
Session or establish live authority.

The uncommitted [DOCX v4 follow-up](docx-text-structure-followup.md) fixes
misplaced text being reported as complete and paragraph tab-stop definitions
being emitted as content. It passed 25 synthetic tests in a fixed graph and a
separately built corpus artifact reported the new recipe. Real Word fidelity,
source acquisition, migration and whole-milestone acceptance remain open.

The inactive [operator-only planning MCP declaration](planning-mcp-operator-followup.md)
binds an allowlisted tool to reviewed endpoint and descriptor hashes. Its
synthetic Session control confirms draft MCP calls still refuse. Integrate
operator review, approval, current revalidation and journal/replay checks before
allowing dispatch; the helper alone is not authority.

The [planning MCP replay follow-up](planning-mcp-replay-followup.md) adds an
uncommitted restricted-start binding and synthetic tamper controls. It has no
live producer. Resume-mode activation, stopped-lifecycle recovery, current
approval and revalidation remain open; do not enable dispatch on this check alone.
The [configuration-binding follow-up](planning-mcp-config-binding-followup.md)
now rejects a Session resume when saved declaration data is removed or changed
while the configuration fingerprint is retained. The later [mode checkpoints](planning-mcp-mode-checkpoint-followup.md)
record inherited modes at startup. The later [ordinary-call binding](planning-mcp-ordinary-binding-followup.md)
adds checkpoint-bound ordinary MCP intents. Live restricted approval,
revalidation, interruption and production dispatch remain open.

## Latest continuation: synthetic declared MCP reads

The preceding inactive-dispatch statements are historical. The uncommitted
[live-read follow-up](planning-mcp-live-read-followup.md) records the current
Session implementation, a repaired MCP lifecycle source mismatch, and its
synthetic tests. A working-tree PTY test now carries MCP evidence through draft
acceptance and inference; the aligned snapshot passed 45 focused tests as recorded
there. A subsequent injected source-reference failure exposed dispatch after
lifecycle recording stopped; the follow-up records the repair and 46 passing
focused tests. A controlled after-dispatch result-source failure then showed
acceptance refusal and no replay after resume; the expanded snapshot passed
47 focused tests. It does not establish P31I acceptance. Next, audit the entire authority and replay path,
and complete the remaining P30/P31 work and host-dependent gates above. Preserve
the dirty worktree and all evidence; do not run capacity workloads or relax the
native profile. The [review prompt](review-prompt-working.md) remains provisional.

The latest replay continuation also rejects duplicate MCP starts for the same
request and call across epochs; the [follow-up](planning-mcp-live-read-followup.md)
distinguishes the synthetic validator reproduction from actual replay and
records the fixed-source tests. Deferred planning decisions and their explicit
later save transition are not implemented.

The DOCX follow-up now records a v5 repair for runs nested in property containers
being emitted as complete paragraph text. Its two synthetic document suites
passed 27 tests on an isolated source snapshot including a freshly built corpus
artifact probe. Real Word fidelity, installed acquisition and index migration
remain open; the frozen independent qualification set was not run.

The managed-reference follow-up also records a same-floor anchor substitution
reproduction and conservative consistency repair. An isolated snapshot passed
69 focused tests and strict compilation. This does not authenticate advancing
floor lineage or close the protected-read and send-time authority gaps.

The [current-source P30 decision check](p30-current-decision-followup.md)
passed 138 focused synthetic tests and strict test-environment compilation on
a private snapshot of the dirty source. A PDF-enabled local package from the
same code plus complete documentation passed the generic installed-package
verifier and a separate synthetic installed decision Session probe. Its source
ref falls back to `v0.1.0`, so it is not a release candidate. This is not a full
baseline, live account check, qualified consumer or milestone acceptance.
The decision probe is now also a finite `dev/verify.exs` scenario; source and
installed modes passed with the same synthetic example artifact and unchanged
inventories. The scenario also checks denial and in-flight cancellation without
replay. See the current-source P30 record for its exact limits.

The [planning CLI continuation](planning-cli-followup.md) adds a startup flag
and actual effective-ceiling display, retains the ceiling on resume and disables
edit grants under it. A fixed snapshot passed 101 focused tests and strict
compilation. In-session transitions and deferred-decision saving remain open.
The subsequent synthetic CLI MCP journey exercises an operator declaration,
explicit approval and a fresh approval after resume; the expanded snapshot
passed 102 focused tests. Live server and whole-platform acceptance remain open.
The later planning CLI record documents and repairs a case where a ceiling
selected on resume was lost on a subsequent resume. It records a locked
checkpoint, synthetic multi-resume tests and the limitation for old unrecorded
restrictions; an in-session transition is still absent.
That record also describes a repaired MCP replay failure after a resumed draft
was cancelled. Its expanded fixed snapshot passed 135 focused tests and strict
compilation; live and whole-milestone gates remain open.

## Later working-tree continuation

The latest [planning CLI record](planning-cli-followup.md) supersedes the
earlier replay and grant details above. A legacy resume now checkpoints paused
or disabled knowledge ceilings. MCP reconstruction tracks restricted resume
checkpoints even without declared planning reads, retains draft restrictions
until cancellation or consumption, and refuses work between a checkpoint and
its new MCP epoch. The permissions layer refuses to issue or apply edit/shell
session grants under restrictive or invalid modes; a temporary draft retains
the preexisting grant for use after cancellation. The record distinguishes the
synthetic regressions, actual-Session control and the working-tree suites from
full acceptance. A separate strict compile attempt failed to acquire Mix's TCP
filesystem lock with `:eperm`. An in-session planning exit remains unimplemented.
New version-2 checkpoints preserve local and inherited ceilings on same-owner
resume, but old version-1 checkpoints can have already collapsed their origin;
neither mode field alone authorizes removal of a restriction. Deferred
decision capture and explicit revalidated save also remain open.

The [DOCX continuation](docx-text-structure-followup.md) now uses
`ipse-documents-v6`. It refuses duplicate recognized strict/transitional
attributes after a synthetic contradictory visibility value was exposed as
complete text. The working-tree document suites passed 28 tests including a
freshly built artifact probe. This supersedes the v4/v5 status above; real Word
fidelity, acquired-source integration, index migration and the untouched frozen
independent qualification set remain open.

The [P30C coverage continuation](p30c-coverage-followup.md) now returns a null
selection when eligible records are nonempty but no usable pack is established,
except for a proven zero-byte allocation. Synthetic tests and the separately
built Knowledge artifact exercise this in both planner modes. This is still an
untrusted pure policy, not protected consumer integration or qualification.

The provisional [planning transition implementation notes](planning-transition-design-followup.md)
trace staged input, resource quiescence, replay and MCP epoch constraints. A
working-tree native-terminal `/plan` entry now has local synthetic Session,
receipt, resume, MCP epoch and PTY controls. The affected CLI, Session, draft,
permissions and MCP selection passed 152 tests after a resumed-draft replay fix.
Local `/plan exit` now has focused replay, Session, synthetic prefix-recovery,
prior-reader and PTY controls; the affected selection subsequently passed 155
tests with exit implemented. New explicit CLI startup selections now carry
local provenance and can be exited; old ambiguous selections remain restricted.
Child configuration drops the parent-only startup marker. The latest affected
combined selection passed 166 tests; a subsequent 45-test selection covered
resuming a fresh startup marker and configuration/delegation. Deferred save,
actual crash-boundary and resource qualification remain open.

A [local embedding transport smoke](local-embedding-smoke.md) used one synthetic
input against the already installed Qwen3 0.6B embedding model and obtained a
validated 1,024-dimensional vector. This was a direct provider call, not a
Session, offline, retrieval-quality or protected-storage qualification.
An [embedding input-binding repair](embedding-input-binding-followup.md) now
rejects returned vector pages whose canonical input digest differs from the
dispatched input. Corpus/graph/storage controls and a separately built corpus
artifact passed; model-weight identity and authentication of historical rows remain open.
Corpus now also treats a stored vector whose input digest does not match the
current raw chunk as missing at query time, without deleting the row. A later
versioned preprocessing recipe and model-weight identity remain open.
The credential-free `./bin/ipse demo` also completed using its temporary demo
workspace and the current operator configuration and normal session directory;
this invocation was not isolated from the existing operator configuration.

All of these changes remain uncommitted in the shared dirty worktree. Their
focused test totals are separate runs, not a current-source full regression.
The native profile, protected lineage and current-authority barriers, P31 core
capture/recall and capacity, P30 experiments, real Word and installed journeys,
human/platform evidence, full documentation review, final adversarial audit,
focused commits and push are still required. The [review prompt](review-prompt-working.md)
is provisional and must be rewritten against the final reviewed source.

The subsequent [working-tree regression](working-tree-regression-followup.md)
passed 215 selected synthetic tests, a forced strict test-environment compile
of 152 modules, the ordinary strict compile and repository formatter check after
local TCP access was approved. This supersedes the earlier strict-compile
failure, not the failed full regression or any native, live or platform gate.
The developer confirmed that no host running the admitted 7.2.10 profile is
available, and then requested adapting gates to available resources. The plan
now allows qualified completion for the tested scope while unavailable platforms,
accounts and human journeys remain explicitly unverified. Storage, authority
and safety evidence is still required before affected capabilities are enabled.
The [available-host diagnostic](available-host-diagnostic.md) records a full
private-helper run on 7.2.11: 2,788 passed, 4 skipped and 36 excluded. It does
not qualify the production profile. A separate follow-up with an existing PDF
parser passed five tests, including the four skips. The
separate Linux sandbox fixture run passed 17 cases. The
production profile remains unverified on this host. Continue independent
implementation and report that qualification separately.

The subsequent [embedding admission continuation](embedding-input-binding-followup.md)
also checks each new vector against its source chunk before Store commits the
projection. A synthetic pre-fix mismatch reproduced; State and MCP controls now
reject it without changing stored records, and a constructed historical row
remains readable and reindexable. Model identity, source authorization and the
versioning of future preprocessing remain open. This work is uncommitted and
does not qualify P31 retrieval or the production native profile.
A synthetic two-artifact upgrade test now exercises the mismatch, partial
fallback and reindex through fresh real Sessions and the same isolated State
binding. The first artifact is deliberately altered for the fixture; it is not
a released historical binary. See the same record for scope and limitations.

The [planning transition record](planning-transition-design-followup.md#journal-exhaustion-at-a-transition-boundary)
now covers an actual writer-exhaustion failure between a checkpoint and its
declared-read epoch. MCP replay accepts a correctly sealed final receipt for
inspection and still refuses later work; Session reopening remains prohibited.
Before-first-epoch and pre-start cases also have synthetic replay controls.
This is not a power-loss test or P31I completion.
Subsequent controlled Session-death tests cover the checkpoint, entry receipt
and declared-read epoch boundaries, including repeated recovery and stale input
fencing. They use a test-only writer proxy and synthetic input; see the same
record for their limits.

The [synthetic P30 shadow control](p30-current-decision-followup.md#synthetic-planner-to-session-shadow-control)
now runs the actual Knowledge planner in a fixture worker through Session
approval and local decision transport for selection and assessment. The worker
has no publication capability and its supplied facts remain untrusted; this is
not a protected consumer or a frozen experiment. The affected decision selection
passed 102 tests; real candidate capture and source/current-authority binding
remain prerequisites for P30C/D/E.

The managed-reference pure projector now refuses refreshing an ambiguous
version-1 null-record dependency across a changed root. This fixes a synthetic
stale-result counterexample but also refuses old changed-root projection events
of that shape on replay; see the [compatibility record](managed-reference-marker-followup.md#legacy-null-record-refresh).
The projector is still not wired into Session. Six protected Session controls
in the expanded run stopped at the unsupported filesystem and did not exercise
their positive journeys.

## 2026-10-27 DOCX continuation

The working-tree v7 recipe now extracts referenced header and footer parts with
region locators and explicitly partial page-layout coverage. See the
[follow-up](docx-header-footer-followup.md) for synthetic tests and limitations.
This is not real Word fidelity or a complete document-ingestion journey. The
qualified-scope rule recorded above applies to unavailable hosts and services;
it does not turn unimplemented integration into a pass.

The subsequent [capture-fragment repair](capture-fragment-followup.md) sends
partial source selections to pending and makes the host reject them as literal
publications. Whole-event quoted or pasted text can still be misclassified, and
existing records have not been reclassified; do not treat this as complete
intake or current-authority enforcement.

The unwired managed-reference projector now requires the same Collection root
for every dependency version. Legacy record or absence outputs can depend on
root metadata even when their selected subject is unchanged. See the
[compatibility record](managed-reference-marker-followup.md#legacy-record-and-absence-output-may-depend-on-root-metadata):
old changed-root projection events now refuse replay, and no production current
authority or automatic migration follows from this repair.

An internal [record-only observation experiment](record-observation-followup.md)
and pure version-4 dependency provide a candidate for reusing an unchanged
record after an unrelated write. They are not Session-wired or authenticated;
suppression history, complete lineage and the actual send barrier remain open.

## Pause and resume checkpoint

The developer requested a pause on 2026-10-27. Resume P30/P31 in this agent;
the developer declined independent subagents. Preserve the extensive uncommitted
and untracked work, including diagnostic evidence. No milestone has been declared
complete, and the working review prompt is provisional.

The latest managed pending-capacity work is recorded in
[pending-capacity-followup.md](pending-capacity-followup.md). The host normalizer
enforces the pending count and encoded-byte limits under the Collection lock;
synthetic real-normalizer and cross-VM tests passed on the private test-only
7.2.11 helper. A later saved-consent Session fixture passed at 63 pending records
and refused at 64 with settled consent, replayable journal and unchanged root
(seed 46573). A 50-test integration selection passed (seed 46574), and removing
the host capacity call in the diagnostic copy made the new test fail as expected
(seed 46575); restoration passed (seed 46576). It directly seeds synthetic records
and uses the private helper, and is not a production storage or real user intake
qualification. A synchronized two-Session saved-consent control passed with at
most one publication from the same 63-record generation (seed 46580); both may
be refused by contention, and a fresh attempt must then succeed. Details and
earlier failed fixture assumptions are recorded in the capacity follow-up. The
full Session file passed 24 tests (seed 46581); a subsequent strengthened root
witness assertion and the race control passed together (seed 46582). The
developer authorized adapting gates to available resources,
but the production native storage profile remains unqualified on this host.

The full isolated diagnostic completed with 2,837 passing, 4 skipped and 36
excluded; it predates the latest retention, queue and planning changes and used a
private test-only profile override. The main working-tree full run failed on the
unsupported filesystem. See the diagnostic records for exact scope and limitations.
Current-source full checks, the adversarial post-implementation audit, the required
whole-document editorial review, and final handoff remain outstanding. Commit and
push focused changes only when a genuine subgoal is complete and its checks pass.

On 2026-10-28 an instrumented native-owner test killed the helper after a partial
staged write and checked retained allocation and reclamation on the available
tmpfs and Btrfs mounts. The transaction file passed 21 tests on tmpfs (seed
46586), and the focused Btrfs control passed (46587). See the
[kernel recovery record](kernel-profile-recovery.md#partial-stage-owner-death-control)
for source hashes and limits. This is not quota, crash-durability or native
profile qualification. The capacity workload must not run until the recorded
helper-pinning, review and workload safety gaps are resolved.
An escalated read-only check found the current UID cannot write loop-control or
device-mapper control, so it cannot use those devices directly for the missing
Btrfs writeback-failure test. No device was modified; other possible methods
have not been ruled out.

The working-tree DOCX v10 recipe rejects missing, ambiguous or misplaced
annotation identities and adds a point location for a unique visible body
reference only when the body segment is emitted. Annotation-bearing documents remain partial while comment ranges and
other stories are unresolved. See the [annotation follow-up](docx-annotation-followup.md)
for the reproduced errors, tests and scope. This is not Word interoperability,
installed ingestion or P31F acceptance; older extraction indexes need explicit
re-extraction or requalification.

## Current full diagnostic in progress

On 2026-10-28 a new fixed-source diagnostic graph was created at
`_build/current-full-v10-NbLWaesE`, with source tree
`cdd4b9ada06a19337ac430e8c459155f5c2af354` and test-only-profile tree
`4c33c89f7aaeda8d6ae3ee1e905c5953f603b7ff`. Its private helper SHA-256 is
`b7ea344b9b631208e9f766885d781cf3753d8569ed6a55f08fbe610fa28528bb`;
only the profile source differs between these synthetic commits. Dependencies
were copied into the graph, and `MIX_ENV=test mix compile --force
--warnings-as-errors` succeeded; dependency compiler warnings were emitted.
The full `mix test --seed 46602 --max-cases 2` run started with
`TMPDIR=/var/tmp/ipse-current-full-v10-x4iNz8Gh`; output is
`_build/current-full-v10-NbLWaesE/_build/full-regression-46602.log`.
The run exited 2 after 1,972.5 seconds: 2,856 of 2,860 tests passed, four
failed, four skipped and 36 excluded. All four recorded failures were Knowledge
setup tests missing the bundle described below. Its log SHA-256 is
`4f172d782a1aef10aa2172c430f56d49d1b158f755e41ab4db7f7be3cf1e734b`, and
the synthetic graph's tracked worktree was clean after the run. The test-only kernel override is not production
profile, durability, lifecycle or platform qualification. The graph was frozen
before this note and any later working-tree changes.

The running full diagnostic has reported four Knowledge setup failures with
`extension_bundle_unavailable`: this graph was compiled but its ignored inert
bundle was not built. Do not alter it while the run is live. A separate graph
`_build/bundle-control-dZ4plbBp` cloned the same frozen tree, compiled it, ran
`MIX_ENV=test mix run --no-start dev/build-bundles.exs`, and passed all seven
Knowledge setup tests (seed 46610). Its catalog and artifact-manifest SHA-256
values are `afbba186a20e2143687dc6b421f04445206dde30025ad7b30c39afa98dd8c047`
and `2b4029e191cbbe3410e2ed4f8a3dfa8fa6f607aa1edca10eaa8de389842f80f5`.
This identifies the first failure in those controls; the original full run failed.
A future full graph must build the bundle before testing and include the newer
V2 capacity work. No profile or test gate was weakened.

A corrected next-run graph is prepared at
`_build/current-full-corrected-KJqSdscV`. Its current-source tree is
`27653434e52376e686b3386ebb54d38139578291`; the private test-only kernel
profile tree was `ca04edff2b68a777611ea09884e3c350445f7b54`. A subsequent
legacy resume-test update produced tree `2c5f6e88401a5c082943a4bd18833dd0514b15d1`.
It includes the V2
capacity and pending-observation changes and the copied-history test as of
preparation. Dependencies were copied; strict test-environment compile succeeded
with dependency warnings, and the inert Knowledge bundle was built. Its catalog
and manifest hashes are
`567590bc3403ddf2e6b128675f9d0e079512bfcce473eeb79a34b6464aa2c3de` and
`2fe6f8cff0cc832fc53ab8c88cb24912ec11d2ecf801642d524754913fa9c3b4`.
The existing optional PDF parser binary was copied with SHA-256
`85cde09bd8783ef99427bcd07f5708b33b9e46138e58288d2790eed1544b6556`;
its source tree matches the earlier build graph. Knowledge setup and both PDF
test files passed 12 tests (seed 46617). The legacy normalizer, signed V3
publication and SourceIndex selection also passed 61 tests (seed 46618). The
separately excluded Linux sandbox selection passed 17 tests (seed 46619; 22
other cases excluded). Those controls used
`/var/tmp/ipse-corrected-full-ZgUw7LFR`; the fresh full-run scratch directory is
`/var/tmp/ipse-corrected-run-379NTOFt`. The corrected full run started with
`mix test --seed 46621 --max-cases 2`; output is
`_build/current-full-corrected-KJqSdscV/_build/full-regression-46621.log`.
Tool session 50684 and BEAM PID 2760743 were live at start; verify the working
directory before relying on a PID. The wrapper writes
`_build/full-regression-46621.exit` only after Mix returns. Poll the same handle
or inspect authoritative process state; do not restart on an observation timeout.
Record any later working-tree differences from this graph.
This preparation is not production native-profile or parser-fidelity qualification.

The internal [pending proposal observation](pending-observation-followup.md)
now verifies a stored proposal and signed V3 format/live/anchor pages at one
checked root, including the recipe-selected override check. The related private
diagnostic selection passed 65 tests (seed 46614). This is historical integrity
only: source proofs have not been authenticated anew, and current consent,
expiry, actual display and acceptance are not established. It is not wired into
Session or a review workflow. The current corrected full diagnostic snapshot
includes this component, although an earlier snapshot did not.
Stored proofs identify a Session but not its selectable state directory; a
cross-session reviewer must not guess the journal location or accept a copied
historical prefix as proof of the current source. See the follow-up for the
remaining location, locking and durable redaction requirements. A synthetic
copied-window/redaction control passed with the SourceIndex suite (19 tests,
seed 46616); it does not establish durable cross-session redaction.

After the earlier full diagnostic snapshot was frozen, the working tree added a shared
host pending-capacity check to legacy version-2 managed proposals under the
`pending.` prefix, retaining the V3 check and leaving other legacy prefixes
unchanged. A synthetic pre-fix regression accepted normalization at 64 records
(seed 46603);
boundary and other-prefix controls passed (46605), as did a saved-consent Session
control with a checked unchanged root on the private test helper (46606). The
expanded selection passed 66 tests (46607); removing the V2 check in the isolated
copy made the Session test fail as expected (46608), and restoring it passed
(46609). The shared two-Session contention control passed for V2 and V3 (46611).
The corrected running full-suite snapshot includes this change; direct
Collection writes, imports and other prefixes still require their own rules.

After the corrected snapshot was frozen, the real Knowledge worker Session test
was extended to reconstruct the same Session's source window and revalidate a
stored pending proof alongside signed observation. Both synthetic unattended
input and PTY cases passed on the private helper (seed 46623). An in-memory
redacted-index refusal was then added and both cases passed again (46624); see the pending
observation follow-up for the exact test hash and limits. This new test is not
in the running full-suite snapshot and establishes neither cross-session source
authority nor a lock-held display or dispatch.
The fixture was then extended to copy actual synthetic journal and source-page
files while the Session was idle. Both copies reconstructed the same proof and
both parent tests passed (46635). After in-memory redaction of the original
reconstruction, the unchanged copy still accepted it (46636). This demonstrates
ambiguous candidate paths, not durable redaction or protected rollback detection.

An actual separately built worker and saved-consent Session also demonstrated
the unresolved whole-event attribution failure: synthetic PTY input explicitly
identified as a third-party report still produced a current literal note (seed
46625). See [the capture follow-up](capture-fragment-followup.md) for the
counterexample and isolated fixture hashes. This is evidence against enabling
automatic current recall, not a successful attribution test.
The updated Session regression passed `mix format --check-formatted` and the
documentation checker reported 666 Markdown files, 5,323 local links and zero
errors after the plan and review-prompt updates.

The uncommitted DOCX extractor is now recipe v11 and binds a bounded, unique
same-paragraph comment range to visible-text byte offsets. The synthetic
document suites passed 32 tests (46629); a separately built artifact passed the
new range probe (46630), and a later hidden/deleted text control passed (46631).
The first suite attempt (46628) used a stale v6 test and failed; the running full
diagnostic predates v11. See [the annotation follow-up](docx-annotation-followup.md)
for source hashes, unsupported range cases and real Word limitations.
An additional pre-fix test exposed dangling range markers incorrectly claiming
complete coverage (46632); after the partial-coverage repair, the current two
document suites and artifact probe passed all 32 tests (46633).

Native question answers now take the pending path in the Knowledge worker and
the host independently rejects them as literal notes. A synthetic actual V3
test demonstrated the old host published a forged literal (46642), while the
repaired host kept the root unchanged and accepted a pending proposal (46644).
See the [capture follow-up](capture-fragment-followup.md) for unit tests,
snapshot identities, historical-read caveats and remaining attribution work.
This change postdates the running full regression snapshot.
A later synthetic PTY, built worker and saved-consent Session confirmed pending
publication for an actual native question answer. A deliberately weakened
worker published it as current with the old host check (46651), while the
restored host refused and the three parent Session tests passed (46652).
An extracted diagnostic archive also passed a pure synthetic guard probe using
the packaged Knowledge and host modules; the capture follow-up records its hash
and the distinction from an installed terminal publication.
After these host and test changes, working-tree `mix compile --warnings-as-errors`
and repository-wide `mix format --check-formatted` both exited successfully.

The corrected prior full diagnostic (seed 46621) completed with exit 0: 2,870
passed and 36 excluded in 2,007.7 seconds. Its log SHA-256 is
`bc67aa509b610643c5cd35f986f386548ed45419fc5d6cea396cf44703ec9654`.
It used the private test-only kernel helper and predates the v11 DOCX and
native-answer changes. The graph also omitted tracked `bin/ipse` and
`third_party/APACHE-2.0.txt`, so it is not a complete-source or production-profile
qualification.

A new current-source diagnostic snapshot is frozen at
`_build/current-next-xRcQ2ygb`, with synthetic private-index tree
`614691c4bad7da7b99f744bbd9817f1a5f742516`. It copies current source, tests and
docs, but retains the private 7.2.11 test-only profile and helper
`b7ea344b9b631208e9f766885d781cf3753d8569ed6a55f08fbe610fa28528bb`.
Replacing that one profile file in a separate private index with the production
source yields tree `35ce1c2e8e090779a1aba7f17af2903f82e14016`; the running
diagnostic uses the test-only tree, not that production tree. The diagnostic
index matched its source immediately before the run.
The operator permission manual and this evidence record were updated after the
snapshot, so compare documentation separately before final acceptance.
`MIX_ENV=test mix compile --force --warnings-as-errors` passed, and the inert
bundle catalog was rebuilt with SHA-256
`7a351f3b32935bea2c89eaffef20954adb22f6fd49eeb3330da0ef59acab0548`.
The full run started as unified-exec session **71517** and BEAM PID 2966601
(verify its working directory before relying on a PID), with seed 46653,
`--max-cases 2` and scratch `/var/tmp/ipse-next-full-ixvMIJvI`. Its log is
`_build/current-next-xRcQ2ygb/_build/full-regression-46653.log`; the wrapper
writes `_build/full-regression-46653.exit` only after Mix returns. This run was
intentionally stopped when the same missing `bin/ipse` and Apache license were
discovered in the copied graph. The log ends with SIGTERM and has no ExUnit
summary; although the BEAM returned 0 and the wrapper recorded 0, this is an
interrupted run, not a pass. Its log SHA-256 is
`ec4848e81a0643cb4737b99c8523dfb39066eba0db0d852ee30cb11250f800d5`.
A corrected source snapshot and fresh run are required.

Separately, `_build/production-build-Au0AOr9b` copied the current source with
the unmodified production native profile and ran `./dev/build.sh` successfully
with already checked-out dependencies and `HEX_OFFLINE=1`. A first attempt
failed because the isolated Hex home lacked a registry cache; the retry copied
only the installed registry cache and succeeded. The build emitted dependency
warnings, strictly compiled 154 project files and built the inert bundle. Its
private source-index tree is `3e2f8294a2bdde80c0d16f8f85fdf1ec46fc457f`,
production helper SHA-256 is
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`, and
bundle catalog SHA-256 is
`fbdc3bb73322f75d83caa20e3fb3110305de76ae132bfead454d7c7bc3aab0f6`.
This used the default parser-free build and did not verify dependency fetching,
an installed package, or storage qualification on kernel 7.2.11. Source and
test directories matched the working tree when the build completed; later
documentation changes are outside that snapshot. This first build copy also
omitted the tracked launcher and Apache license, so it is incomplete and must be
repeated on a complete source snapshot.

After copying the two omitted files, the same isolated production graph passed
`./dev/build.sh` again with the offline cache. All tracked non-documentation
files matched the working tree at that point. Its updated private-index tree is
`a2db6b71922beaffab77d268870bdc8fee99737b`, the production helper SHA-256
remained `891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`,
and the newly rebuilt bundle catalog SHA-256 is
`25bb48c32204caed3b4095e072e1b83ff8c6eb35ceda9b62f5c67178f07e1f24`.
An `env -i` isolated-home `./bin/ipse demo` on this graph exited 0; it was a
scripted demo with no live model. Documentation differs from later handoff
edits, and the build still does not qualify protected storage or a package.
An isolated default `./dev/package.sh` build, including the approved PDF parser,
completed with exit 0 in this production graph using copied offline Hex/Cargo
caches. The archive is `dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`,
SHA-256 `213c997d689f14758d7e9f3bb9a4879701514324139633fee8653323c8c34c9f`;
its generated checksum file verified successfully with `sha256sum -c`.
The package log SHA-256 is
`dc8d46b92fad07bbdae72bbf13757d226e6b585c8687e98d3261fced8786beec` and
the built PDF helper SHA-256 is
`b9f9a3148dfa1bf4bff8ce8861124c9be542d2f944c9326893a7dc6a18420327`.
The package's documentation `source_ref` is the copied graph's Git HEAD
`4dc1f7c70d05afedb318f4163656885cfeb6f396`, not an identity for the dirty
working tree at `668e6a3`; the archive is diagnostic and is not ready for
distribution. No release was published.

The first installed-package verifier (session 35174) exited 1 after several
successful CLI and synthetic memory checks; its synthetic conformance turn
reported an error before model dispatch. Its log SHA-256 is
`f03025fc25eb1fe762c5992ed680398474f5dd9ce88cc787ad89415bcb20fa96`.
That run put scratch inside the source graph. A retained synthetic reproduction
confirmed the nested workspace loaded repository instructions and failed because
the context exceeded its limit with compaction disabled; this supports, but does
not by itself prove every detail of, the first failure. The source conformance
suite separately passed 11 tests (46655). Do not count the failed package run as
a pass.

The same exact archive was rechecked with scratch outside the checkout at
`/var/tmp/ipse-installed-check-T6eNUqP5` and exited 0 (session 82764). It
reported the installed package scenario passed, including toolchain-free CLI,
setup, synthetic conformance and explicit-memory checks. The retained log
`_build/installed-package-clean.log` SHA-256 is
`b06abffad7fd4c9db24d0fd95d86e60695066c8ee90e608ca996ab19282c6267`.
This verifies the named general package scenario, not protected Knowledge
storage on 7.2.11, live-model quality, human use, or the dirty-source link
identity; the first contaminated failure remains part of the record.

On the same isolated production graph, the locked offline Rust PDF tests passed
9 tests; the production-profile Elixir parser, PDF extraction and staging
suites passed 9 tests (seed 46656). A separately built `corpus/state-lexical`
artifact at `_build/corpus-proof` has manifest SHA-256
`95d754b000531573ffb94166e81f88aa73286300e4ada8a752d050e3c6303ad1`.
The same artifact passed `dev/verify.exs` document checks against both the
source SDK and the exact installed archive, each reporting the PDF resource
backend available, six synthetic checks, unchanged inventories and no live
inference. The checks include text, DOCX revision handling, PDF default-off and
explicit extraction, and dependency notices. They are synthetic artifact
proofs, not real-document fidelity, macOS, protected Knowledge storage or a
distribution-ready source identity.
Repeats retained `_build/document-source-check.log` and
`_build/document-installed-check.log` in the production graph, with SHA-256
`044c2e014db306fdd523baadb1455f959fb0b8dba27cb2c1233fdfae791dce3e` and
`40f5e2c2711c876928139def3c2551cc50c1260e96a7b65e770140e53ba0340f`;
both exited 0.

The same production graph also built the documented `decision-calls` example
artifact, then ran the seven-check synthetic decision verification against both
source and installed runtime. Both passed with unchanged inventories; see
[the P30 follow-up](p30-current-decision-followup.md) for hashes and limits.
This is not live decision access or a qualified Knowledge consumer.

A newer production-profile package graph, `_build/production-guard-inGks1jJ`,
includes the subsequent signed-observation repair and historical tests. Its
tracked files and relevant source directories matched the working tree before
building. Its private source-index tree is
`3aee82ca9cc9e250a6af9f992a1b044fa121af8a`. The default PDF-enabled
`./dev/package.sh` completed with exit 0 using isolated offline caches; the log
SHA-256 is `d9195fce1b77ca5e7f6dc7c8980124bf762358ddf68ec1ef0176c546eb4a74a0`.
The archive SHA-256 is
`51a240509b0700564cce6575d9a09d2ca15acf73af92221afef2820997a1be4c`, and its
checksum file verified. Its PDF helper SHA-256 is
`b9b7266bb7a8a843df5e71f389ab37e602043606e0e5c0e87edae79a1e9e0863`.
It still identifies copied Git HEAD `4dc1f7c70d05afedb318f4163656885cfeb6f396`
in documentation links, so it remains diagnostic rather than a release.

The updated archive's installed-package verification passed with exit 0 (session
28213), using scratch `/var/tmp/ipse-guard-installed-lBifYPBv`. Its retained
`_build/installed-guard-check.log` SHA-256 is
`c335a75690d269dc3d2888b68fa64a1213459b071fc4ea14187fc380fe744821`.
It reports the general installed package scenario, synthetic explicit memory,
private home and no system development toolchain on the runtime path. It does
not establish protected Knowledge storage, live models, human workflows or a
distribution-ready source reference.
The unchanged corpus and decision artifacts also passed their respective
synthetic installed verification against this updated archive. Their logs are
`_build/document-guard-check.log` and `_build/decision-guard-check.log`, with
SHA-256 `40f5e2c2711c876928139def3c2551cc50c1260e96a7b65e770140e53ba0340f`
and `ac6c4f0cd8c67828b2c9c51eb3048326febeed44607d9cfa3d4adfa1d1c31695`.
The document proof reported its PDF resource backend available. These are not
protected source-currentness, real-document quality or live service proofs.

The corrected full diagnostic graph is `_build/current-complete-GyrZw9bd`.
Before starting, every tracked file was byte-compared to the working tree except
the intentional private `native/ipse-storage-profile.rs` override; the complete
source directories, including untracked work, also matched. Its private test
tree is `772bc00ab42599aefc48707d46108d26c1dfa125`; substituting the production
profile in a separate index yields `4650af6c559c43f3d8245fa36a3868d67d9f259d`.
Forced strict test compilation and inert bundle building passed. The test helper
SHA-256 is `b7ea344b9b631208e9f766885d781cf3753d8569ed6a55f08fbe610fa28528bb`
and bundle catalog is `af83bb704a06077f5d760119f2ddc68271e85e624d4d8cea61fae894f5edfd4b`.

The corrected full run (seed 46654, `--max-cases 2`) completed with exit 0 and
an ExUnit summary of 2,876 passed and 36 excluded in 2,018.1 seconds. Its log
`_build/current-complete-GyrZw9bd/_build/full-regression-46654.log` SHA-256 is
`b952571585aa178f669b4cc4c657dc28416e9aadb505b9a12a1b727d74f0dece`, and its
private index still matched tracked source afterward. It used scratch
`/var/tmp/ipse-complete-full-3NkzfWJH`. This is a private-helper diagnostic, not
production kernel qualification; the graph predates the historical-observation
repair and later handoff/test updates.
After that graph was frozen, `ObservedRead.managed_record` was tightened to
recheck the signed literal against the current recipe. A subprocess regression
recreated an old signed native-answer literal and confirmed the new reader
refuses it; the pre-repair reader reproduced acceptance (46661), and 67 signed
observation/read-view tests passed after restoration (46662). See the capture
follow-up for hashes and limits. The ongoing full run and earlier archive do not
include this later host change or its new test fixture.
The fixture was later extended to sign and observe an old partial-source literal
as well, then verify the current reader refuses both it and the old native
answer (46664). The 46663 snapshot includes the reader repair but predates this
additional fragment test; raw reads and stored historical values remain outside
the observation guard.
Subsequent signed literal and pending tests exposed an incorrect assumption that
the evidence path was always `evidence.sources` (46668 and 46669). Both readers
now follow the selected recipe path, and 69 signed-publication/read-view tests
passed (46670). See the [pending observation follow-up](pending-observation-followup.md)
for source hashes and limits. Full run 46663 and the latest archive predate this
additional reader correction; source authority and current eligibility are
still not established.

A second full diagnostic ran on
`_build/current-guard-Wl3wzvvw`, which includes the earlier historical-reader guard and the
portable synthetic historical-record fixture. Before starting, all tracked
files except the intentional test-only kernel profile were byte-compared with
the working tree, and the relevant source directories including untracked files
matched. The test-only private-index tree is
`cb7fc37e24006517d8820f13a5e019fcb2132b38`; a separate index with the production
profile yields `2bac7d989a413282a6a03435bed419f0457f3b86`. Forced strict test
compilation and the inert bundle build passed. The private helper SHA-256 is
`b7ea344b9b631208e9f766885d781cf3753d8569ed6a55f08fbe610fa28528bb`, PDF
helper `85cde09bd8783ef99427bcd07f5708b33b9e46138e58288d2790eed1544b6556`,
and bundle catalog `0eec37191c8828c7bea202862fda51b4a01ebcad30358ab9b05a55351fcd7070`.

The full run at seed 46663 finished in 1987.0 seconds with **2877 passed,
36 excluded**, and wrapper exit 0. Its retained log
`_build/full-regression-46663.log` has SHA-256
`3c323a9ad786d76db9c274b9fadbc760c4b949bea593c15fc13c49789eb9519e`.
Both 46654 and 46663 are private-helper diagnostics, not production storage
qualification; distinguish their source snapshots and record both outcomes.

The complete-source snapshot including the subsequent evidence-path correction
and extended historical tests is `_build/current-path-EdFtAdFo`. Every tracked
file except the intentional test-only kernel profile and all relevant source
directories, including untracked files, were byte-compared with the working
tree before the run. Its test-only index tree is
`2bb1e5f90284a532ca79af0b52c97c135d2e9253`; the separate production-profile
index yields `c8ff2ed4905e4bcf640b5513c2b310aeee5e983c`. Forced strict test
compilation and inert bundle building passed. The test helper SHA-256 is
`b7ea344b9b631208e9f766885d781cf3753d8569ed6a55f08fbe610fa28528bb`, PDF helper
`85cde09bd8783ef99427bcd07f5708b33b9e46138e58288d2790eed1544b6556`, and
bundle catalog `cc3fd5e8c5cdfa7ce47d4eb72de99ecb4c63ac1957b54df150f989da3eded88d`.

Full diagnostic seed 46671 finished in 1943.5 seconds with **2879 passed,
36 excluded**, wrapper exit 0 and an unchanged private source index. Its
`_build/full-regression-46671.log` SHA-256 is
`e56f14b5b5e0e49d3affff252ed37ef248054c0a9225030477414c0d5ce5517c`.
Seed 46663 finished on its earlier snapshot. Neither diagnostic qualifies the production
storage profile, and both snapshots predate later handoff/documentation edits.

A corresponding production-profile package snapshot is
`_build/production-path-82hNCCJT`. All tracked files and relevant source
directories matched the working tree before its private index was frozen at
`0467a57a3cfdbaf706a67deb0dee67f0e79003ab`. The offline PDF-enabled package
build completed with exit 0 and reported a built archive. The archive SHA-256
is `fa1e20798210032febbe5711b6885f4572d925873b1994807513286df9291aeb`,
its checksum file verified from the distribution directory, and the build log
SHA-256 is `b01b603a58ba936c318290987723c9874fe4797232803acfacf91778b20f73aa`.
The production runner, PDF helper and extension catalog SHA-256 values are
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`,
`ef79b2391c94c1257d3bddae3d701f6666e6e82534f599649ee088fd40c4b171`, and
`e31a7f20252b63f106b8ae670977ea042f53c3e68f72a28ccf39589e7369a402`.
The documentation source reference is the copied graph's Git HEAD `4dc1f7c70d05afedb318f4163656885cfeb6f396`,
not the dirty working tree; this package is diagnostic and not a release.

The first installed verifier attempt under `/tmp` exited 1 with disk quota
exceeded while copying its extracted release; prior setup and approval checks
passed, but the scenario as a whole did not. Its log SHA-256 is
`2e813af30b5fb7236e20db8a7bb6d57b63501e5ae3c1187af0abbfaf44568634`.
A retry using isolated `/var/tmp/ipse-path-installed-vZQ8ESe6` scratch completed
with exit 0 and reported the general installed-package scenario passed, including
synthetic explicit memory, a private home and no system development toolchain
on the runtime path. Its log SHA-256 is
`3485677c20a39960300f678f0f81bcb224030955e653fda5636296803199124e`.
This does not establish protected Knowledge storage, live models, human workflows,
or a distribution-ready source reference. The failed `/tmp` attempt remains
part of the record.

The existing separately built corpus and decision artifacts also passed their
synthetic installed checks against this archive, with unchanged inventories and
the PDF resource backend available. The document and decision log SHA-256 values
are `40f5e2c2711c876928139def3c2551cc50c1260e96a7b65e770140e53ba0340f` and
`ac6c4f0cd8c67828b2c9c51eb3048326febeed44607d9cfa3d4adfa1d1c31695`.
These checks do not establish real-document quality, a live decision service,
protected Knowledge currentness, or a qualified consumer.

An additional review found that the signed literal reader assumed top-level
`lineage` and `category` fields even though its selected declarative recipe
specifies their paths. Two signed-publication fixtures relocated these fields
independently; both published and then failed observation before the repair
(46672). The reader now relies on the extracted candidate's existing comparisons
with signed lineage and category. The signed-publication, observation and
read-view suites passed 71 tests (46673), then 71 again after adding dependency
validation to both fixtures (46674). Logs in `_build/current-fields-audit`
have SHA-256 `a1851d3043ac1e23aeeff212819fe4fa5e8d1504964ca30636ce4a976e5c16fc`
(expected pre-fix failure), `291bd38cf50b75b235bb77969d6e769d5c3504342f0223162f2b09c5552211c4`
(46673), and `00dd747883704939ac89fb7b82ca5570e64615e74a86d9c508961651828d2846`
(46674). They use the private 7.2.11 helper; these observations remain historical
and do not authenticate present source or consent.
Working-tree strict compilation and the complete formatting check passed after
the repair. The first sandboxed compile could not acquire Mix's TCP lock
(`:eperm`); the retry ran outside that restriction and exited 0. The subsequent
documentation check passed 666 Markdown files and 5333 local links, with the
existing permission warnings on unrelated `.serenity-*` directories.

The newest diagnostic graph `_build/current-fields-audit` matched all tracked
non-document source except its test-only kernel override and all of `lib`,
`extensions`, `test`, `dev` and `examples`, including untracked files, before
its run. Its private test tree is `65a343ca3cc358b0350a62b703e5155aa5bd02d8`;
the corresponding production-profile index tree is
`a527e8f18441c1f0088fa287220dcd98f2ce6d81`. Full regression seed 46675 was
intentionally stopped for the requested pause. Its log ends in SIGTERM, has no
ExUnit summary and hashes to
`47a4a59f4964418e8d4438d474bc8cab7b682b21c1d634e498ccc5147b766f8c`.
The wrapper returned 0, which is **not a pass**. The private helper does not
qualify production storage; seed 46671 passed on the preceding source snapshot.
The prior package likewise predates the latest literal-field repair.
The corresponding production-profile graph `_build/production-fields-audit`
matched tracked non-document source and the complete `lib`, `extensions`,
`test`, `dev` and `examples` directories. Its private source-index tree is
`65158dd1a7a409ca5e24ebfa8b3852f7642ada7c`. Its offline PDF-enabled package
rebuild completed with exit 0 and reported a built archive. The archive's
SHA-256 is `1f6c6087b46b42dde8777c80f7ca57b7612bc6f6bb5166101f9ede2da923146e`,
its generated checksum verified, and the log SHA-256 is
`7e9f6d33b07ddcec5b8d9ea2a0584f673b4134c87af4a0f37c890ffac98660ef`. The
production runner, PDF helper and extension catalog hashes are respectively
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`,
`8be404097eff59d45d8d50329a48958520b4e0df08901651d4f69b7301ac9fe5`, and
`719bf02542422a93c77fe8c60c20020dd6d207aec44dc8e569cbd6e4f5012c5e`.
The copied Git HEAD `4dc1f7c70d05afedb318f4163656885cfeb6f396` appears as its
documentation source reference, so it remains diagnostic. General package and
separately built document and decision artifact checks all exited 0 using
isolated `/var/tmp/ipse-fields-installed-LVoFi5aE` scratch. Their respective
log SHA-256 values are
`99322f3e0db4bdc67d97bc0526047c0020eb8a57b2f2ff73707a65ccfe145dee`,
`40f5e2c2711c876928139def3c2551cc50c1260e96a7b65e770140e53ba0340f`, and
`ac6c4f0cd8c67828b2c9c51eb3048326febeed44607d9cfa3d4adfa1d1c31695`. These
are synthetic installed scenarios with private homes and unchanged inventories;
the document check reported its PDF resource backend available. They do not
prove current protected Knowledge, live models, real-document quality or a
distribution-ready source identity. No release is authorized.

A subsequent signed V3 control relocated a pending proposal's recipe-selected
lineage field. Publication succeeded, but the historical proposal reader refused
it (46676) because it also assumed top-level `lineage`. The working-tree reader
now uses the extracted candidate's lineage for the signed metadata comparisons;
the required proposal ID and pending-state checks remain. The signed-publication,
observation and read-view suites passed **72 tests** (46677) using the test-only
helper. The expected pre-fix failure and passing log SHA-256 values are
`680210ca2c715a7884e04af2958d7c7388401bf74bf02e964fa609c18e5f2fa3` and
`875b0be975085d27a32c5dd013d23d84797833a6061597a19bf56b35cba5995d`.
Strict compilation and formatting passed. Current source hashes are
`770f3b70379bcd267a0dc651a9c1ace6e2d8443bef1af3e726a57f88d78cdbb1`
for the reader and `52b96b8c102e6074118929534e02c6bca3c3fa5d7450dad2de85e99dd4420676`
for the integration tests.

The newest graph `_build/current-proposal-audit` matched tracked non-document
source except the intentional test-only kernel override, and the complete `lib`,
`extensions`, `test`, `dev` and `examples` directories including untracked files.
Its test tree is `96f62e44a36e238ff82159db9daebe16c0425877` and its
production-profile index tree is `6caf12f439c774fe72a9bda2164943a0a30b12ca`.
Full regression 46678 was intentionally stopped for the requested pause. Its
log ends in SIGTERM without an ExUnit summary and hashes to
`ba812773a52295daa30da4a11f2b69c257ece6c16e1329c8c2266db5445e74df`.
Its wrapper returned 0, which is **not a pass**. The private helper does not
qualify production storage. Earlier regressions 46671 and 46675 predate this
change and remain separate evidence.

The corresponding production-profile graph `_build/production-proposal-audit`
has private source-index tree `f0890436fec8ee7c14ed08aac9f93f944b359d24`.
Its offline PDF-enabled package build exited 0 with a built-archive message.
The archive checksum verified; the archive and build log SHA-256 values are
`09b96f11f03a9a90c3dbb173c0f37b09f0d4c7c6703fa1912e2bfd7d1b1b1871` and
`0384c5bf8e69d0f8678a22a150c7f1f5d7023babeb0ba77cdcb4e8976f5ee500`.
The contributor manual `docs/developer/collection-sdk.md` was subsequently
updated to explain the selected paths, so this archive predates that edit.
The graph `_build/production-proposal-docs` adds the corrected manual and has
private source-index tree `579179bf64b150870349a84c20344bfdbedf5117`. Its
offline PDF-enabled rebuild exited 0 and reported a built archive; its checksum
verified. Archive SHA-256 is
`1a4d36b4a6867e030691ec49d5c0ff6543635d50476e3c2dbbf2cb7284a33b6e` and
build log SHA-256 is
`01c57908039b98e84f40f64c36a89c2ce0090451980f8c833456e229ad53dfc3`.
The production runner, PDF helper and extension catalog SHA-256 values are
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`,
`4ef55a639f83f431bdfa6dfbeb93ce47cea123533d5c9521060723832a115f36`, and
`65f18a73f5fc5c76871d26ee25bec3c1ce58541d3ae043423277d280accd71c0`.
General package and existing document and decision artifact checks all exited 0
using `/var/tmp/ipse-docs-installed-EzFNqB8j` scratch. Their respective log
SHA-256 values are
`2dbd93164bc005092f6daf6a4e6c7d15feba2ff2b45f807c3627e11ff293ccbe`,
`40f5e2c2711c876928139def3c2551cc50c1260e96a7b65e770140e53ba0340f`, and
`ac6c4f0cd8c67828b2c9c51eb3048326febeed44607d9cfa3d4adfa1d1c31695`.
They use synthetic fixtures with unchanged inventories; the document check
reported the PDF resource backend available. They do not prove protected
Knowledge currentness, live models or real-document quality. The copied Git
HEAD is still not an identity for this dirty source; the archive is diagnostic
and no release is authorized. The archive's contributor manual contains the
updated selected-path explanation. A byte-for-byte comparison with the source
manual fails because packaging rewrites repository links; inspection confirmed
those rewritten links use the copied Git reference already called out above.

The declared-read planning recovery test now additionally holds the response
after the real Writer has synced `planning_exited`, then kills the Session
before acknowledgment. This extends the existing controlled process-death
matrix; it is not a power-loss or human terminal test. The focused run passed
one test with 15 excluded (46679) in `_build/planning-boundary-audit`. Its log
SHA-256 is `2fb6ab3eae866288829999da92472485fc7ed8779a6ca3b9950b668efa6b97e5`
and the test file SHA-256 is
`13c07a039c504f4787a2496af00fb013698a94755b76b779ed4d7fd61a5ca269`.
The surrounding planning, MCP and execution-mode selection passed 38 tests
(46680), with log SHA-256
`531dbb0ff1f552858ec485d9e2a076a52ee4a837965c7fee260d2fc58e8f93d1`.
This test-only edit is later than the full-regression
snapshots; the existing package's runtime and bundled manual are unaffected.
The test graph matched tracked non-document source except its test-only kernel
override and complete `lib`, `extensions`, `test`, `dev` and `examples`
directories. Its private test tree is
`d150f2b5e1acfdca43ee0fcfc7788353ab36b8e1`, and substituting the production
profile yields `d7f1b59165d94b1031cb936a070339d8907efd06`. The newest full
regression, seed 46681, was intentionally sent SIGTERM after reporting failures
to reduce test contention. Its log `_build/full-regression-46681.log` ends with
SIGTERM and has SHA-256
`008624ec3e98c1a7453f18c6889f53f5202ea766bdfb977f988eb932274dcb22`; there is
no final ExUnit summary. The wrapper returned 0, which is **not a pass**. It
reported an ExUnit timeout at 300 seconds in
`collection_migration_test.exs:440`, during the near-full backup page import,
and a second timeout at 120 seconds in `collection_migration_test.exs:808`,
during a 2,000-distinct-value import. Four full suites were concurrently using
the host; contention is plausible but not proven. Preserve the failed run and
record, then rerun both exact cases with less competing load rather than
counting this run as a pass. This test-only
kernel helper does not qualify production storage; previous full runs are
separate snapshot evidence.

After 46681 started, the planning death matrix gained the complementary case
that kills the Session before `planning_exited` is appended. It expects the
planning ceiling and witnessed entry to survive, then requires a fresh observed
exit after recovery. The planning/replay selection passed 38 tests (46682) in
`_build/planning-preexit-audit`; its log SHA-256 is
`ba7f324897cf0668c9523c30145bb9194ec12f77b26379869cad6fdaa54dd746`, and
the updated test SHA-256 is
`8094116c7641ce9976d36943d8f8480796ad7cf8a6c467623daf0f4b0b26646b`.
Seed 46681 predates this test-only edit. The new graph matched tracked
non-document source except the intentional test-only kernel profile and all
of `lib`, `extensions`, `test`, `dev` and `examples`, including untracked
files. Its test tree is `fa5fe8378de268d87b302aa0e5bae53dc074b1aa`, and the
production-profile index tree is `177a95fd26f347c5290d068c99dd6e894fd089a5`.
Full diagnostic seed 46683 was intentionally sent SIGTERM after a failure to
reduce test contention. Its `_build/full-regression-46683.log` ends with
SIGTERM and has SHA-256
`af460c80a05764b53a55b0b3b3d0e66da78ae7f741a804d34f9b34d50979b0b8`; there is
no final ExUnit summary. Its wrapper returned 0, which is **not a pass**. It reported a
300-second timeout in the near-full migration case at
`collection_migration_test.exs:440`. Investigate the case with less competing
load and run the latest full snapshot again after the other suites finish. Do not interpret the test-only profile as
production qualification. This test-only edit does not alter the packaged runtime.
The separately excluded Linux native-sandbox cases on this same graph passed
11 tests in `test/ipse/tools/sandbox_test.exs` (46657) and 6 in
`test/ipse/runner/stdio_test.exs` (46658). Other tests were excluded by those
`--only native_sandbox` selections. These checks do not qualify the separate
protected-storage profile or unavailable macOS backends.
The four separately excluded `memory_scope` tests also passed on this graph
(46659), using short-lived delegated user services; two nonselected cases were
excluded. A subsequent user-service query found no `ipse-measure-*` units. This
measures the test scenarios on the available Linux host and does
not establish an untested platform or protected-storage admission.

A working-tree `./bin/ipse demo` exited zero on 2026-10-28. The first run
inadvertently loaded the existing operator configuration rather than an isolated
home; its output identified that configuration and nonsecret effective settings.
An isolated-home retry initially lacked the installed Hex archive, then passed
after copying only the existing Hex archive into a temporary home. This is a
scripted credential-free demo, not a live model or full installed-user journey.

