# Review and verify a complete change

Choose an observable property, exercise the complete path, then verify the actual
candidate at its source, process, platform, and installed boundaries. Evidence
belongs to the revision/configuration/environment tested. Fixtures prove no real
account behavior, algorithm quality, or unexecuted OS guarantee.

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

Pure fixtures must also reproduce the host's canonical dependency union. Use
`ManagedReference.union/1` before placing reads into an invocation, including
negative variants. Session stores reads in digest order; two individually valid
cached root observations in another order are not a valid invocation input.
Keep the full set and change only the intended root, policy or cache condition
when testing its refusal. A populated fixture cache is trusted consistency data,
not evidence of a committed read or current publication authority; the registered
Session cases below establish those boundaries separately.

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
live-page split fence. Each Session must complete, settle and close; idle resume
may append only its ownership record before confirmed close, with no Worker replay.
A separate legacy-reader case first creates a genuine managed record through the
registered route, then requires a newly reviewed legacy reader to refuse its text.
These two cases retain private synthetic roots printed as `REGISTERED_CAPTURE_ROOT`.
They exercise repeated additions, not elapsed retention, annual turnover or quality.

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
Synthetic responses establish this source path, not live-model quality or an
installed runtime.

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

Capture the journal after `Session.close_confirmed/1` returns. On idle resume,
require those bytes as an exact prefix. With the current release-receipt layout,
the only suffix before closing the resumed Session is one complete ownership
record validated by `ReleaseReceipt.valid_owner_marker?/2`; legacy journals with
no receipt layout remain byte-for-byte unchanged. Confirmed close then appends
its release intent. Validate that intent against the same owner and the native
signed-release claim separately from the resume assertion. Neither ownership nor
release records permit replaying effects or changing prior conversation records.
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
controlled-host faults from unmodified runtime qualification. Turnover records
separate the genuine native review time from an explicitly supplied future
as-of expiry component; neither a virtual timestamp nor native IO proves that
a year actually elapsed.

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

Run subprocess controls in isolation as well as in the full suite. Declare every
module they load and use absolute source/code paths with a private working
directory. A plain Elixir VM can otherwise resolve an application from the
checkout's basename, and a previously loaded fixture can hide a missing dependency.

The declaration-CLI fixture copies tracked and nonignored untracked repository
files into a temporary synthetic repository. Run the full suite from a clean
committed clone when the working checkout contains private or unrelated untracked
files; do not let a verification fixture copy those files as test input.
An isolated source copy also needs its own Git metadata and admitted source index
for this fixture's `git ls-files` call. Record that setup before execution; a
directory copied without `.git` cannot establish a passing declaration workflow.

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
Successful idle resume preserves the exact prior journal bytes and adds only the
validated ownership record and confirmed-close release intent. The verifier checks
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

