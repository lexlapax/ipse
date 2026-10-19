# Complete comparison declaration, 2026-10-19

Historical implementation and verification record. The containing commit follows
`3181f54`. Current procedures are in the
[evaluation training manual](../../developer/knowledge-evaluation.md#declare-the-complete-comparison)
and [Research user manual](../../operator/research-extensions.md).
This increment does not complete P27 or establish held-out quality.

## Declare every strategy without reading data

`EvaluationPlan.build/1` produces all seven variants from one explicit local
specification. The public CLI normalizes artifact paths, validates the complete
plan and creates an exclusive owner-only output. It applies permissions before
writing the private review seed. Generation opens no dataset member, manifest,
artifact or provider. The Session fixture now uses the same builder instead of
maintaining a second strategy matrix in its test helper.

The public specification declares profiles, model digests, algorithm options,
common answer generation, fixed time policy, fifty queries and finite budgets.
Its dataset member names are examples, not verified names from the sealed
manifest. Executable preflight and a clean complete freeze remain separate.
The baseline budgets allow 1024 requests. With equal per-project division this
covers every possible distribution of fifty answer requests among one through
fifty projects. Inference-heavy preparation has a separately declared finite
8192-request cap. Neither unused shares nor exhausted roots are renewed.

## Preserve the capacity failures

The initial complete-plan integration run passed ten of twelve tests. Both
seven-variant cases failed because Research's actual catalog and implementation
accepted at most three sources while the comparison declared ten. This was a
domain capacity mismatch, not a model failure.

After raising that count ceiling, the isolated package suite passed seventeen
of eighteen cases. Ten short sources returned `result_too_large`: the automatic
unassessed open claim repeated all full citations already present in `evidence`.
The 12000-byte result ceiling was preserved.

Public output now represents that synthetic open claim with zero-based
`evidence_indexes` when its entire citation basis appears in the final ranking.
Conversion occurs at publication after fusion and reranking. Internal claims
retain their original citation basis. Missing basis citations preserve that full
basis instead of dropping provenance or creating a dangling reference. Attributed
graph claims retain their own basis unchanged. Ten short provided sources fit;
ten longer quotations still refuse at the original byte ceiling. A ten-source
count allowance cannot guarantee that every legal provenance/quotation set fits.

## Verification boundaries

The first focused pass had 26 tests and covered the complete matrix, CLI,
Evidence and package controls. It preceded the final publication-order refinement
and the separate ten-source public-Session control. Later verification belongs
to the final containing commit's reported checks; this earlier pass alone does
not attest those edits.

The final declaration/public-Session suite passed four tests in 10.1 seconds,
seed 509317. The preceding combined run passed twenty of twenty-one; its new
Session test incorrectly read the receipt envelope as the result. Correcting
the test to inspect `receipt.value` produced the four-test pass. That correction
changed no runtime behavior. The other twenty controls, including final-order
mapping, query completeness and the isolated capacity suite, already passed.
The documented seven artifact builds and actual CLI generation also completed
in a fresh private directory, with no inference or input access.

Both prior exact-source hosted matrices completed successfully:
[storage/accounting at b13c153](https://github.com/lexlapax/ipse/actions/runs/39250792470)
and [diagnostics at 3181f54](https://github.com/lexlapax/ipse/actions/runs/39252112114).
All 24 steps in each Linux/macOS job were inspected. Those green runs do not
explain the earlier append timeout or MCP negatives and do not attest this later
declaration increment.

Final local verification passed 1146 tests with 17 Linux-only exclusions in
597.4 seconds, seed 516214. Strict stdio tracing and both actual macOS enforcement
tags were enabled. Build, format, warnings-as-errors compilation and pinned CI
policy passed. Documentation checks covered 231 files and 2572 local links
without errors. The operator and contributor chapters were reviewed as complete
manuals, including their procedures, cross-references and limits.

Fresh independent artifacts passed sixteen base Session checks and seventeen
MCP Research checks through both source and extracted-runtime routes. Every
route reported zero model requests and no domain modules loaded into the host.
Installed wrappers hid development tools and confirmed unchanged host/archive
bytes. The existing archive SHA256 remained
`d5d2517e87cf358cfe6b6d82060719e6be52ce0e5fcf7920fc4729df7d5c8a4f`.
No archive or release was rebuilt. These checks use macOS arm64, Elixir 1.20.3
and OTP 29; they do not attest a new hosted source revision.

The credential-free demo passed with an isolated operator home and the existing
Mix toolchain. Its first isolated invocation lacked Mix's existing Hex archive
and stopped before startup; preserving `MIX_HOME` and allowing the required local
Mix socket corrected that verification setup without installing dependencies.

The remaining capacity audit identified the controlled gateway's whole-run
512-call ceiling. Fifty ten-source Research queries can require 550 calls.
Its existing negative test proves that document selection does not renew that
cap. A workload-derived finite allowance and a direct full-workload control
remain necessary before the complete held-out freeze. The source-count and
result-publication repairs above do not close that separate gate.

No held-out corpus, queries, labels, manifest contents or evaluator were opened
for this change. No model inference, model download or paid provider was used.
The original failed runs remain retained. No host SDK bounds, production
deadlines, cleanup assertions or authority grants were widened.
