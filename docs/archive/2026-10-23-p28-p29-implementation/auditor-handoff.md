# P28 and P29 implementation audit preparation

Prepared 2026-10-24; the newest runtime increment adds
[Grok API and registered-client OAuth](../2026-10-24-xai-provider-research/index.md)
after `5bb5761`. Its frozen identity and final verification must be recorded
before treating it as audit-ready. Earlier exact live wire evidence is at
`492d091`, and RC1 release preparation is at `e944fcf`.
This handoff is prepared for independent implementation review, not an external
audit or a completeness verdict. P29's original registry/Gemini/OpenRouter gates
pass; its newly authorized Grok scope remains under verification. Final release
acceptance and stable publication remain open.
The developer has authorized the [approval UX implementation](../2026-10-24-approval-implementation/index.md)
before external audit. Its candidate and fresh verification supersede the old
baseline only when explicitly recorded in the [new receipt](../2026-10-24-approval-implementation/verification.json);
inspect the new grants, root/child/SDK
scope, revocation, stale input and inert resume in addition to both original briefs.
RC draft cleanup is complete: [receipt](rc-assets.json) records absent release,
retained tag and verified local files after explicit developer authorization.
Use the [current plan](../../plan.md) for status and the
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

Preserve unrelated `.claude/`; do not read, stage or delete it. The initially
untracked `erl_crash.dump` was inspected privately and removed on the developer's
explicit 2026-10-24 request; `9ba3994` adds its ignore rule. The ignored `.env`
contains private credentials and is not audit input.
Use synthetic fixtures and the non-secret live receipts. Do not publish a release
or repeat paid inference as part of an ordinary read-only audit.

## Requirement-to-evidence map

Each row is an audit starting point, not a substitute for checking every numbered
step, field and refusal in the briefs. Inspect both positive and negative controls.
The [earlier hosted receipt](final-hosted.json) records every job/step in the exact
`9c5eb6a` Ubuntu/macOS matrix; its [combined receipt](combined-verification.json)
connects that baseline to local native-inclusive and installed proofs. The
[current candidate receipt](../2026-10-24-approval-implementation/verification.json)
keeps new and superseded verification separate.