For the actual managed export adapter, also run:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only worker_input_boundary --max-cases 1
mix test test/ipse/session/managed_supersession_session_test.exs --max-cases 1
mix test test/ipse/session/operator_assertion_integration_test.exs --only managed_approval:true --max-cases 1
mix test test/ipse/extension/managed_collection_call_session_test.exs --only native_root_approval --only root_subscriber_refusal --max-cases 1
```

The first suite checks paged delivery, strict Saved commitments and permission
withdrawal between a committed read and the next actual VM input, including idle
resume without callback replay. Its paged positive reads root metadata. The
genuine approval fixture additionally reads a committed note and its original
inactive Session proof. Its shell cases use the same actual native review and
require an exact file effect, owned spawn/cleanup records and shell stdout in
the next provider request's tool-result message. Checking the assistant's command
text would not prove that stdout was delivered. The paired source-change case
alters the original journal during the input wait and requires no effect admission
or target file after approval. Select these two cases with
`--only managed_shell_approval:true`; the complete `managed_approval:true` cohort
also preserves write approvals, denial, stale tokens, cancellation and owner loss.
Both shell consumers close and resume idle with their exact saved messages and
only the validated ownership suffix. Confirm the final signed release claim and
unchanged target after resume; recovery must start no command or model request.
A disclosed one-use BEAM controller pause inspects the
actual transaction's native descriptor set before its unchanged pipe write:
three policy locks, consuming/original Session locks, Session/Writer controls and
actual Worker stdin must belong to that same native process. The original lock
must remain busy. The native supervisor and importing transaction are distinct
processes; a Port PID alone cannot identify the importer.

Keep root-only metadata distinct from a signed note's contents. The original
write/shell/MCP positives and fault controls in
`managed_collection_call_session_test.exs` use the `native_root_approval` tag.
Their parent launches the same test and SDK fixture inside the existing PTY
driver; the child retains the original policy, root observation, provider
responses and proposed effect. Require the inspection tool followed by the
approved effect, version-3 dependencies without a literal upgrade, three
completed requests, confirmed effect cleanup/current result and strict Saved/idle
recovery. An OTP Agent records actual HTTP requests because Terminal consumes its
own mailbox; it supplies no response or completion witness. Observe the frozen
Session with read-only system state, since ordinary `Session.info` can correctly
refuse during ownership transfer.

For each tool, inject root change, revocation, expiry or owner loss only after
the actual terminal has displayed the full proposal and is waiting for input.
The first three faults still receive the native answer but must admit no effect,
release a withdrawn result and make no third provider request. Expiry waits for
the original signed wall-clock deadline. Owner loss kills the original consumer
and supplies no answer; require its actual lock to become acquirable before
resuming that same Session. Do not delete or replace the lock. All faults retain
the exact saved messages and version-3 dependencies across idle resume, with no
target, MCP tool call or additional provider request. Use `--only native_root_fault`
to select these twelve waiting controls; running-operation and HTTP boundaries
need their own controls. The paired subscriber control still withholds arguments
when no native channel can own their display. Native approval is not permission
to bypass that refusal.

Select `--only native_root_running` for the two shell execution boundaries.
Both receive genuine approval before the original delayed command creates its
`shell-started` marker. Revocation then preserves the command's completed file
and private observed stdout, but requires withdrawn result delivery, no stdout
result in the captured terminal and no third provider request. Owner loss instead
kills the consuming Session before the final write. Follow the registered shell
resource to its actual effect process and native Port, rather than assuming the
turn task owns that Port. Observe its process-group anchor, shell and sleep child;
require their exit and an absent final file after the original command duration.
Both cases compare the complete retained reference union with the actual approval
snapshot and preserve strict Saved state and inert idle recovery. Use the shared
`native_root_loss_lineage/2` assertion for these and the MCP loss cases below:
missing effect cleanup keeps lineage reconstruction unavailable across resume.
These controls do not establish native sandbox confinement or detached-descendant
behavior.

Use `--only native_root_mcp_boundary` for root-metadata approval across stdio and
HTTP. Pair each allowed start/send with revocation after its admitted start. Set
the existing service gate only during the native approval input wait, so ordinary
initial discovery remains possible. After the fresh answer, wait for the real
service's next catalog request and require exactly one journaled `mcp.start`
admission before revoking and releasing that request. The service must receive
no tool call and create no target; the journal retains confirmed start cleanup
and withdrawn delivery without `mcp.send` or a third provider request. Preserve
the positive's exact file, one tool call and separately confirmed start/send.
The `--only native_root_prestart` selection adds HTTP revocation/expiry during
the native input wait and a stdio helper-identity positive. Capture all accepted
HTTP connections before changing the policy, wait for the original signed expiry
when selected, and require identical traffic after the answer with no admitted
effect, target or tool call. For helper identity, set the existing substitute
only after the genuine display and before the answer; the full allowed call must
complete while its `--admitted-stdio` marker stays absent. Restore the prior
environment selection in `after`, including on assertion failure.

Use the same strict Saved and idle recovery checks for both transports. For HTTP,
take the complete accepted-connection log after confirmed close, including cleanup
traffic, then require identical bytes after idle resume and its confirmed close.
Do not filter out initialization or DELETE requests. HTTP uses an explicitly
selected loopback fixture with the normal config loader; it supplies no TLS or
remote-service qualification.

Select `--only native_root_loss` for lost HTTP initialization and held HTTP/stdio
owner loss. Set the existing fault flag during native input, then require the
actual initialization-received marker or physical tool effect before observing
automatic termination or killing the consumer. Held loss must stop the registered
transport and close the real HTTP socket or stop the recorded stdio server PID.
Wait for the original OS lock to release before strict Saved and idle recovery.
Compare the complete retained reference dependencies with those displayed for
approval. In these fixtures, derive reconstruction availability from committed
effect cleanup: a missing record requires `managed_lineage_unavailable`, which
must survive resume; confirmed cleanup lets the reconstruction API return the
retained union. Current use still requires fresh admission. Do not forge a cleanup
record or delay the original fault to obtain an available lineage. Require the appropriate
absent/preserved target, unchanged tool/model counts and, for HTTP, identical full
traffic after settled cleanup and resume.

Inject a fault at its actual purpose: a hook around shared source acquisition
may now intercept an earlier Worker input, before a later publication watcher
exists. Keep independent allowed-path and denial assertions, and preserve the
first failed evidence when repairing fixture timing. These synthetic local-route
controls establish neither human attribution, live-model quality, installed
delivery nor accepted-decision support by those cases. Run Rust native tests and Mix terminal
cohorts serially because they share the conservative per-user terminal lock.

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

The separate opt-in `genuine_pending_accepted_recall` journey in
`test/extensions/knowledge/knowledge_session_test.exs` uses freshly built isolated
Knowledge artifacts, two ordinary captures and actual public native acceptance.
Its registered capture and recall endpoints use distinct explicit service IDs;
reusing a protected ID for a different origin is a real refusal. Wire fixtures
must select actual returned source handles rather than infer task order from
user-role messages after native reference framing. The accepted-input observer
adds the original management journals to its actual importer descriptor checks.
Run the single- and multiple-decision cases with strict Saved, original-source
and altered-event controls. After the multiple-decision recall, the same journey
also cancels a native forget without changing the target, disables capture, then
forgets one accepted decision while its original Session journal is temporarily
unavailable. It authenticates the retained exact-target suppression, refuses
reacceptance planning from that retired anchor, preserves the immutable link and
other decision, and verifies settled zero-service accounting and unchanged
original journals. Its synthetic root prints as `ACCEPTED_RECALL_ROOT`.
The same journey then forgets the remaining accepted decision with the native
transaction owner killed after its durable root switch and before cleanup.
`accepted_decision_forget_loss.exs` installs a test-only child-host pause at that
exact boundary; the native helper and production source files are unchanged.
Require a failed CLI result, an absent target, authenticated exact-target
suppression, the unchanged immutable link, and stopped native owner/Port.
The management journal must be unconfirmed and its reservation remain publishing.
Inspect twice and require identical journal/control bytes and no replay. This
controlled-host fault is separate from the unmodified successful forget.

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_RECALL=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_recall --max-cases 1
```

