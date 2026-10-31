# First actual primary-pair adapter requests

2026-10-31, isolated source `39ab23f`, Ollama 0.40.13 at the explicitly selected
`http://127.0.0.1:11434`. This records two actual requests from the existing
1000-call local allowance. It is not a Session/registered-service journey,
semantic comparison, context-capacity qualification or offline proof.

## Declaration and first outcomes

Before dispatch, the private harness wrote a two-call declaration containing
exact selected primary manifest hashes, synthetic input hashes, 60000-ms request
deadlines, a32-token answer-output cap and zero retries. Both metadata scans
matched the original [provisioning identities](ollama-provisioning.json). A local
reservation row precedes each adapter call. No model pull, daemon setting change,
paid route or existing model removal was requested.

The embedding adapter returned one valid1024-dimensional vector from
`qwen3-embedding:0.6b-q8_0`, with its actual input digest and typed result checks.
The completion witness was true. Elapsed time was2407ms; the service reported
13prompt tokens. These are one cold request's observations, not performance
percentiles or model quality.

The direct native chat adapter returned the expected five-byte synthetic answer
from `qwen3.5:4b`, with zero tools and17input/2output tokens, in2632ms. Its
completion witness was **false**. Inspection showed that the harness called
`Ollama.complete/4` directly, whereas the normal `Provider.complete/4` wrapper
sets the final native-completion marker. The false witness is correct for that
invocation and is retained; a parsed response is not promoted to witnessed host
completion. No production repair, retry or additional call was performed.

The [sanitized receipt](local-primary-smoke-20261031.json) retains numerical
outcomes, hashes and metadata without response text, thinking or vector values.
Its SHA256 is `4a958bef7ad8876a08d7ad747596dcaa89c5f997f3612f5d6523a8d010dc3a1d`.
The executed harness remains `/tmp/ipse-local-primary-smoke-20261031.exs`, SHA256
`d58b2f7c203b5f24a66b5ab6904238dfc352195a0544204421d504df508b0414`.
Its unused-alias warning is a development-harness diagnostic, not a runtime
build failure. The original declaration, call reservations, first outcomes and
metadata remain under `/tmp/ipse-local-primary-smoke-20261031`; nothing was rerun
to replace those first outcomes.

## Loaded context differs from architectural limits

Before these calls both selected models were unloaded. Afterward `/api/ps`
reported4096 context tokens for each, matching the selected digests. This is
service-reported residency, not per-request backend attestation or continuous
placement. It is substantially smaller than the32768/262144architectural
limits in model metadata. An operator cannot use the architectural limits as
the active context allocation. The existing [configuration procedure](../../operator/configuration.md#allow-a-longer-extension-answer)
separates server context settings from output caps; the ordinary Ipse provider
profile does not configure the daemon's context.

The harness did not request a different context or prove long-input behavior.
Protected model/job identity, context selection/checks and owned service recovery
remain D1 work. The report's `local_execution: not_attested` and quality
`unverified` are unchanged. The larger frozen main-source suite was still running
independently; these requests do not change its source claim or fixture results.

## Allowance

Charge **2 of1000local calls**, leaving **998**. Both calls received parsed
responses; the direct chat witness limitation does not refund its charge.
ChatGPT remains226of300conservatively charged, with74remaining. Downloads remain
the already acquired primary pair; the separate small decision-model candidate
was not acquired or called.
