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
in current manuals, audience/history rules, and archive hashes. It does not execute
Markdown or judge usability. Review
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
and fixed-clock collision tests for parallel
fixtures. Probe macOS enforcement separately with a disposable workspace:

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
later native/package steps. Its 45-minute platform job budget is separate from
model/worker/native/test deadlines. A green source step does not prove skipped
later gates, and a partial review retains its omissions after local repairs.
