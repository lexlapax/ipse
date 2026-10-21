> Historical review of `166914a`, captured 2026-10-21. Current behavior is taught in the [knowledge manual](../../developer/knowledge-extensions.md); current acceptance is in the [plan](../../plan.md). The original report body below is unchanged.

# Independent Daybreak review of Ipse P27 at `166914a`

- Exact target: `166914a365784e80afb48551138be01bc6b1044b`
- Review date: 2026-10-21
- Primary checkout: clean, on `main`, equal to `origin/main`, kept read-only
- Disposable review copy: public tracked archive under `/tmp/ipse-p27-review.MYeIrC`
- Verdict: **not ready for the private held-out freeze or P27 completion**

P27 has a coherent optional-package architecture and strong fail-closed host contracts, but the current evaluator can construct the wrong historical source population. Two additional reachable defects weaken portable identity and bounded resume. The first defect must be fixed before any held-out prediction run. After those repairs, P27 still requires the already-declared actual-model quality, independent semantic review, exact resource comparison, engine selection and final candidate gates.

## Intent

P27 is intended to provide independently useful Corpus, Graph and Research packages on generic extension host contracts. It must preserve named profile selection, source and citation identity, bounded operations, deletion and expiry behavior, approvals, egress, ownership, cancellation, journaling, shared budgets and no replay. Its frozen comparison must publish all 350 first outcomes, expose labels only after complete prediction and audit evidence, qualify one strategy independently at 90% answer support and 95% citation support, measure exact workload-charged RAM, and select an engine only after matched quality and resource evidence.

## Findings

### F1. High: the frozen evaluator drops the generation that was current at `as_of_ms`

**Location:** `dev/evaluation/runner.exs:2114-2123`, reached from Research gateway selection at `:1202`, Corpus/Graph projection selection at `:1419`, and rerank approval reconstruction at `:1874-1877`.

**Trigger:** A source has generation 1 observed before the frozen `as_of_ms` and generation 2 observed after it. The dataset contract permits this shape and retains every generation. `current_documents/2` groups all versions, chooses the maximum generation, then rejects that row because its observation is in the future. It never falls back to generation 1.

**Impact:** The source population is historically wrong. Corpus and Graph omit the generation that was current at the selected time. Research's gateway omits it too, and rerank admission reconstructs the same wrong population. Because prediction, approval and audit use the same helper, a seven-strategy run can be internally consistent while comparing the wrong evidence. Resource totals are wrong with it. This invalidates engine-selection evidence for any workload containing this ordinary version pattern.

**Evidence:**

- `docs/developer/knowledge-evaluation.md:955-968` says the dataset retains all generations and leaves lifecycle projection to the execution plan.
- `docs/developer/knowledge-evaluation.md:1149-1160` says only current eligible generations reach projection and every variant receives the fixed `as_of_ms`.
- `docs/operator/corpus.md:75-77` says sources observed after the selected time are not current evidence.
- The existing multi-generation test at `test/knowledge_evaluation_runner_test.exs:348-374` gives both generations the same observation time, so it misses this case.
- A finite probe copied the exact helper logic with generation 1 observed at 1000, generation 2 at 3000 and `as_of_ms` 2000. It exited 1 and printed `%{actual_keys: [], expected_keys: ["eligible-v1"]}`.

The same ordering error applies when a later lifecycle row, such as a suppression or deletion, is observed after the frozen time. The evaluator can suppress an earlier generation retroactively.

**Focused repair:** Apply observation-time eligibility before choosing the maximum generation. Then apply the chosen row's state and expiry policy. Add a public-Session seven-strategy regression with an older eligible generation and a future replacement, plus a future tombstone case. If the intended policy is instead that any later-known generation erases all earlier history, reject such datasets in `Dataset` and `Contract` and remove the as-of reconstruction claim from the manuals.

### F2. Warning: independent knowledge contracts accept integers beyond portable JSON identity

**Locations:**

