# P27 bounded final-answer calls, 2026-10-21

Historical implementation and diagnostic record after
`fad2856916b658487a23375c3484b4382e3f79a9`. P27 remains open. Current operating
instructions belong to [configuration](../../operator/configuration.md#allow-a-longer-extension-answer);
contributors should use [model effects](../../developer/extension-effects.md#request-bounded-text-inference)
and [evaluation training](../../developer/knowledge-evaluation.md). Acceptance
belongs to the [plan](../../plan.md#p27-optional-research-graph-and-rag).

## Preserve the two failed operating policies

The user selected the existing pinned `qwen3.5:9b`, CPU-only execution and
reasoning for final answers only. The earlier default-thinking diagnostic
retains [eight deadline failures](../2026-10-20-p27-quality-remediation/index.md#retain-the-default-reasoning-deadline-result).

The [advisory-brevity trial](brief-trial.json) appended a fixed instruction to
aim for at most 128 reasoning tokens. That instruction was advisory, not an
enforced limit. It preserved the eight exposed inputs/schemas, 4096-token
allowance and 120000 ms request deadline. One first response decoded in
112258 ms; seven were cancelled at 120001 ms. The one decoded response described
the freshness gauge with two separately cited claims. This observation is not an
independent semantic grade or a quality improvement claim. The advisory was not
integrated into production instructions.

The [long-deadline trial](long-trial.json) retained the original instructions and
enabled default thinking, selected a version-three request, and explicitly set
root/profile/request to 480000 ms with 8192 output tokens and reservations. It
predeclared stopping on the first invocation or decode failure. Its first
lexical Q02 request timed out at 480001 ms; no answer decoded. The trial stopped
after that single admission. It used a fixed 439-file prototype inventory
`206c31b69e371e76ef1a984df1fd545bff4a607b6213bc770e929a14d004c39a`,
before the complete evaluator integration. It does not certify the final feature.

Both trials verified the pinned model's enabled default before inference,
preserved unique canonical attempts and confirmed Session, native and staging
cleanup. Their source inventories remained unchanged. There were no retries,
private workload reads, model/provider switches or matched resource claims.
The long trial's initial preparation refused a missing directory argument;
another preparation refused macOS archive metadata that doubled the file
inventory. Neither preparation reached inference. A fresh metadata-free source
snapshot produced the retained single actual attempt.

## Keep the longer allowance explicit

The repair adds no SDK generation or invocation timer. `model.complete` version
three shares version two's structured response and byte bounds, with a bounded
600000 ms request ceiling. An operator-only profile field explicitly grants
the longer model-call allowance; root policy and each request still narrow it.
Absent that field, old snapshot bytes and the 120000 ms ceiling are preserved.
Project configuration cannot grant the override, ordinary main/child settings
exclude it, and saved-source validation still requires exact captured execution.

The existing SDK-1 answer helper forwards the complete prepared request. The
evaluator has a separate closed policy for version-three answers while keeping
extraction and rerank at version two, 4096 tokens and explicit thinking suppression.
The real measured path verifies the answer model's enabled default in each owned
cell. SDK-2 aggregate/read/publication limits remain unchanged. Scoring binds the
chosen policy and retains the individual 90%/95% qualification gates.

The [host review](review-a.md) and [evaluation review](review-b.md) found no
defects in the scoped implementation. They are independent source reviews,
not execution proofs or whole-P27 acceptance. The [whole-manual review](manual-review.md)
found one stale selection reference; the README now names the two version-two
selections explicitly. Source/installed synthetic selections exercise the longer
policy without claiming actual model quality or long generation.

Final operating-policy selection and the new private evaluation freeze remain
open. A single exposed diagnostic combining advisory brevity and the supported
600000 ms ceiling is separately declared to stop after one admission regardless
of outcome. Its existence does not authorize replacing failed first outcomes or
opening the private workload. No engine has been selected.
