# P28 and P29 implementation audit preparation

Prepared 2026-10-24; runtime candidate is now `9c5eb6a`, with exact live wire
evidence at `492d091` and RC1 release preparation at `e944fcf`.
This is a draft handoff, not an external audit or a completeness verdict. Final
combined verification, release rehearsal and fresh-operator acceptance remain
open. Use the [current plan](../../plan.md) for status and the
[implementation index](index.md) for subsequent receipts. This dated record can
be superseded; the operator and developer manuals own current procedures.

## Scope and authoritative requirements

Audit all of the accepted [P28 brief](../2026-10-23-p28-p29-design/p28.md) and
[P29 brief](../2026-10-23-p28-p29-design/p29.md), including their tests and Done
conditions. The objective is complete implementation/testing and an independent
assessment of completeness. Backward compatibility is not required; correctness,
authority, accounting and recovery regressions remain failures.

The accepted decisions retain ChatGPT as the announced built-in default, choose
`v0.1.0` as the first release, permit the existing runner's `gh` for draft release
automation, add Gemini then OpenRouter after the previous four providers, restrict
compatible services to explicit loopback/local billing, and default OpenRouter
data collection to deny. No dependency was added for the new adapters.

Preserve unrelated `.claude/` and `erl_crash.dump`; do not read, stage or delete
them. The ignored `.env` contains private credentials and is not audit input.
Use synthetic fixtures and the non-secret live receipts. Do not publish a release
or repeat paid inference as part of an ordinary read-only audit.

## Requirement-to-evidence map

Each row is an audit starting point, not a substitute for checking every numbered
step, field and refusal in the briefs. Inspect both positive and negative controls.

| Package / required behavior | Implementation and verification entry points | Evidence and remaining gate |
| --- | --- | --- |
| P28 WP1: one version source, compiled identity, both version commands, help/archive/application agreement | `mix.exs`, `lib/ipse.ex`, `test/ipse/cli/version_test.exs`, `dev/verification/package.exs` | [WP1 receipt](wp1-verification.json), [platform receipt](wp1-hosted.json); repeat on final candidate |
| P28 WP2: actionable safe refusals, status JSON, unchanged locked/mismatched/torn journals, no term/credential dumps | `lib/ipse/cli/errors.ex`, `test/ipse/cli/errors_test.exs`, configuration/MCP suites | [WP2 receipt](wp2-verification.json), [platform receipt](wp2-hosted.json); survey CLI-reachable errors independently |
| P28 WP3: stable doctor IDs/status/recovery, offline invariance, bounded explicit GETs, credentials/permissions/store/extension findings | `lib/ipse/cli/doctor.ex`, `test/ipse/cli/doctor_test.exs`, `Ipse.Runner.current_uid/0` | [Doctor receipt](wp3-verification.json), [hosted receipt](wp3-hosted.json); new provider probes and UID repair need final combined gate |
| P28 optional WP3b kernel probe | Existing native sandbox policy and doctor availability wording | Explicitly deferred under the brief's allowance; availability is never enforcement |
| P28 WP4: explicit billing/provider choice, TTY/headless preview/save, exact JSON, private atomic write/backup, preservation, optional login, offline diagnosis | `lib/ipse/cli/setup.ex`, `lib/ipse/private_file.ex`, setup/private-file/Auth suites | [WP4 receipt](wp4-verification.json), later installed/platform checks; P29 adds explicit route profiles |
| P28 WP5: sidecars, strict matching tags/notes/assets, symlink/cwd handling, draft-only release matrix, install/upgrade/uninstall | `dev/release.exs`, `.github/workflows/release.yml`, `dev/release-launcher.sh`, `test/dev/release_test.exs`, installed verifier | [WP5 receipt](wp5-verification.json), [later full platform matrix](p29-wp2-hosted.json); actual RC draft/assets/inspection/deletion still required |
| P28 WP6: whole first-user manual, examples/links/limits, unassisted fresh OS account walkthrough | Operator install/index/configuration/usage/recovery, developer testing/configuration | Whole-manual review and installed examples pass; genuine walkthrough remains open |
| P29 WP0: primary protocol research before coding, native continuation and usage semantics | [Wire facts](wire-facts.md), linked official sources and schematic examples | Recorded before adapter work; explicitly verified OpenAI display-name/slug pair added after first live refusal |
| P29 WP1: closed registry, existing constants/manifests/destinations/usage/cost/journal equivalence, documented exceptions | `lib/ipse/provider/registry.ex`, `test/ipse/provider/registry_test.exs`, `test/fixtures/provider_registry/provenance.json` | [Registry receipt](p29-wp1-verification.json); fixtures captured from independent `dd510a7`, not regenerated from refactor |
| P29 WP2: shared fragmented server, native builders and common text/tools/replay/limits/errors/usage/terminal controls | `test/support/provider_fixture.ex`, `test/support/provider_conformance.ex`, provider conformance suite | [Local receipt](p29-wp2-verification.json), [Ubuntu/macOS full matrix](p29-wp2-hosted.json); six routes use common controls, with dedicated ChatGPT controls retained |
| P29 WP3: explicit model/upstream, no fallback/shortcuts, collection policy, first/later identity checks, native private continuation, bounded complete calls and usage | `lib/ipse/provider/chat_completions.ex`, native protocol tests and shared conformance | [WP3 receipt](p29-wp3-verification.json); inspect mismatch-before-text and usage-before-refusal controls |
| P29 WP3 integration: API/local billing, fresh selected credentials, profile/child/SDK projection, resume drift and budgets/unpriced costs | Router integration and extension invocation suites; registry/MCP/native environment filters | Focused controls pass; exact `8160f0d` full suite failed only the diagnosed doctor UID issue, repaired at `62d3ad7`; final suite pending |
| P29 WP4 request/destination: native GenerateContent, header-only key, fixed query digest, explicit model grammar, Vertex refusal, schema/thinking/tool conversion | `lib/ipse/provider/gemini.ex`, Gemini native/conformance suites | [WP4 receipt](p29-wp4-verification.json); existing destination goldens remain unchanged |
| P29 WP4 response/recovery: original signed parts/order, hidden thoughts, native/synthetic IDs, parallel result grouping, terminal refusals, usage partiality | Gemini protocol/session/child/SDK/compaction/usage/budget tests | Positive wire round trips and idle/torn-tail controls pass; final suite/platform gate pending |
| P29 live: explicit confirmation, bounded text plus two-step tool turn, no secrets/transcripts, no retries | `dev/verification/live_provider.exs`, `test/dev/live_provider_test.exs` | [Exact `492d091` live receipt](p29-live-final.json): both providers pass; Gemini signed parts observed; missing counters remain partial |
| P29 WP5: registry menus/billing/credentials/probes, route questions/private previews, coherent provider/accounting manuals and priority | Setup/doctor/CLI suites, `AGENTS.md`, operator/developer provider chapters | [WP5 receipt](p29-wp5-verification.json): 83 CLI controls pass; final combined source/package/platform gates pending |

