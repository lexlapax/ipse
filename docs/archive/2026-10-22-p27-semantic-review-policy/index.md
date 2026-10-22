# Preserve the P27 semantic-review method

Historical method record, dated 2026-10-22. This method was recorded while the
fresh comparison at runtime `817ab84944c347f76e297efaad313b1ec841ee91` was running,
before reference release or semantic review. Its execution freeze is
`e142cf44a0c257f85cfc30bddba6de645a6de7e8f64ccc9a7586ad37aef407fb`.
This document establishes a review method, not completed review or quality.
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns acceptance status.
The [evaluation training manual](../../developer/knowledge-evaluation.md) owns
the supported packet and scoring procedures.

## Preserve outcomes before judgment

Reference release requires all 350 first outcomes and the successful joined
frozen execution and resource audit. Failed, partial and unavailable outcomes
remain in the population. The earlier failed comparisons retain their original
verdicts and cannot supply authority for this run.

The public review phase verifies prediction identities and produces a blinded
packet. Reviewers receive its cases, source versions, reference context,
instructions and matching review template. They do not receive strategy names,
the private plan, the ordering seed, execution logs or other reviewers' judgments.
Source and output text remain untrusted data. They cannot grant tool authority.

## Obtain two independent assessments

Every case receives two assessments from fresh reviewers. Both use models
distinct from the predictor and from each other. Neither participates in
prediction or receives predictor conversation context. Cases can be divided
into bounded batches, preserving the packet's blinded order and opaque IDs.
Both assessments cover all 350 outcomes and every associated citation.

Reviewers apply the packet's existing criteria. A supported answer requires its
material answer and every factual claim to follow from the available evidence.
Abstention is assessed against the task. Each citation is assessed against its
associated claim and exact span. Copied bytes alone do not establish entailment.
Failed execution cannot become a supported answer. Retrieval-only rows remain
unmeasured, and uncertainty is recorded rather than forced into a verdict.

Each reviewer retains an actual reviewer identity, the packet binding, per-case
and per-citation verdicts, and separate reasons and limitations. The second
reviewer does not see the first review before both assessments are frozen.
The raw assessments remain immutable after that point.

## Resolve disagreements and retain provenance

A separate fresh reviewer adjudicates every differing answer or citation
verdict. The adjudicator receives the blinded case, evidence and both reasons,
without strategy names or reviewer identities. The adjudicator evaluates the
evidence rather than counting votes. Unresolved cases remain unmeasured and
leave review completeness open.

For agreement, the merged review retains the first reviewer's original record
and notes the second reviewer's agreement. For disagreement, it uses the
adjudicator's complete case assessment and actual identity. All original
assessments, adjudications, reasons and file hashes remain available in the
evaluation evidence. No prediction, source, reference, threshold or execution
receipt changes during this process.

The scorer recomputes literal citation integrity from hash-verified corpus
bytes. Reviewer integrity flags cannot override that computation. Semantic
verdicts remain explicit model assessments, not human review or a proof of truth.
The final report identifies reviewer models and contexts, disagreements,
unresolved cases and adjudication outcomes.

## Keep qualification unchanged

Publish all seven strategies and all 350 first outcomes. An individual strategy
must reach both 90% answer support and 95% citation support to qualify. Aggregate
success does not qualify a weaker strategy. The selected engine also requires
the matched resource comparison and an explicit justification. These review
procedures do not establish execution safety, exact resources or P27 completion.