| Package / required behavior | Implementation and verification entry points | Evidence and remaining gate |
| --- | --- | --- |
| P28 WP1: one version source, compiled identity, both version commands, help/archive/application agreement | `mix.exs`, `lib/ipse.ex`, `test/ipse/cli/version_test.exs`, `dev/verification/package.exs` | [WP1 receipt](wp1-verification.json), [platform receipt](wp1-hosted.json), [final local source/installed proof](combined-verification.json) |
| P28 WP2: actionable safe refusals, status JSON, unchanged locked/mismatched/torn journals, no term/credential dumps | `lib/ipse/cli/errors.ex`, `test/ipse/cli/errors_test.exs`, configuration/MCP suites | [WP2 receipt](wp2-verification.json), [platform receipt](wp2-hosted.json); survey CLI-reachable errors independently |
| P28 WP3: stable doctor IDs/status/recovery, offline invariance, bounded explicit GETs, credentials/permissions/store/extension findings | `lib/ipse/cli/doctor.ex`, `test/ipse/cli/doctor_test.exs`, `Ipse.Runner.current_uid/0` | [Doctor receipt](wp3-verification.json), [earlier hosted receipt](wp3-hosted.json); new probes and UID repair pass final source/native/installed/hosted gates |
| P28 optional WP3b kernel probe | Existing native sandbox policy and doctor availability wording | Explicitly deferred under the brief's allowance; availability is never enforcement |
| P28 WP4: explicit billing/provider choice, TTY/headless preview/save, exact JSON, private atomic write/backup, preservation, optional login, offline diagnosis | `lib/ipse/cli/setup.ex`, `lib/ipse/private_file.ex`, setup/private-file/Auth suites | [WP4 receipt](wp4-verification.json), later installed/platform checks; P29 adds explicit route profiles |
| P28 WP5: sidecars, strict matching tags/notes/assets, symlink/cwd handling, draft-only release matrix, install/upgrade/uninstall | `dev/release.exs`, `.github/workflows/release.yml`, `dev/release-launcher.sh`, `test/dev/release_test.exs`, installed verifier | [WP5 receipt](wp5-verification.json), [successful RC workflow](rc-hosted.json), [downloaded asset inspection and completed cleanup](rc-assets.json); stable publication open |
| P28 WP6: whole first-user manual, examples/links/limits, unassisted fresh OS account walkthrough | Operator install/index/configuration/usage/recovery, developer testing/configuration | Fresh Linux run recorded and accepted; product-navigation assistance and approval-fatigue finding remain explicit qualifications |
| P29 WP0: primary protocol research before coding, native continuation and usage semantics | [Wire facts](wire-facts.md), linked official sources and schematic examples | Recorded before adapter work; explicitly verified OpenAI display-name/slug pair added after first live refusal |
| P29 WP1: closed registry, existing constants/manifests/destinations/usage/cost/journal equivalence, documented exceptions | `lib/ipse/provider/registry.ex`, `test/ipse/provider/registry_test.exs`, `test/fixtures/provider_registry/provenance.json` | [Registry receipt](p29-wp1-verification.json); fixtures captured from independent `dd510a7`, not regenerated from refactor |
| P29 WP2: shared fragmented server, native builders and common text/tools/replay/limits/errors/usage/terminal controls | `test/support/provider_fixture.ex`, `test/support/provider_conformance.ex`, provider conformance suite | [Local receipt](p29-wp2-verification.json), [Ubuntu/macOS full matrix](p29-wp2-hosted.json); six routes use common controls, with dedicated ChatGPT controls retained |
| P29 WP3: explicit model/upstream, no fallback/shortcuts, collection policy, first/later identity checks, native private continuation, bounded complete calls and usage | `lib/ipse/provider/chat_completions.ex`, native protocol tests and shared conformance | [WP3 receipt](p29-wp3-verification.json); inspect mismatch-before-text and usage-before-refusal controls |
| P29 WP3 integration: API/local billing, fresh selected credentials, profile/child/SDK projection, resume drift and budgets/unpriced costs | Router integration and extension invocation suites; registry/MCP/native environment filters | Focused controls and final native/installed/hosted gates pass; earlier doctor UID failure and macOS timed wait retained in their receipts |
| P29 WP4 request/destination: native GenerateContent, header-only key, fixed query digest, explicit model grammar, Vertex refusal, schema/thinking/tool conversion | `lib/ipse/provider/gemini.ex`, Gemini native/conformance suites | [WP4 receipt](p29-wp4-verification.json); existing destination goldens remain unchanged |
| P29 WP4 response/recovery: original signed parts/order, hidden thoughts, native/synthetic IDs, parallel result grouping, terminal refusals, usage partiality | Gemini protocol/session/child/SDK/compaction/usage/budget tests | Positive wire round trips, idle/torn-tail controls and final native/installed/hosted gates pass |
| P29 live: explicit confirmation, bounded text plus two-step tool turn, no secrets/transcripts, no retries | `dev/verification/live_provider.exs`, `test/dev/live_provider_test.exs` | [Exact `492d091` live receipt](p29-live-final.json): both providers pass; Gemini signed parts observed; missing counters remain partial |
| P29 WP5: registry menus/billing/credentials/probes, route questions/private previews, coherent provider/accounting manuals and priority | Setup/doctor/CLI suites, `AGENTS.md`, operator/developer provider chapters | [WP5 receipt](p29-wp5-verification.json): 83 CLI controls pass; final source/native/installed/hosted gates and whole-manual review pass |
| Authorized approval follow-up: root native edit mode, exact full-argument/cwd/sandbox shell reuse, bounded grants, inspect/revoke, fresh input, denial, cancellation, non-inheritance and inert resume | `lib/ipse/session/permissions.ex`, Session/Turn, CLI/Terminal, native path checks; `test/ipse/session/permissions_test.exs`, CLI/delegation suites; installed permission proof | [Implementation and receipt](../2026-10-24-approval-implementation/index.md); seven-effect fixture reduces seven decisions to two; inspect limitations and current gate status |
| Requested machine label during ChatGPT authorization | `lib/ipse/auth.ex`, Auth/setup fixtures and operator login procedure | [Machine-label record](../2026-10-24-sign-in-host-label/index.md); fixture-tested hostname/fallback and unchanged protocol; no new real browser trial |

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