## Material implementation decisions to inspect

The release checksum helper uses already-required OTP crypto rather than adding a
platform checksum executable dependency. A fixed query belongs only to Gemini's
registry spec and native adapter; operator base URLs still refuse all queries.
Unsigned imported Gemini history has no invented placeholder signature; API
refusals direct the operator to fresh session/handoff recovery.

OpenRouter accepts exact upstream equality plus only the independently verified
`openai`/`OpenAI` catalog pair. Other undocumented aliases refuse. It retains the
raw reported name and never changes routing lists. Native reasoning arrays remain
ordered and private. Provider credit cost is ignored; canonical spend requires
the operator's rate card. Native Rust launchers independently scrub new key names;
the frozen executable evaluation logic under `dev/evaluation/` is unchanged.

Doctor's UID repair separates a trusted read-only host query from native shell
workspace admission. Native overlap refusal remains tested. The first failed
source baseline and earlier macOS timed waits are retained; later success does
not erase them or justify weakening assertions.

## Reproduce the final verification

Follow [verification training](../../developer/testing.md) from an isolated
checkout with fixed source/build files. Start with the ordinary build, formatting,
warnings-as-errors compile, docs/policy checks, full tests and isolated demo. On a
supported Linux host, also run `mix test --include native_sandbox`. Report skipped,
excluded and unsupported checks explicitly. Run native protocol tests with
warnings denied. Use separate build roots for the supported Elixir floor.

Build the package and use its exact printed archive path, not a wildcard matching
an older archive:

```sh
./dev/package.sh
elixir dev/verify.exs installed package \
  --archive /absolute/path/to/the-built-archive.tar.gz \
  --input examples/memory-corpus.json
```

The package proof checks sidecar/version/build identity, setup/doctor/demo,
symlink/cwd behavior, no-extension resume, selected-extension changed-build refusal,
old-build recovery, standalone operation and unchanged inventories. Ordinary
hosted CI additionally runs the independent model/extension/MCP/embedding/results/
knowledge proofs and macOS enforcement cases. Require exact candidate receipts;
earlier successful platforms do not prove later code.

## Open acceptance gates

Final combined source/native, installed and hosted receipts must finish and be
reviewed. Then rehearse `v0.1.0-rc.1`: inspect the draft's two platform archives
and checksum sidecars, verify them, retain the workflow/asset facts, and delete
the draft as the brief requires. This is distinct from actual publication.

The required unassisted fresh-OS-account install-to-first-task walkthrough has not
occurred. An isolated `IPSE_HOME` fixture is not that evidence. Record actual
operator confusion and repairs rather than inventing a pass. Final `v0.1.0`
publication belongs to the developer after WP6 acceptance and review.

The [walkthrough observation record](../2026-10-24-p28-walkthrough/index.md) is
prepared but not started. RC1's draft workflow is running at
`e944fcf`; it must finish before draft assets can be inspected. `9c5eb6a` adds
only more precise invalid-cap and late identity-refusal messages to the runtime.
It has 303 passing provider/configuration/CLI controls and a passing complete
installed proof, including 24 verified runtime-notice files. Its fixed full/native
check remains in progress. The earlier `492d091` native-inclusive suite completed
with 1710 passed and 19 excluded, followed by a passing isolated demo. The
[combined receipt](combined-verification.json) preserves exact build scope.
Successful wire handling is unchanged from the
exact live-tested `492d091`; inspect that source difference rather than calling
the earlier live receipt an exact-final-build test.

After those gates, replace this draft status with the exact audit candidate and
remaining limitations. The independent auditor should return requirement-level
findings with file/line evidence, commands actually run, severity/consequence and
whether each item is implemented, missing, contradicted or unverified. No external
audit has been performed by preparing this document.