The pure target/type grid is `test/ipse/session/accepted_decision_lifecycle_test.exs`;
those shaped fixtures grant no native authority or current-use permission.
To verify accepted-decision reclamation, run the separate actual-deadline journey:

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_EXPIRY=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_expiry --max-cases 1
```

It captures through a registered synthetic provider and accepts through the real
native CLI. The trusted fixture shortens the saved policy before acceptance;
the resulting native publication stores that actual finite deadline. Require
refusal before expiry with unchanged target/control, wait for the real deadline,
then reclaim after disabling capture and temporarily withholding the original
Session source. The target/live row must disappear while the authenticated anchor
clocks, immutable link, peer and original journals stay unchanged. Check exact
settled expiry intent/accounting and subsequent duplicate acceptance refusal.
No native clock, review time or storage receipt is manufactured. This short
actual wait does not establish 30/90-day or annual endurance, human attribution,
installed behavior or model quality. Run the ordinary literal/history expiry
controls after changing their shared normalizer or management accounting.

The accepted-retention journey checks the complete choice/read/lifecycle path:

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_RETENTION=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_retention --max-cases 1
```

For ordinary, preference and current decisions it requires public native pin,
actual typed recall through the registered provider, cancellation without effect,
automatic retention and a public one-day duration. A separate native host call
selects a two-second duration through the same owned management entry, then waits
for real expiry, requires a new pin to refuse without changing control state,
and reclaims after disablement with the source unavailable.
The public record/link remain byte-identical through all retention choices;
only signed metadata changes, with one generation per committed operation.
The expanded trusted fixture selects a finite 16-operation allowance for its
five additional lifecycle effects and later refusal controls. Product limits
remain unchanged. Check the compact retention witness in the read receipt and
preserve the legacy deadline-mismatch refusal without that witness. The pure
page/receipt fixtures prove syntax and consistency, never native Review authority.
A shared lease must also work at the ordinary
resource ceiling, reject foreign/forged/spent handles, and preserve the combined
original-owner budget. Follow the
[fresh-runtime recipe](../archive/2026-10-26-p30-p31-implementation/pending-review-boundary-20261031.md#local-evidence-and-limits)
with the corresponding opt-in variable and tag. These are synthetic source
journeys, not independent human, live-model or installed evidence.

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
contention roots print as `WORKER_CAPACITY_ROOT`. These small metadata controls
do not establish maximum managed-output performance; keep the ordinary 4-MiB
result regression and later managed capacity qualification separate.

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
```

Retain size/inode/symlink/permission/nonblocking controls and bounded ignored FIFO
probes. Linux tests authority/FIFO/descriptor transfer; macOS covers only portable
protocol cases. Operator tests use actual synthetic PTYs and the bundled helper's
compiled identity. They cover terminal matching, deadlines, parent loss, a stopped
old helper's cleanup fence and opaque Session witnesses. Run these test commands
serially: their conservative per-user lock intentionally makes overlapping native
test programs contend. PTY input remains automated, and ordinary CLI/card adoption
and independent human journeys need separate verification. Keep atomic ordinals
and fixed-clock collision tests for parallel fixtures.

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

Probe macOS enforcement separately with a disposable workspace:

```sh
IPSE_MACOS_WORKSPACE=$(mktemp -d)
elixir dev/verify-macos-sandbox.exs priv/ipse-runner "$IPSE_MACOS_WORKSPACE"
```

Default checks file/network refusal, allowed paths, inheritance, and signing.
Optional process-boundary checks can expose documented detached-work gaps; nonzero/
gaps are not passing containment. Owned bundle/files are removed; macOS may retain
OS-managed app containers.

## Diagnose with synthetic data

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
