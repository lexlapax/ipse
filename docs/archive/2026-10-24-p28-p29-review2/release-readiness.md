# v0.1.0 release readiness

Dated 2026-10-24. Historical handoff after the second independent review and the
developer-requested author adversarial review. The [plan](../../plan.md) owns
acceptance, the [installation manual](../../operator/install.md) owns operator
procedures, and [verification training](../../developer/testing.md) owns release
execution. No stable tag or publication is created by this record.

## Candidate and delivered material

The verified runtime and release-verifier candidate is `45cae30`. Later evidence
and editorial commits do not substitute for that source identity. The
[verification receipt](verification.json) records the actual local and hosted
results, exclusions, artifacts and earlier failed/canceled runs.

The local native-inclusive baseline at `5d9650e` passes 1,783 tests with 19
excluded. Host code, native helpers, configuration, dependency versions and the
release workflow are unchanged in `45cae30`. Its developer-verifier change has
33 focused tests, installed checks on both toolchains and its own complete hosted
rehearsal.

The release body is [docs/releases/v0.1.0.md](../../releases/v0.1.0.md), rendered
locally as `dist/release-readiness/45cae30/release-notes.md`. Its links use the
future stable tag; an RC body is rendered against its actual RC tag instead.
The exact-commit local Linux archive, checksum, build identity and runtime-notice
verification are retained beside that rendered body. The hosted Linux/macOS
archives and sidecars are retained in the `workflow` subdirectory, separate from
the local newer-toolchain archive. These are retained candidate files, not
published GitHub release assets.

## Review findings and qualifications

The [second review corrections](index.md) restore useful configuration, skill and
provider diagnostics, tighten installed diagnosis and release admission, preserve
safe stream codes, and correct manuals and evidence. The
[author adversarial review](self-review.md) adds refusals for linked/non-file
archives and incomplete doctor reports, then preserves numeric OpenRouter stream
codes. The [compiler-isolation follow-up](compiler-isolation.md) fixes a fourth
author-review finding in developer verification, with actual cross-toolchain
controls. A pre-existing short private MCP-value collision remains documented.
Author review is not a fresh independent acceptance verdict.

The [offline release-flow receipt](offline-release-flow.json) and its
[historical fixture source](offline-release-flow.exs) exercise the exact workflow
shell bodies at `5d9650e`, unchanged in `45cae30`, with a fake GitHub CLI. New
stable/RC drafts, recovering an unpublished draft, refusing a published release and rejecting incomplete
platform assets all pass. Run that fixture only from the trusted exact candidate.
This does not establish real tag-push token permissions, uploads or remote
re-download behavior.

The developer accepted an assisted fresh Linux walkthrough; it is not relabelled
unassisted. There is no human macOS or human upgrade walkthrough. Grok API
inference remains unverified after HTTP 403, and registered-client OAuth needs
an approved Ipse client and live eligibility. Gemini foreign-history acceptance
has fixture coverage without a live acceptance result. These qualifications
remain explicit in the plan/evidence and applicable release notes.

## Review prompt

Review runtime/verifier candidate `45cae30bd7aeab332a1c0821f43d6ec53b8a8406`
and any later documentation-only changes for v0.1.0 readiness. Use the rejected
`c2a19cb` review in this directory as the baseline. Read the accepted P28/P29
briefs, current plan, correction index, author self-review and exact verification
receipts. Check R1/R2, F7/F11, the remaining P3 dispositions and S1–S4 with causal
counterexamples, including numeric OpenRouter codes, linked archive admission,
omitted configured-doctor findings, and installed compiler isolation. Confirm
useful CLI causes, bounded private-value handling, unchanged approval/recovery boundaries and draft-only
release behavior. Cross-check run 40154297591, its source, all jobs/steps and actual
artifact identities. Preserve failed/canceled results and distinguish synthetic
fixtures, installed/OS checks and live accounts. Inspect the final notes/manuals
and source equivalence rather than treating green receipts as acceptance.
Use a clean clone; do not read/copy `.claude/` or the user's working-copy edits.
Do not change the checkout, push, authorize/sign in, make paid requests, tag or
publish. Return severity-ranked reproducible findings and a readiness verdict,
with independent acceptance separate from human/live qualifications/publication.

## Remaining release actions

First obtain final acceptance of the repaired candidate and the recorded human/
live qualifications. Choose the exact release commit after inspecting any later
evidence-only diff. Keep the unrelated working-copy manual edit out of that tag.
The stable tag must be `v0.1.0`, matching `mix.exs`; pushing it invokes the verified
workflow and creates an unpublished draft only after both platform jobs and asset
admission succeed.

Inspect that tag-triggered run to completion. Confirm the draft state, version,
build identities, notes, exact four assets, checksums and runtime notices after
remote re-download. A failed upload can leave a partial draft; do not publish it.
A successful manual rehearsal does not close this real remote inspection step.
Publication remains an explicit developer action after draft inspection.
