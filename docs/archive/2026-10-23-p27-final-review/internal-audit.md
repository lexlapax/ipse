# Final internal whole-P27 audit, 2026-10-23

Historical review and repair record. Three independent model reviewers examined
`89151b6e049e1f7c8b2d396ea42f7c788e155955` against the whole P27 contract, then
inspected the integrated repair. This is a separate audit from the preserved
[external review of ca5838b](review.md). Current instructions belong to the
[operator MCP manual](../../operator/mcp.md), [MCP training](../../developer/mcp.md)
and [effect training](../../developer/extension-effects.md).

## Scope and disposition

The [common brief](internal-review-brief.md) required whole-milestone source,
architecture, acceptance and evidence review, rather than only reviewing the
latest fixes. The preserved reports are [reviewer A](internal-review-a.md)
(gpt-6-astra), [reviewer B](internal-review-b.md) (gpt-6.1-sol) and
[reviewer C](internal-review-c.md) (gpt-6-sol). Their initial warnings remain in
place; each report appends its post-fix assessment. All three found no concrete
remaining defect in the integrated patch. That is bounded review evidence, not
a claim that every possible defect or manual sentence was independently checked.

The lead's disposition retains P27 acceptance within its documented optional
scope, with the repairs below and the original evaluation limits. No further
concrete architecture, implementation or acceptance defect was established.

The lead accepted two causal findings and one related configuration case:

| Finding | Reproduction and repair |
| --- | --- |
| Ordinary MCP success/error output can recreate a private value during redaction | With configured values `q[redacted]` and `zz`, external text `qzz` becomes `q[redacted]`. Before repair, a real ordinary Session persisted it and continued its batch. Shared result admission now rechecks after redaction, returns unknown without external text, stops the batch and preserves inert resume. The owner explicitly selected unknown-and-stop for unsafe server-error diagnostics. |
| Resource and prompt rendering shares that publication gap | Catalog controls reproduce the same collision in both families. The complete rendered output now receives the same final privacy check. The extension-only error check is removed because shared admission owns the invariant; successful retained-source validation remains. |
| Legacy MCP public arguments disagree with their stored hash | Own-server legacy hashing was restored earlier, but public arguments still used global redaction. A valid overlapping-secret configuration could open its legacy Session yet fail extension binding before approval. This was also present at a7f4982. Legacy public arguments now use their writer's own-server rule, while response redaction remains global. A real loaded two-server configuration passes exact approval, dispatches once, validates saved actions and resumes idle without discovery or replay. No validator or legacy record shape is relaxed. |
| Redacting a configuration argument can create another server's private value | A three-server configuration reproduces this with argument `qzabc` and private values `abc`, `zabc`, `q[redacted]`. The final argument-publication check refuses it. The supported file loader still checks the whole manifest against all configured private values before admission. |

The first two rows share one publication-boundary repair. No new dependency,
process, module or public record format is introduced. The implementation changes
three existing files; tests exercise the actual owners. The unsafe-output rule
does not undo remote effects or permit replay. Direct raw server maps are internal
fixture inputs, not a replacement for the supported configuration-file admission
procedure; no broader raw-map privacy guarantee is claimed.

## Whole-milestone assessment

