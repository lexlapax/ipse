# Long-answer manual review

Read all six requested documents in full: operator configuration; developer configuration, extension effects, knowledge evaluation and extension invocations; model-calls README. Compared their feature claims/examples with the current ModelCall, Profiles/Config, Answer/Contract/Runner/Session/Score and proof-selection diff. Source/editorial review only; no commands, models, proofs or tests executed, and no sealed/private inputs accessed.

## Correction needed

**Low — stale selection reference misidentifies the version-two proofs.** `examples/model-calls/README.md:39–40` says “The last two select version-2 structured output,” immediately after requiring five selections. The final two are now `json-none` and `json-long`, but `json-long` sends version three. The actual version-two controls are `json` and `json-none` (`dev/verification/scenarios.exs:model_selection/1`). Replace “The last two” with “`json` and `json-none`”. The following version-three explanation is correct.

## Remaining verdict and limits

No other concrete correction needed for the current feature. The chapters coherently explain operator-only opt-in, root/profile/request narrowing, unchanged absence/legacy behavior, version-one/two ceilings, schema/output limits, SDK-2 aggregate constraints and the SDK-1 answer helper. The operator example is complete for configuration inspection and clearly requires separately selected extension/service work; timeout recovery preserves uncertainty and forbids replay. Contributor examples connect the request/profile changes to approval, saved execution, evaluator contracts and focused verification. Manuals distinguish prompt synthetic responses from actual generation duration/quality, and keep milestone evidence outside current teaching.

This does not certify long live inference duration, output quality, actual resource measurements or final platform/package acceptance. The ongoing public trial is outside this review's evidence.
