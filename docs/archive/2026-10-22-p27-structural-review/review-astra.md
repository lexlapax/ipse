Historical review, 2026-10-22. Read-only assessment of the uncommitted candidate
against `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb`, before the recorded repairs.
Reviewer model: `gpt-6-astra`. Original report SHA-256: `f9b37efa3fb235eb4492d432599581e1646faf4c252705928b22ba5665b92ef0`.
The report body below is retained unchanged; line numbers identify that reviewed view.
Use [current training](../../developer/index.md) and [the disposition record](index.md)
for current ownership and acceptance limits.

# Independent consolidation review

Reviewed the uncommitted candidate against HEAD `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` in `/Users/spuri/projects/lexlapax/ipse`. This was a read-only source review, including untracked source/test/tooling files. The only written file is this report.

## Findings

1. **warning** — `/Users/spuri/projects/lexlapax/ipse/docs/developer/architecture.md:124-125` overstates batch validation before effects.

   The new tool walkthrough says to validate the whole response's arguments, workspace policy, and applicable nested guidance before executing any proposed call. The implementation guarantees batch call-identity and aggregate resource admission; argument decoding and workspace guidance are checked sequentially for the current call. This matters to the contributor learning the effect boundary: a later malformed call does not prove that earlier effects in the same response were prevented.

   Causal path: `Session.Turn.model_completed/3` calls `Tools.admit_calls/2`. In `/Users/spuri/projects/lexlapax/ipse/lib/ipse/tools.ex:398-425`, that checks response/turn counts, argument-byte totals, IDs, and the function container shape. It does not decode arguments or inspect paths. `/Users/spuri/projects/lexlapax/ipse/lib/ipse/session/turn.ex:507-525` takes only `hd(s.calls)`, decodes that call, and performs its nested-context preflight. `accept_tool_result/3` at lines 789-792 appends the completed result before dropping the head and starting the next call. Therefore a response containing a valid approved first write and malformed second arguments can complete the first write before rejecting the second call.

   Evidence classification: source-supported finding with a bounded admission check, not a complete mutation reproduction. Calling `Tools.admit_calls/2` in the existing development BEAM with two valid distinct IDs, a valid first write argument string, and `"{"` as the second write argument string returned `{:ok, %{calls: 2, argument_bytes: 33}}`. No filesystem effect was attempted.

   Smallest correction: describe whole-response identity/count/byte admission first, followed by per-call argument, workspace/guidance, approval, and durable-intent checks. Preserve runtime behavior. Do not introduce batch transaction semantics to match the current sentence.

No concrete runtime correctness, security, cancellation, journal, or source-identity regression was established in the reviewed paths. I have no additional actionable structural finding at sufficient confidence. This is not an approval of unexecuted platform or package checks.

## Checks and coverage

- Read the standalone brief, shared review rubrics, and consolidation maps/progress for orientation. Inspected actual candidate files and HEAD versions rather than treating the progress notes as verification.
- Inspected tracked changes and untracked source/test/tooling inventories. Used AST-based comparison across all old host sources and all current host plus bundled sources to focus manual tracing on changed bodies. The initial scan saw 3,292 old and 3,324 current `def`/`defp` clauses. This is a review aid, not behavioral equivalence proof: normalization deliberately ignored module qualification and later internal-call spelling, so namespace correctness was also inspected directly.
- Traced Session callback admission into synchronous Turn/Invocation transitions; tool sequencing; invocation action/inference/output admission; task scopes and separately tracked file effects; lock/writer calls; source identity; provider stream framing and adapter call sites; merged auth/HTTP behavior; MCP discovery/dispatch/cleanup; extension bootstrap and host identity inventory.
- Inspected moved developer command paths, verification/evaluation compiler inventories, package/launcher resources, CI references, and current example references. The four shell entrypoints and `bin/ipse` retain executable mode `0755`.
- Compared literal `test` declarations over all prior and current test files. All 1,426 previous literal names remain; the current tree has 1,427, adding the host-identity inventory case. This does not prove every assertion/setup/tag stayed equivalent, nor count generated test declarations.
- `git diff --check` passed.
- Ran the pure two-call admission check described above. No suites, builds, dependency downloads, new artifacts, or full runtime workflows were run.
- Read the current documentation indexes and the architecture, usage, and testing chapters, with targeted cross-checks of other changed documentation. Historical navigation/provenance changes were sampled; this review does not certify every rewritten chapter, fenced example, archived body, hash, or heading.

## Limits

The final corrected-source full baseline, native platform controls, packaging, independent installed-runtime proofs, and clean compilation remain the parent's verification responsibility. I did not rerun the supplied earlier test results. This review does not establish Linux/Arch or macOS enforcement, browser authorization, real account/provider behavior, paid inference, model quality, or frozen-comparison compatibility.

No private held-out inputs, questions, answers, prediction/journal/evidence content, account files, credentials, remote host state, or other chats were accessed. No subagents were created, and no source fixes were applied.
