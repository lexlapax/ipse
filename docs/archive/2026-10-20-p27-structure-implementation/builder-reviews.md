# Artifact builder integration reviews

Historical scoped records, 2026-10-20, against the S04 draft over `c9c4999`.
The private integration baseline was `c516602`; only its S04 diff was transferred
to main. The [verification receipt](builder-verification.json) binds the exact
459-file runtime/test/tool inventory and passing platform executions. Current
construction guidance belongs to the [artifact training chapter](../../developer/extension-artifacts.md).
Whole-P27 acceptance remains in the [plan](../../plan.md#p27-optional-research-graph-and-rag).

## Lead disposition

Acted on all three integration findings. The lab invariant regression now copies
all six sources and establishes a successful seven-artifact build before changing
the module name. A private deletion mutant subsequently published the changed
artifact and failed the intended refusal assertion, proving the corrected test
detects loss of the guard. The observer initially expected older ExUnit wording;
the actual failed assertion and terminal result were independently inspected.
The original builder was restored. Eight focused regressions and both full suites
pass with the real guard.

Both manual findings are corrected: the source-reading path names the shared
builder, and the incompatible-package exercise edits a disposable manifest and
lets import derive its identity. It no longer asks the finite builder to consume
an edited artifact. Reviewer A separately inspected both corrections. Root ran
the literal exercise on both platforms and confirmed the worker stayed unloaded.

Earlier prototype iterations also corrected duplicate CLI flags and MCP omissions,
shared Spec entrypoints and cleanup covering stage initialization. Root reproduced
unstable artifact bytes caused by random staged compiler filenames, then replaced
that pipeline with public compilation using a stable original source filename.
Repeat-build byte identity and diagnostic rejection now have actual regressions.
The older prototype comparisons do not stand in for the integrated checks.

Both final reviewers inspected the whole affected chapters and READMEs. Their
source inspection is distinct from the root's platform execution evidence below.
The original reports follow with heading levels adjusted for this collection.

## Integration review a

### Findings

#### 1. [warning] The lab-entrypoint regression can pass after its guard is removed

**Location:** `/tmp/ipse-p27-builder-integration-source/test/artifact_builder_test.exs:9-10,94-104`.

The per-test source copy contains only `examples/extension-lab/src/memory.ex`, while the recipe necessarily proceeds to `lookup.ex` and four other worker sources. The declaration-drift test renames Memory and accepts any nonzero builder exit with no published output. If the `Spec.module/1` equality check is removed, the two renamed Memory versions can compile successfully, then the missing Lookup source still raises and stage cleanup still removes the output. The test therefore passes without the invariant it claims to protect.

Copy the complete finite lab source set and establish a successful unmodified lab construction control before applying the rename, preferably to a separate output. Then refusal after mutation cannot be explained by incomplete fixture inputs. This is a source-traced false positive; no build or mutation was performed by this reviewer.

#### 2. [warning] The incompatibility exercise asks the finite builder to preserve an edited manifest

**Location:** `/tmp/ipse-p27-builder-integration-source/docs/developer/extension-artifacts.md:246-249`.

The chapter tells the reader to change the runtime platform in a scratch artifact and “rebuild its manifest identity through the builder.” The consolidated command accepts only recipe, SDK, output and the MCP omission fixture. It has no edited-artifact or runtime-platform input, and it reconstructs runtime fields from the current VM. Rebuilding the recipe would discard the intended incompatible-platform edit; using the existing scratch directory as output would refuse.

Describe the actual exercise directly: edit only the scratch manifest's runtime platform, retain its otherwise valid file inventory, and import that scratch copy into an isolated store. Import derives the new identity from the edited manifest bytes. Then observe activation refusal. No production builder escape hatch is needed.

#### 3. [nit] The installed-proof reading path still names the removed lab builder

**Location:** `/tmp/ipse-p27-builder-integration-source/docs/developer/extension-proof.md:35`.

The ordered source-reading list still instructs the reader to open `build.exs` beside the lab's Spec and worker sources. `examples/extension-lab/build.exs` is deleted by this integration. Point that entry explicitly to `scripts/build-artifact.exs` and its `extension-lab` recipe, consistent with the command above and the central construction chapter.

### Runtime and migration scope

Reviewed the complete integration diff against private baseline `c516602`, including the added builder/test, all five deleted originals obtained from that baseline, CI commands, static/dynamic/generated callers, updated stdout assertion and file count, AGENTS code map, trusted workers, lab Spec and proof/config consumers, host Manifest validation and measured runtime-command construction. This review uses `/tmp/ipse-p27-builder-integration-source`, not main or historical prototype C3.

The current compiler uses stable original source filenames, captures diagnostics through public `Code.with_diagnostics/2`, retains private working-directory containment for the saved worker's load marker and purges separately compiled lab versions. The added Spec diagnostic boundary is before stage ownership, so its refusal cannot strand an owned artifact stage. Prior fixes for duplicate flags/omissions, shared Spec entrypoints and cleanup coverage remain present. No further evidence-backed implementation defect was found.

Checked that measured helper launches prepend `model-calls` to argv before the generated Erlang entry sets `System.argv` and requires the CLI script. Active callers use the finite command with the recipe; the independent knowledge builder remains selected separately. The old lab stdout assertion was replaced with an output-path assertion plus a real count of seven descriptors, retaining warning and proof-result checks.

### Whole-manual scope

Reviewed whole chapters, including their unchanged explanation and exercises:

- `docs/developer/extension-artifacts.md`
- `docs/developer/extension-model-calls.md`
- `docs/developer/extension-embedding-actions.md`
- `docs/developer/extension-mcp-actions.md`
- `docs/developer/extension-proof.md`
- `docs/developer/extension-scenarios.md`
- `docs/developer/knowledge-evaluation.md`
- `docs/operator/extension-lab.md`
- Complete READMEs for embedding-actions, model-calls, mcp-actions and saved-results.

The evaluation chapter's complete 1,872-line flow was reviewed in the preceding independent manual pass; this integration changes only its answer-artifact build command, which was checked in that whole flow and against the actual new grammar. Its measured generation/version, custody and qualification meaning remains unchanged. No new/moved chapter requires an index destination change. The central artifact chapter owns construction grammar and staging; specialist chapters keep their task and protocol teaching. Apart from findings 2 and 3, no additional consequential manual contradiction or incomplete fresh-output command was found. Existing source/installed proof distinctions are retained without treating the pending stronger common verifier as implemented.

### Checks and limits

- Inspected all current source and documentation diff hunks and searched active callers/manuals for removed full builder paths and contextual `build.exs` references.
- Independently inspected `Code.fetch_docs(Code)` for `with_diagnostics/2`; its public metadata reports `since: "1.15.0"`, within the documented Elixir 1.18 minimum.
- Ran `git diff --check c516602`; it passed.

No artifact/repository build, ExUnit/full suite, worker/model/service operation, private evaluation corpus/questions/gold or evaluation report was run or opened. No source, main checkout or prototype was modified. The owner-reported latest and historical prototype checks were not counted as my executions. Historical prototype equivalence does not prove the new compiler, and this read-only review establishes no installed/platform or complete measured proof result.

### In-review correction of finding 1

Finding 1 is resolved in the latest source revision observed before delivering this report. The fixture now copies all six lab worker sources, and the invariant test first requires an unmodified successful lab build with seven descriptors. It applies the rename afterward and uses a separate fresh `changed` output path for the refusal. Source inspection confirms that the former missing-Lookup and existing-output explanations can no longer make this regression pass. I did not execute the corrected test.

### Final manual disposition in main

Findings 2 and 3 are resolved in the corrected main-workspace manuals. Read the complete revised incompatible-package exercise and ordered reading path.

The incompatibility exercise now uses the previously built Lookup artifact, copies it into a disposable directory, edits only that scratch manifest's platform, imports it to derive the edited manifest identity, asserts incompatibility and executable-admission refusal, then demonstrates hash refusal after changing the imported fixture license. It explicitly states that the finite builder does not consume edited artifacts. Source inspection confirms Worker checks platform compatibility before options validation or launching executable code, and Store's invalid-artifact result matches the example.

The proof chapter now names `scripts/build-artifact.exs`, identifies the finite `extension-lab` recipe and links the authoritative construction flow. It no longer directs the reader to the deleted lab builder.

This disposition is source/manual inspection only. I did not execute the literal exercise, rerun the corrected focused tests or run any broad build/test/service operation. The owner's live platform controllers and reported focused results remain separate evidence.


## Integration review b

## S04 integrated builder review B

### Findings

1. **[P2] Repair the incompatible-manifest exercise.** `docs/developer/extension-artifacts.md:245-255` tells a reader to change the runtime platform in a scratch artifact and “rebuild its manifest identity through the builder.” The new `scripts/build-artifact.exs:1-10,159-210` accepts only five fixed recipes and a fresh output path; it cannot consume or rebuild a modified scratch artifact. The old example-specific builder was also deleted. Rewrite this as a fixture/manual manifest-edit exercise with exact hash/update steps, or point the reader to the existing `extensions_store_test.exs` case rather than instructing an impossible builder operation.

2. **[P3] Replace a deleted source-reading step.** `docs/developer/extension-proof.md:31-38` still directs contributors to read `build.exs` as item 2, immediately after the new `scripts/build-artifact.exs` command. `examples/extension-lab/build.exs` is deleted in this diff; the shared builder is now the implementation to trace. Name its full path (and finite `extension-lab` recipe) so the ordered training exercise has a real target.

### Reviewed scope and limits

Read the full integrated `scripts/build-artifact.exs`, `test/artifact_builder_test.exs`, the complete diff against private base `c516602`, the five original builders (their baseline content was previously reviewed and the base retains the same 46/46/61/87/71-line files), lab Spec and worker source, generated `EvaluationMeasuredExecution.command/4` launch shape, migrated static/dynamic call sites, CI and active old-path references. Read the full changed developer chapters `extension-artifacts`, `extension-embedding-actions`, `extension-mcp-actions`, `extension-model-calls`, `extension-proof`, `extension-scenarios`, operator `extension-lab`, and all four affected example READMEs, plus audience indexes. The complete `knowledge-evaluation.md` was read in the preceding evaluator review; this integration changes only its answer-builder command, which I inspected against the current chapter and dynamic helper.

No further runtime defect was established by source inspection. The current builder uses `OptionParser` keep flags to expose duplicate options, an exact finite recipe set, the shared lab module/description checks, single-declaration MCP omission check, stable original source filenames through `Code.compile_string`, captured diagnostics for Spec and artifact compilation, staged on-load containment, manifest validation and fresh-target publication. The changed test directly checks repeat-build byte identity. These observations do not prove all former source and installed proof scenarios: the reported seven actual CLI regressions predate the final Spec-diagnostic guard, and full positive five-recipe/platform/installed checks remained pending at review time. I ran no builds, tests, services, models or private inputs and changed neither MAIN nor the integration checkout. Historical C3 prototype receipts were not treated as evidence for this integrated compiler.
