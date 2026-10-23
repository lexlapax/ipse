# Final independent internal P27 adversarial audit

Role: read-only adversarial reviewer. Writable scope: none in the repository.
You may save your structured report under /tmp using your unique reviewer label.
Do not spawn children. Do not modify source, tests, archives, services, model
state, Git refs or another checkout. Do not run a full Mix suite concurrently
with other reviewers. Read-only inspection and small isolated causal probes are
allowed; use synthetic inputs and no network or paid/live-model inference.

Repository: /Users/spuri/projects/lexlapax/ipse
Exact target: 89151b6e049e1f7c8b2d396ea42f7c788e155955 on main.
Read AGENTS.md and verify target/clean state first.

## Intent

Ipse must complete P27 within its documented independently configurable optional
Research/Graph/Corpus scope while preserving host authority, provenance,
suppression, bounded IO, accounting, cancellation and inert recovery. The
reference choice must be supported by the immutable seven-strategy/350-outcome
comparison and its disclosed judging/placement limits. Current operator manuals
must give runnable usage with the measured minimal authority; developer manuals
must teach actual ownership and verification. Recent audit repairs must close
their causes without breaking legacy journals or weakening independent packages.

Challenge the implementation against that intent. This is whole-P27 review, not
just a review of the last diff. Do not reopen accepted scope choices merely
because you prefer another design. Identify concrete defects and evidence gaps.

## Source and requirements

Use docs/plan.md P27 acceptance criteria and current manuals as requirements.
Inspect lib/ipse host contracts, extensions/knowledge and associated tests/dev
evaluation/verification tooling. Trace the important end-to-end paths and their
failure boundaries. Read all affected operator/developer chapters as whole
documents when assessing reader flow and claims. Follow actual implementation
and callers; a passing test or verifier is evidence only for what it covers.

Recent changes: git diff a7f4982..89151b6, especially the focused last commit
git show 89151b6. Original review and dispositions:
- docs/archive/2026-10-23-p27-independent-review/index.md
- docs/archive/2026-10-23-p27-review-remediation/{index.md,verification.json}
- docs/archive/2026-10-23-p27-maintenance/{index.md,verification.json}
- docs/archive/2026-10-23-p27-final-review/{index.md,review.md,verification.json}
- docs/archive/2026-10-23-p27-heldout-comparison/
Read previous dispositions as claims to verify, not conclusions to preserve.

Recheck C1 legacy own-server redaction hash versus cross-server output redaction;
C2 canonical absent-v1/explicit-v2 headers and saved bindings; C3 post-redaction
private diagnostic refusal/unknown. Look for version switching, missing/malformed
fields, descriptor drift, partial effects, unknown recovery, and secret transport.
Review ordinary/extension MCP, skills' regular-file/owned preflight lifecycle,
late inference admission closure, SDK result envelopes, State/MCP store deletion
and capacity, extraction, chunk fusion, citations, import/export and as-of limits.

Challenge the new capability-preset inert tests for actual coverage and cleanup.
Challenge reference state-dense/no-reranker/top_k10 instructions, optional rerank
authority, raw owner independent:true flag and global-completeness dependence,
dated archive correction notes, mixed CPU/GPU placement and every verification
claim. Preserve original frozen evidence and judgments. No inference/rejudging,
dataset release, consumed seal replay, model downloads or host service changes.

The owner accepted versioned real-model evidence from 817ab84 plus final-code
checks, not a 350-answer rerun just for consolidation. The explicit owner grammar
resolution was approved, extends the registered method and changes no strategy's
qualification or hybrid score; all original records stay frozen. Exact RAM means
optional Linux cgroup workload-charged peak, including cache/kernel, not RSS/VRAM.
Single-run/order, partial 8GiB GPU residency, unknown tokens and local unpriced
cost remain limits. No stronger real-world quality or backend attestation claim.

## Verification scope

Fresh target sources have a clean macOS default suite: 1497 passed, 1 skipped,
36 excluded; Linux native-inclusive: 1550 passed, 19 excluded. Both package and
exact installed-package proofs and all 12 MCP checks in source/installed modes
passed. Both formatters 1.18.5/1.20.3 passed locally on OTP29; no local OTP27
runtime assertion. These are recorded claims to inspect. Exact-commit hosted run
40032500880 is in progress; do not call it green without reading its current state.

Recommended read-only checks: git status --short; git rev-parse HEAD;
git diff --check; inspect actual receipts and tested controls. Request bounded
tests from the root instead of launching full suites or mutating shared builds.
If a probe needs compilation, isolate its directory/source modules and report
the exact command, inputs and observed outcome. Do not lower timeouts or asserts.

## Report

Return a structured Findings list with severity critical/warning/nit, precise
file:line, reachable trigger, consequence, causal/source evidence and smallest
justified repair. Distinguish reproduced observations from source-only concerns.
Include an acceptance/coverage matrix with PASS/FAIL/UNPROVED/accepted-limit for
the plan criteria, and checks you personally ran versus receipts you inspected.
Say no findings if none are justified. No cosmetic padding or preference-only
rewrites. Root owns adjudication, user questions, implementation and verification.

Also apply the interrogate skill's rubric and code-quality lens at:
/Users/spuri/.agents/skills/oh-my-pstack/skills/interrogate/references/rubric.md
/Users/spuri/.agents/skills/oh-my-pstack/skills/interrogate/references/code-quality-review.md
Read both fully. Favor cohesive ownership and deletion of genuine complexity;
do not add files/layers against the owner's consolidation preference without a
concrete maintenance or correctness benefit.
