# P27 paused continuation, 2026-10-19

Saved at the user's request before assessment of newly reported external P26
findings. **P27 is incomplete and paused.** This is a dated handoff, not a user
manual or completion verdict. Read [AGENTS.md](../../../AGENTS.md), this file and
the [P27 acceptance criteria](../../plan.md#p27-optional-research-graph-and-rag)
before resuming. Reinspect the actual branch, worktree, processes and CI state.
Current procedures are in [Corpus](../../operator/corpus.md),
[Graph](../../operator/graph.md), [Research](../2026-10-22-before-structural-consolidation/docs/operator/research-extensions.md)
and [evaluation training](../../developer/knowledge-evaluation.md).

## Source, pause and P26 review

Implementation was clean on `main` and pushed to `origin` at
`8183920ebdce0d8fcc03abdcb8f41d57849163cb` before this documentation handoff.
No implementation changed during the frozen experiment. The handoff commit
changes documentation only.

The user reports P26 gaps found by an external agent. The findings have not been
supplied in this chat or assessed. Previous P26 closure is not a verdict on that
new review. The review target supplied was
`10b9dd66d06ef28718b58530a7e5b01c7c50397a`; runtime cleanup repair was
`fb4627e5722f29d9bb62f1f51e781f9087d9be18`, initial memory implementation
`108aa8632b4a6e6dde8441f73a19727224280963`. Obtain the findings before resuming
P27. Reproduce accepted defects and refresh affected P27 evidence after changes
to shared Session, State, approval, journal, worker or cleanup contracts.

The only local P27 operation was comparison handle `97435`. Its exact process
identity was verified before SIGTERM at the user's pause request. The tool
returned exit 0, but **no `finalized.json` exists**. Evaluation and extension
worker VMs stopped. The editor language service and Ollama were left alone.
Historical process IDs and tool handles are not authority for later termination.

No Session cleanup acknowledgment was obtained for the interrupted Session.
Process death is not confirmation. Inspect its saved journal/ledger and preserve
uncertain effects and reservations; never replay that work automatically.

## Durable private evidence

Original files remain under `/tmp/ipse-p27`. A verified local copy is saved at:

```text
.ipse/continuations/p27-2026-10-19-pause/
  private-manifest.json
  pause-receipt.json
  frozen-file-map.json
  frozen-files/
  final-comparison-e63cc06de5b9/
  heldout/
  task-state/
```

This directory is already ignored by Git and **is not pushed**. It holds private
predictions, journals, sealed dataset members, task records and compiled files.
Never commit or publish those payloads. New directories are owner-only, regular
files are mode 0600, and symlinks were preserved without following them. No model
weights were copied.

The private manifest covers 3,962 entries and 225,222,168 regular-file bytes.
Its SHA-256 is
`41ea57b8f5a032c709e61a7692a8e9f8611700067db8eb73fe3139b86885b855`.
The separately written `pause-receipt.json` is outside that manifest. The frozen
file map preserves 2,107 verified source/runtime references in content-addressed
blobs. Verify the manifest and listed file hashes before relying on the copy.

Plans and freezes retain their original absolute paths. If `/tmp` is cleared,
inspect destinations before restoring necessary files to those paths. Do not
overwrite user files, automatically restore global toolchain files, rewrite
frozen identities, or claim a changed checkout/runtime is the old experiment.

Important files in `task-state/`:

- `requirements.tsv`: P27-01..14, required evidence and open acceptance.
- `decisions.tsv`: decisions, reasons, evidence and results.
- `quality-execution-brief.md` and `quality-preregistration.md`: full comparison
  contract, budgets, resource policy and unchanged quality gates.
- `post-first-run-repair-plan.md`: confirmed defects and investigation order.
- `current-live-comparison.md`: detailed history; its older live claims are now
  superseded by this pause record. The older `current.md` is also stale.
- `comparison-progress.exs`, `audit-comparison-storage.exs` and
  `audit-comparison-accounting.exs`: content-free metadata audits, with original
  absolute paths. Inspect before running restored copies.
- `first-storage-live-audit.json` and `first-accounting-live-audit.json`: final
  partial-run audits of 11 lifecycle cases and 11 closed sessions.

`finalize-first-comparison.exs` was prepared for a completed 350-row run and never
executed. It is inapplicable to this interrupted 280-row output. Do not weaken its
guard or manufacture rows to make it run. Review/scoring was not performed.

## Interrupted actual comparison

Root: `/tmp/ipse-p27/final-comparison-e63cc06de5b9`.

| Identity | Value |
| --- | --- |
| Source | `8183920ebdce0d8fcc03abdcb8f41d57849163cb` |
| Freeze file | `frozen-fixed-time/manifest.json` |
| Freeze SHA-256 | `87d7c3c0ae7209cb2b4f1439e4f06d842d2d2b4115a8313a249d4dc71611e49f` |
| Execution contract SHA-256 | `917a60a14ea7592118e0cb652fe48da6ad489b4637525bb029846de0bf9cc61d` |
| Dataset manifest SHA-256 | `2759aebcd62f1d6368ce41dfd038ead0d4948f78ab5db4ba41ae92d7e9336063` |
| Explicit common snapshot | `1792377772000` milliseconds |
| Output | `heldout-fixed-time/` |
| Partial prediction SHA-256 | `5f0adcb046f1c05b6bd556ec13d034e261a3cf2093df79a0a47038c8d62c7c85` |

The original attempt failed with `manifest_time` before inference or predictions.
`as_of_ms: "manifest"` requires an explicit recognized as-of field; the dataset
has `frozen_at`. A metadata-only decision explicitly selected that timestamp
before semantic input exposure. Only this plan field changed; seed, profiles,
artifacts, thresholds and budgets stayed fixed. Both attempts are retained.

Execution used public Sessions, concurrency 1, warm repeats 0, top_k 10 and the
same answer policy across strategies. Models were already installed local
`embeddinggemma:latest` at 768 dimensions and `qwen3.5:9b`, selected through
`http://127.0.0.1:11434`. Recorded digests:

```text
embeddinggemma:latest 85462619ee721b466c5927d109d4cb765861907d5417b9109caebc4e614679f1
qwen3.5:9b           6488c96fa5faab64bb65cbd30d4289e20e6130ef535a93ef9a49f42eda893ea7
```

Text profiles select 4096 output tokens and explicit `reasoning_effort: "none"`.
Finite request/token budgets and their two-project allocations are in the plans.
No downloads, paid providers, fallback, individual prediction retries or budget
renewal occurred. Matching model metadata does not prove immutable weights.

| Variant | Saved | ok | partial | failed | refused |
| --- | ---: | ---: | ---: | ---: | ---: |
| lexical | 50 | 3 | 0 | 0 | 47 |
| graph_explicit | 50 | 2 | 0 | 0 | 48 |
| graph_model | 50 | 0 | 3 | 0 | 47 |
| dense | 50 | 16 | 0 | 4 | 30 |
| hybrid | 30 | 3 | 0 | 0 | 27 |
| rerank | 25 | 0 | 0 | 0 | 25 |
| research | 25 | 0 | 0 | 0 | 25 |
| Total | 280 | 24 | 3 | 4 | 249 |

All saved rows are first attempts. Seventy required rows were not produced.
Execution gaps include 188 `result_too_large`, 41 `host_failed`, 20 `denied` and
15 `invalid_model_output` records; these counts do not partition prediction rows.
`ok` means protocol completion, not verified semantic quality.

No expected answers or qrels were read manually. The predictor's isolated input
projection consumed query fields without labels. Complete-grid guards prevent
review/scoring of this partial output. There is no blind packet, semantic review,
finalized comparison or engine selection. Any corrected actual comparison is an
**exposed rerun**, never a fresh unseen holdout. Do not overwrite this output,
recreate its budget root, or silently restart the old command in a new directory.

## Evidence and verification limits

The final storage audit covers 11 of 14 lifecycle cases, including Research's
explicit not-applicable case. Saved inventory hashes match. Completed State cases
have suppressed roots, zero selected/draft/orphan pages after collection,
unchanged namespace slots, exact tombstone increments and an approved delete for
each collected page. This proves those storage observations, not semantic quality.

The final closed-session accounting audit covers 146 unique requests: 100
embeddings, 21 extraction calls and 25 answer calls. Canonical usage and resource
records match, with confirmed attribution/admission/dispatch/settlement. All report
known totals, local billing and unpriced cost. Embedding text-output counts remain
null/inapplicable. The interrupted Session is excluded and needs separate audit.

Local `a3007ee` baseline: 1152 passed, 17 Linux-only exclusions, seed 566544,
663.1 seconds. `8183920` review-preparation checks: 36 passed, seed 63858,
184.2 seconds. Build, format, strict compile, CI policy, credential-free demo and
235-document/2590-link checks passed at their recorded increments. None completes
the interrupted model comparison. Relevant records:
[selection independence](selection-independence.md),
[storage lifecycle](storage-lifecycle.md), [review preparation](review-preparation.md).

CI evidence:

- `250080e`, run 39269141923: both hosts green, all steps audited.
- `a3007ee`, run 39272939320: both hosts fail the suppressed seven-variant test
  at `knowledge_evaluation_runner_test.exs:92`, outer timeout 60000 ms. Linux was
  importing artifacts; macOS was awaiting a query. Log: `a300-hosted-failed.log`.
- `8183920`, run 39275849251, Linux job 118139817925: same timeout while awaiting
  a query; suite 816.2 seconds. Log: `818-linux-job.log`.
- Last macOS response for job 118139818159 reports completed/success, but detailed
  step 21 remains in progress and later steps pending. Complete step auditing is
  still required. Saved response: `818-macos-job-pause.json`. Intermittent GitHub
  502 responses are observation failures, not evidence of job termination.

Older `f5` append-timeout and `2cbb` MCP-discovery negatives remain unexplained.
Green reruns do not establish their cause. Never weaken deadlines, assertions,
cleanup checks or TLS to obtain a pass.

## Resume tasks

1. Assess the external P26 findings first. Keep P27 paused until the user resumes
   it. Revalidate repository state, private evidence and affected host contracts.
2. Inspect the interrupted Session's journal/ledger; preserve uncertain effects
   and reservations. Keep this partial experiment immutable.
3. Reproduce and repair the following with synthetic fixtures:
   - Runner omits `max_steps`; Session defaults to 30 admitted calls across both
     embedding and text. Dense completed 20 embedding plus 10 text requests, then
     refused 15 queries before dispatch. Use the existing finite operator setting
     for the declared workload, preserving defaults, SDK bounds and budgets.
   - Fusion keys full spans; rerank keys chunks. Twenty proposals had ten
     candidates but six to eight distinct IDs. Approval correctly denied them.
     Encode consistent identity without dropping evidence or reducing top_k.
   - Cited results exceed the 12000-byte ceiling. Reproduce assembled payloads and
     measure components. Design bounded public representation/paging/reference
     reads preserving candidates, quotes and provenance. No design is selected.
     Research must remain independent, with no silent ingestion or repeated
     inference merely to read result pages.
4. Diagnose integration-test phase durations and work amplification. Preserve all
   variants, suppression, accounting, lifecycle checks and existing deadlines.
   Separate independent fixture units only if that reflects the actual boundary;
   do not hide a slow operation.
5. Examine scoring's failure-kind distinction: failed empty answer-policy rows
   use `retrieval_only`, whose semantic verdict must remain unmeasured. This
   prevents false passes but cannot numerically count failed answers as zero in
   a complete support denominator. Reproduce before repair; keep intentional
   retrieval-only runs unmeasured. Record any metric-version change before a new
   experiment, preserving the original 90%/95% gates.
6. Run focused regressions and required source/native/installed/platform checks.
   Reconcile every P27-01..14 requirement, including update/expiry/import,
   suppression races, isolation, cancellation, denied/unavailable/malformed
   effects, uncertain settlement and zero idle replay. Narrow proofs do not close
   broader requirements.
7. Before another authorized model comparison, record a clean source/artifact/
   runtime/plan/profile/prompt/metric freeze, fresh installed-model metadata and
   explicit finite budgets. Label it an exposed new experiment. Never renew the
   old root or retry individual quality rows. Keep all seven strategies, 50
   queries, top_k 10, common answer policy and failed/partial rows.
8. Finalize/hash all first predictions before references. Prepare the concrete
   blind packet before requesting independent reviewer authorization. No new agent
   or external message is authorized. Root and generating Qwen cannot independently
   grade their own answers. Literal membership is separate from semantic support.
   Preserve 90% support/correct abstention, 95% semantic citation precision and
   zero authority/isolation/replay/resurrection failures.
9. Report Recall@5, nDCG@10, support, citation precision, paired deltas, clocks,
   sampled harness memory, storage lifecycle, canonical usage and known/unknown
   cost. Optional OS/model RSS remains unmeasured under the original policy.
   Select engines by measured utility/cost, not existence.
10. Review whole operator/developer manuals, verify examples/links, reconcile
    plan/archive and audit every original acceptance requirement. Commit and push
    verified focused changes under AGENTS.md. Do not close P27 early.