- `extensions/knowledge/src/graph.ex:117-125` and `:349-362`
- `extensions/knowledge/src/evidence.ex:37-49`, `:1021-1030`, and `:1057-1060`
- `extensions/knowledge/src/research.ex:174-187`

**Trigger:** Supply `9_007_199_254_740_992`, one above the largest exactly representable JSON integer, as Graph `as_of_ms` or as a provided Research source's generation or timestamp. Graph checks only that `as_of_ms` is a nonnegative integer and publishes no schema maximum. `Evidence` and the Research provided-source validator also accept unbounded positive generations and nonnegative timestamps.

**Impact:** These values cannot retain exact identity in common JSON runtimes. They can round or collide after crossing the extension or MCP boundary, while citation IDs and time selection depend on their exact values. This is inconsistent with Corpus's safe-integer bound and the documented knowledge contract.

**Evidence:**

- Corpus enforces `0..9_007_199_254_740_991` at `extensions/knowledge/src/corpus.ex:93-94`.
- `docs/developer/knowledge-extensions.md:923-936` describes `as_of_ms` and related protocol numbers as safe integers.
- A direct public-code probe passed `9_007_199_254_740_992`. `IpseKnowledge.Evidence.source/1` returned `{:ok, source}`, and Graph accepted the query far enough to emit a `host_call`. The probe exited 1.

**Focused repair:** Define shared safe unsigned and positive integer predicates in the independent package. Use them for Graph query time, Evidence generations and timestamps, fact times, and Research provided sources. Add minimum and maximum constraints to Graph's published schema. Test the maximum safe value and maximum plus one across Corpus, Graph, Research and Evidence.

### F3. Warning: saved-session operator-question reconstruction is quadratic

**Location:** `lib/ipse/session/saved.ex:218-265`, especially the prefix reconstruction at `:235`; admitted ceiling at `lib/ipse/journal/limits.ex:3-6`.

**Trigger and call chain:** Resume a valid journal containing many completed `ask_operator` turns. `Saved.restore/2` validates the whole journal, then `restore_question/2` enumerates every historical `operator_question`. For each question it copies the preceding events with `Enum.take/2` and reruns `restore_validated_context/1` over that prefix.

**Impact:** Resume cost grows with the sum of all question positions. A valid 100,000-event journal with frequent questions can require hundreds of millions to billions of event reductions before recovery completes. The problem is reachable through ordinary turns and does not require malformed input.

**Evidence:** `lib/ipse/session/saved.ex:72-84` already projects the complete history once. Lines 218-220 acknowledge that validation, but lines 221-240 reconstruct every question prefix again. The configured event ceiling is 100,000.

**Focused repair:** Validate question checkpoints during one chronological reconstruction. Carry projected messages and active question state, check the prefix digest when the question event is encountered, and remove repeated `Enum.take/2` and `restore_validated_context/1` calls. Add a scaling regression with many completed questions and assert near-linear growth.

## Structural concern to address before completion

`dev/evaluation/runner.exs` is 2,667 lines and owns phase dispatch, dataset projection, scheduling, Session execution, gateway lifetime, predictions, first-grid sealing, audit merging, resource attribution, schema construction and output files. It also transports active run, policy, gateway and selected time through process-dictionary entries. I did not find a second incorrect receipt caused by this structure, so file size alone is not a release defect. Still, the concentration made the as-of error easy to reuse consistently across prediction and approval. Before declaring structural readiness, split phase dispatch, cell execution, prediction sealing and audit joining behind explicit context values while retaining the frozen byte contracts.

## Architecture assessment

### Package and host ownership

The main boundary holds. Corpus, Graph, Research, BM25, graph traversal and reranking remain outside `lib/`. The public SDK owns invocation/result publication contracts; generic host modules own MCP, model, embedding, State, effect-result and mixed-action admission; Builtins remain separate from the independently built knowledge packages. Config, Saved and CurrentInvocation now have distinct responsibilities rather than duplicating policy and reconstruction inside Session.