## Candidate identity and verified scope

The approval/default-mode baseline `dac11dc` passes the complete local and
[hosted Linux/macOS matrix](../2026-10-24-approval-implementation/dac-hosted.json).
The successor `5bb5761` changes initial ChatGPT `agent_name_hint` to `ipse@HOST`
while preserving returning registrations. Its local native-inclusive suite and
installed proof pass; consult the current receipt for its hosted result.
`8ee16dc` and its cancelled run 40112830571 are superseded, not still running.
Earlier successful `48a42d8` and `9c5eb6a` checks retain their narrower scopes.

The new Grok increment changes registry, shared Responses handling, OAuth/storage,
setup/doctor, output-budget admission and native secret filtering. Its
[research/work packages](../2026-10-24-xai-provider-research/index.md) extend the
original brief explicitly. Inspect API/subscription credential isolation,
foreign ciphertext refusal, trailing stream marker admission, legacy reasoning
accounting, visible-only output caps and unknown rotating-refresh outcomes.
There is no Ipse xAI client registration yet and no Grok live inference result.
The older Gemini/OpenRouter live receipt does not verify Grok or new auth code.
Later documentation-only commits can embed a later build identity without
changing runtime source; distinguish them from the tested binary. Preserve the
unrelated working-copy edit in `docs/operator/usage.md` and `.claude/`.

RC1 is an earlier rehearsal at `e944fcf`, with its own passing complete workflow.
Both downloaded archives, sidecars, GitHub digests and 13 runtime-notice files per
archive pass inspection. Those bundles use Elixir 1.18.5/OTP 27.3.4.19. The actual
downloaded Linux bundle also passes isolated setup/doctor/demo. Local inspection
does not claim execution of the macOS archive on Linux; macOS execution is proved
by its hosted installed checks.

## Open acceptance and independent verdict

The developer reports a successful existing-account Linux attempt from the draft:
installation, explicit ChatGPT setup/browser sign-in, doctor and demo have terminal
evidence; real task, individual approvals, inspection and resume have follow-up
operator confirmation. The [observation record](../2026-10-24-p28-walkthrough/index.md)
retains this distinction without authorization URLs or private transcripts.
A later attachment establishes a newly created Linux account/home and an explicit
fresh-state check. That run selected Demo and real Ollama `qwen3.5:9b`; the
developer accepts it and requests work on excessive approval prompts. The record
retains account/product-navigation assistance, so it is not claimed to be wholly
unassisted. The [approval UX research](../2026-10-24-p28-approval-ux/index.md)
compares primary documentation. The authorized follow-up is now implemented and
under final combined verification. Human upgrade was skipped because only one release was
available; the automated upgrade proof remains separate evidence.

The inspected draft has been deleted on explicit developer authorization, with
downloaded bytes/checksums, the RC tag and workflow facts retained.
Final `v0.1.0` tag/publication belongs to the developer after WP6
acceptance and inspection. These are explicit open P28 gates. P29's original
scope passed its own gates; the selected Grok increment needs final verification
and an explicit disposition of unavailable registration/live-account evidence.

The independent auditor should check every brief item and return requirement-level
findings with file/line evidence, commands actually run, severity/consequence and
whether each item is implemented, missing, contradicted or unverified. Treat the
open human/release gates as unverified, not as successes inferred from fixtures.
Verify that each receipt supports its claimed scope; green tests alone are not a
completeness verdict. No external audit has been performed by preparing this
handoff, and the overall P28/P29 goal remains open.
