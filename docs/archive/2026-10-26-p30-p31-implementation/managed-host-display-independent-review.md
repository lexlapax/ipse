# Independent review of managed host/display refusal

2026-10-29. This scoped review covers the frozen
[managed host/display refusal cohort](managed-host-display-refusal.md), not
complete P31C0. The reviewer verified its ten source/artifact manifest entries,
209 private runtime BEAM hashes and helper hash. The inspected fresh approval
and progress paths refuse or redact managed arguments, and the recorded ordinary
approval control displays its full arguments. No tests were rerun in this review.

The review identified three concrete gaps requiring repair:

1. Legacy pending native or extension questions can expose managed arguments
   after source loss both through the resumed subscriber notification and
   through `Session.info/1`. Recovery must bind the exact saved call or
   invocation to valid lineage, fail closed on tainted or ambiguous provenance,
   and prevent answer continuation as well as display.
2. Managed `state.put` and `state.delete` under an existing allow or `--yes`
   can reach the ordinary State writer without a current-use fence. They can
   persist derived content after its source or consent becomes stale.
3. Managed `service.call` can send derived arguments to another worker without
   a current source/Consent fence. It must refuse until its owned start and send
   boundary is implemented and verified.

The reviewer also identified a publication candidate requiring an actual
two-source test: `collection.call` and `collection.managed` check the new
request's proof set, but may not hold the complete inherited managed dependency
union through the final publication switch. A stale source A and independent
current cited source B distinguish that question. Interim refusal is required if
the missing inherited fence is confirmed.

The six recorded refusal controls do not cover these gaps, arbitrary delayed
output sinks or in-flight source loss. Repairs and their own tests remain open.
