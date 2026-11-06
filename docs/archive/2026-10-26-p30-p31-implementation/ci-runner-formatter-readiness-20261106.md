# Hosted runner and formatter readiness repair

Dated **2026-11-06 UTC**. Historical CI observation and configuration record.
[Testing](../../developer/testing.md#run-the-complete-source-baseline) owns current
verification procedures, the [dependency inventory](../../developer/dependencies.md#ci-inventory)
owns toolchain inputs, and the [plan](../../plan.md) owns remaining acceptance.

## Actual hosted outcomes

[Run 42156333552](https://github.com/lexlapax/ipse/actions/runs/42156333552)
at `2e3871f3d06521862586f496ac4246ccc3028afe` has aggregate conclusion
`cancelled`, but its Linux job actually **failed** at
`mix format --check-formatted`. The source build and optional PDF protocol checks
passed. `mix test`, demo, packaging and the later independent proofs were skipped.

[Run 42162122524](https://github.com/lexlapax/ipse/actions/runs/42162122524)
at `1740e9d60cbbaf41776784abcb12c651c2c71782` stopped at the same Linux
formatting step. Its [macOS job](https://github.com/lexlapax/ipse/actions/runs/42162122524/job/127710009049)
had no steps and no allocated runner. The recorded failure annotation states:
`The configuration 'macos-14-arm64-us-default' is not supported`.
These observations establish neither an account/billing problem nor a
60-minute timeout. The check workflow has no concurrency-cancellation rule.

Neither run produced a complete default-test result. Their final test counts
are **null**, not zero; the hosted baseline and subsequent package/install gates
remain unqualified. The separate [interrupted local regression](source-regression-489-20261106.md)
does not supply those missing results.

## Configuration and formatter policy

GitHub's [runner-image retirement notice](https://github.com/actions/runner-images/blob/main/README.md#available-images)
records retirement of macOS 14 Actions images on 2026-11-02. Its current
[hosted-runner table](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
lists `macos-15` as a standard arm64 image. Both check and draft-release matrices
now select pinned `macos-15`, preserving the failed job's requested architecture.
Every existing test, macOS enforcement, package and installed-proof step remains.
No tag, publication, rerun or cancellation was dispatched for this repair.

CI already selects Elixir 1.18/OTP 27; the local default formatter identified as
Elixir 1.20.4. The earlier Linux formatter diff lists 40 files, mainly different
line wrapping for long generators, guarded definitions and keyword bodies.
Contributor guidance now selects Elixir 1.18 as the canonical source formatter
while retaining supported newer runtimes for compilation and tests. It adds no
tool-manager dependency and changes no formatting assertion or line-length limit.
The existing 1.18.5/OTP 27.3.4 toolchain was selected without installation.

## Canonical source adoption and local checks

The first copy-only proposal passed its syntax/source-preservation assertions,
but review rejected it before adoption: the proposal helper appended a second
final newline after `Code.format_file!` had already supplied one. The proposal
and helper preimage remain retained; it changed no actual source. This shows why
AST equality alone is insufficient to establish canonical formatting.

After removing that redundant append, proposal 02 selected **1,053** files from
the declared formatter inputs and Git-known paths, plus the explicit new native
module and five test owners. It proposed **42 changed files** in the then-current
candidate. That count is separate from the **40 historical CI failures** above.
All parsed ASTs matched with node metadata removed, and proposal source hashes
remained exact. Adoption rechecked every preimage and normalized AST, then
confirmed all expected postimages and preserved modes. Archive snapshots and
unrelated untracked fixtures were outside selection.

The first canonical Mix check exited zero but emitted an `Elixir.Hex` BEAM-load
error, `corrupt atom table`, from a reused archive incompatible with the selected
VM. It is retained as a non-clean check, not reported as error-free. A fresh
independent check used an empty `MIX_ARCHIVES` and isolated `MIX_BUILD_PATH`:
`mix format --check-formatted` exited **zero with an empty log**, without fetching
dependencies or starting Ipse. The action-pin policy check also exited zero, and
the selected source hash pre/post guard passed.

A direct documentation check in the working checkout included unrelated,
nonignored historical source-copy trees and failed with 3,326 findings. It is
retained as a contaminated-view attempt, not evidence that the current manual
view passed or failed. A subsequent indexed current-manual check passed across
1,244 Markdown files and 10,188 local links with zero errors, excluding unrelated
untracked trees. The independent formatter check supplies no hosted test/package
result.

Private formatter evidence is retained under `minimum-formatter-118-20261106-01`:

| Evidence | SHA-256 |
| --- | --- |
| Successful proposal 02 | `4fe761cf95185578aeea6659fa2c1eb93013911a9cb696f8d88d6cb41b6c1c6a` |
| Equal proposal before/after source hash manifests | `c0d1f05c6163e75536a528411208910ace491ce065fefe82a7bbe31737936754` |
| Metadata-free AST snapshot | `7108b3d2218116a5c3d7dd758c824e06c09ce6fa6ed14c3c9a296da14181d455` |
| Adoption 01 | `ec6695ed8a147540d83f18cc2490c1ecdc73bb0aba8e6336aacdac3dfd01dfde` |
| First check log, exit zero with Hex error | `5c6b04601df3d17f5a22cac0dd793c04fa74a7a65b7d7769c05211521e3f051a` |
| Independent check 02 status, including separate documentation failure | `7d8562472e5ac15662c8cf422c01008068442379b0d855937463b0dae97fc63e` |
| Clean second formatter log | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

## Subsequent hosted build boundary

[Run 42168797121](https://github.com/lexlapax/ipse/actions/runs/42168797121)
at `6fe6b51f97dd9ab9e21d0e38bfea2d409c3fe2ca` reached the Linux default
tests after passing the floor-toolchain build, PDF protocol, formatter, strict
compilation, native protocol, policy and documentation steps. Its test outcome
was still pending at this observation; no aggregate pass follows from those
earlier steps.

The replacement macOS runner allocated successfully and completed toolchain
setup. Its build then failed with Rust E0433 at `native/ipse-runner.rs:152`:
the review-notice-v4 command referenced the Linux-only `ipse_owner_control`
module without the target guard used by the neighboring modes. A focused repair
adds that same Linux target guard. Local strict Linux helper compilation and
the existing bound-environment unit control pass (one passed, 83 filtered),
with unchanged native-source postchecks. They establish no macOS build or
runtime pass; the hosted failure and skipped later steps remain failed/unrun.
The retained job-log digest is
`db4ec784f5b5068581dc0a0872cbf4643b4f3ae537a09fef829c12b9558302b2`.

## Exact earlier formatter scope

The following paths are the complete list reported by the Linux formatting step
at `2e3871f3`; they are historical observations, not a prediction of a later diff:

```text
dev/evaluation/protected_answer.exs
dev/knowledge/native_notes_retained_probe.ex
dev/knowledge/native_notes_seed.ex
dev/knowledge/native_notes_turnover.exs
extensions/knowledge/src/corpus.ex
extensions/knowledge/src/evidence.ex
extensions/knowledge/src/graph.ex
extensions/knowledge/src/knowledge.ex
extensions/knowledge/src/store.ex
extensions/knowledge/src/store/collection.ex
lib/ipse/cli/documents.ex
lib/ipse/cli/knowledge/management.ex
lib/ipse/extension/actions.ex
lib/ipse/extension/collection/document_source_use.ex
lib/ipse/extension/collection/managed_retention.ex
lib/ipse/extension/collection/observed_read.ex
lib/ipse/extension/inference.ex
lib/ipse/provider/ollama_models.ex
lib/ipse/runner/management_terminal.ex
lib/ipse/runner/operator.ex
lib/ipse/runner/review.ex
lib/ipse/session.ex
lib/ipse/session/document_embedding.ex
lib/ipse/session/draft.ex
lib/ipse/session/draft_lineage.ex
lib/ipse/session/managed_approval.ex
lib/ipse/session/managed_lineage.ex
lib/ipse/session/managed_reads.ex
lib/ipse/session/managed_supersession.ex
lib/ipse/session/managed_tool_use.ex
lib/ipse/session/operator_assertion.ex
lib/ipse/session/pending_acceptance.ex
lib/ipse/session/pending_rejection.ex
lib/ipse/session/source_window.ex
lib/ipse/session/stored_sources.ex
lib/ipse/session/turn.ex
lib/ipse/tools.ex
test/dev/evaluation/runner_test.exs
test/ipse/session/planning_mcp_test.exs
test/support/generation_paged_budget.exs
```

The retained private read-only investigation is `ci-read-only-20261106-01`.
The exact public-source formatter diff, excluding setup/environment and job
cleanup output, has SHA-256
`2fcc32a239f872dc409d17e684c182351f67242d01b0e2d9f53f08a236371f8e`;
the path-list SHA-256 is
`2160c19207ac16bbea4f993bbc429fc3ae5700be770d2e77d642b1b4dac87a72`.
No full job log, token, private context or fixture journal is exported.

Each hosted job retains its existing 60-minute bound for the complete sequence.
No actual result yet establishes that all later checks fit that bound or that a
particular hosted filesystem supports every native fixture. A future successful
run qualifies only the exact completed commit/platform checks. It establishes no
original retained-notebook recall/day/year, live-account, independent-human or
real-model quality result.