Named profiles are closed and package-specific. Enabling Memory, Corpus, Graph or Research does not silently enable another package. Profile validation rejects unused authority in the sampled repaired cases. The host binds approved model, MCP and embedding destinations to selected descriptors and reconstructs saved results without replay.

### Knowledge identity and lifecycle

Store publication uses immutable pages and a final conditional root update. Suppression, tombstones, stale projection checks, collection reachability and unknown-effect stop behavior are present and covered by focused tests. Citation rows retain source, generation, content, chunk, byte and quote identities. The scorer recomputes literal citation integrity from hash-validated corpus bytes instead of trusting the semantic reviewer. RRF now fuses on chunk identity, the listener checks IPv4 and IPv6 procfs tables, and package profile validation rejects the prior unused-MCP-authority cases.

F1 remains a separate evaluator lifecycle defect. The production Store's current-view policy does not justify changing the frozen dataset's declared historical selection.

### Generic effects, ownership and budgets

The reviewed paths journal intent before effects, keep child MCP denial, bind complete proposed egress, return unknown after ambiguous interruption, and do not replay. Mixed action limits remain finite and operation-specific. Embedding and model requests use selected profiles and schema-bound plan-three output contracts. Canonical usage, shared request/money limits and saved usage reconstruction use the common owners introduced before this commit.

No new reachable approval bypass, silent provider switch, automatic replay, result-publication truncation, or budget escape was established in this review.

### Frozen evaluation and measurement

The declaration fixes seven strategies and fifty questions. The scorer enforces the plan-three strategy list, a complete first grid, independent applicable review, 90% support and 95% citation precision per strategy, and at least one individually eligible strategy. Missing outcomes, retrieval-only rows, incomplete review and zero citation pairs do not qualify.

Measured execution binds runtime and source identities, claims native authority before work, runs preparation, fourteen cells and finalization, audits the merged streams, verifies cleanup receipts and separates fresh-lifetime peaks from whole-population interval peaks. The selected Linux metric is workload-charged cgroup memory rather than sampled RSS. Synthetic controls exercise this protocol, but they are not actual-model quality or resource evidence.

F1 blocks reliance on a private measured run until repaired. The engine-selection decision mechanism and final decision are still absent by design because the evidence gates remain open.

### Manuals

The operator manuals keep Corpus, Graph and Research as separate tasks and state the attribution limits. The developer manuals distinguish public SDK, generic host, Builtins and independent packages, and they separate fixtures from actual-model evidence. The current plan plainly marks P27 incomplete. The consolidated manual checker passes. I found no new broken link or material ownership contradiction. The F1 behavior contradicts the documented evaluation lifecycle and needs code repair or an explicit contract change.

## Open acceptance work, not implementation findings

The following gates remain open and this review does not satisfy them:

1. Repair F1 and rerun the affected public evaluator matrix before exposing the private workload.
2. Produce all seven strategies and all 350 first outcomes on the untouched held-out input.
3. Obtain independent semantic judgments after complete prediction and post-exit audit evidence.
4. Show at least one strategy individually reaches 90% answer support and 95% citation support.
5. Run the matched actual-model comparison, including the exact-memory baseline requested by the user.
6. Complete exact workload-charged RAM, latency, usage and storage comparisons under the selected CPU policy.
7. Select and document an engine only after quality and resource gates pass.
8. Complete the originating chat's final exact-candidate source, native, package, installed and platform gates. I did not run or adopt those checks.

Existing fixture, synthetic, prior-source and earlier external-review receipts remain evidence only for their named scope. They cannot close these gates.

## Reviewer panel and lead judgment

The adversarial panel used three read-only reviewers with the same milestone intent and rubric, plus this lead review.

- Reviewer A: two warnings. I accepted the quadratic Saved finding. I kept Runner coupling as a structural concern rather than a demonstrated runtime defect.
- Reviewer B: one warning. I accepted and reproduced the unsafe-integer boundary.
- Reviewer C: one warning. I accepted and reproduced the frozen as-of generation defect.

