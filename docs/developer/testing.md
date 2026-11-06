# Review and verify a complete change

Choose an observable property, exercise the complete path, then verify the actual
candidate at its source, process, platform, and installed boundaries. Evidence
belongs to the revision/configuration/environment tested. Fixtures prove no real
account behavior, algorithm quality, or unexecuted OS guarantee.

Use the [complete source baseline](#run-the-complete-source-baseline) after a runtime
change, then select the focused owner below. Documentation-only and packaging
changes have their [own checks](#verify-documentation-and-packaging-at-their-own-boundaries).

| Boundary to change | Focused verification path |
| --- | --- |
| Session evidence, capture or accounting | [Protected publication](#verify-session-evidence-and-protected-publication) |
| Worker input, native approval or result release | [Managed delivery](#verify-managed-delivery-and-effect-admission) |
| Pending/accepted notes, retention or clocked turnover | [Native note lifecycle](#verify-native-note-management-and-clocked-retention) |
| Filesystem policy, native helpers or terminal ownership | [OS and protocols](#exercise-actual-os-policy-and-native-protocols) |
| Document extraction, source acquisition or generations | [Document boundary](#verify-document-acquisition-and-generation) |
| Source/installed SDK or a real account | [Independent artifact](#prove-an-independent-artifact-without-rebuilding-the-host), [live provider](#verify-a-real-provider-explicitly) |

Keep source/build outputs fixed during a run. Concurrent compilation or native
rebuilding can invalidate executable pins. Use separate checkouts/build roots for
different toolchains. [Setup](index.md) supplies prerequisites; the
[security policy](../../SECURITY.md) defines threat assumptions and private reporting.

## Establish the candidate and acceptance conditions

```sh
git status --short --branch
git diff --stat
git diff
```

Record the exact revision/base and unrelated edits, preserving them. Inspect source,
callers, tests, manuals, and dependencies together. An extension can propose host
effects; a core change can affect every extension. A small diff is not automatically
a small authority change.

Write expected observations before repairing code. Include allowed behavior,
relevant refusal, cancellation, and saved recovery. For a write-approval change,
follow the existing Session fixture: complete proposal, denial, absent file,
recorded denial, and eventual turn completion. Then inspect approval of only that
same pending action. Make the original failure observable rather than testing only
a helper's return shape.

| Changed ownership | Start with |
| --- | --- |
| Prompt/approval/questions/cancellation | `test/ipse/session_test.exs`, `test/ipse/session/permissions_test.exs`, `test/ipse/cli_test.exs`, `test/ipse/tools/questions_integration_test.exs` |
| Effects and unknown outcomes | `test/ipse/session/recovery_test.exs`, `test/ipse/session/file_effect_test.exs` |
| Journal/lock/reservation/source closure | `test/ipse/journal/`, `test/ipse/journal_test.exs` |
| Task/native cleanup | `test/ipse/session/resources_test.exs`, `test/ipse/runner/` |
| Controlled peer ownership | `test/ipse/session/resources_controlled_test.exs`, `test/ipse/session/resources_controlled_close_test.exs`, `test/ipse/session/resources_controlled_guard_test.exs`, `test/ipse/session/resources_controlled_receipt_test.exs` |
| Provider wire/stream/usage | `test/ipse/provider/`, `test/ipse/provider_test.exs`, `test/ipse/usage/` |
| Shared adapter contract and captured HTTP requests | `test/ipse/provider/conformance_test.exs`; event builders in `test/support/provider_conformance.ex`, transport fixture in `test/support/provider_fixture.ex` |
| Generic extension or bundled/package behavior | `test/ipse/extension/`, `test/extensions/` |
| Configuration/workspace/client | Matching `test/ipse/config/`, workspace, and CLI suites |
| Operator error/recovery rendering | `test/ipse/cli/errors_test.exs`, configuration and MCP validation suites; include private synthetic values and unchanged-journal controls |
| Offline diagnosis and explicit metadata probes | `test/ipse/cli/doctor_test.exs`; preserve untouched listeners, credential bytes, held locks and absent workers/state |
| Trusted development/runtime proofs | `test/dev/`, `dev/verification/` |

Trace validation→authority/approval→durable intent→effect→receipt→cleanup→saved
validation→idle resume. Identify every owner that can die between steps and what
can still execute afterward. For a cleanup example, follow Worker failure through
`record_cleanup`, `close_claimed`, and `await_cleanup` in
`lib/ipse/extension/worker.ex`. Callback failure can have confirmed native cleanup;
a dead worker without its receipt cannot. Read the consumer that commits the fact.

## Run the complete source baseline

```sh
./dev/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
elixir dev/check-ci-policy.exs
elixir dev/check-docs.exs
mix test
IPSE_CHECK_HOME=$(mktemp -d)
IPSE_HOME="$IPSE_CHECK_HOME" ./bin/ipse demo
```

The build uses locked dependencies/Rust helpers. Tests use loopback HTTP, generated
keys, temporary state, and real processes, without paid credentials. Require a
completed ExUnit summary plus exit status. SIGTERM/partial output is not a finished
suite; deliberate process/TLS failure logs alone are not failed tests. Retain failed
runs when investigating.

Mix locks and fixtures need loopback sockets. Use the environment's permission
flow or a permitted terminal, without disabling TLS, skipping assertions, or
changing transports. Test the supported toolchain floor when changing compilation
or raw ERTS launch, using isolated build roots. Raw launch explicitly selects
Unicode output; locale defaults must not corrupt protocols. Broaden/repeat tests
when a new change/failure warrants it, rather than rerunning unrelated suites.

### Isolate subprocess inputs and shared resources

Run subprocess controls in isolation as well as in the full suite. Declare every
module they load and use absolute source/code paths with a private working
directory. A plain Elixir VM can otherwise resolve an application from the
checkout's basename, and a previously loaded fixture can hide a missing dependency.

A temporary directory alone does not isolate workspace instructions. Discovery
can reach a caller's ancestor `AGENTS.md` and linked resources. Conformance
creates a fresh repository boundary using a private `.git/HEAD` marker, without
requiring Git; an empty `.git` directory is not a valid boundary. Its declared
local guidance remains ordinary snapshot input. Test both exclusion of oversized
ancestor guidance and retention of fixture-owned guidance without raising the
context cap.

Use ordinary `mix test` startup for tests that create Sessions or extension
workers, including `ConformanceTest`. `--no-start` is suitable only when a fixture
explicitly supplies every required application owner or is definition-only.
An absent DynamicSupervisor is a setup failure, not evidence that a conformance
expectation or cleanup boundary should change.

Run preparation-purity assertions in a fresh plain Elixir child. The ordinary
Mix test process already owns the started application, so its global application
list cannot establish that an OFF preflight starts no application. Pass the
parent's actually loaded runtime paths and run the original preflight,
disabled-entry and no-effect assertions inside that child. Select exactly the
intended control and require its successful completion. The
[`CandidateAssessmentSession` test](../../test/dev/evaluation/candidate_assessment_session_test.exs)
uses this pattern with absent Session/Input supervisors and unchanged ports,
while remaining runnable under ordinary suite startup.

The declaration-CLI fixture copies tracked and nonignored untracked repository
files into a temporary synthetic repository. Run the full suite from a clean
committed clone when the working checkout contains private or unrelated untracked
files; do not let a verification fixture copy those files as test input.
An isolated source copy also needs its own Git metadata and admitted source index
for this fixture's `git ls-files` call. Record that setup before execution; a
directory copied without `.git` cannot establish a passing declaration workflow.

Separate fixture source from executable runtime origins. An explicit frozen SDK
code path does not install an uncommitted development-script overlay. Trace
cwd-relative lookups, adjacent `Code.require_file` calls and sources copied into
child checkpoints, then pin the actual files each process will load. A separate
source CWD can use immutable absolute SDK paths without copying the runtime;
record its exact source overlay and keep the host's original manifest unchanged.
That source-only arrangement does not satisfy a fixture that explicitly needs
Git/index or Mix build metadata. Validate the closure required by the chosen
scenario, rather than treating one staging recipe as universal.

Before starting a side-effecting driver, compile every actual staged module owner
in a definition-only check. Select only its module AST; top-level requires,
environment installers and `main(System.argv())` footers can start real work.
Parse and compare entry/footer syntax separately without executing it. Record
diagnostics and unchanged source/runtime inputs, and check that no App, native
helper, Session or socket started. This catches a missing helper or stale cwd
before execution; it proves neither that setup ran nor that a workload succeeded.
Inspect compile-time attributes and macros first: compiling a module executes
them, so selecting its AST is not confinement for untrusted code.
Normal-host and private clock-adapter code paths remain distinct qualifications.

Before parallel groups, identify global OS owners and fixed paths. Separate VMs
do not separate the per-user native terminal lock: keep operator/PTY/Rust terminal
cohorts serial. Eligible groups need private real CWD/checkouts, Git/index,
App/dependency build metadata and HOME/TMP, with an exact disjoint file-list union.
Do not apply a second partition filter to explicit groups. Ordinary direct
`Session.approve` fixtures are not automatically terminal users; inspect their
actual helper closure. Bound aggregate CPU, memory and fixture storage before
dispatch, retaining native product deadlines. Filesystem free space alone does
not prove per-user quota headroom. Never remove retained evidence to make a run fit.

A clean child environment must explicitly select an installed UTF-8 locale. A
Latin-1 startup warning can corrupt JSON stdout and Unicode cleanup paths; fix
the environment rather than suppressing warnings or retrying effects. Use the
fixture's qualified storage mount and bounded own write/sync preflight; a setup
refusal is not a product-path result.

When transferring code paths with `-pa`, exclude the implicit current-directory
entry and reverse the argument sequence so successive prepends retain the original
search order.
The verification fixture bootstrap locates the loaded `Ipse.Extension` BEAM and
validates its SDK directory. It does not infer that directory from the checkout's
application-like name. The shadow-directory regression exercises this distinction
in a fresh VM.
The [MCP-store contract control](../../test/extensions/knowledge/store_contract_test.exs)
loads Profiles, Evidence and MCPCAS explicitly, runs in a temporary directory,
and checks that those modules remain unloaded in the parent.

## Require positive controls and inspect uncertainty

Do not infer refusal from absent display text. Observe the unchanged file/store,
server request count, intent record, actual worker exit, and cleanup. For a path
change, prove allowed workspace access and refusal of a nearby escape before
execution. For a provider field, inspect valid and malformed wire results. For
bindings, prove allowed scope and a refused cross-scope operation.

A finding names trigger, expected/actual consequence, and evidence. Preserve the
first counterexample. A later pass does not diagnose it. Do not change production
deadlines, add sleeps, or accept multiple outcomes just to quiet a strict fixture.
A fixture-coordination repair needs evidence that product behavior was correct.
For expiry, prove the stored wall-clock deadline actually elapsed, using a bounded
monotonic wait, then retain unchanged-record/failed-receipt/inert-resume checks.

Presentation, durable append, and completed turn differ. In a prompt/presentation-
only fixture, an info call queues behind the same finishing callback:

```elixir
assert_receive {:ipse, ^pid, {:presentation, "<answer>visible</answer>"}}, 5_000
info = Session.info(pid)
assert info.phase == :idle
assert_receive {:ipse, ^pid, {:done, :ok}}
```

Keep journal/native/cleanup assertions afterward. With after-turn jobs, wait for
actual settlement rather than assuming that observation ends the turn.
Observation watchdogs are not product latency guarantees.

Unless explicitly labeled live or installed, the recipes below exercise
synthetic fixtures. Actual native means the real stated kernel/helper boundary
with automated input, not independent human attribution. Record the selected
platform, inputs and exclusions; no fixture pass alone proves semantic quality,
full capacity or annual endurance. Authoritative topic chapters own the detailed
contracts; this chapter selects observations and verification commands.

### Bind fixture messages and canonical dependencies

CLI prompt display can precede turn completion: busy-to-idle keeps an already
active reader rather than redrawing its prompt. A PTY fixture should require
completion and the current prompt after its last question display, allowing
either display order. A historical initial prompt is insufficient. Keep exact
native-answer/source, no-effect and confirmed-cleanup assertions afterward;
raising a watchdog does not repair an ordering assumption.

Fixture providers must distinguish an operator task from host context. A valid
`Ipse.Session.Reference` message uses the user role and can follow a task or a
completed tool group. When a fake chooses its next action from the latest task or
tool result, select that message through the public validator:

```elixir
last_real = messages |> Enum.reject(&Ipse.Session.Reference.reference?/1) |> List.last()
```

Keep the complete input for assertions. Check the expected reference placement,
content and safe tool tail separately; retain ordinary user messages and malformed
reference markers. This fixture selection grants no production authority and must
not remove host context from the real provider request.

Pure fixtures must also reproduce the host's canonical dependency union. Use
`ManagedReference.union/1` before placing reads into an invocation, including
negative variants. Session stores reads in digest order; two individually valid
cached root observations in another order are not a valid invocation input.
Keep the full set and change only the intended root, policy or cache condition
when testing its refusal. A populated fixture cache is trusted consistency data,
not evidence of a committed read or current publication authority; the registered
Session cases below establish those boundaries separately.

### Reopen the same mode and inspect permitted suffixes

Capture the journal after `Session.close_confirmed/1` returns. On idle resume,
require those bytes as an exact prefix. An ownership-only suffix assertion
requires the **same effective approval and execution mode** at reopening,
including approval origin, headless state and enclosing ceiling. Preserve the
fixture's explicit ordinary approval policy; do not replace it with a default
or revive an ended Session-only grant to make a byte assertion pass.

For that same-mode case, the current release-receipt layout appends one complete
ownership record validated by `ReleaseReceipt.valid_owner_marker?/2`; legacy
journals with no receipt layout remain byte-for-byte unchanged. The shared
[`assert_idle_resume_journal/3`](../../test/support/resume_assertions.exs) helper
checks this contract. A legitimate mode change can additionally append
`execution_mode_resumed`. A mode-transition fixture must assert that exact
transition and strict Saved reconstruction, rather than accepting arbitrary extra
records or applying the ownership-only helper to a different mode.

Confirmed close then appends its release intent. Validate it against the same
owner and native signed-release claim separately from the reopening assertion.
Neither ownership, mode nor release records permit replaying effects or changing
prior conversation records.
Closing an active lifecycle epoch first records an unsigned closure with
`cleanup_confirmed: false`; that record cannot predict the later native release.
Require its digest in the current release intent and check the signed-release
claim after confirmed close instead of expecting the closure itself to assert
completed cleanup. The parallel-delegation demo exercises this sequence.
When intentionally corrupting a journal, establish the
original source binding first and assert the earliest actual refusal: a modified
record or shifted byte offset can invalidate lifecycle sources before the
domain-specific checkpoint validator runs. Keep a separate pure validator control
when its narrower refusal is also part of the contract.

### Separate setup, execution and reconstruction failures

Distinguish timeout before command-handler startup from timeout during active work.
The evaluation-session fixture observes its worker's readiness and active Session
phase before asserting post-effect cancellation; a separate delayed-start case
keeps the short policy and proves that no command handler ran. Concurrent HTTP fixtures
must also reserve enough listener backlog for all clients started before accepts.

Restore must validate committed records/source bindings before permissible torn-tail
repair. Corrupt receipts must not pass because repair removed evidence. Check
configuration drift, captured CAS, source identity, cached results, and each
unstarted/unknown classification. Never replay an uncertain effect to reconstruct
its display or event.

## Verify Session evidence and protected publication

Follow [Session sources](session-sources.md) for proof/current-use ownership and
the [Collection SDK](collection-sdk.md) for publication and accounting. Pair an
allowed current source with the intended refusal; do not let an earlier provider,
shape or Worker-frame error stand in for the boundary under test.

### Use registered transport for managed history

For managed-history integration, use a registered native provider route even
when responses are synthetic. A `provider_module` callback on the demo route
does not supply actual send/completion ownership. Use the existing loopback HTTP
fixture, explicit service registration and a supported request deadline; keep
the normal adapter and completion witness. Do not construct a successful witness
or remove managed dependencies to make a test proceed.

The default `knowledge_session_test.exs` capture positives use that registered
wire route too. Its synthetic responder recognizes only its declared literal
task inputs after the native request drops host-only Reference markers, and
reconstructs tool-result IDs only from calls actually issued in that request.
The real provider request retains all reference content. Keep the deliberately
unregistered recall-refusal case separate, and require native-answer capture to
finish its expected turn as well as publishing its record.
A known refused capture can return its failed action to the registered model
and finish the turn normally. Preserve that refusal's failed commit, empty
effect accounting and unchanged store assertions; an unrelated unregistered-route
error must not supply the negative control.

### Build a genuine capture before testing queue races

Use the registered V3 capture cases as worked examples:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only registered_capture_lifecycle --only registered_capture_sequence --only registered_competing --only registered_capture --max-cases 1
```

The lifecycle cases require actual first-publication Identity activation, a
second new Session's successful addition and unchanged active domain metadata.
They preserve exact request/effect bindings, measured settlement, strict Saved
reconstruction and idle resume without Worker or model replay. The queue case
first proves admission below capacity, then requires a failed capture action at
64 pending records with unchanged root bytes and settled liability. Its registered
model receives that known refusal and can complete the turn normally. Require two
completed adapter requests per attempt, including the refused attempt; a route
error cannot stand in for the capacity control.

The sequence case saves 27 candidates through 54 actual adapter requests, checks
the resulting records and distinct original Session proofs, and crosses a nonzero
live-page split fence. Each Session must complete, settle and close. Same-mode idle resume follows the
[suffix contract above](#require-positive-controls-and-inspect-uncertainty), with no Worker replay.
A separate legacy-reader case first creates a genuine managed record through the
registered route, then requires a newly reviewed legacy reader to refuse its text.
These two cases retain private synthetic roots printed as `REGISTERED_CAPTURE_ROOT`.
For the source and publication owners, follow [Session sources](session-sources.md) and the [Collection SDK](collection-sdk.md); repeated additions do not exercise elapsed retention.

For the bundled headless CLI path, run:

```sh
mix test test/ipse/cli/knowledge_test.exs --only headless_pending_cli --max-cases 1
```

Each case performs actual native permission setup, then starts a separate CLI
process with argv text or a regular file redirected to its OS stdin. The task
remains `unattended_input`; five registered adapter requests must finish and one
exact pending record must preserve that source, with `never_current` eligibility,
settled consent accounting, valid Saved reconstruction and a signed release claim.
Require zero CLI exit, a completed turn and denied write/shell targets. An empty
store or an unknown capture must fail; checking only that no literal exists is
vacuous. The process has no `--yes`, grant injection or historical BEAM overlay.
Run the complete file after changing its launcher to preserve setup/refusal cases.
Use the topic's separate installed/live checks when those boundaries change.

The concurrency case first saves a synthetic protected candidate, fills the pending
population to 63, and coordinates two Sessions at the capture barrier. Five
synthetic native HTTP responses cover the initial save, both competing requests
and only the winner's continuation. Exactly one writer must publish and finish.
The loser retains a known refused action, then cannot deliver its next Worker
input using the root invalidated by the winner; its turn must fail without a
second inference request. Require strict Saved and idle recovery for both, with
settled accounting and no Worker replay. Its retained root prints as
`COMPETING_CAPTURE_ROOT`. The service slot releases before either extension
waits at the barrier. Excluded cases have not run. These are protocol and
ownership controls, without real model inference or semantic-quality evidence.

### Distinguish admission, source and mapping refusals

Use the supported single-new-record V3 publication shape when a fixture is
testing current capture rather than the deliberately closed legacy API. The
`registered_capture` cases in the same file cover a successful paged SDK result,
revocation during worker entry and ambiguous publication mappings. The paged
case must prove a successful publication as well as the original result binding
and saved reconstruction. After revocation the turn ends with an error because
the registered route refuses another model dispatch; require the denied commit,
empty reservation ledger and exactly one dispatch intent. Waiting for a fake
second HTTP response would hide that correct refusal behind a fixture timeout.

The `read_only_export` case uses that same supported V3 shape to test a different
boundary: a read-class export can enter planning, but its publication must be
recorded as denied even under ordinary `--yes`. Require an empty Consent ledger
and unchanged generation/floor, as well as denied workspace writes. Keep its
original read/output-release, interrupted-cleanup and tampered-replay assertions.
Its deliberately unregistered main route refuses the later managed continuation;
registering that route would remove a separate negative control. A legacy-shape
refusal before any publication intent does not test the read-class denial.

For a missing-original-source negative, isolate source authority from protected
delivery. The `legacy_origin` cases build a legacy journal without its original
file binding and submit an untrusted generation-zero candidate without first
requesting a managed snapshot. Legacy consumers cannot receive the current
protected snapshot frame; testing that earlier refusal would never reach the
source-origin check. Require the V3 action's exact `collection_consent_denied`
outcome, no reservation or storage change, valid historical reconstruction and
inert legacy resume. V2 remains refused before intent. Pair those negatives with
the same no-snapshot V3 request from a current Session: it must actually publish,
settle and complete through the registered route, then resume without replay.
The worker's claimed generation is only a CAS input, never source authority.

### Check accounting, owner loss and replay bindings

Use `publication_accounting` and `publication_fault` in the same Session module
for supported V3 accounting and owned-loss changes. The conflict control first
publishes successfully, then submits an unobserved stale generation. A managed
snapshot at the newer root would instead trigger the prerequisite guard before
storage CAS. Require one conflict, conservative full settlement, no retry and an
unchanged root. The successive-save control reconstructs every V3 metadata change
from actual stored values and prior revisions, checks its receipt/hash and exact
measured charge, and proves the fixed budget fits actual-first plus reserved-next
but cannot fit two conservative reservations.

Keep the native-loss and foreign-caller controls at their actual boundaries. V3
checks sources before domain preparation, before admission and inside the admitted
publication callback. The Session-loss fixture blocks the third query, after a
durable `publishing` row exists, then kills the owner. Require actual lock-owner
exit, full unresolved liability, no selected root and strict idle recovery with
unchanged accounting and Worker trace. Blocking the second query cannot prove
that post-admission boundary. The separate foreign/stale/changed-action callers
must all refuse while the genuine caller still publishes successfully.

The `publication_binding` control keeps a successful headless V3 capture and
mutates one binding or receipt field at a time. Current inner action/result
version 3 contains effect binding version 3 plus `metadata_version: 3`; historical
metadata-V2 bindings keep version 2. Check actual V3 anchor-page metadata when
tampering with its selected key, rather than adding an obsolete V2 `anchor_key`.
Require replay rejection after recalculating the outcome digest, so a trivial
stale digest is not the only barrier. The unchanged positive must also settle,
preserve one visible attributed candidate and resume without replay.

### Preserve selected evidence across callbacks

For ordinary private text callbacks, keep Session open until the actual expected
text reaches the fixture. A first-request start/end or a generic payload marker
does not prove delivery of a later request's answer. Optional consumers do not
delay Session completion for acknowledgments, and close cancels queued work.
The `managed_sink_input` matrix must still retain its exact frame-text and physical
file assertions, its required-consumer positive and all managed-content refusals.
Use the stream integration tests to distinguish a completed transport end from
later required-delivery failure and canonical answer admission.

Keep the two A/B race points distinct. `worker_inherited_union` withdraws original
literal A after B's quote commits but before its next Worker frame is delivered.
`managed_ab_probe` instead lets the Worker receive B's genuine quote while the
root-bound A read is current, then holds inside that quote callback before the
candidate is submitted. A separate registered Session advances the root. Trace
the actual publication-prerequisite call: its state must retain the full earlier
union, its candidate must contain B's exact SDK proof, and admission must refuse
before a publication intent. Require real seed/winner saves, unchanged winner
root, settled accounting, strict Saved and inert recovery. A seed route error or
an earlier input-frame refusal cannot qualify that later publication boundary.

## Verify a real provider explicitly

After building the source checkout, prepare a dedicated operator configuration
with an explicit Gemini, Grok API or pinned OpenRouter profile as described in
[provider configuration](../operator/configuration.md). Supply its key privately
through the documented environment variable. These commands make real API
requests and can incur charges:

```sh
IPSE_LIVE_PROVIDER_CONFIRM=openrouter elixir dev/verify.exs live provider \
  --provider openrouter --profile router --config /private/path/router.json
IPSE_LIVE_PROVIDER_CONFIRM=gemini elixir dev/verify.exs live provider \
  --provider gemini --profile gemini --config /private/path/gemini.json
IPSE_LIVE_PROVIDER_CONFIRM=xai elixir dev/verify.exs live provider \
  --provider xai --profile grok --config /private/path/grok.json
```

The confirmation must exactly match the resolved provider. Project configuration
is disabled. Review the printed model, upstream, API billing and destination.
The driver makes at most three requests: exact text, one fixed echo call, and its
native continuation. It executes no model-selected external tool, retries nothing,
and narrows each request to at most 1024 output tokens, 64 KiB and 60 seconds.
An existing tighter profile cap remains tighter. A session budget causes refusal
because this standalone driver cannot enforce its ledger; use a dedicated bounded
verification config or a normal budgeted session. It does not bypass a configured
policy. Exit 0 requires both text and tool checks to pass.

For Grok, the printed output limit covers visible output only; xAI excludes
reasoning and function-call tokens from that parameter. It is not a total-token
or spending ceiling. Select a low reasoning effort explicitly when appropriate.
This driver supports the API-key route only, not subscription OAuth.

Retain the non-secret JSON plan/result with the exact source revision, environment
and date in a dated archive receipt. Results include canonical usage, failed
requests, counts of Gemini signed parts and Grok encrypted reasoning items, and
Grok's reported model and cost ticks, without text, signatures, ciphertext or keys.
Partial usage is valid evidence of missing API counters, not evidence of zero
cost. `test/dev/live_provider_test.exs` uses loopback/stub controls only; those
fixtures do not establish live access. The command loads the already-built source
application without compiling; it is separate from the artifact verifier below.

## Prove an independent artifact without rebuilding the host

The finite `dev/verify.exs` command uses an existing source SDK or compatible
installed archive. It never repairs/rebuilds an input artifact. Start with:

```sh
IPSE_PROOF_ROOT=$(mktemp -d)
elixir dev/build-artifact.exs model-calls --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_PROOF_ROOT/model"
elixir dev/verify.exs source model --sdk _build/dev/lib/ipse/ebin \
  --input "$IPSE_PROOF_ROOT/model" --selection json-none
```

Expect nine passed assertions, precompiled harness, and unchanged inventories.
A loopback fixture supplies text/usage, without real inference. Inspect behavioral
assertions; unchanged files alone prove no successful operation. Repeat the SAME
artifact against the exact archive printed by the packager:

```sh
IPSE_ARCHIVE=/absolute/path/to/the-compatible-archive.tar.gz
elixir dev/verify.exs installed model --archive "$IPSE_ARCHIVE" \
  --input "$IPSE_PROOF_ROOT/model" --selection json-none
```

Source success proves no installed compatibility. Preserve old artifacts for upgrade
checks; rebuilding tests a different claim. [Examples](../../examples/README.md)
cover model/embedding/MCP/saved-output recipes and their distinct assertions.

For the decision operation, build its example artifact and verify the same bytes
against source and the selected archive:

```sh
elixir dev/build-artifact.exs decision-calls --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_PROOF_ROOT/decision"
elixir dev/verify.exs source decision --sdk _build/dev/lib/ipse/ebin \
  --input "$IPSE_PROOF_ROOT/decision"
elixir dev/verify.exs installed decision --archive "$IPSE_ARCHIVE" \
  --input "$IPSE_PROOF_ROOT/decision"
```

The synthetic loopback fixture checks approval, the selected compatible route,
typed advice, journaled usage, denial, interruption and idle resume. Expect seven
passing checks and unchanged inventories; this is not a live account or
Knowledge-consumer test.

### Follow compilation and runtime ownership

`dev/verify.exs` delegates closed grammar to Scenarios. Scenarios owns finite source/
module/argument/assertion declarations; Runtime inventories inputs/origin and
compiles trusted proof modules in a separate VM before verification work starts.
Source proofs use the development compiler with the source SDK. Installed proofs
use the selected release's own compiler through its bundled launcher, with a
private environment; the driver's Elixir version must never be mixed with the
archive's compiler modules. This permits a newer driver to verify an older
supported bundle. Package checks
are loaded only for the explicit package scenario, without broadening measured
compiler closure. Domain assertions stay in their proof modules.

Runtime rechecks host/dependency/ERTS/boot/harness/utility bytes around launch and
execution. Child HOME/TMP are private. PATH contains declared utilities and selected
Erlang, without system Elixir/Mix/Rust. This is controlled trusted execution, not
OS confinement. Canonical paths account for aliases. Ordinary runtimes are removed
on success/failure; service evidence remains at selected output. Measured cases
retain runtime/evidence to reopen exact files. Retention authorizes no retry.

| Scenario | Required input/selection |
| --- | --- |
| `model` | Model artifact; default/none/json/json-none/json-long |
| `embedding`, `mcp`, `saved-results` | Matching artifact; default |
| `lab` | Built lab parent directory; default |
| `memory`, installed-only `package` | `examples/memory-corpus.json` |
| `knowledge`, `knowledge-independence`, `knowledge-complete` | Parent of Corpus/Graph/Research artifacts |
| `knowledge-evaluation` | Lexical Corpus |
| `knowledge-recovery`, `knowledge-graph-lifecycle` | Graph state-model |
| `knowledge-corpus-lifecycle`, `knowledge-selection` | Corpus state-dense |
| `knowledge-mcp`, `knowledge-research` | Corpus mcp-lexical / Research mcp |
| `documents` | Corpus artifact; matching parser-enabled source host or standard archive; default selection |
| `model-service` | Compiled model-service Rust probe and fresh evidence output |
| `measured-knowledge`, `measured-authority` | Seven-artifact map, clean repository, fresh output, optional Linux backend |

Measured-knowledge accepts default/sealed/structured/sealed-structured plus
sealed-long-answers/sealed-gpu-answers policies. Other scenarios except model use
default. Closed grammar rejects unused/duplicate/unknown arguments. Measured cases
refuse unsupported OS before inputs/output. Follow [evaluation](knowledge-evaluation.md)
for exact maps/seals/measurement setup rather than inventing launch arguments.
`test/dev/verification_test.exs` checks grammar, compiler closure, changed inputs,
source/installed launch, retained failure, and cleanup precedence.
The Knowledge independence test keeps the nine real memory/package workflows and
adds disabled, idle and resumed Sessions for every capability preset. Its call
counters cover worker startup, State, MCP, embeddings and model requests. These
extra inert controls exercise granted authority without invoking domain operations
or contacting an inference service.

## Learn a complete workflow through the compatibility lab

```sh
IPSE_LAB_ARTIFACTS=$(mktemp -d)/artifacts
elixir dev/build-artifact.exs extension-lab --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_LAB_ARTIFACTS"
elixir dev/verify.exs source lab --sdk _build/dev/lib/ipse/ebin --input "$IPSE_LAB_ARTIFACTS"
elixir dev/verify.exs installed lab --archive "$IPSE_ARCHIVE" --input "$IPSE_LAB_ARTIFACTS"
```

Read spec, worker callbacks, `dev/verification/lab.exs`, then Scenarios/Runtime.
Construction creates immutable versions/lookup/observers without importing or
selecting them. Lab memory recognizes fixed entity/link syntax, demonstrates
before-request service-backed recall and after-turn approved CAS, and retains
occurrence/view/extractor/package versions. Identical new text is a new source;
repeated catch-up deduplicates. Its fixed-range catch-up permits eight pages of
eight records and reports gaps/continuation.

Domain ceilings are eight sources, sixteen entities, and 7000-byte stored values,
below host bounds. Forget removes whole contributing sources and suppresses their
IDs, potentially removing other facts. Forget-all retains a tombstone and clears
future context; captured pre-forget revisions conflict. Earlier journals/snapshots/
transfers remain. These teaching semantics are distinct from bundled explicit Memory.

The proof checks schema/required-service refusal, exact private/metadata views,
feed pressure, questions, writes, stale work, and idle resume. The final deliberate
required-service crash ends safe-to-continue false and expected cleanup unconfirmed.
Exit zero means positive/negative expectations matched, not every cleanup succeeded.
Extend it with an independently observed effect assertion, keeping construction
outside activation and host bytes unchanged. A historical FROZEN_CORE or one
platform's BEAMs cannot establish current/cross-platform compatibility.

## Verify documentation and packaging at their own boundaries

Read each affected chapter wholly and execute its credential-free examples.
Validate configs through real CLI with isolated application home. Account-dependent
steps need implementation review plus explicit reporting of unexecuted checks:

```sh
elixir dev/check-docs.exs
mix run examples/session.exs
./bin/ipse --help
```

The checker rejects absolute filesystem links and targets outside the repository,
then validates local targets/anchors, JSON examples, focused-test file paths
in current manuals, audience/history rules, and archive hashes. The pinned raw
manual snapshots in the public-producer evidence resolve relative links from
their original paths only after the manifest and snapshot hashes are verified;
same-page anchors still resolve in the snapshot. Other archives use their own
locations. It does not execute Markdown or judge usability. Review
prerequisites/placeholders/expected results/recovery. Docs-only changes need those
checks, without invented runtime regressions. Preserve substantial old manuals
under the [archive policy](../archive/index.md#archive-policy).

Packaging, runtime-path, worker-launch and helper changes need package verification.
Standard packages include the optional PDF parser, which needs Rust/Cargo 1.88+;
the ordinary PDF-free source build still needs Rust 1.85+. Use
`IPSE_BUILD_PDF=0 ./dev/package.sh` only when deliberately verifying a parser-free
bundle. Parser-enabled verification additionally follows the
[native parser checks](../../native/ipse-pdf/README.md#build-and-installed-use),
including its source/installed artifact proof. Keep parser resource-backend
unavailability distinct from successful extraction, especially on macOS. Run the
package baseline with the exact archive produced:

```sh
./dev/package.sh
elixir dev/verify.exs installed package --archive "$IPSE_ARCHIVE" \
  --input examples/memory-corpus.json
```

Set IPSE_ARCHIVE to the exact newly produced archive first. Avoid ambiguous/stale
globs. The verifier extracts private HOME/IPSE_HOME and tests real CLI help/demo,
workspaces, locks/helpers, bundled behavior, and Memory. It borrows no checkout
priv directory. Its offline doctor check verifies stable findings and no auth or
session-directory creation with a demo route. A separate fresh home follows setup
preview, private save, configured doctor and demo; preview must leave no directory,
and saved provider provenance must identify the operator file. Every doctor route
must return the complete ordered version-1 check set. Missing, duplicate or
reordered findings refuse verification, as do unexplained skips and unexpected
warnings; only the documented experimental native-policy warning is admitted on
macOS. CLI checks have declared utilities
without Erlang/development commands; the precompiled harness adds bundled Erlang.
The package proof also runs `inference status --json` with malformed conversation
configuration and an absent operator home. It requires the exact empty report,
unchanged configuration and no home creation, then checks unsupported flags and
an absent-reservation reconciliation. These offline CLI checks do not establish
native confirmation or actual remote-service quiescence; those require separate
terminal and service controls.
The hosted matrix allows 60 minutes for the whole build, test, package and
independent-proof sequence. This finite orchestration budget is separate from
individual assertions and product deadlines. Record an outer job cancellation
separately from a failing test, and retain which proofs actually finished.
Use extracted `./ipse` for CLI and `./bin/ipse eval` for trusted evaluation.
A local build is not publication. Distribution needs matching runtime notices via
`IPSE_NOTICES_DIR` and the [dependency inventory](dependencies.md).

The packager includes current manuals and renders references to omitted source
files, examples and historical records as repository links at the recorded build
commit. Historical records remain unchanged in Git; they are not duplicated in
the runtime bundle. A missing full commit falls back to the application version's
tag and is labelled in `docs/bundle-links.json`. The archive is checked after
creation for required manuals and unresolved local prose links. Fenced example
text and third-party notice bytes are preserved. Source-build instructions still
require a checkout and development tools; a link does not bundle those inputs.

The application version comes from `mix.exs`. Build and package scripts force
compilation with `IPSE_BUILD_COMMIT` set to the current Git revision, unless an
explicit build value was supplied. A source archive without Git metadata reports
a null commit. Direct Mix compilation can also report null; runtime never invokes
Git. Check `./bin/ipse version --json` or the extracted `./ipse version --json`.
The package verifier compares the archive name and both version commands with the
packaged application specification without a development toolchain. This metadata
does not prove that a checkout was clean; record its diff separately.

Packaging writes a streaming OTP SHA256 sidecar in standard checksum format.
The installed package command validates it before extraction. Its launcher proof
uses a relative symlink chain and checks the caller's actual workspace. An upgrade
control copies the release and recompiles a test copy of the public identity
module, changing a real inventoried host BEAM. An extension-free saved session must
resume; one with selected extensions must refuse without journal mutation, and
still resume with the previous release. The original archive/host stay unchanged.
Successful same-mode idle resume preserves the exact prior journal bytes and adds
only the validated ownership record and confirmed-close release intent. For a
legitimate mode transition, apply the [exact suffix rules](#require-positive-controls-and-inspect-uncertainty) above. The verifier checks
the current intent and native signed-release claim, while a denied resume permits
no suffix.

For a local distribution, prepare the exact bundled toolchain's notices in
`IPSE_NOTICES_DIR` before packaging. Hosted CI/release jobs obtain the official
versioned Elixir and OTP notice files through the already-approved `gh` CLI,
verify blob/content hashes, and retain provenance in `licenses/runtime-notices.json`.
Legacy `NOTICE` files and current `LICENSES/` layouts are both preserved. A
missing/truncated source, unsafe path or mismatched blob stops the job before
packaging. Custom-distribution notices remain the packager's responsibility.

Before a tag, run `mix test test/dev/release_test.exs` and the full package proof.
Complete documentation repairs before selecting that tag: root guides and current
manuals are shipped files, so a later checkout edit does not repair an existing
archive. Keep an affected draft unpublished while reconciling its source and
rebuilding. Never silently move a published tag or replace published assets.
The tag workflow admits only the `mix.exs` version or a numbered RC and requires
`docs/releases/vVERSION.md`. It repeats every ordinary CI step on both platforms;
a guard test catches omissions when CI changes. Asset admission checks exact
supported basenames and the `mix.exs` version, both platform archives and their
checksum sidecars. Archives must be nonempty regular files, and sidecars must be
regular files; symbolic links refuse before hashing or upload. The draft body
renders the notes' versioned links against the
actual stable or RC tag, so an RC does not depend on a future stable tag.
The approved runner `gh` creates
an unpublished draft only after both matrix jobs pass and their retained archives
are collected and admitted as a complete set. A failed platform creates no draft.
The final job uploads the admitted files and re-downloads them for inspection.
An upload/network failure can still leave an incomplete draft; inspect the final
job result before publishing.
Retries may replace draft assets; a published release refuses modification.
Publication and RC deletion are explicit developer actions after inspection.

Exercise the same artifact handoff without creating or changing a release:

```sh
gh workflow run release.yml --ref main
```

This manual event derives the version from `mix.exs`, runs the full platform
matrix and admits the collected assets. Draft mutation and remote re-download
steps run only for a matching tag-push event. Record the manual run's source and
terminal result; it proves artifact handoff, not draft creation or publication.

## Exercise actual OS policy and native protocols

Default tests exclude host enforcement. They compile the complete experimental
macOS verifier in a separate Elixir VM without launching its platform probes.
That catches broken function links on either platform; actual policy enforcement
still requires the separate native checks. On supported Linux:

```sh
mix test --include native_sandbox
```

On macOS:

```sh
mix test test/ipse/tools/macos_sandbox_test.exs test/ipse/runner/stdio_test.exs test/ipse/tools/macos_filesystem_test.exs --include macos_sandbox --include macos_filesystem
IPSE_MAC_TESTS=$(mktemp -d)
rustc --edition=2021 --test native/ipse-macos-sandbox.rs -o "$IPSE_MAC_TESTS/policy"
"$IPSE_MAC_TESTS/policy"
```

Included tests fail when requirements are absent; exclusions/skips prove no policy.
### Qualify the storage mount and helper

For a storage-profile change, isolate the new helper and compile-pinned Runner
from earlier diagnostic graphs. Run the Rust selector/feature controls, actual
positive protected publication and explicit unsupported-filesystem refusal,
plus retained-stage sync/owner-loss/reinventory controls. Preserve first failures
and rerun only repaired cases while iterating. An exact-kernel tmpfs pass cannot
qualify Btrfs, native shell confinement or reboot durability. Match a full
source/package candidate to its own freshly built helper before final acceptance.

The exact-kernel storage fixture distinguishes its two mounts. Its positive
publication uses the qualified temporary filesystem. Its Btrfs refusal runs only
when the checkout is on Btrfs or you explicitly select an existing Btrfs root:

```sh
IPSE_TEST_BTRFS_ROOT=/absolute/path/on/btrfs mix test test/ipse/runner/storage_profile_test.exs
```

The fixture creates and removes a private test directory under that root. A
tmpfs checkout without an explicit root skips only the Btrfs case; that skip
proves no Btrfs behavior. An explicitly selected wrong filesystem fails the
assertion instead of silently skipping. The exact kernel requirement still
applies; this test setting changes no production storage admission.

### Observe bounded native pipe delivery

For the private Linux stdin handoff, run the actual pipe/transaction component
separately from Session qualification:

```sh
mix test test/ipse/runner/transaction_pipe_test.exs test/ipse/extension/worker_test.exs --max-cases 1
```

It imports the real supervisor's stdin description and writes a complete bounded
binary frame under kernel lock and owner controls. Wrong operation/expiry/frame,
duplicate delivery, concurrent ordinary input, elapsed admission and owner-loss
cases must refuse or retain uncertainty at their actual boundaries. The small
Rust reader fixes pipe capacity at 4096 bytes and records the first partial read
before Session-control, source-owner or supervisor loss. No complete-frame
receipt may follow that partial delivery. For a pre-write zero-byte assertion,
observe actual native source-owner exit; a BEAM actor's `DOWN` alone can precede
its native cleanup. Policy/source lock contents are synthetic, not valid
publication permission or original Session proofs. The shared native-owner fixture
keeps that distinction explicit. Worker cases independently build an artifact and
exercise its actual VM: opaque preparation, exact native frame, early-response
buffering, original timeout/cleanup, supervisor pinning and 257 successive handoffs
through one Worker. The substitution control changes valid JSON while retaining
the original protocol ID; native delivery must fail before that callback runs.
These component controls qualify no SDK authority, semantic source union, model
quality or untested platform. Native-exit observation retries transient procfs
read errors within its original bound; success still requires an absent process
or an observed exited state. Persistent read failure is not proof of exit.

### Check filesystem and terminal ownership

Filesystem cases need actual case/normalization behavior and inode checks. Native
fixtures use private homes, not the operator cache. The [sandbox chapter](sandbox.md)
teaches Linux prerequisites, signing, listener identity, and detached-work limits.
For copy/authority changes, run their real Rust fixtures:

```sh
IPSE_NATIVE_TESTS=$(mktemp -d)
rustc --edition=2021 --test -D warnings native/ipse-file-copy.rs -o "$IPSE_NATIVE_TESTS/copy"
"$IPSE_NATIVE_TESTS/copy"
rustc --edition=2021 --test -D warnings native/ipse-bound.rs -o "$IPSE_NATIVE_TESTS/bound"
"$IPSE_NATIVE_TESTS/bound"
rustc --edition=2021 --test -D warnings native/ipse-operator.rs -o "$IPSE_NATIVE_TESTS/operator"
"$IPSE_NATIVE_TESTS/operator"
mix test test/ipse/runner/operator_test.exs test/ipse/session/input_test.exs
mix test test/ipse/runner/leased_terminal_deadline_test.exs
```

Retain size/inode/symlink/permission/nonblocking controls and bounded ignored FIFO
probes. Linux tests authority/FIFO/descriptor transfer; macOS covers only portable
protocol cases. Operator tests use actual synthetic PTYs and the bundled helper's
compiled identity. They cover terminal matching, deadlines, parent loss, a stopped
old helper's cleanup fence and opaque Session witnesses. Run the native, operator
and PTY tests serially: their conservative per-user lock intentionally makes
overlapping native test programs contend. PTY input remains automated, and ordinary CLI/card adoption
and independent human journeys need separate verification. Keep atomic ordinals
and fixed-clock collision tests for parallel fixtures. The leased-terminal
deadline test covers arithmetic and rounding; it does not prove clock-rate or
suspend equivalence or replace the PTY and actual Session controls.

The private Linux Session/Host terminal bridge controls require a matched PTY;
the cancellation control also needs its test-only pause hook. They are excluded
from the default `mix test` run and must be run separately when qualifying that
boundary. From the repository root, after building the native helper, run them
serially:

```sh
IPSE_TTY_TESTS=$(mktemp -d)
rustc --edition=2021 -D warnings -O test/support/operator_pty.rs -o "$IPSE_TTY_TESTS/pty"
"$IPSE_TTY_TESTS/pty" "$(command -v mix)" test test/ipse/session/share_host_job_test.exs --only controlled_tty_bridge
IPSE_SHARE_TTY_PAUSE=1 "$IPSE_TTY_TESTS/pty" "$(command -v mix)" test test/ipse/session/share_host_job_test.exs --only controlled_tty_loss
```

These use synthetic output and do not qualify protected terminal delivery.

Probe macOS enforcement separately with a disposable workspace:

```sh
IPSE_MACOS_WORKSPACE=$(mktemp -d)
elixir dev/verify-macos-sandbox.exs priv/ipse-runner "$IPSE_MACOS_WORKSPACE"
```

Default checks file/network refusal, allowed paths, inheritance, and signing.
Optional process-boundary checks can expose documented detached-work gaps; nonzero/
gaps are not passing containment. Owned bundle/files are removed; macOS may retain
OS-managed app containers.

## Verify managed delivery and effect admission

Use [Session sources](session-sources.md#deliver-a-managed-export-input-under-its-original-owners)
for the current owner chain, [effects](extension-effects.md) for separate effect
permission, and [MCP](mcp.md) for transport ownership. Component transport receipts
do not replace real source proofs or the Session's selected dependency union.

### Settle actual Worker frames before cancellation

For the actual managed export adapter, also run:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only worker_input_boundary --max-cases 1
mix test test/ipse/extension/managed_collection_call_session_test.exs --only protected_outer_cancel --max-cases 1
mix test test/ipse/session/managed_supersession_session_test.exs --max-cases 1
mix test test/ipse/session/operator_assertion_integration_test.exs --only managed_approval:true --max-cases 1
mix test test/ipse/extension/managed_collection_call_session_test.exs --only native_root_approval --only root_subscriber_refusal --max-cases 1
```

The Worker-input selection checks paged delivery, strict Saved commitments and
permission withdrawal between a committed read and the next actual VM input,
including idle resume without callback replay. Its paged positive reads root metadata.
For cancellation, keep the independent VM at its explicit barrier. A callback
marker alone does not establish host input settlement. The settled case waits
for the matching delivered receipt before cancelling. The pre-settlement case
holds the actual writer-thaw response, queues cancellation in Session's mailbox,
then releases that response before the publisher can commit input completion.
Require actual publisher, Worker and native-helper exit, no invented input or
outer result, strict reconstruction and idle resume without callback replay.
The paired mismatch case sends different Session/job/input identifiers and must
still obtain the genuine delivered receipt. No hook changes authority or supplies
a successful native response. Run the complete baseline after the focused selection.

### Approve signed-source effects through the native sink

The genuine approval fixture additionally reads a committed note and its original
inactive Session proof. Its shell cases use the same actual native review and
require an exact file effect, owned spawn/cleanup records and shell stdout in
the next provider request's tool-result message. Checking the assistant's command
text would not prove that stdout was delivered. The paired source-change case
alters the original journal during the input wait and requires no effect admission
or target file after approval. Select these two cases with
`--only managed_shell_approval:true`; the complete `managed_approval:true` cohort
also preserves write approvals, denial, stale tokens, cancellation and owner loss.
Both shell consumers close and resume in the same effective mode with their exact
saved messages and the validated ownership suffix. Confirm the final signed release claim and
unchanged target after resume; recovery must start no command or model request.
A disclosed one-use BEAM controller pause inspects the
actual transaction's native descriptor set before its unchanged pipe write:
three policy locks, consuming/original Session locks, Session/Writer controls and
actual Worker stdin must belong to that same native process. The original lock
must remain busy. The native supervisor and importing transaction are distinct
processes; a Port PID alone cannot identify the importer.

### Exercise metadata roots across tools and transports

These cases in `managed_collection_call_session_test.exs` select root-only
metadata, not signed-note content. Their PTY children use the same SDK,
policy, provider responses and proposed effects. Inspect frozen ownership
with read-only system state: ordinary `Session.info/1` can correctly refuse
during a share. An independent request recorder avoids Terminal consuming the
fixture's own observation messages; it must supply no response or witness.

| Selection | Observe at the actual boundary |
| --- | --- |
| `--only native_root_approval` | Inspection then approved write/shell/MCP effect; version-3 union, physical target, completed registered requests and current result |
| `--only root_subscriber_refusal` | No-channel subscriber receives no private approval arguments |
| `--only native_root_fault` | Root/revocation/actual signed expiry after complete display admits no effect or third request; owner loss stops the consumer and releases its original lock |
| `--only native_root_running` | A genuinely approved shell has started; revocation preserves its effect but withdraws stdout, while owner loss stops the actual group/child before the delayed final write |
| `--only native_root_mcp_boundary` | Discovery remains available before approval; after the real catalog request and one `mcp.start`, revocation prevents `mcp.send`, tool call and target |
| `--only native_root_prestart` | HTTP revocation/expiry during input leaves complete traffic unchanged; the distinct stdio identity positive completes without entering its substitute helper |
| `--only native_root_loss` | After actual HTTP initialization or a held effect, consumer loss closes the socket or recorded stdio PID and releases the original OS lock |

Pair every fault with its allowed path, exact full approval dependency snapshot,
strict Saved reconstruction and inert idle recovery. Never delete or replace a
lock to make it acquirable. A registered shell resource, its native Port and
process-group anchor identify ownership; the turn task need not own that Port.
Missing committed effect cleanup must retain `managed_lineage_unavailable`
across resume; reuse `native_root_loss_lineage/2` rather than forging cleanup.

HTTP observations include **all** accepted connections through confirmed close
and idle close, including initialization and DELETE cleanup. Do not filter them
to manufacture unchanged traffic. Restore test-only environment selections in
`after`. Wait for an actual signed expiry and actual owner exit at the stated
stage, not a generic callback marker or a BEAM `DOWN` that can precede native
cleanup. Injecting around source acquisition can otherwise hit an earlier Worker
input instead of the intended later effect.

Follow [the source-owner walkthrough](session-sources.md#retain-sources-through-a-protected-display-or-review)
for retained descriptors and [MCP](mcp.md) for transport ownership. These
metadata controls do not substitute for original-note/current-use controls.
Run terminal/Rust cohorts serially under their shared per-user lock.

### Preserve nested effects and helper continuations

Pair native approval with actual effect and input observations in
`managed_collection_call_session_test.exs`:

| Selection | Required boundary |
| --- | --- |
| `--only nested_discovery` | MCP discovery finishes with at least four version-3 admissions before native input; current, denied, changed-root, revoked, stale-code, cancelled and lost-Session outcomes remain distinct |
| `--only native_nested_tool` | An approved file tool writes once and returns through guarded input; denial writes nothing; a stale-root write remains an unknown action without another Worker frame |
| `--only native_inference_approval` | Text, embedding and decision helpers retain their original model-tool invocation task, exact approved wire input, accounting and continuation across approval, denial and changed root |

Inspect the sealed parent/action/source binding and original task's tracked
effect owner during the native input wait. Foreign approval and completion calls
must refuse while its share is frozen. An allowed MCP or file effect requires
the physical target, successful guarded callback and completed command. Denial
returns a known denied action without dispatch. Cancellation and Session loss
commit neither the requested action intent nor another input. The separate
no-channel subscriber case must still withhold all approval arguments.

For inference, capture actual HTTP bodies through the registered native adapter.
Require only the approved helper messages or typed request, with no parent history
or tool definitions; an empty `tools` array supplies no definitions. A source
change during approval sends only the initial main request while retaining the
helper's failed/partial metering admission and unknown next input. Keep that
distinct from an unknown native write: Host stops before preparing another frame,
so the only delivered input is the original committed root read. Do not manufacture
an unknown input to represent that action. Each case preserves strict Saved state,
source commitments, exact idle-resume suffixes and unchanged effects/traffic. These
root-metadata controls establish no signed-note-content, live-model, human or
installed qualification.

Use `--only managed_nested_result` in
`managed_collection_call_session_test.exs` for explicitly allowed native and MCP
effects followed by actual guarded Worker continuations. Require the physical
write, successful complete callback, exact last-result/action-chain input hashes,
status-only native-tool preview and strict Saved/idle recovery. Its withdrawal
controls pause the real Session at the committed action reply, change the actual
root or permission outside the effect scope, then release the unchanged Host
continuation. The effect must remain recorded while no result callback runs;
the typed input is unknown and idle resume repeats neither effect nor delivery.
This fixture pause supplies timing, not approval or a native delivery receipt.

Use `--only helper_withdrawal_boundary` in the same suite to pair current generic
and decision helpers with source changes before their actual dispatch. Each stale
case must keep two metering admissions but observe exactly one HTTP request: the
initial main request. Require the failed helper action, its exact intent binding,
partial helper accounting and an unknown next input carrying the complete original
dependency commitment. Keep the listener alive through strict Saved reconstruction
and idle resume, with unchanged callback trace, messages and unknown input. The
separate completed-Worker case must still finish through a later main request
containing only the withdrawal notice; its original result remains unchanged.
These distinct timings prevent an earlier input refusal from masquerading as a
successful later-main continuation.

### Observe signed-note helper dispatch and ordinary final use

For the same preflight boundary with eight actual signed notes, use separate
fresh roots for the allowed and withdrawn-source cases. First build the matching
helper with `./dev/build.sh`. On the supported Linux notes profile, select a
qualified fixture filesystem; the example uses tmpfs at `/dev/shm`, not an
assumption that `/tmp` supports protected storage. The two seed roots must be
absent. Build the test graph and run:

```sh
MIX_ENV=test mix compile --warnings-as-errors
IPSE_NOTE_TEST_ROOT=$(mktemp -d /dev/shm/ipse-decision-pack.XXXXXXXX)
TMPDIR="$IPSE_NOTE_TEST_ROOT" elixir --erl '+S 2:2' test/support/managed_literal_pair_runner.exs "$IPSE_NOTE_TEST_ROOT/allowed" _build/test/lib split
TMPDIR="$IPSE_NOTE_TEST_ROOT" IPSE_LITERAL_AB_ROOT="$IPSE_NOTE_TEST_ROOT/allowed" IPSE_TEST_MANAGED_PACK=1 mix test test/ipse/extension/managed_collection_call_session_test.exs --only managed_pack_actual_overflow --max-cases 1
TMPDIR="$IPSE_NOTE_TEST_ROOT" elixir --erl '+S 2:2' test/support/managed_literal_pair_runner.exs "$IPSE_NOTE_TEST_ROOT/stale" _build/test/lib split
TMPDIR="$IPSE_NOTE_TEST_ROOT" IPSE_LITERAL_AB_ROOT="$IPSE_NOTE_TEST_ROOT/stale" IPSE_TEST_MANAGED_PACK=1 mix test test/ipse/extension/managed_collection_call_session_test.exs --only managed_pack_actual_overflow_stale --max-cases 1
```

The allowed path must deliver the shadow result without publishing notes. For
withdrawal, require all eight observed note dependencies, a failed decision
with no decision dispatch, one main request, partial helper accounting and an
unknown next Worker input. Restore the original source inode and bytes, then
require strict saved reconstruction and idle resume with no replay. Fixture
cleanup also restores a held source after an interrupted assertion. The
loopback service and terminal input are synthetic, not live-engine or human
quality qualification.

`split` creates eight notes across two originals. Use `split8` when requiring
eight distinct original Sessions, and assert the seed manifest's actual source
count. The allowed case also compares Worker and ordinary final-use observations:
both independent passes must batch, while root-only dependencies retain fresh
root reads. Preserve its context/recipe/dependency/source/expiry/revocation
refusals, genuine view-capacity fallback, strict Saved and same-mode idle checks.

### Retain inherited input and result capacity

Run `--only worker_inherited_union` in the same suite for actual A/B input
boundaries. Each case builds its own matched PTY driver and creates a fresh
current-runtime native statement/publication seed in a private home, with no
external seed directory or historical BEAM overlay. Consumer selection remains
explicit trusted fixture configuration. The negative pauses after B's actual
quote commits, removes A's original journal and requires an unknown input with
no next callback. The independent-B positive requires the actual stored record,
current B proof, registered-model continuation, strict Saved/idle recovery and
byte-identical restoration of A. Retained roots print as `WORKER_INHERITED_ROOT`.

Use `--only worker_input_capacity` for managed page-input journal accounting.
After actual source begin, the disclosed owner-side hook obtains a real competing
Writer reservation, leaving eight general events or 4096 general bytes. The
admitted five-page result must complete from its own token, materialize, release
only its unused capacity and survive strict Saved/idle checks. The hook changes
no limits, deadlines or source permits. A separate 65536-byte journal case must
refuse before source begin without sealing or leaking reservations. Retained
contention roots print as `WORKER_CAPACITY_ROOT`. Keep the ordinary 4-MiB result regression and populated capacity checks separate
from this journal-reservation control.

Use `--only managed_presentation_input` and `--only managed_sink_input` for the
unsupported private Worker purposes. Preserve actual ordinary formatter/text/
notification/feed callbacks and acknowledged managed metadata delivery. Managed
private inputs must stop before their respective intent, queue or dependent
model request; optional notifications remain known unstarted, required ones fail,
and already committed effects survive. Include required text on an ordinary
registered model route so a callback-child/producer identity error cannot pass
as a managed-data refusal. Inspect exact idle suffixes: a selected
`lifecycle.record` process records a valid new resume epoch as well as its release
owner, while initializing no consumer or feed. These controls use synthetic
root metadata and real callback artifacts; they establish no record-content,
installed, human or quality qualification.

## Verify native note management and clocked retention

The [operator procedure](../operator/knowledge-permissions.md) defines the fresh
review commands. [Knowledge extensions](knowledge-extensions.md#confirm-a-pending-decision)
and the [Collection SDK](collection-sdk.md#manage-a-retained-note-through-native-review)
own candidate facts, native permits, publication and deferred settlement. These
recipes test those distinct boundaries; a structural fixture supplies no permit.

### Retain accepted-decision journals through approval

For accepted-decision approval, run the distinct native journey and Writer
snapshot controls serially:

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_APPROVAL=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_approval --max-cases 1
mix test test/ipse/session/share_barrier_test.exs --only approval_journal_snapshot --max-cases 1
```

The journey first captures through the registered adapter and accepts a real
pending card through the public native review. Unmodified consumer cases approve
one exact workspace write and deny another, preserving both original journals.
Observed child hosts install a disclosed pre-display pause before their normal
entry/policy admission. The unchanged native send then receives the actual
source, policy, consuming Session and acceptance-journal lock descriptors plus
Session/Host controls. The observer checks the exact sealed/frozen Writer
snapshot and current journal token/link/operation. Its separate loss case kills
that actual exported journal helper before display, requiring no approval payload,
no tool/effect start, CLI failure and consumer death, followed by strict Saved and
idle recovery without replay. Private JSON fixture data supplies no native permit
or completion witness. The small Writer tests establish private inode admission
and the combined 128-entry bound; they do not establish 128-note recall capacity.

For history expiry, create the successor through the current native Session
correction flow, retaining its actual statement source, separate relation review,
settled publication and confirmed close. Keep the original signed retention
deadline and wait for it before public reclamation. A standalone review receipt
cannot replace the Session/source-owner fence of a current correction. The
`save_history_expire` case in `operator_assertion_integration_test.exs` checks
the complete path, including disabled capture, retained successor, zero inference
and an unchanged original journal.

### Reject, correct or accept pending candidates

For pending rejection, first run the synthetic-source/native management grid:

```sh
mix test test/ipse/cli/management_reject_public_test.exs test/ipse/session/pending_rejection_test.exs --include native_sandbox --max-cases 1
IPSE_TEST_GENUINE_PENDING_REJECTION=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_rejection --max-cases 1
```

Pair read-only `knowledge defer` inspection with live/expired and revoked
targets; require exact deadline/revision/hash and unchanged Collection,
accounting and journals. Then exercise stale/cancelled review and concurrent
management/root changes. The opt-in Session journey must create a genuine
proposal, cancel without effect, disable capture and reject with the original
source unavailable. Require exact candidate suppression, preserved shared
source/peer/anchor, settled zero-service accounting and old-backup refusal.
Its failure root prints as `PENDING_REJECTION_ROOT`.

Combine the existing `--knowledge` and `--management-review` PTY modes when
exercising disablement and rejection. Follow [proposal management](knowledge-extensions.md#confirm-a-pending-decision)
for facts and authority; deferral renews neither expiry nor acceptance permission.

Pending-text correction has its own preparation, capacity and native journeys:

```sh
mix test test/ipse/session/pending_correction_test.exs test/ipse/cli/management_correction_public_test.exs test/ipse/extension/pending_capacity_test.exs test/ipse/extension/collection_review_gate_test.exs
IPSE_TEST_GENUINE_PENDING_CORRECTION=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_correction --max-cases 1
IPSE_TEST_GENUINE_PENDING_CORRECTION_DEADLINE=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_correction_deadline --max-cases 1
```

Run opt-in cases with separate fresh-bundle runtimes. Preserve source/time/
category and peers, stale/cancelled refusals, source withdrawal/revocation during
input, retired-key refusal and a separate fresh acceptance of the edited key.
The actual-deadline case stages before its short trusted expiry and waits past
that deadline: require the old root, full unknown liability, an unconfirmed
journal and identical repeated inspection. Its owner-side telemetry pause
supplies fault timing, never a permit, fabricated clock or native receipt.
Failure roots print as `PENDING_CORRECTION_ROOT`.

For selected batches, run the pure boundary/membership and CLI denial checks,
then each actual-Session native case in its own fresh SDK/bundle runtime:

```sh
mix test test/ipse/session/pending_batch_test.exs test/ipse/cli/management_batch_public_test.exs
IPSE_TEST_GENUINE_PENDING_BATCH=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_batch --max-cases 1
IPSE_TEST_GENUINE_PENDING_BATCH_PARTIAL=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_batch_partial --max-cases 1
IPSE_TEST_GENUINE_PENDING_BATCH_EIGHT=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_batch_eight --max-cases 1
```

Pure 8-KiB vectors prove shape only. Actual batches must capture each proposal,
retain its original journal and obtain a different fresh native event/code per
item under one manifest. Cancellation, stale input and source withdrawal stop
before promotion. Cancelling item two must preserve the known first acceptance
and exact remaining pending record, with separate accounting and inert inspection.
The eight-item case uses a disclosed 16-operation fixture allowance, not a quota
increase. Check each manifest/proof/item index/count and retain `PENDING_BATCH_ROOT`.

### Recall, retain and retire accepted decisions

The `genuine_pending_accepted_recall` journey in
`test/extensions/knowledge/knowledge_session_test.exs` builds fresh artifacts,
captures two proposals and accepts through the actual public native review.
Capture and recall endpoints require distinct explicit service IDs; rebinding
an existing ID to another origin is a real refusal. Select actual returned
source handles, not presumed user-message order. The importer must retain the
original management journals alongside the Session sources.

Require single/multiple-decision wire recall, strict Saved and altered-event
refusal. A cancelled forget changes nothing. After disablement, successful
forgetting with the original Session source unavailable must preserve the link,
peer and journals, authenticate exact-target suppression, and refuse reacceptance.
Its retained root prints as `ACCEPTED_RECALL_ROOT`.

The separate post-switch owner-loss step uses
`accepted_decision_forget_loss.exs` to pause the child at that exact boundary.
Require CLI failure, an absent target, authenticated suppression, unchanged link
and stopped native owner/Port. The journal remains unconfirmed and reservation
publishing. Repeat inspection, not the mutation, with identical control/journal
bytes. This controlled fault is distinct from unmodified successful forgetting.

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_RECALL=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_recall --max-cases 1
```

The pure target/type grid is `test/ipse/session/accepted_decision_lifecycle_test.exs`;
those shaped fixtures grant no native authority or current-use permission.
To verify accepted-decision reclamation, run the separate actual-deadline journey:

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_EXPIRY=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_expiry --max-cases 1
```

This actual-deadline fixture accepts through the registered provider/native CLI
under a short trusted saved policy. First require unchanged target/control
before expiry; then wait past the actual signed deadline and reclaim after
disabling capture and withholding the original source. Target/live rows disappear
while anchor clocks, link, peer and original journals remain. Check settled
zero-service expiry accounting and duplicate-acceptance refusal. Keep the shared
literal/history normalizer controls when changing this path; a short real wait
is not annual endurance.

The accepted-retention journey checks the complete choice/read/lifecycle path:

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_RETENTION=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_retention --max-cases 1
```

Require native pin, actual registered-wire recall, cancelled review, automatic
retention and public finite duration for ordinary/preference/current decisions.
The short-duration component waits for real expiry, refuses another pin without
control changes, then reclaims after disablement with the source unavailable.
Record/link bytes stay exact; only signed metadata changes, one generation per
committed operation. Its disclosed 16-operation allowance is fixture setup.

Validate the compact retention witness and legacy deadline-mismatch refusal
without it. Pure pages prove consistency, not native Review authority. Shared
leases must work at the ordinary resource ceiling, reject foreign/forged/spent
handles and preserve the combined original-owner bound. Use the
[fresh-runtime recipe](../archive/2026-10-26-p30-p31-implementation/pending-review-boundary-20261031.md#local-evidence-and-limits)
with the matching opt-in variable/tag; [the management owner](collection-sdk.md#manage-a-retained-note-through-native-review)
explains publication and settlement.

### Follow literal relations and process-clock retention

For literal-replacement lifecycle checks, reuse
`test/support/managed_supersession_session.exs` for actual statement/relation
reviews, physical publication and exact close/resume suffixes. The history-use
and interrupted-compaction launchers select their distinct follow-up checks in
that isolated child process. Extend those checks rather than copying the setup:
a copied fixture can retain obsolete ownership assertions even while exercising
the same production path. Run the related native cases serially:

```sh
mix test test/ipse/session/managed_supersession_session_test.exs test/ipse/session/managed_history_use_session_test.exs test/ipse/session/managed_compaction_diagnostic_test.exs --max-cases 1
mix test test/ipse/session/managed_supersession_native_test.exs test/dev/knowledge/managed_v3_turnover_native_test.exs --max-cases 1
```

History use checks signed historical attribution, successor removal, unavailable
originals and revocation. Interrupted compaction kills the original caller after
staging and requires native controller exit, an unchanged root, unconfirmed
journal/control status and no replay. Its printed directory retains synthetic
diagnostic evidence. Neither check establishes annual turnover, complete capacity
or model quality.

`managed_supersession_native_test.exs` runs its six default modes through that
genuine Session path. The split fixture pauses after the actual new assertion
is committed but before its worker selects a root, then seeds explicitly
synthetic page geometry around the authentic selected records. Publication must
still authenticate the real old/new sources, use native review and commit all
eight sidecars within the closed read and measured reservation bounds. Filler
rows supply no source authority or capacity-quality result.

The deadline control pauses at the actual root-switch boundary, waits past the
exact signed target deadline and requires the native elapsed reply while its
transaction remains live. Deterministic pause modules are installed in their
isolated child host before initial permission review and retain stable inventoried
BEAM paths. They change no native helper or production source. Distinguish these
controlled-host faults from unmodified runtime qualification. The existing
turnover records separate genuine native review time from an explicitly supplied
future as-of expiry component. They do not exercise a native year-long lifecycle.

Before building a process-clock lifecycle workload, verify that the selected VM
and Rust standard library observe the same instrumented clock:

```sh
elixir -e 'ExUnit.start(max_cases: 1); Code.require_file("test/dev/knowledge/process_clock_test.exs")'
```

This standalone check starts no Ipse application and needs no built SDK or native
terminal. It compiles `dev/fixtures/process_clock.rs` as a private Linux/glibc
x86-64 preload library and uses fresh plain VMs/Rust children in private homes.
It compares realtime clocks with raw kernel observations at zero, fractional-second
and 30/90/365/400/466/500-day offsets, checks real monotonic timers, and requires malformed
or missing offsets to refuse wall reads. Other platforms skip explicitly.
The loader and syscall ABI reuse the [existing host dependency](dependencies.md#host-and-build-inventory).

The offset is fixed before exec and applies only to that process tree. A lifecycle
driver must finish or inspect all admitted work, confirm owner exit and release,
then start new processes at the next simulated day; it must not advance clocks
across a live native permit or unknown operation. Actual native review, signed
deadlines, publication, accounting and recovery remain required. This fixture
does not alter the machine clock, kernel file timestamps or the production helper,
and its preload is never a production configuration option. Clock coherence alone
qualifies no turnover, capacity, model quality or elapsed real year.

After building the matching helper on a supported native allocation profile,
exercise actual signed retention across fresh processes:

```sh
mix test test/dev/knowledge/managed_clock_lifecycle_test.exs --max-cases 1
```

Require actual statement/relation reviews, settled publication, confirmed close
and the original signed deadlines. The first journey checks pinning at day 30
and ordinary/history reclamation at days 91/366. The second creates its first
successor at day 100, refuses early history reclamation at days 366/464 and
reclaims at day 466. Original Session bytes and the retained successor must
survive. Repeated operation inspection and idle recovery change neither the
journal nor the recorded deadline.

These are finite signed-retention controls, not a real elapsed year or a
completed annual workload. The [storage lifecycle guide](knowledge-storage.md)
owns the native runner/audit contract; [Session sources](session-sources.md)
owns current-source checks at later use. A standalone review receipt cannot
replace the actual correction's Session/source-owner chain.

Late Session work also needs coherent clocks inside stdio. Production stdio
deliberately removes ambient environment from its supervisor and child. Its
unchanged native pipe handoff refuses a deadline more than five seconds away,
so preloading only the outer VM cannot establish this test clock. The late
journey therefore uses a private copied SDK whose Runner adapter adds only
`LD_PRELOAD` and `IPSE_TEST_CLOCK_OFFSET_MS` to both stdio environments. Every
phase checks the copied Runner hash, actual child-clock coherence and removal
of an unrelated synthetic environment canary. This is a disclosed controlled
host; production source, helper bytes, five-second handoff bound and permissions
are unchanged. The first journey retains the stock host. Never add these test
variables to production environment handling.

The printed `NATIVE_CLOCK_LIFECYCLE_ROOT` retains synthetic logs, copied runtime
identity and phase reports, including failures. All work closes before the next
process date; no application, helper or machine clock changes globally. These
few operations establish their clocked paths, not frozen daily intake,
overlapping owners, offline imports, compaction, maximum payloads or annual
turnover with the selected additional 10,000 mixed changes. Run that complete
workload separately. No active Session is carried across these process dates.

The [native population runner](knowledge-storage.md#populate-through-actual-native-statements)
reuses `ManagedClockLifecycle.check_stdio_clock/1` and checks copied source/SDK/
dependency bytes before every bounded segment. Run its two-day smoke separately
from the full 2,100-effect initial plan in
`test/dev/knowledge/native_notes_seed_test.exs`. Then use the
[complete population audit](knowledge-storage.md#audit-the-complete-retained-population)
against the exact closed root/control and every signed note.

Audit the cohort's frozen SDK with a separately copied current caller; it starts
no terminal review or publication. Inflight/incomplete stores and reused output
paths must refuse. Preserve failed cohorts and their claims: restoring a
deliberately changed empty fixture grants no replay permission. Clock, smoke
and read-only audit passes do not establish annual capacity or quality.

## Verify document acquisition and generation

Follow [document ingestion](knowledge-extensions.md#follow-acquired-document-bytes-into-cited-storage)
and [Collection storage](collection-sdk.md#stage-ordinary-documents-under-their-own-grant)
for source and publication authority. Keep parser/extraction, workspace source
ownership, native staged storage and installed fidelity as separate assertions.

For document Collection split-append changes, run the native staged-publication,
root-race and empty-facts controls with:

```sh
mix test test/extensions/knowledge/collection_split_append_native_test.exs
```

The fixture builds a Corpus artifact and runs each tagged control in a separate
worker VM, so it does not rely on domain modules loaded by another test. It
does not establish full Collection capacity or installed document quality.
The producer progression model uses the same isolated-artifact approach:

```sh
mix test test/extensions/knowledge/producer_progress_test.exs
```

Its geometry and fault controls exercise bounded synthetic model data; native
publication and full source/Session qualification need their separate checks.

For Word ingestion, run `mix test test/extensions/knowledge/document_ingestion_test.exs`.
Its child VM uses the selected SDK and dependency paths rather than inheriting
unrelated parent code paths. The fixture checks synthetic documents and does
not replace real-Word fidelity or installed-user qualification.

For the Collection workspace snapshot and publication boundary, first run
`./dev/build.sh` to refresh the shipped artifact catalog, then run:

```sh
mix test test/ipse/session/workspace_acquisition_test.exs test/ipse/session/workspace_snapshot_binding_test.exs test/ipse/extension/collection/workspace_document_guard_test.exs test/ipse/session/document_effect_activation_test.exs test/ipse/session/resources_authority_test.exs
mix test test/extensions/knowledge/document_acquisition_session_test.exs --only workspace_word_cancel_registration --only workspace_word_capacity_boundary --max-cases 1
```

The narrow native selection runs three synthetic cases. Registration cancellation
must confirm cleanup, leave the same Session idle, stop the dormant peer and
publish no source head. Component controls distinguish this unstarted work from
active document or generic file effects, whose uncertain completion remains
unknown. The capacity cases acquire exactly 1 MiB of original bytes and 64 KiB
of extracted UTF-8 text in 32 chunks, verify first/middle/last citations, and
withhold evidence after replacement or loss of the original. Identical restoration
and same-ID resume must recover citations without replaying acquisition. Separate
one-byte-over originals and extracted text must refuse without replacing the head.

Use `--only workspace_word_native` instead for the broader changed-file,
owner-loss and recovery cohort. The fixture verifies the shipped catalog and
imported artifact, but the catalog alone cannot establish that it was freshly
built from current source. A PNG thumbnail's inert padding exercises original
byte geometry and retains its explicit unexamined-part warning; it does not
qualify rendered-Word fidelity. Installed-package and independent
document-quality checks remain separate.

## Diagnose with synthetic data

For the integrated notes workload's loopback provider, run
`mix test test/dev/knowledge/synthetic_ollama_lifecycle_test.exs`. The listener
monitors its owner while idle and while reading a request, reports bounded fixture
failures, and closes on owner loss. Its request-read limit is 30 seconds total;
the workload runner retains its separate 120-second request wait and 30-second
completion wait. An interrupted turn remains unknown and is never replayed.
These synthetic controls do not establish populated recall or a completed day.

Use observability privacy/pressure fixtures and compare callback failure with real
cleanup against interrupted trace catalog publication. For argument-free dispatcher
sampling:

```sh
./bin/ipse extension check --config priv/demo/operator.json \
  --fixture priv/demo/conformance.json --extension annotation --no-project-config \
  --developer-trace --trace-ms 1000 --trace-events 32
```

`Observability.Trace` uses isolated OTP27+ trace sessions on the new synthetic
Session's exported callbacks. Reports retain arities/timings, without args/messages/
state/returns/PIDs. Unsupported OTP refuses, without legacy global tracing. One
sample is in flight; disarmed calls are gaps. Complete is always false, with
one-in-flight sampling. Limits are 1..5000 ms/1..128 samples, defaults 1000/32.
Watchdog stops on deadline/dependency death subject to scheduling; cleanup failure
fails conformance. This is dispatch sampling, not complete timeline/latency profiling.

For incomplete stdio, keep runtime deadlines/strict receipts while allowing enough
observation time for admitted init/callback/close. CLI freeze/launch/exit timing
cannot identify every inner wait. The captured-CLI fixture runs seven invocations
under one two-minute test watchdog; its expiry identifies no individual stalled call:

```sh
mix test test/dev/evaluation/declaration_cli_test.exs --seed 596778
IPSE_TEST_STDIO_PROBE=1 mix test test/ipse/runner/diagnostics_test.exs test/ipse/extension/feeds_test.exs
```

The probe retains fixed phases/classified results/arities/timings, without payloads
or environment. Its isolated session ends at owner loss/twenty seconds/64 calls and
labels coverage incomplete. MCP stages permit sixteen fixed timing records; absent
stages explain no cause. Privacy fixtures reject unrelated/private markers.
Bounded frame/drain load uses explicit trial/concurrency limits:

```sh
mix run dev/diagnose-stdio-cleanup.exs --iterations 1000 --concurrency 16 > /tmp/ipse-stdio-cleanup.jsonl
mix run dev/diagnose-stdio-cleanup.exs --iterations 100 --concurrency 4 --sandbox native > /tmp/ipse-stdio-native.jsonl
```

Native setup serializes and never falls back. Debugger breakpoints alter scheduling
and may expire deadlines. Formatted redaction protects neither raw state nor locals.
No debugger listener/distributed node is enabled. Remote diagnostic exporters need
explicit destinations/TLS/credentials and dependency review.

## Design comparisons and independent review

Freeze acceptance inputs/criteria before authoring, with positive/refusal/lifecycle
cases and independent held-out material where needed. Repeating one exposed case
is tuning, not new independent coverage. Freeze runner outside a self-development
candidate and retain exact revision, uncommitted diff, config/artifact/input hashes,
exclusions, assistance, and reviewer model/scope. The author should not be the only
reader of its delivered artifact. Separate fresh reviewer context from private
author reasoning. Static review cannot certify unexecuted runtime/OS behavior.
[Operator workflows](../operator/development-workflows.md) provide the complete
frozen-runner task; the scripted `dev/demo-self-development.exs` proves skill/resource
loading, not coding quality or unattended operation.

Name the quantity measured. `dev/measure-memory.exs` measures a fixed lexical
fixture, stored state, latency, and sampled VM memory, without inference. It proves
neither semantic support, exact peak, invoice cost, nor another host's performance.
Startup has a separate exercise. Actual-model quality/exact charged-RAM uses
[frozen evaluation](knowledge-evaluation.md) and [measurement](measurement.md).
Null metering is unavailable, not zero; estimates and reservations have distinct
[accounting](accounting.md) rules.

Review new dependencies, endpoint/TLS/proxy authority, credential boundaries,
terminal escaping, hidden reasoning, and privacy on error paths. Follow the
[private reporting procedure](../../SECURITY.md#reporting) for vulnerabilities.
Live accounts, external scans, model calls, publication, and deployment need their
applicable authorization; repo text does not grant it. Keep private transcripts,
secrets, and raw reports outside Git. Publish sanitized evidence only as authorized.

Finish with behavior, exact commands/results, failed/excluded checks, assistance,
and remaining limits. Dated evidence goes to the archive; status to the plan.
Inspect the exact revision's [hosted workflow](../../.github/workflows/ci.yml), including
later native/package steps. Its 60-minute platform job budget is separate from
model/worker/native/test deadlines. A green source step does not prove skipped
later gates, and a partial review retains its omissions after local repairs.
