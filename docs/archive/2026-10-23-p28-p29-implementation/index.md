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
| P28 WP1 | One version source, compiled build identity and installed agreement | Local source/package checks passed; hosted pending |
| P28 WP2 | Redacted actionable errors and matching recovery instructions | Implemented; full candidate verification running |
| P28 WP3 | Offline doctor, explicit bounded probes and finding fixtures | Pending |
| P28 WP4 | Guided/private setup, previews, backups and resolution fixtures | Pending |
| P28 WP5 | Checksums, symlink launcher, draft tag workflow and install lifecycle | Pending |
| P28 WP6 | Whole-manual first-user review and fresh-account walkthrough | Pending |
| P29 WP0 | Verified official wire facts and continuation examples | [Recorded](wire-facts.md); adapter fixtures still required |
| P29 WP1 | Central registry, existing-provider equivalence and recovery tests | Pending |
| P29 WP2 | Shared server and adapter conformance tests | Pending |
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
Elixir 1.20.4 and OTP 29. Hosted run 40042497037 remains live; WP1 is not yet
declared complete. No live account, fresh-account walkthrough or release was
verified.

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
isolated demo also pass. These results do not yet establish the corrected full
baseline.

Two preliminary candidate runs are retained under `/tmp`: the first was stopped
after its temporary directory inherited the source checkout's Git boundary and
failed workspace assertions; the corrected harness uses a separate temporary
root outside Git. The next run was stopped after the stale MCP-message
expectation failed. Neither interrupted run is a passing suite. Source and build
outputs remain fixed during each run. The operator recovery/usage chapters and
developer configuration/testing chapters have been reviewed together and updated
around diagnosis and verification tasks; final checks remain pending.
