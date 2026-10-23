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
| P28 WP1 | One version source, compiled build identity and installed agreement | In progress |
| P28 WP2 | Redacted actionable errors and matching recovery instructions | Pending |
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

Verification is incomplete. The source build, formatting, warnings-as-errors
compile, two focused version tests, CI pin-policy check and documentation check
passed. The full suite (seed 1587) was interrupted at the user's explicit pause
request, with exit 130 and no final ExUnit summary. It is not a passing suite.
The chained demo and package build never started; installed and hosted checks
have not run for this change. Initial checks exposed an already stale local
PlugCrypto checkout; the existing lock selected 2.2.1 and dependency fetching
restored it. The first compile caught a module-attribute syntax error, corrected
before the passing build/focused checks.

See the [pause and resume handoff](resume.md) before continuing.