The reviewers did not duplicate one another's concrete findings. That lowers consensus confidence relative to a repeated finding, but each accepted issue has a reachable call path and direct source evidence. F1 and F2 also have finite reproductions. No reviewer claimed P27 complete. All agreed that held-out quality, actual-model resources, independent semantic review and engine selection remain open.

Rejected or reclassified observations:

- Large Store and Runner files are not defects solely because of line count. Runner's coupled responsibilities merit planned decomposition because they impede audit and already share the F1 helper across multiple trust checks.
- Reviewer independence is asserted by custody and metadata, not cryptographically proven. `Score` states this limit; the independent review procedure is the acceptance mechanism.
- The direct source import size/continuation limits are documented, fail closed and have recovery instructions. I treated them as accepted limits.
- I did not reopen prior external-review findings that current source and regressions show as repaired, including RRF chunk fusion, score-time literal-integrity recomputation, IPv6 listener inspection and unused profile authority.

## Checks actually completed

All commands below used the exact tracked archive. No actual model or paid provider ran.

| Check | Result |
| --- | --- |
| Exact target and clean primary checkout | Passed; HEAD and `origin/main` were `166914a365784e80afb48551138be01bc6b1044b`, with no worktree changes |
| Focused tests: evaluation score/review/freeze/measured, knowledge Store/domain regressions, mixed actions and schema-bound model calls | First attempt failed before compilation because the sandbox denied Mix's local TCP event/lock mechanism (`:eperm`). The identical elevated loopback-capable run passed **104 tests** in 94.4 seconds |
| `mix format --check-formatted` | Passed in the disposable archive |
| `mix compile --warnings-as-errors` | First sandboxed attempt failed on the same Mix local TCP lock. The identical loopback-capable run passed |
| Documentation checker | First attempt failed because a Git archive has no `.git` metadata. After initializing and staging the disposable archive only, it passed: **326 Markdown files, 3,413 local links, 0 errors** |
| Frozen generation probe | Expected failure reproduced: actual eligible set was empty; expected set contained generation 1 |
| Safe-integer probe | Expected failure reproduced: Evidence accepted generation/time `9007199254740992`, and Graph emitted a host call for that `as_of_ms` |
| Prior public external review | Read through the explicitly authorized read-only SSH path `serenity:/tmp/ipse-p27-review-b9370fb.md`; no remote files or services were changed |

The focused test run compiled public dependencies already present in the main workspace into the disposable `/tmp` build. It did not fetch or install dependencies.

## Exclusions and evidence limits

- I did not open `.ipse/private-evaluations/p27-2026-10-20-c1` or `/tmp/ipse-heldout-independent-20261020-c1`.
- I did not read ignored configuration, credentials, private journals, environment dumps or private evaluation data.
- I did not launch actual inference, a model daemon, MCP service, native cgroup population, packaging job, installed-runtime matrix, full test suite or hosted CI job.
- I did not claim the originating chat's packaging/final-candidate checks as my checks.
- I did not modify, commit, push or change branches in the primary checkout. Temporary probe files and local Git metadata exist only in the disposable `/tmp` archive.
- The review covered the milestone architecture and relevant implementation/tests, but it is not an exhaustive formal proof of every generic host module.

## Readiness verdict

**P27 is not implementation-ready for the private held-out freeze.** F1 can corrupt the comparison population while leaving prediction, approval and audit mutually consistent, so it is a pre-freeze blocker. F2 should be fixed with the same boundary sweep, and F3 should be repaired before bounded-journal recovery is treated as structurally complete.

After repair and focused regressions, the project can proceed to a fresh candidate validation and then the untouched held-out execution. P27 cannot be declared complete unless an independently reviewed strategy passes both fixed quality thresholds under the matched actual-model resource comparison and the project records the resulting engine selection.
