# Corrective review record

Historical review evidence, 2026-10-22. These source-only reviews cover the
streaming-audit and explicit-context increment after `e402be6`. Their line
references describe the source/documents at each review. They do not independently
establish the parent's test results, model quality or a passing private comparison.
Current procedures belong to the [evaluation manual](../../developer/knowledge-evaluation.md);
acceptance belongs to the [plan](../../plan.md#p27-optional-research-graph-and-rag).

## Lead dispositions

The reviewers agreed on streaming literal comparison, retained per-cell identities,
separate parsed bounds, explicit versioned context, CPU/GPU separation, completion
versus embedding evidence and unchanged historical authority. Their design warnings
became implementation requirements. Corrective streaming implementation reviews
found no actionable issue. Context implementation review A found two missed fixture
callers. Both were migrated, with affected tests run afterward; no compatibility
overload was added. Review B found no additional contract defect.

Whole-document review A found no actionable issue and independently verified the
previous-plan snapshot's original hash and body preservation. Review B identified
an omitted explicit zero-failure safety gate and missing runnable extended-answer
preflight. Both findings were accepted. The plan now states the safety gate; the
manual teaches a bounded approved public-Session request through a fresh owned
service. Follow-up B found both resolved. The exact example subsequently passed
against a synthetic fixture, including saved context, accounting, decode and
cleanup. That exercise makes no semantic-quality claim.

All original reports below are retained with SHA-256 identity. Relative source
paths and temporary report paths are historical references. The original private
seal and its failed public audit were not amended. References remain sealed.

## Review 1: ipse-p27-merged-audit-review-a.md

Original SHA-256 `bb06885b86869d269f2f7334fc37be3b3a0a40f357833d306082238e1a3cec41`.

# Saved measured-comparison capacity review

Source-only review at the supplied checkout. Read the reviewer rubric and quality lens. No private data, remote host, labels, inference, or repository edits. The reported run sizes and natural exits are supplied facts, not independently observed.

## Findings

- **warning — dev/evaluation/runner.exs:766,843; dev/evaluation/measured_execution.exs:1088.** Writer and audit contracts disagree. Finalization reads each of six cell streams without an aggregate bound and writes their ordered concatenation. Closed domain files individually allow 67,108,864 bytes at runner.exs:726. Audit instead requires both the aggregate file and the sum of cell parts to fit 67,108,864 bytes. Fourteen admitted cell files can therefore produce a valid concatenation rejected solely for size. The supplied 68,167,328-byte execution stream exceeds this by 1,058,464 bytes. Audit holds actual bytes, every part, and a concatenated copy; raising one constant retains unnecessary aggregate allocation. Execution bytes are never decoded downstream: audit only hashes them. Suggest exact bounded chunk comparison in schedule order, with incremental SHA-256 and exact EOF/length checks, returning identities rather than every merged binary. Preserve the prediction-specific failure code. Derive aggregate maximum from the bounded admitted cell count and per-cell file bounds; use verified cell identities to determine expected sizes, never an arbitrary size chosen from this observed run. Keep explicit bounds on parsed streams.

- **warning — dev/evaluation/runner.exs:790-799,2582; dev/evaluation/measured_execution.exs:1091-1123,1400; dev/evaluation/score.exs:163-204.** Fixing the merger alone does not establish a general capacity contract. Finalizer parses predictions, timings, request-resources, usage, and resources through a 33,554,432-byte whole-file JSONL reader, with a 1,048,576-byte bound on each decoded line. Measured audit currently reads these aggregates up to 64 MiB, and resource-summary.json separately up to 64 MiB. Resources.summary stores all storage snapshots in its output, so summary size scales with the input. Scoring reads predictions up to 64 MiB, then enforces 16,384 rows, 262,144 bytes per row and further semantic text/depth/collection bounds. Thus parsed-stream capacity needs an explicit shared policy where appropriate, while score semantic restrictions remain intact. For this supplied run, predictions 4,150,340; resources 4,407,917; summary 4,441,901 are within these byte bounds. Resource-summary exceeds 1 MiB but its measured audit consumer uses 64 MiB, so changing that reader to Runner's default 1 MiB would introduce a new failure. Sizes alone cannot prove prediction rows satisfy scoring. Do not enlarge every reader in response to an execution-log problem.

- **critical if proposed as admission for the original run — dev/evaluation/freeze.exs:324-333; dev/evaluation/measured_execution.exs:605-622; dev/evaluation/runner.exs:446-469; docs/developer/knowledge-evaluation.md:843-869.** Existing mechanisms do not admit a new independent verifier for an old seal. Freeze.verify requires the original clean source snapshot and exact measured runtime snapshot. MeasuredExecution.context! additionally requires its source directory and evaluator file hashes to match. Scoring re-runs this same audit and matches its hash before accessing labels. Documentation explicitly binds the audit to captured evaluators and describes the cumulative 64-MiB rule. Patching captured code, injecting replacement BEAMs, or bypassing these checks would break authority. The original measure/audit failures must remain failures even after a product fix. An independently versioned re-audit is a new acceptance mechanism requiring explicit review and authority, not a CLI option already present.

## Smallest sound product design

Keep two operations clear: prove ordered byte identity of all six aggregate streams; parse bounded semantic evidence for grid/resource checks. The former needs constant working memory and incremental hashing, not a map containing six binary bodies. Compare exact chunks across cell boundaries against one aggregate descriptor and require all expected bytes and final EOF. Verify regular files, bounded cell count and cell sizes, short reads, growth/truncation, and digest agreement with audited cell identities. A hash-only equality comparison is weaker than the existing literal equality contract; preserve literal comparison while computing report hashes. For parsed streams, consume exactly the checked bytes, or re-read with strict bounds and revalidate the consumed digest before accepting. Avoid a compare-then-unverified-reopen gap. The current cells-first audit also benefits from digest agreement during comparison rather than trusting files remain unchanged between reads.

A derived larger aggregate bound plus materialization would unblock this instance but can multiply memory by fourteen, and still leaves finalization's32-MiB parsed-stream bounds. Streaming only execution while retaining the existing semantic bounds is a bounded incident fix; a single six-stream comparison implementation is easier to maintain than six independently evolving comparison paths. Preserve report.merged_files as digest bindings and retain resource recomputation against verified data.

## What independent re-audit would require

A separate approved verifier identity must be bound independently of the original execution identity. Verify original source/runtime artifacts as evidence without claiming that the new audit executable is the original runtime. Preserve manifest, experiment, plan, frozen source/runtime hashes, claims, first predictions, cell inventories, root/stage receipts, and original public failure outputs byte-for-byte. Record separate verifier source/build identity, protocol version, explicit capacity-only amendment, input inventory digest, original failure identity and reason, and new report digest outside the original freeze/reports. The result must say 'independent re-audit under version X', with original measure/audit still exit1/file_limit.

The new verifier must reproduce all original non-capacity checks, including launch authority, receipt identities and cleanup, no replay/consumption claims, prepared schedule, first prediction grids, exact six-stream concatenation, resource recomputation and finalization identity. It must construct original launch expectations from the captured execution artifact identities, not its own newly built BEAMs. Comparing old and new results on ordinary passing fixtures and every existing tamper case is essential evidence that only capacity admission changed. Capacity policy must be fixed before label access and apply uniformly to all cells/variants; no data selection or regenerated summaries. Existing review/score gates must explicitly understand and bind the separate audit authority before it can authorize label release. Until that contract is approved and implemented, an external read-only diagnostic can explain failure but cannot provide the current CLI's successful measured audit authority.

## Regression evidence required

Extend test/knowledge_evaluation_measured_test.exs:241's existing literal-equality tests with an actual aggregate above 64 MiB whose individual parts remain admitted. Exercise 64 MiB exactly and 64 MiB+1, empty cells, chunk and cell boundaries, reorder, same-length mutation, append, truncation, missing/nonregular files, and oversized individual cells. Require returned hashes to equal independently hashed fixture bytes and input trees to remain unchanged on success/failure. Check all six names, including aggregate resource tampering with a correspondingly edited summary. Keep explicit parsed-stream/row bounds tested independently of raw comparison capacity. The existing dev/verification/measured_knowledge.exs:340 tamper suite provides integration coverage to extend, but does not currently exercise aggregate capacity.

Verification performed: direct source tracing of all six merged stream producers/consumers, cell inventory bounds, freeze and context checks, scoring admission, resource summary construction, existing unit/integration tamper tests, and authoritative developer manual. Elixir 1.20.3/OTP 29 is available. No runtime reproduction or tests run; the assignment permits writes only to this report, so no fixture files were created. No claim about actual retained run integrity or successful re-audit is made.

## Review 2: ipse-p27-merged-audit-review-b.md

Original SHA-256 `881aea6dbf22b5e09e8a3f9bae8a6d28d546ab272b349d824f5bb6d17c1f4ef7`.

# Independent source review B

Scope: source-only, no private workload, labels, packets, continuations, remote host, or inference accessed. Read requested rubric and code-quality lens. No repository edits. Supplied run sizes/statuses treated as reported facts, not independently verified.

## Findings

- **warning — Runner.audit_merged_files/2, dev/evaluation/runner.exs:843–860; finalize_reports around 765.** Writer concatenates all cell files without an aggregate size ceiling; audit reads each merged stream with 67,108,864 bytes, and independently imposes the same aggregate bound on the ordered parts. The reported 68,167,328-byte execution stream necessarily refuses before comparison. Each legal 64 MiB cell can contribute to a legal larger concatenation. This is a producer/consumer contract defect, not evidence that measured execution failed or that its evidence passes. Raising only the `actual` read bound still fails the parts accumulator. Current code retains merged bytes, parts, and joined bytes together; a much larger global constant multiplies memory without addressing the model.

  **Smallest strong design:** audit opaque execution bytes by bounded fixed-size incremental reads, verifying ordered exact concatenation and EOF, computing the SHA256 while comparing. Return digests/byte counts for opaque evidence rather than returning execution bytes that the only production caller immediately hashes. Preserve per-cell 64 MiB regular-file restrictions and derive aggregate ceiling from admitted cell count times per-cell ceiling, with runtime cumulative counts and stable-file checks. Bind concatenation order to the verified schedule. Predictions can retain their separate 64 MiB parser/scorer contract; do not turn streaming into unlimited input or silently relax prediction admission. Do not merely hash independently if the intended contract remains exact byte equality; incremental comparison supplies it directly.

- **warning — downstream reader contract, runner.exs:2582–2586, 2642–2654; measured_execution.exs:1112, 1400–1417; score.exs:161–202.** There is more than one bound. Finalization parses merged predictions, timings, request-resources, usage and resources using a 32 MiB whole-file reader and a 1 MiB per-row decoder. Measured audit materializes these through the 64 MiB merged reader, then splits/decodes whole streams with a 64 MiB per-row ceiling. Its resource-summary reader has a 64 MiB ceiling. Score retains 64 MiB total prediction bytes, 16,384 rows and 262,144 bytes per prediction row. Runner scoring_context also has 64 MiB predictions; review inputs have 32 MiB. Resources.summary returns storage snapshots and budget snapshots, so summary size grows with source evidence, rather than being a tiny fixed aggregate. Cell domain_files caps each file at 64 MiB and 4096 paths but hashes via File.read!, and append writers have no explicit stream cap. The reported ~4.4 MiB summary/resources and ~4.15 MiB predictions fit these bounds; these are future capacity mismatches, not another demonstrated failure of this saved run.

  **Suggestion:** explicitly document distinct contracts for opaque merge verification, parsed JSONL, prediction scoring, and JSON summaries. Do not remove the small parser/scorer limits incidentally. Preserve current accepted limits unless deliberately revised with boundary tests. A product repair should trace and test each stream consumer, including finalization, not advertise a blanket arbitrary-size guarantee after repairing execution alone.

- **critical if used as acceptance — Freeze.verify_v2!/2 at freeze.exs:325–334; MeasuredExecution.context!/2 at measured_execution.exs:605–644 and execution_context!/1 / validate_precompiled!/1; Runner.scoring_context/1 at runner.exs:452–478.** No existing authority path admits a patched independent auditor for the old run. V2 verifies exact source snapshot and current measured runtime; context additionally requires the frozen evaluator source location and hashes, and validates captured precompiled execution context. Review and score re-run this audit and compare its returned digest before references are loaded. A fixed source tree cannot honestly pass the old seal through the current CLI, and an external successful concatenation check alone does not satisfy its scoring gate. Natural stage/root exits establish useful process facts; they do not substitute for the remaining audit predicates.

  **Suggestion:** keep original seal, runtime identity, first outcomes, measure exit1 and audit exit1 permanently intact. A separately versioned, read-only re-audit is conceptually defensible but requires an explicit new admission contract; current code does not provide it. Record separately: auditor source/runtime/version and scope; original execution freeze/source/runtime hashes; immutable input inventory with byte lengths/digests and ordered cell identities; original failed command outcomes; full unchanged native/service/authority/budget/resource/prediction checks; capacity-policy delta and evidence that all noncapacity predicates are equivalent; independent review of that contract before labels; and deterministic new report hash. Verify the old captured bytes as evidence without pretending the new auditor ran as them. Extend review/score authority explicitly to this separately identified report and retain the original execution freeze in prediction/review binding; never reuse the old audit version/hash domain for a new rule set. Demonstrate no mutation, no native/model launch, no attempt-claim consumption, and no label path access. Keep label release blocked until the new authority and all checks are admitted. Whether this original run counts is a declared acceptance decision, separate from fixing the product. Do not retrospectively call its original commands passing.

## Regression proof required

1. Real Runner helper with synthetic complete six-stream cells: aggregate execution at 64 MiB−1, exactly 64 MiB, and above 64 MiB; individual cells within ceiling. Assert success and known digest/bytes above old bound. Include chunk boundaries crossing cells and empty cells.
2. Same-length mutation, truncation, appended suffix, reordered cells, nonregular/missing files, oversized individual cell, aggregate over admitted bound. Each refuses without writes; predictions retain first_predictions_changed versus other merged_stream_changed semantics.
3. Through measured audit, confirm merged hash map and final prediction/resource identities remain the same on small existing fixtures. Verify all parsed-stream/finalization limits independently and row bounds explicitly.
4. For any new re-audit authority: altered original source/runtime/native/domain/prediction/resource bytes refuse; wrong auditor version/hash refuses; stale review authority refuses before labels. Trace zero label reads and zero launches/claims with positive controls. Repeat audit must be deterministic and evidence bytes unchanged.

Verification performed: source call-chain inspection and existing measured merge test inspection (test/knowledge_evaluation_measured_test.exs:240–291 covers small exact merge, mutation, truncation, order; no capacity boundary). A cheap standalone Elixir reproduction was attempted but did not compile because of an expression-spacing typo; no successful runtime reproduction is claimed. The size failure itself follows directly from the literal guard and reported size. No real-data verification or test suite run.

## Review 3: ipse-p27-streaming-audit-repair-review-a.md

Original SHA-256 `7cfa886247619fb24b28a1dc2f0d24ecd8e865efe44e0b9f082545f9646d4d47`.

# Streaming audit repair review

Reviewed the full working-tree diff of runner.exs, measured_execution.exs and knowledge_evaluation_measured_test.exs against the original capacity failure. Applied the requested correctness, root-cause, structural, verification, complexity and traced-security lenses. No actionable correctness or security findings in this diff. Product repair is acceptable subject to the ongoing test run and documentation reconciliation. This is not acceptance of the captured failed run.

## Verified by source tracing

- The aggregate hashes and retained semantic inputs come from the same chunks that were literally compared to the aggregate descriptor. No unchecked aggregate reopen is introduced. Each part's incremental SHA-256 is checked against its already-audited domain inventory, so coherently changing both a cell and the aggregate after inventory audit cannot pass. The old implementation lacked this second binding.
- IO.binread requests at most min(remaining,65536). A short nonempty part read continues with the actual count; an early EOF/error fails. Aggregate short reads fail literal equality. At zero remaining, the part must be at EOF; after every part, the aggregate must also be at EOF. Initial stat sizes must match the inventoried sizes and their sum. Empty files correctly hash as empty binaries.
- Parts remain in audited stage order. audit_stage! now returns evidence plus the original domain files inventory only for cell stages. Preparation/finalization return nil for the latter. The only audit_stage! caller was migrated, and the only production audit_merged_files caller was migrated. Public evidence maps and report.merged_files retain their previous field shapes and values for the same inputs.
- The upper bound of fourteen is consistent with prepared!'s existing exact fourteen-cell check and the native descriptor construction. It is not an invented workload expansion. Supporting one through fourteen in the lower-level helper also permits small focused fixtures. Each part remains limited to64 MiB; raw aggregate capacity is consequently at most896 MiB. The sum-derived raw limit is redundant mathematically after the per-part checks, but clearly documents the resource contract.
- The five parsed streams stay bounded at32 MiB, matching finalization's existing bound now expressed through the shared constant. The execution stream is omitted from retained inputs and only hashed. Measured audit obtains predictions, timings, request-resources, usage and resources from those verified retained inputs. The64-MiB resource-summary JSON reader and scoring limits remain unchanged.
- Returning a tuple from audit_stage! is a small ownership change that avoids re-reading the domain inventory and does not introduce a new public report field or substitute new launch identities. No authority, seal, replay, receipt or label-release mechanism changes.

## Tests and remaining verification

The new64-MiB+1 fixture exercises the causal failure with two independently bounded cell parts, checks the aggregate digest, proves raw execution is omitted from retained inputs, and tests a same-length mutation in its final byte. Existing small fixtures now check each of the six streams against its inventory and reject coherent cell-plus-aggregate rewrites. The bounds test verifies both oversized individual raw parts and oversized semantic aggregates fail before reading their contents.

Additional boundary tests would improve coverage but are not blockers established by this review: exactly64 MiB, a nonempty part ending inside a chunk followed by another nonempty part, aggregate appended bytes, and zero/fifteen cell inputs. Current code handles these cases directly. Existing empty streams and the64-MiB+1 final part already exercise the zero-length and short-final-chunk branches.

I did not rerun tests concurrently with the parent agent's full measured test run. Verification performed here consists of the complete requested diff, call-site searches, and inspection of prepared-stage cardinality and downstream consumers. No private retained data, SSH, labels, inference, repository edits, or changes to the earlier review report.

## Scope caveat

This repairs future evaluator capacity. The finalizer still materializes stream concatenations, domain inventory auditing still materializes individual files, and semantic parsing retains bounded inputs. Those are existing bounded/allocation behaviors, not regressions caused by the streaming comparison. The original frozen evaluator continues to fail its original audit; this diff provides no independent re-audit admission path and must not be presented as one.

## Review 4: ipse-p27-streaming-audit-repair-review-b.md

Original SHA-256 `fc8acb33d227d10477f1dd1181e0070b5911728fdc55f47c33370091be42b187`.

# Independent repair review B

Reviewed full working-tree diff of runner.exs, measured_execution.exs and knowledge_evaluation_measured_test.exs, plus call sites, closed-domain inventory verification and schedule construction. Applied supplied correctness/root-cause/structural/verification/complexity/security rubric. Source only; no private data, SSH, repository edits or inference. No tests executed independently; parent-reported red/green and ongoing full-file run are not my verification.

## Verdict

No actionable correctness or security defect found in this product repair. The change resolves the writer/auditor aggregate mismatch without weakening ordered byte equality or introducing another large opaque buffer. It does not supply authority to re-audit the old frozen run, and does not claim to.

## Traced checks

- `audit_stage!` retains all prior domain/native/service/grid checks and calls `Runner.audit_cell` before returning the exact closed inventory (`domain["files"]`). The latter compares the full saved inventory against current domain files. Passing those recorded hashes to merge verification closes the coherent-cell-plus-merged-rewrite hole: equality between two changed files alone is insufficient; each read part must also match its previously audited digest.
- Merge streams are opened once for comparison. Parsed bytes and aggregate SHA256 derive from the same chunks that were compared. Measured audit consumes those returned bytes directly; it does not reopen merged parsed inputs. Execution is never added to the retained inputs map. Aggregate report field values remain the same hashes on unchanged small evidence; stage evidence maps retain their old fields.
- Recorded sizes enforce each cell file <=64 MiB, and summed sizes constrain raw execution to cell_count*64 MiB. Initial lstat sizes must match. Each part consumes its declared size, requires part EOF, and is hash checked. Final merged EOF rejects a suffix; early part EOF is rejected, early merged EOF cannot equal the expected chunk. Positive short part reads advance by actual byte count and eventually either complete or refuse, rather than skipping bytes. Empty files use the SHA256 empty digest and explicit EOF.
- Order comes from `stages`, built using the verified prepared schedule; tuple filtering preserves it. `prepared!` already requires exactly14 cells; prepare/finalize yield nil and only cells yield inventory. The public helper's1..14 bound supports small synthetic tests without loosening the real caller's14-cell invariant. Only production caller of `audit_merged_files/2` is migrated, and tests use its new return/argument contract.
- Parsed streams use32 MiB, matching the existing finalization reader rather than pretending to support arbitrary aggregate sizes. Prediction scorer64 MiB, per-row decoder and64 MiB summary limits remain separate. The product therefore supports larger opaque execution merges, not unlimited parsed evidence; this is an appropriate narrow scope.
- New tests cover64 MiB+1 with individually legal cell files, a final-byte corruption after many chunks, coherent cell/merged mutation with stale inventories, parsed/individual size refusal, and existing order/truncation checks. The closed-stream fixture hashes files incrementally.

## Nonblocking verification improvement

**nit — test/knowledge_evaluation_measured_test.exs, new boundary tests.** The new bounds test fabricates oversized metadata, which correctly proves early contract refusal but does not exercise a physical file growing/truncating against a retained inventory. Existing merged truncation and same-length mutation tests plus explicit EOF logic give good source confidence. If extending these tests, add an appended suffix and a truncated cell with unchanged inventory, and assert empty/15-cell rejection; keep these small instead of adding another large fixture. This is coverage hardening, not a demonstrated implementation failure or a reason to delay the repair.

Original-run disposition remains unchanged: the old seal/source/runtime and original exit1 outcomes must be preserved. This diff changes frozen evaluator source/BEAM identity and cannot be substituted into that old authority. An independently versioned retrospective audit still requires the separate admission contract described in the earlier report, before any label-release/review/scoring gate can accept it.

## Review 5: ipse-p27-context-contract-design-review-a.md

Original SHA-256 `3ab9522434ed76f1a2cdee7ec06ef53f6204c7ecd556a015d8d2b0531964e7a5`.

# Explicit context contract design review

Verdict: proceed with a versioned ModelService and portable experiment contract, with the constraints below. The repair belongs in evaluation service admission and Freeze policy binding. No core provider change is justified by the supplied evidence. The 223 failures at total 4096 tokens are consistent with the reported daemon context, but this source review does not independently establish the diagnosis on retained data.

## Actionable design findings

- **warning — dev/evaluation/model_service.exs:104-106,115,1049-1078,1206-1236,1259.** Version currently doubles as a device selector: v1 means CPU, every other branch means GPU, and saved evidence verification runs only for v2. Merely admitting v3 config will misclassify CPU, omit saved validation and emit v1 receipts. Decode config shape/version at the boundary, then use the existing device! result for device behavior. Extend saved verification explicitly to v2/v3, preserving v1 behavior. Emit receipt version from validated config. Use separate exact v3 device shapes, CPU with policy only and NVIDIA with existing policy plus UUID; reject irrelevant UUIDs and legacy cpu_policy on v3. A small context accessor or explicit v3 branch is sufficient; no generalized policy framework.

- **warning — dev/evaluation/model_service.exs:984-1013,1049-1078.** /api/show supplies capabilities, not observed effective context. Requiring context on every /api/ps row would reject embedding models incorrectly, while accepting any nonempty final resident list would allow embedding-only evidence to pass without demonstrating completion context. Pass validated capabilities into resident validation at both live inventory and saved-receipt validation. Every completion-capable resident must have a bounded positive integer context_length equal to the declared value. A model with both completion and embedding capabilities is completion-capable. Define the required relevant completion set explicitly; for this experiment it is the configured 9B text model. Require its presence after work. With multiple relevant text models, one resident completion model cannot prove the missing model's context. Do not infer relevance from a hard-coded model name. Embedding-only rows may expose a different positive context value; it must not be compared to text context. Record the observed field without pretending it is historical evidence. Initial inventory must stay empty.

- **warning — dev/evaluation/freeze.exs:48-60,85-90,405-409,459-482.** Portable policy currently binds only a device policy, deliberately excluding the local GPU UUID. Bind context_tokens and the CPU/NVIDIA policy in experiment v3; retain UUID, origin, filesystem paths and runtime files in local resolution. Preserve this separation. Compare both dimensions before artifact import, data access, output creation or execution claims, in declaration and resolution/freeze validation. Do not allow v3 experiments to resolve through a v1/v2 service just because device strings match. Conversely, avoid silently adding context semantics to old experiment v2 records. Keeping the local manifest version2 is reasonable because its shape already embeds experiment digest, resolution and launch recipe; its version is independent of experiment/config versions.

- **warning — dev/evaluation/freeze.exs:377-409; test/knowledge_evaluation_freeze_test.exs:207-232.** New long-answer declarations must reject absent selection and automatic-context service configs, but historical experiment v2 plus plan v3 must remain readable under its original semantics. Current tests explicitly declare long-answer plans without a resolution and expect experiment version2. Split creation admission from historical decoding. Updating the existing decoder to reject those old records would violate the proposed backward compatibility. Preserve a literal historical fixture and separately change the new-declaration test to expect refusal or supply explicit v3 context. Do not manufacture an exception that permits automatic context merely because a declaration is synthetic.

- **warning — Freeze plan/service compatibility validation; dev/evaluation/contract.exs:319-339,460-478.** The correct static guard is context_tokens greater than the maximum max_output_tokens across text profiles, not just p27_answer and not embedding profiles. Reject missing, zero, negative, noninteger and unreasonably large context values at service config validation. This proves only that some prompt space exists. It does not prove the largest real prompt plus generation fits. Do not call16384 universally sufficient from the8192 allowance alone; require the exposed real diagnostic and document observed prompt headroom, reasoning/final output behavior and effective /api/ps context before any new private freeze. Keep8192 output and600s SDK timeout unchanged.

## Minimal structure

Use config v3 because exact closed v1/v2 schemas and receipt evidence differ. Portable experiment v3 is likewise appropriate because its policy gains a required inference parameter; no new plan version is needed solely for daemon context. Keep both legacy config clauses intact and add one v3 clause whose device selector supports CPU and existing NVIDIA policy, then reuse device-based behavior. Put bounded context shape validation in ModelService and the profile/context compatibility guard in Freeze, which owns both inputs. Freeze should project portable policy from validated service selection rather than duplicate ModelService's device interpretation.

Construct OLLAMA_CONTEXT_LENGTH only for explicit-context configs and include it in the exact environment used to spawn the daemon and verify its saved receipt. Existing environment constructor only contributes a closed PATH/LANG/HOME/IPSE_HOME/TMPDIR map, so it need not gain a context override. Extend resident row projection only for v3 and invoke the same validation in live and saved evidence paths. Keep placement_history_proven false; a post-callback context observation does not establish every preceding request's context. /api/show model context metadata may be diagnostic but cannot replace the effective /api/ps check.

## Required focused verification

1. Preserve v1 CPU and v2 NVIDIA config, environment, receipt projection and historical experiment tests unchanged where their contracts are unchanged. New v3 CPU/NVIDIA exact-shape tests should reject invalid context and device/context mismatch.
2. Test context equal to the largest text output allowance fails, one greater passes the static guard, and a larger non-answer text profile controls the maximum. Missing selection for new extended-answer declarations must fail before artifact/data access.
3. Test v3 final inventory with the required completion model at16384 and an embedding-only model at2048 passes; completion at4096, missing context, absent required completion, duplicate rows, bad digest and coherent saved environment/context edits fail. Initial nonempty inventory still fails. Test both live admission and offline receipt verification.
4. dev/fixtures/model_service.exs:463 currently emits resident rows only in GPU mode, with no context_length; the default CPU fixture has an empty /api/ps result. Add an explicit-context fixture mode that emits CPU resident evidence as well, deriving its observed context from the staged environment. Keep old fixture behavior for legacy versions. The Rust probe already accepts supplied resident evidence, so prefer extending its fixture inputs over rewriting that probe.
5. A real exposed diagnostic is required separately from synthetic proofs. Its clean source/runtime must be frozen anew; no original seal, original outcomes or labels are changed. Retain the supplied original failure statistics as historical evidence only.

Verification here: source inspection of ModelService config, inventory, environment and saved receipt paths; Freeze declaration/decoding/resolution; long-answer profile contract; service and freeze tests; Elixir synthetic daemon and Rust probe. No tests, network calls, private data access, SSH, new inference or repository edits. Official Ollama behavior is supplied evidence for this review, not independently re-fetched documentation.

## Review 6: ipse-p27-context-contract-design-review-b.md

Original SHA-256 `196b1e9d858619a92369fa5a79fdaf164ba97ba5db0e5601259e83852ed086c6`.

# Explicit context contract: independent design review B

Verdict: approve the narrow direction with the admission details below made explicit. Source inspected: ModelService validation/environment/inventory/resident/receipt paths, Freeze declaration/resolution decoding, Contract long-answer profiles, and model-service fixtures/tests. No repository edits, inference, private data, SSH, or independent verification of supplied daemon statistics. No tests executed.

## Actionable design findings

- **warning — ModelService.resident_rows!/3 and verify_receipt/4 (model_service.exs:1049,115).** Existing v2 admission means GPU policy, requires positive VRAM for every resident and only requires a nonempty final list. A naive `version >= 2` extension would accidentally forbid v3 CPU; preserving only nonempty final inventory could admit an embedding-only final list without any context proof. Make placement depend on normalized selected device, and context depend on v3 plus completion capability. Require final resident evidence for the relevant selected completion model(s), not merely some resident row. Identify those models using the captured show capabilities joined by validated name/digest; a dual-capability model is completion-capable. Check integer bounded context_length and exact equality to configured context_tokens for those rows. Embedding-only rows need no equality to the completion context. Both live inventory and offline receipt verification must run the same checks using that inventory's validated model rows, rather than re-querying a daemon. Keep initial residency strictly empty. Final evidence proves final observation only, not all previous requests.

- **warning — Freeze.declare/4, decode_experiment!/1 and require_device!/2 (freeze.exs:43,403,478).** New-context admission must not silently alter old experiment-v2 interpretation or the old strict config/receipt shapes. V3 is justified: it introduces a required environment field and observed-evidence predicate, beyond optional metadata. Retain old decoders verbatim; version the service config/receipt and portable experiment, but retain execution manifest v2 and plan v3 where their own formats have not changed. New experiment-v3 policy must explicitly contain context_tokens plus portable device policy; local GPU UUID stays in local service resolution, not portable policy. Require exact service/policy context equality as well as device equality during create/resolve/verify, before any dataset access or attempt claim. Reject mixing a v3 experiment with automatic-context v1/v2 service. Preserve reading old v2 experiments containing long-answer plans so their immutable outcomes can still be diagnosed; gate *new declarations* of extended-answer plans to explicit-context v3. Do not enforce the new policy retroactively in Contract's historical plan parser or Freeze's historical decoder. Clarify declare-without-resolution: long-answer declarations must refuse rather than silently default CPU/automatic context.

- **warning — static context sufficiency guard, Freeze plan/service binding.** context_tokens > max(profile.max_output_tokens) over all text profiles is a sound necessary guard and catches the reported4096-vs8192 contradiction. It is not proof that the prompt plus full generation allowance fits. State this limit precisely;16384 leaves8192 tokens nominally for prompt, but byte-bound prompts and chat templates do not establish a token bound. Keep the guard at the Freeze boundary where both plan and service selection exist, not in ModelService's standalone config validator (which has no profile knowledge). Require bounded positive integer context_tokens in ModelService. Refuse equality as well as smaller context. A fresh exposed diagnostic must confirm actual API/daemon configuration and exercise the selected answer workload before private freeze; final /api/ps is additional evidence, not a substitute for that preflight. Do not change generation allowance or SDK timeout to hide context failures.

## Smallest sound implementation

Keep device! as the canonical normalized CPU/NVIDIA selection, adding one strict v3 config clause with context_tokens and device_selection; CPU selection contains policy only, NVIDIA retains policy+UUID. Avoid duplicating the staging or daemon lifecycle. Generate OLLAMA_CONTEXT_LENGTH only for v3 in the existing sanitized environment map, using exact integer formatting, and bind it through the existing configuration digest and receipt environment equality. Audit every existing `version === 1/2` branch: device_policy, environment, inventory history flag, resident projection, final nonempty policy, receipt construction and offline verifier. CPU/GPU behavior must follow device; presence of context evidence must follow schema version. Do not introduce a global history flag that implies continuous context observation.

Extend the existing inventory helper to pass validated model capability rows to resident validation. Retain context_length in v3 resident receipt rows so offline verification can actually verify it; do not discard it with Map.take before validation. Reuse that path for live and saved evidence. No core provider change appears necessary for the proposed global daemon context mechanism; completion requests already have independently bounded generation allowance.

Freeze needs a small canonical service-policy projection that returns device and, for v3, context_tokens, used by declaration and resolution equality. Prefer that over adding parallel independent device/context policy paths. Keep semantic schema validation explicit for historicalv2 vs newv3. Existing manifest source/runtime hashing then naturally binds a fresh implementation; no captured runtime patching is needed or allowed.

## Focused verification requirements

1. Config/env: v1 CPU and v2 NVIDIA exact historical shapes/receipts unchanged; v3 CPU/NVIDIA valid, invalid/missing/float/zero/oversized context refused, malformed device refused, ambient context cannot override declared value.
2. Receipt: missing/string/float/wrong completion context refuses; embedding context can differ; dual-capability models require completion context; embedding-only final residency cannot stand in for selected completion evidence; changed receipt version/environment/config digest refuses; initial resident list stays empty.
3. Freeze: context equal/below maximum text output refused, above accepted; mismatched policy/resolution refused before data reads and claims; missing resolution/automatic context refuses new long-answer declaration. Historical experimentv2 fixture decoding remains successful and does not acquire a new completion predicate.
4. Synthetic fixture: add opt-in context reporting/config expectations for v3; retain defaults for v1/v2. Current fixture /api/ps rows contain size/VRAM but no context, so globally requiring context breaks unrelated historical fixtures. Exercise both CPU and mixed policies, and same validator through live synthetic run plus offline receipt audit.
5. Exposed real diagnostic separately establishes the new daemon context and selected model behavior; synthetic proofs do not prove model success or available memory. All private labels remain sealed. Old4096-context runs remain original first outcomes and are not replayed/relabelled as context-correct.

The supplied failure pattern is strongly consistent with context exhaustion; this review has not independently inspected the logs and does not prove that every model_request_failed has that cause. Configuration repair should be accepted on its contract and exposed diagnostic evidence, not by retrospectively changing old outcomes.

## Review 7: ipse-p27-context-contract-implementation-review-a.md

Original SHA-256 `dba28f4e5e49752f7b23b1be196c61bcbefdb0fa3a736bb1c080697481967386`.

# Explicit context implementation review

Verdict: one actionable warning blocks completion of the caller migration. No additional correctness or security defect found in the new context admission and saved evidence logic. Source-only review; no tests or inference run independently.

## Finding

**warning — test/knowledge_measured_model_fixture_test.exs:21 and test/verification_test.exs:1063, caused by dev/fixtures/model_service.exs:9.** The fixture configuration signature changed to options keywords, but two test callers still use the old interface. The Linux terminal-exit cleanup test passes :exit_on_answer as the fourth argument; configuration now asserts Keyword.keyword?(options), so that test fails before testing ownership/cleanup. The generated closure-verification expression calls configuration/5 with nil and the verification boolean; only arities3/4 now exist, so it raises UndefinedFunctionError rather than exercising captured-fixture integrity. The migrated measured_knowledge caller was not the sole caller. Migrate these to fault: :exit_on_answer and verification: <existing boolean>, respectively, and run the affected tests/proofs. Do not retain an unused compatibility overload. These failures are established directly by source call shape; the supplied41 focused passing tests did not cover them.

## Checked implementation

- Config v3 accepts exact CPU/NVIDIA device shapes and bounded integer context1..1048576. Historical v1/v2 exact config schemas remain intact. device_policy derives from device!, not the version, and v3 receipts are emitted as3 and independently checked against config3.
- OLLAMA_CONTEXT_LENGTH is emitted only for v3 and added after the closed environment constructor values. Saved evidence must contain the exact selected environment and started.json configuration digest. Native fixture asserts its presence/value for explicit-context cases and absence for legacy cases.
- Completion classification uses captured capabilities. All configured completion-capable models must be resident after callback with exact declared context; every observed v3 context is bounded positive. Embedding-only contexts may differ. Duplicate, unknown-name, digest and placement checks remain. CPU requires zero VRAM, NVIDIA requires positive observed VRAM as before. No claim of continuous context or placement history is added.
- Both live and saved v3 paths require equal before/after model metadata, preventing a post-work capabilities change from dropping the completion requirement. Shared resident validation projects the exact saved fields and rejects extras through saved-row equality. An embedding-only standalone config has a vacuous completion set, consistent with its lack of completion models; measured 9B admission still requires its model capabilities.
- Freeze emits experiment3 when explicit context is selected; its portable policy binds context and device policy without UUID/host paths. Resolution must match both. Static context guard examines every text profile's max_output_tokens. Legacy experiment2 remains readable without context, while new long-answer declarations without explicit context fail. Local manifest structure remains version2 and retains experiment/runtime/source identity checks.
- Positive synthetic measured runs select16k context for long answers on CPU/GPU. The daemon tracks actual requested resident fixture models and reports2048 for embedding, configured context for text. Native verification adds five cases and updates its aggregate case count to31. Existing failure-path control, cleanup and request behavior are retained.
- The previously reviewed streaming audit diff remains consistent: aggregate identities bind literal compared bytes and audited per-cell hashes; raw execution is not retained; parsed streams remain32 MiB. No new authority or old-seal admission path was introduced.

## Verification boundaries

Reviewed the full requested evaluation/fixture/verification diffs, affected test diffs, and searched all repository fixture configuration calls, including aliases and generated expressions. No private evaluation files, remote hosts, labels, new inference, child agents or repository edits. The41-test result is supplied by the parent, not a test run performed here. Linux source/installed proofs remain necessary for the new native cases and affected cleanup test. A real exposed diagnostic remains separate from synthetic proof and is required before claiming16384 fits the full workload prompt plus output. This implementation neither changes the old sealed run's failure status nor authorizes labels.

## Review 8: ipse-p27-context-contract-implementation-review-b.md

Original SHA-256 `d912fd76825c6c6ddcd0f1a703eba0b284a85ecdeeee4ff237a4d62db069fd7b`.

# Context contract implementation review B

Verdict: **no actionable findings** in the inspected implementation. Source-only review of the full diffs for the four evaluation modules, both model-service fixtures, three verification modules and affected knowledge-evaluation tests, applying the requested correctness, root-cause, structural, complexity, verification and traced-security lenses. Earlier reports preserved. No repository edits, private inputs, SSH, inference, child agents or independent test runs. The supplied41 passing focused tests are parent-reported evidence, not a run performed by this reviewer.

## Admission and evidence traced

- ModelService.device!/1 now accepts a strict configv3 shape with context_tokens bounded to positive integer1..1048576 and CPU or existing NVIDIA selection. The old v1/v2 clauses retain their exact shapes. device_policy and resident placement checks follow the normalized device, so v3 CPU is not accidentally subjected to GPU admission. No profile generation allowance, reasoning setting or core provider behavior changed.
- environment/3 puts OLLAMA_CONTEXT_LENGTH into the existing sanitized environment only for v3. The constructor must still return its exact allowed key set, so cannot override this field. Context is formatted from the validated integer. Native fixture explicitly asserts the expected value and its absence for legacy modes.
- Live inventory validates show capability rows before deriving completion names. A dual-capability model is included by the `completion` membership test; embedding-only models are exempt from declared-context equality. V3 resident rows retain bounded positive context_length, and all completion models must appear after work with exact context. Empty/embedding-only final lists cannot substitute for selected completion evidence. Initial residency remains empty. CPU size_vram must be zero; mixed placement retains the old positive-VRAM rule.
- Live before/after metadata must match for v3. Offline verify_receipt independently checks both validated inventories, recomputes resident projections and compares them exactly to the saved rows, checks metadata equality, binds exact receipt version/environment and started configuration digest. Consequently missing/extra resident fields, changed context and capability drift refuse. The measured auditor still verifies receipt-file hash and decoded equality to the cell outcome before invoking this read-only verifier; no daemon contact or execution authority is added to that path.
- Freeze.declare refuses new long-answer declarations without context, checks strict greater-than output capacity over every text profile, and emits experimentv3 only for explicit context. decode_experiment accepts the exact old policy for v2 and the exact extended policy for v3, with independent bounded context validation. Historical v2 long-answer plans remain readable through the nil-context path. require_service_policy is used in create and resolve (and consequently verification), binds both portable context and device to the local service before dataset reads or execution claims, and rejects mixing an explicit-context service into an automatic-context historical policy. GPU UUID stays local. Execution manifest remains v2, avoiding unrelated format churn.
- The context guard is only a necessary bound. No code claims to establish tokenized prompt fit or continuous request history. Final observed context is not evidence that every prior request used that context; the preflight exposed diagnostic remains necessary before private acceptance.

## Fixture and consumer migration

- The changed ModelService fixture configuration function has one source caller, migrated to keyword options. Long-answer synthetic measured comparisons request16384 context while retaining the CPU/GPU choice; legacy fixture defaults do not gain context requirements. The daemon validates the selected environment, records resident models only after synthetic work and reports a deliberately smaller embedding window, exercising the intended capability distinction.
- Native verification adds context CPU/GPU positives plus wrong/missing/empty negatives; the31-case outer count matches the expanded list. The probe's context mode names and CPU/GPU selection match the configuration branches. These are synthetic contract checks, not real model/memory proofs.
- The streaming diff remains the reviewed implementation: closed-domain inventories flow through audit_stage tuples, hashes bind exactly compared bytes, parsed inputs are returned without reopening, and execution bytes are not retained. No missed production consumer or changed report field was found.

## Verification limits

The changed tests cover service shape/bounds, saved CPU/GPU context evidence and embedding exception, wrong/missing/float context, environment substitution, portable policy/context equality, necessary capacity guard, historical resolution, streaming regression and coherent rewriting refusal. I did not execute them. Linux native/source/installed verification remains outstanding as stated by the parent; macOS focused tests cannot establish those paths. No original seal is modified or admitted under the new source, and this product change does not authorize label release, retrospective passing status or replay.

## Review 9: ipse-p27-context-manual-review-a.md

Original SHA-256 `2f6e692ab69f62f6714766fdb5787228ccbfbd5c4df24e532a9ca00e0223e778`.

# Context and streaming manual review

Findings: none. No actionable critical, warning or nit findings in the reviewed documentation snapshot.

Reviewed the complete developer evaluation chapter, operator configuration and troubleshooting chapters, current plan, new private-comparison archive index and preserved previous plan, and archive policy/navigation. Compared the changed contracts with Freeze, ModelService, Runner and MeasuredExecution and the previously reviewed fixture/verification implementation.

The manuals distinguish service/experiment v3 from execution seal v2 and preserve historical automatic-context reads. The worked resolution selects explicit CPU context and changes only device selection for the GPU alternative. The necessary context/output guard is not represented as proof of prompt fit; exposed validation remains required. Completion capability, embedding context, final snapshot limits and lack of placement/context history are described consistently with implementation.

The streaming description preserves ordered exact-byte comparison, cell inventory hashes, individual64-MiB bounds, raw aggregate capacity, and32-MiB parsed-input limits. Runtime capture, separate read-only audit, no replay and label-release authority remain explicit. The private run remains failed despite natural native closure and retained predictions. Neither the new reader nor context policy is presented as authorization to reinterpret that run.

Compared the condensed P27 acceptance against its preserved predecessor. Independent optional packages/profiles, lifecycle and stale evidence, bounded operations, approval/accounting/cleanup/no replay, unchanged SDK authority, independently authored held-out work, all seven strategies and350 first outcomes, independent judgments and literal checks, individual90%/95% qualification, matched resource/latency/storage evidence, engine justification and whole-codebase/manual/platform review remain represented. Historical increment chronology is retained in the archive rather than appended to procedures.

Independent local verification performed: extracted the original P27 section from git object e402be6:docs/plan.md and computed SHA-256660129bd3a28b77154b49d64076fbc3702149056df2103020b1dc430c1d3a86c, matching the archive header. Reversed the documented archive/developer relative-link rebasing and compared the entire archived section with the original: exact equality. This confirms the previous plan's historical body was preserved.

No independent runtime tests, inference, private-data inspection, SSH, link sweep or code-block execution performed. The parent-supplied focused/floor/CLI/link results were treated as supplied evidence only. Pending full/native/installed verification and exposed-diagnostic cleanup are not claimed complete here. No repository edits; only this report was written.

## Review 10: ipse-p27-context-manual-review-b.md

Original SHA-256 `9d8719da82232a50df20c56c4dbbefca2a8909ab4366717d8ecc807b6aa79b85`.

# Context/streaming manual review B

Read-only review of the complete current evaluation chapter, operator configuration/troubleshooting, development plan, retained private-comparison record and previous-plan snapshot, with archive policy/index. Compared changed guidance with the previously reviewed implementation and current Contract/Freeze checks. No private data, remote access, inference, repository edits or children. No independently executed test, CLI, link or live diagnostic verification is claimed; supplied passing checks remain parent evidence.

## Findings

### warning — docs/developer/knowledge-evaluation.md:662–669 (and exposed tuning procedure:480–517)

**Finding:** the new mandatory exposed-context preflight has no runnable procedure using the policy the reader is required to verify. The chapter tells the reader to test exact model/reasoning/output/context settings before sealing private data, then moves directly to declaration/sealing. Its only exposed tuning recipe selects a version-one tuning plan and an already-running daemon. That route cannot exercise the extended-answer policy: Contract.long_answers?/1 requires plan3 plus json_schema_v3, and Contract.validate rejects model_call_timeout_ms on other plans. Merely following the nearby tune command therefore cannot verify the600-second/8192-output explicit-context answer policy. The synthetic selection explicitly establishes no real prompt fit.

**Suggested fix:** add a short worked exposed diagnostic procedure, or link an existing current runnable procedure, that uses the selected servicev3 configuration and the actual version-three answer request/profile. Show prerequisites, fresh output, one bounded exposed request, how to inspect actual final context_length and decode/accounting result, and the cleanup condition required before private freezing. Keep it a small component diagnostic; no need for a generic framework or extra acceptance workload. Do not substitute the ongoing diagnostic's partial success for a reusable procedure or claim cleanup before verified.

### warning — docs/plan.md:364–391

**Finding:** the replacement P27 acceptance list omits the old explicit zero-failure safety criterion. The retained previous-plan table required `zero authority/isolation/replay/resurrection failures`. Current prose preserves several related behaviors and explicitly bans replay, but never states the isolation criterion or the zero-failure completion gate. Moving the old text into a historical snapshot makes that snapshot unsuitable as the authority for a still-required current gate. This is a scope loss in an otherwise substantial consolidation, rather than a request to restore historical status paragraphs.

**Suggested fix:** add one sentence/bullet to current acceptance: require zero authority, isolation, replay and resurrection failures in applicable deterministic/source/native/installed controls, preserving declared platform limits. Keep original failures in evidence and require corrected-source verification; do not imply every historical attempt must have passed or expand scope into unclaimed sandbox guarantees.

## Other reviewed boundaries

No additional actionable issue found in the changed version distinctions,64KiB exact streaming contract,64MiB individual/14-cell opaque bounds,32MiB parsed bounds, context-vs-output necessary guard, embedding exception, legacy history, source/captured-runtime authority, or privacy/label-release instructions. The new archive marks provenance and historical status, links replacements and preserves old first outcomes/failing public commands without claiming retrospective admission. The plan keeps350 outcomes, per-strategy90%/95%, complete audit before labels, independent review, exact charged-memory subjects, engine selection and final manual integration open. No current manual claims that the old seal can acquire the repaired evaluator or that the pending exposed diagnostic establishes private quality.

## Review 11: ipse-p27-context-manual-review-b-followup.md

Original SHA-256 `784956f6a5f323ad95daa630ac85785e0698c6bdf139baec77f740c292db5855`.

# Manual corrections follow-up B

**No actionable findings in the two corrections.** Source-only follow-up; no execution of the new snippet, inference, private inputs, remote access or repository edits. Parent's synthetic execution of the exact snippet is still pending and is not claimed here.

- docs/plan.md now explicitly requires zero authority/isolation/replay/resurrection failures on applicable corrected-source controls while preserving historical failures and platform limits. This closes the acceptance-scope finding without rewriting older verdicts.
- The new exposed-answer section supplies a fresh-output driver selecting servicev3, the actual p27_answer profile, Answer.prepare/5 with json_schema_v3, exact artifact/request/execution/destination approval, one-request budget, public evaluation Session invocation, first-result preservation, accounting, decode and separate Session/service cleanup evidence. It has a concrete run command and expected observations, and distinguishes a small route check from representative prompt-fit verification and semantic quality.

API tracing: Session.open's required map fields and artifact shape match; ModelCall.prepare and delegated_approval checks match the host contract; the validator returns exactly the tuple Session.validate_approval expects. Approval executes in the evaluation caller's wait loop, so the closure can read that caller's Process context set after Session.open. The returned `next` run is retained before later assertions, and the after block closes that latest state. Session.snapshot's accounting key and the nested helper response text match existing Runner usage. ModelService.verify_receipt checks servicev3 success, exact configured environment, observed completion context and cleanup after callback closure. Prepared/citation shapes match Answer validation. A callback decode/assertion failure remains a failed service work outcome rather than printing a passing summary.

The snippet contacts the explicitly selected real service runtime and intentionally creates exposed local diagnostic artifacts only. It does not load private dataset paths from the resolution, consume a measured seal, replace captured modules, release references or claim a quality pass. Supporting exact-snippet synthetic execution and terminal real diagnostic cleanup remain separate verification evidence.
