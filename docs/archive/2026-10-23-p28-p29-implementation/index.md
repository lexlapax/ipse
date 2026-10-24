# P28 and P29 implementation record

Work started 2026-10-23 UTC against `229439597ee33029a4ce7497782ce55e78dca058`.
This is an implementation and verification record, not an
acceptance verdict. The [plan](../../plan.md#p28-operator-usability-and-release-readiness)
owns scope; the [design briefs](../2026-10-23-p28-p29-design/index.md) preserve the
accepted design decisions. Current procedures belong in the operator and developer
manuals. Unrelated `.claude/` and `erl_crash.dump` were present at start and remain
outside this work.

## Execution and acceptance map

Implement each ordered package with behavior tests, whole-chapter manual review,
source checks, and the relevant installed/native controls. Push verified focused
commits and retain hosted platform results. Backward compatibility is not a user
requirement; authority, recovery and correctness regressions remain unacceptable.

| Package | Required result | State |
| --- | --- | --- |
| P28 WP1 | One version source, compiled build identity and installed agreement | Complete at `b4788b4`; local source/package and both hosted platforms pass |
| P28 WP2 | Redacted actionable errors and matching recovery instructions | Complete at `6818000`; full local and hosted Ubuntu/macOS checks pass |
| P28 WP3 | Offline doctor, explicit bounded probes and finding fixtures | Full native suite passes at `a89fce7`; hosted pending; later installed proof passes |
| P28 WP4 | Guided/private setup, previews, backups and resolution fixtures | Full native suite and installed first run pass at `9907877`; repaired hosted gate pending |
| P28 WP5 | Checksums, symlink launcher, draft tag workflow and install lifecycle | Implemented; local package/upgrade proof passes; tag rehearsal and hosted pending |
| P28 WP6 | Whole-manual first-user review and fresh-account walkthrough | Pending |
| P29 WP0 | Verified official wire facts and continuation examples | [Recorded](wire-facts.md); adapter fixtures still required |
| P29 WP1 | Central registry, existing-provider equivalence and recovery tests | Implemented; fixed pre-refactor fixtures and 312 focused checks pass; full/platform gates pending |
| P29 WP2 | Shared server and adapter conformance tests | Shared server preserves 54 tests; 33 conformance cases and all 110 provider tests pass ([receipt](p29-wp2-verification.json)) |
| P29 WP3 | Pinned OpenRouter and explicit loopback compatible adapter | Pending |
| P29 WP4 | Native Gemini, signed continuation and canonical accounting | Pending |
| P29 WP5 | Registry-driven doctor/setup and coherent provider manuals | Pending |
| Auditor handoff | Requirement matrix, exact commits/checks, exclusions and commands | Pending |

Release publication, real account probes and a genuinely unassisted fresh-user
walkthrough require their own evidence. Synthetic tests cannot establish these.
Prepare all implementation and test material for the external auditor without
claiming the auditor's verdict or publishing a release on its behalf.

## P28 WP1

`Ipse.version/0` reads the application specification; `build_info/0` adds runtime
facts and an optional compiled Git commit without runtime subprocesses. Build and
package scripts force compilation to prevent stale embedded identities. Help,
version commands and archive names share `mix.exs`'s version.

The package proof's runtime dispatcher passes the archive path to its existing
package owner so that it can check archive/application/CLI agreement. This small
scope expansion is necessary to verify the artifact actually supplied rather than
a filename derived from the same script under test. No measured/evaluation path
changes.

At the original checkpoint, verification was incomplete. The source build,
formatting, warnings-as-errors
compile, two focused version tests, CI pin-policy check and documentation check
passed. The full suite (seed 1587) was interrupted at the user's explicit pause
request, with exit 130 and no final ExUnit summary. It is not a passing suite.
The chained demo and package build never started; installed and hosted checks
have not run for this change. Initial checks exposed an already stale local
PlugCrypto checkout; the existing lock selected 2.2.1 and dependency fetching
restored it. The first compile caught a module-attribute syntax error, corrected
before the passing build/focused checks.

The earlier [pause and resume handoff](resume.md) preserves the original
checkpoint. The resumed record below and current plan own subsequent progress.

### Resumed verification

The resumed `b4788b4` source build, formatting, warnings-as-errors compilation,
CI policy and documentation checks pass. The full suite, seed 740904, completed
with 1540 passed and 36 excluded in 1040.1 seconds, exit 0. The isolated
credential-free demo passes. This does not change the earlier interrupted run's
verdict.

A clean `git archive` snapshot of that commit, with a separate build root and
explicit `IPSE_BUILD_COMMIT`, produced the exact Linux archive recorded in the
[verification receipt](wp1-verification.json). Its installed package proof passes,
including archive/application/CLI agreement, toolchain-free runtime behavior,
unchanged inventories and the existing memory/MCP/delegation/recovery controls.
The packaged identity reports the intended source commit, version 0.1.0,
Elixir 1.20.4 and OTP 29. Hosted run 40042497037 completed successfully on
Ubuntu and macOS for the exact `b4788b4` source. Its [job/step receipt](wp1-hosted.json)
includes the full source, native protocol, package, installed feature proofs and
the final experimental macOS verifier. WP1 is complete within its version/build
identity scope. No live account, fresh-account walkthrough or release was verified.

## P28 WP2

The error renderer now supplies recovery routes and never inspects arbitrary
reason terms or exception messages. Startup distinguishes missing, malformed,
locked and incompatible sessions. Status emits Auth's public fields as JSON.
Profile and MCP validation identify known field names without values; MCP also
withholds identifiers overlapping configured secrets. Existing validators and
admission behavior remain authoritative.

The terminal error/question paths use the shared renderer; this additional
presentation integration is necessary so interactive failures obey the same
redaction and recovery contract as command startup. Config source loading now
preserves sanitized profile diagnostics rather than replacing them with the
generic file error. No dependency, provider route, journal or approval contract
changes.

In-memory draft checks passed 61 focused configuration/MCP/error tests and 32
existing CLI/profile integration tests. The independently built candidate passes
formatting, warnings-as-errors and documentation checks; its 42 focused
extension-result/MCP/error controls pass after replacing one stale exact-message
expectation. The complete candidate suite finished with 1547 of 1548 tests
passed and 36 excluded, seed 66291, in 1018.7 seconds, exit 2. Its sole failure
identified a help-text regression: generalizing the JSON option description had
removed the sessions field names. The description is restored, and the original
assertion is unchanged. All 53 CLI tests now pass, including sessions, version
and the existing interactive suite. The complete corrected suite is running in
the fixed independent source/build/temp snapshot. Main-checkout build,
formatting, warnings-as-errors, documentation, 113 earlier focused tests and
isolated demo also pass. The corrected full suite subsequently passed 1548 tests,
with 36 excluded, seed 887600, in 1028.0 seconds, exit 0. The candidate's runtime,
test and developer-tool sources compare identically to committed `6818000`,
including the new files. The [receipt](wp2-verification.json) retains both results.
Exact-source hosted run 40045562195 is pending; no hosted pass is claimed yet.

Two preliminary candidate runs are retained under `/tmp`: the first was stopped
after its temporary directory inherited the source checkout's Git boundary and
failed workspace assertions; the corrected harness uses a separate temporary
root outside Git. The next run was stopped after the stale MCP-message
expectation failed. Neither interrupted run is a passing suite. Source and build
outputs remain fixed during each run. The operator recovery/usage chapters and
developer configuration/testing chapters have been reviewed together and updated
around diagnosis and verification tasks; final checks remain pending.

## P28 WP3

Doctor reuses existing configuration, authentication status, artifact, MCP,
journal, native-helper and private HTTP owners. Offline checks do not refresh
credentials, start workers/servers, acquire session locks or create private state.
The existing Rust `--uid` facility supplies current-user identity through a
bounded Runner invocation. Explicit provider probes send metadata GETs only,
stop after the response status, enforce finite request limits and never retry or
follow redirects. Subscription reachability stays skipped.

The optional WP3b kernel probe is deferred. Linux confinement couples Landlock
preparation with namespace/mount activation in the supervised child's pre-exec
path. Reusing that as a separate standalone probe would require changes beyond
the diagnostic path. Doctor therefore reports helper/workspace policy checks,
explicitly states that kernel enforcement is unprobed, and keeps macOS
experimental. No native implementation or dependency changed.

Ten focused draft controls and 48 independently compiled CLI/error/doctor controls
passed. The main checkout then passed all 63 CLI tests. Review of the maintained
Finch source showed that its request timeout is best-effort and does not establish
a total request ceiling. Doctor now adds an outer owned-task deadline, rejects late
results, and relies on the private HTTP guardian for cleanup. Twelve focused
doctor controls pass, including a stalled response reaching the ten-second ceiling,
client closure, exact API headers, two deduplicated route probes and a failed main
route that cannot be masked by a successful role probe.
The final main-checkout CLI run passes all 65 tests, and the isolated scripted
demo passes. Formatting, warnings-as-errors compilation and documentation checks
also pass. These are checkpoint results while the corrected full/native and
exact-source hosted gates remain pending.

A separate source/build snapshot passed packaging and installed verification,
including a new toolchain-free doctor check and unchanged auth/session state.
That preliminary package and the first native-inclusive suite contain the earlier
JSON help-description regression and precede the outer-deadline repair; they do
not establish final-code acceptance. The first native-inclusive suite completed
with 1574 of 1575 passed and 19 excluded, seed 958251, in 1014.5 seconds, exit 2.
Its only failed assertion is the retained help-description regression. The full
native-inclusive suite is now running against the corrected doctor source.
The main source restores the description while retaining the original assertion.
Native, package and hosted checks for final source remain pending. The draft
extension control initially refused memory-only module loading, as the host BEAM
identity guard requires real files; a run using actual temporary BEAMs passes
without changing that guard.

Recovery/usage and developer configuration/testing chapters are integrated around
offline diagnosis, explicit egress and the distinction between availability and
actual confinement. Their audience indexes link the revised learning tasks.

## P28 WP4

Guided setup requires an explicit provider choice, shows billing and credential
sources, previews exact JSON, and requires typed `write` or non-interactive
`--write`. Existing files require `--replace`; unrelated values are preserved and
an exclusive private timestamped backup retains the exact old bytes. PrivateFile
uses existing OTP file operations; Auth retains its original messages and locks.
No dependency was added. Config's pure preview uses the full existing resolver
to reject preserved cap/profile/environment conflicts before any save or sign-in
offer. The built-in default notice precedes auth and disappears after setup.

Actual-main build, formatting and compilation pass. Combined CLI, Config, Auth
and private-file checks pass 141 tests; the final setup/private-file run passes
14 tests, seed 497535. Earlier prototype checks are not installed acceptance.
The installed verifier now contains isolated preview/save/doctor/demo controls.
Its run, full source and hosted results remain pending. The operator and developer
configuration/usage/testing chapters are integrated around writing and validating
settings, with audience links. The [WP4 receipt](wp4-verification.json) records the
passing installed first-run proof and the hosted Elixir-floor formatting failure,
now repaired with a conventional conditional. No assertion or check was weakened.

The corrected WP3 native-inclusive suite completed with 1577 passed and 19 excluded,
seed 3667, in 1043.0 seconds, exit 0. Its indexed runtime/test/developer-tool source
compares identically to `a89fce7`; [WP3 receipt](wp3-verification.json) records scope.

## P28 WP5

Packaging writes a standard SHA256 sidecar with streaming OTP crypto. This replaces
the brief's proposed platform checksum command with the already required toolchain,
avoiding a new mandatory executable dependency. The installed package command
checks the sidecar before extraction. The launcher resolves bounded portable
symlink chains and preserves the original caller workspace.

The release workflow retains every ordinary CI step, with a consistency test,
uses the approved runner `gh`, and refuses published releases. It creates a draft,
attaches assets after both platform checks, and downloads the complete asset set
for integrity checks. Draft creation precedes the matrix to avoid a new artifact
action dependency; a failed matrix may leave an incomplete unpublished draft.
Official CLI [create](https://cli.github.com/manual/gh_release_create),
[upload](https://cli.github.com/manual/gh_release_upload) and GitHub
[tag trigger](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#push)
documentation was checked on 2026-10-24. No workflow publication command exists.

New installation/release notes cover checksum, first run, side-by-side upgrades,
rollback and uninstall. Arch source setup links to the lifecycle owner instead of
duplicating bundle instructions. Recovery and refusal wording explain handoff.
The installed proof copies a release and recompiles only its test identity module,
then verifies extension-free resume, selected-extension refusal without journal
mutation, recovery using the old release and relative symlink workspace handling.
All existing installed controls pass. The [WP5 receipt](wp5-verification.json)
retains the dirty-snapshot provenance and preliminary verifier failures.
Final hosted checks, RC creation/inspection/deletion, unassisted fresh-account
walkthrough and real release publication remain unperformed.

The exact-source WP2 hosted run subsequently completed successfully on Ubuntu and
macOS; [job/step receipt](wp2-hosted.json) records all checks. WP2 is complete.
The WP5 hosted checkpoint `b99cfe9` stopped at another Elixir-floor formatting
difference in a guarded `with` line. Splitting its type and size checks preserves
the exact admission while formatting under both Elixir 1.18.4 and 1.20.4. A
temporary official precompiled Elixir 1.18.4/OTP-27 toolchain now checks the floor
formatter locally. No new repository dependency or CI relaxation was introduced.
Release credentials are scoped to the GH CLI steps, without adding them to the
ordinary verification environment. Hosted acceptance of the repaired code remains
pending.

## P29 WP1

Before changing provider ownership, a separate `git archive dd510a7` checkout built
the original locked code and captured full configuration manifests, destinations,
normalized usage, costs and five synthetic saved sessions. Request-free legacy
variants omit destination/metering. Original usage restoration is captured too.
The [fixture provenance](../../../test/fixtures/provider_registry/provenance.json)
records source/data hashes and the narrowly declared workspace-path relocations.
The three comparison tests passed against current pre-refactor source first,
seed 700869. Expected values were not generated by the new registry.

The closed Spec/Registry owns defaults, credentials, billing, native usage paths,
reasoning/output limits, embedding capacity metadata, labels/probes and subscription
HTTP hints. Config, Profiles, Provider, Usage, Costs, Budget, extension inference,
MCP environment filtering, CLI, Context and effect-capacity owners now consume it.
Existing journal billing strings, replay keys, destination digests and manifest
fingerprints remain identical to the pre-refactor fixture. A 311-test focused run
passes, seed 309464. The final focused run passes 312 tests, adding fixture-hash
integrity and default endpoint equivalence assertions; formatting passes the
supported 1.18 floor and local 1.20. Full source,
installed and hosted gates remain pending.

Intentional provider-specific exceptions are native wire/replay handling inside
adapters; Transport's existing subscription diagnostic envelope and default stream
error overload; Doctor's named native Anthropic header scheme; and the frozen
evaluation runner. These are protocol or historical ownership, not additional
provider catalogs. The demo's direct deterministic entry point remains outside
the HTTP dispatcher. No provider, SDK or runtime dependency has been added yet.
The registry also preserves the existing Ollama probe's `localhost` alias
separately from native inference's `127.0.0.1` default, so recorded destinations
and probe behavior both stay unchanged. The frozen evaluation map has only the
brief's requested explanatory comment; no executable evaluation behavior changed.

The independent exact-`9907877` WP4 source subsequently passed its complete
native-inclusive suite: 1591 passed, 19 excluded, seed 950188, 1049.6 seconds,
exit 0. Its tracked runtime/test/tool sources remain unchanged. The earlier
installed first-run pass and later installed upgrade proof remain distinct receipts.