| Requirement | Evidence and conclusion |
| --- | --- |
| Source, chunk, generation, hash and citation identity | Reviewers traced Knowledge evidence/storage and host result contracts. Reviewer A hash-verified all 185 evidence members; the current scorer independently reproduces the entire published decoded score, including all 635 literal citation checks. No new contrary defect was established. |
| Deletion, suppression and stale/as-of eligibility | Source and existing causal controls cover State/MCP deletion, delayed work and stale projections. Retained-generation as-of limits remain explicit in the Graph manuals; reconstruction of replaced generations is not claimed. No new resurrection defect was established. |
| Contradictory, stale, negative and weak evidence | Existing algorithm controls and the frozen semantic review remain the evidence. This audit does not obtain new model judgments or claim universal semantic correctness. |
| Approval, profiles, accounting, budgets, cancellation and inert recovery | Reviewers traced host admission, late-deadline completion, transport ownership and saved bindings. New controls exercise partial real effects, unknown plus not-started batch outcomes, zero further inference and zero replay. The legacy control proves use after resume, not merely opening a journal. |
| Independent optional packages and generic host contracts | No mandatory retrieval/model service or new capability grant is added. The existing fifteen-preset inert controls, independent builds and source/installed proofs retain their stated scope. Domain implementations remain under extensions; Session remains the conversation owner. |
| Frozen 350-outcome comparison and ordering | The unchanged bundle contains 344 successful and six failed first outcomes across seven strategies and fifty questions. Predictions and the review method precede reference release. No exposed workload or consumed seal is reused for new acceptance. |
| Individual quality qualification | Hybrid remains 46/50 supported answers and 79/83 supported citations, 95.18%, the sole eligible strategy under the published final judgments. Reviewers' individual disagreements, the one-pair margin and the owner's non-independent grammar resolution remain disclosed. The frozen `independent: true` field contributes to global completeness; it is not relabelled as an independent human review. |
| Resource comparison and engine choice | Existing receipts retain all seven strategies, cell peaks without summation, unknown values and the exact optional cgroup workload-charged-RAM population. Mixed CPU/GPU placement, single-run/order limits and partial 8 GiB GPU residency remain explicit. No new resource measurement is claimed. |
| Consolidation and reader-facing manuals | The audit found no justified additional structural rewrite. The lead reviewed the complete changed MCP/effect chapters and audience indexes, checked related plan/reference claims and ran the documented credential-free MCP example. Current manuals explain ownership and recovery; historical results stay here. |
| Final runtime/package checks | The separate [internal verification receipt](internal-verification.json) binds the exact eight changed runtime/test files, platform commands, logs and package identities. Prior receipts remain statements about their original subjects. |

The versioned measured source remains `817ab84`; the owner accepted that evidence
alongside correctness checks on consolidated code. These host repairs change
neither retrieval nor scoring. Recomputing scores is an offline integrity check,
not fresh semantic evaluation. It exactly matches every published strategy and
gate without model calls or altered judgments.

## Verification boundaries

The corrected focused cohort passes 106 tests. Before-fix trials are retained
separately: an initial five-test selection reproduced four failures but selected
an old ordinary test by the wrong line; a corrected two-test selection reproduced
both ordinary success/error leaks. Neither failed trial is relabelled passing.
Reviewer probes and source-only claims remain distinguished in their reports.

Final platform results and exact source matching are recorded in the receipt.
The macOS default suite passes 1502 tests, with one skipped and 36 excluded,
in 1186.9 seconds. Linux's native-inclusive suite passes 1555 tests, with 19
excluded, in 1036.7 seconds. Both have zero failures. Their source/test bytes
match; each platform builds a fresh package and uses that exact archive for its
installed proofs. These are new checks of the integrated repair, separate from
the earlier 89151b6 results.

Both platform drivers finish with exit zero: build, format, strict compile, full
suite, demo, package, exact installed-package proof, artifact build, source MCP
and exact installed MCP. All twelve MCP assertions pass in each mode/platform,
with unchanged inventories and zero live-model calls. The complete-document/link
check passes: 401 Markdown files, 3643 local links, zero errors. The receipt binds
these logs and both archive hashes; its prior macOS archive copy matches the
earlier receipt before the generated package path is replaced.

No fresh real-model inference, semantic rejudging, charged-memory collection,
consumed-seal replay, macOS sandbox-specific run or local OTP 27 runtime check is
claimed. Local Elixir 1.18.5 formatting runs on OTP 29. Hosted CI must be read
against its exact commit separately. The primary Serenity checkout, its untracked
files and existing services are untouched.
