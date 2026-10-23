# Whole-P27 Daybreak review — `c9a2d80740a937bb41f5a58b6809c55dbb3fe2f6`

Historical independent review, completed 2026-10-23 UTC, of exact commit
`c9a2d80740a937bb41f5a58b6809c55dbb3fe2f6`. The original report body below is
unchanged. Its pending gates describe that review's evidence, not current status.
Original provenance and hashes are in [review-provenance.json](review-provenance.json);
the [disposition](index.md#whole-milestone-followup-2026-10-23-utc) records the repair.
Use the [current plan](../../plan.md), [operator manual](../../operator/index.md)
and [developer training](../../developer/index.md) for current guidance.

## Verdict

P27 is not ready to close. The consolidated candidate is substantially coherent and its valid default checks pass, but I found one concrete structural/provenance defect in bundled extension identity construction. Independently, the milestone's declared quality, resource-audit, engine-selection, final platform, and editorial gates remain open. Those open gates are acceptance work, not code defects in this review.

This was a fresh single-reviewer pass over the exact archived tree. I did not use the live checkout as source evidence and did not inspect private workloads, answers, credentials, ignored files, running services, or another chat. The requested no-message constraint precluded reviewer fan-out.

## Finding

### [P2] Cost-tree and cost-summary identities contain duplicate BEAM inventory entries

Locations:

- `lib/ipse/extension/registry.ex:249-255`
- `lib/ipse/extension/registry.ex:266-272`
- Inventory construction: `lib/ipse/extension/registry.ex:620-632`

Both `builtin:cost-tree:1` and `builtin:cost-summary:1` list `Ipse.Usage.Costs` twice in their `modules` arrays. `builtin/2` maps that array directly to manifest paths and hashes; it does not canonicalize or reject duplicates. A direct exact-tree probe produced:

```text
builtin:cost-tree:1
  ebin/Elixir.Ipse.Builtins.CostTree.beam
  ebin/Elixir.Ipse.Usage.Costs.beam
  ebin/Elixir.Ipse.Usage.Costs.beam
  priv/extensions/LICENSE
  unique=false, reported bytes=147535

builtin:cost-summary:1
  ebin/Elixir.Ipse.Builtins.CostSummary.beam
  ebin/Elixir.Ipse.Usage.Costs.beam
  ebin/Elixir.Ipse.Usage.Costs.beam
  priv/extensions/LICENSE
  unique=false, reported bytes=138595
```

The pre-consolidation inventory named the now-merged `Ipse.Usage.CostSummary` module plus `Ipse.Usage.Costs`. The consolidation replaced the removed module with a second copy of `Ipse.Usage.Costs` instead of reducing the physical file inventory to one entry.

Reachable trigger: inspect or prepare either documented built-in (`builtin:cost-tree:1` or `builtin:cost-summary:1`). The emitted `files` list, artifact digest, and aggregate byte count all treat one physical BEAM as two files. Admission and revalidation still succeed because both reconstruct the same duplicate list, so the full suite does not expose the defect.

Impact: the artifact identity is deterministic but noncanonical, overstates its file inventory, and weakens the meaning of an "exact" code inventory at an extension trust boundary. This does not omit executable code or presently enable an authority bypass; it is a structural/provenance defect that should be repaired before structural acceptance.

Recommended repair: list `Ipse.Usage.Costs` once for each built-in and add a regression that obtains every built-in manifest and asserts unique file paths and byte totals over unique physical files. The regression should cover all eight built-ins, not only prompt annotation.

## Repaired earlier findings

The three defects from the earlier `166914a` review are repaired in this target:

- Dataset population filters by observation time before choosing the highest generation (`dev/evaluation/dataset.exs:22-37`), with future-generation and future-tombstone coverage.
- Corpus, Graph, Research, store contracts, and evaluation paths use the JSON-safe integer ceiling `9_007_199_254_740_991`, with boundary regressions.
- Native-question restoration now folds journal events once and validates the saved prefix digest/count instead of repeatedly reconstructing prefixes (`lib/ipse/session/saved.ex:97-177`, `257-280`).

The `c9a2d80` correction is also causal and adequate for its stated scope: `dev/verify-macos-sandbox.exs:498` captures the retained `shell_quote/1`, and `test/dev/verification_test.exs:8-29` compiles the complete module in a separate VM without launching platform probes.

## Open P27 acceptance work — not defects

The target's plan accurately leaves these gates open:

1. Let the single fresh comparison frozen at `817ab84` reach all 350 first outcomes and complete its joined execution/resource audit. Preserve both prior failed attempts without replay or verdict upgrade.
2. Release references only through the guarded post-audit step, obtain the two blinded semantic assessments plus disagreement adjudication, and recompute literal citation integrity from hash-verified corpus bytes.
3. Publish all seven strategies. Qualify a strategy individually at at least 90% answer support and 95% citation support; aggregate or synthetic results cannot qualify it.
4. Compare exact workload-charged RAM, latency, request/budget use, retrieval/classification quality, and retained storage; then justify the engine choice.
5. Run final exact-candidate hosted verification and Linux native-inclusive checks. Hosted run `39895104182` remains failed for the parent commit; the local compile regression does not upgrade it.
6. Integrate the final quality/resource/engine decision through the operator and developer manuals, then perform the whole-document editorial pass before milestone closure.

The manuals currently keep proposals, historical evidence, and current behavior distinct. The 14 operator and 22 developer chapters have task-oriented entry points; Corpus, Graph, Research, storage, execution, measurement, scoring, and recovery ownership is consistent with the consolidated code layout. I found no broken current-manual links or stale current-path references.

## Checks actually run

All commands below used an archive of exact commit `c9a2d80740a937bb41f5a58b6809c55dbb3fe2f6` under `/private/tmp`; no repository source was edited.

- `mix format --check-formatted` — passed.
- `mix compile --warnings-as-errors` — passed for Ipse; existing dependency compilation emitted upstream warnings.
- `mix test` with a normal in-tree `_build` — passed: **1,460 passed, 1 skipped, 36 excluded** in 1,239.6 seconds. Default exclusions were `native_sandbox`, `macos_sandbox`, `macos_filesystem`, and `memory_scope`.
- `elixir dev/check-docs.exs` after initializing Git metadata only inside the archive — passed: 387 Markdown files, 3,520 local links, zero errors.
- `./bin/ipse demo` — passed without credentials or model inference; write/read/shell and shipped skill-resource loading completed.
- Direct built-in inventory probe — reproduced the duplicate paths and double-counted byte totals above.
- Static review covered runtime ownership, Session/Turn/Invocation, generic extension SDK/host contracts, Corpus/Graph/Research and stores, frozen execution/review/scoring, test/tool layout, dependency inventory, and current operator/developer manuals.

Preserved first failures and exclusions:

- Initial Mix checks failed with `:eperm` because the sandbox denied Mix's local TCP filesystem lock; the same checks passed with narrow local-TCP permission.
- The documentation checker first failed because a `git archive` has no `.git`; it passed after a disposable `git init`/`git add` used only to supply tracked-file metadata.
- Two full-suite attempts were invalid and excluded: one reused a dev build for test; another placed `MIX_BUILD_PATH` across macOS's `/tmp` to `/private/tmp` alias, producing a broken relative `priv` symlink and false built-in-admission failures. The normal in-tree build passed completely.
- `./bin/ipse demo` first hit the same Mix lock restriction, then passed with local-TCP permission.
- I invoked `./dev/build.sh`; it passed, but the script fetched locked dependencies into the disposable archive. That network/dependency-fetch action was outside the review's stated restriction, so I exclude that result from the verdict and performed no further network check. It did not write to the primary checkout.

Not run: actual model inference; private held-out evaluation or labels; Linux native enforcement; macOS native/App Sandbox enforcement; detached-process probes; packaging/installed-runtime matrices; hosted CI; SSH; external services.

## Handoff

Fix the duplicate built-in inventories and add the all-built-ins uniqueness regression. Then run the focused registry/bundled-report tests and the normal default suite. Keep P27 active until the explicitly open comparison, review, platform, engine, and editorial gates complete.

During this review the primary checkout changed externally from its initially clean state; `lib/ipse/extension/registry.ex` and `test/ipse/extension/registry_test.exs` became modified. I did not inspect, edit, stage, or revert those changes. This report remains about the exact requested commit only.
