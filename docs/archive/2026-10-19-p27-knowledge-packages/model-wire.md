# Separate model wire framing from returned text, 2026-10-19

Historical causal investigation after `f89ccee`. The commit containing this record
owns the bounded text-model wire correction. Use the current
[model-call training chapter](../../developer/extension-model-calls.md#receipts-bounds-and-accounting)
for limits and verification. Full P27 acceptance remains open in the
[plan](../../plan.md#p27-optional-research-graph-and-rag).

The [tuning preparation record](evaluation-preparation.md) retains three generic
text-helper failures without claiming a cause. One separately allocated diagnostic
request reproduced an extraction failure but classified it only as `other_error`.
A second one-request diagnostic retained a complete fixed category and error hash.
It identified `Provider response exceeds the configured byte limit.` The error
SHA-256 was `4a8844b6ada05ebd666c241bc52103d54d4667e525e7bb8c114dcc8c454d7e75`.
Both requests used the existing local model, the permitted tuning source and
normal Session accounting. Each had its own declared one-request allocation and
confirmed cleanup. Tracing captured function arities and retained only fixed
categories or error hashes, without argument or response payloads. Neither request
read held-out data or retried within its exhausted budget.

`ModelCall.prepare/2` configured a 65,536-byte provider wire limit. The shared HTTP
reader counts the complete body, including repeated streaming JSON framing.
That limit could therefore stop a permitted 1024-token request before its final
small text and usage records arrived. The diagnostic establishes the failure
boundary of that captured request; it does not retroactively identify every
earlier generic failure or prove extraction quality.

The controlled Session regression sends 2000 valid empty-content streaming records
followed by the ordinary small text result and usage. Its framing exceeds 64 KiB.
Before repair, its expected successful host result failed. The repaired host allows
at most 1 MiB of wire body, while retaining the separate requested text ceiling
of at most 8192 bytes, native assistant receipt ceiling of 256 KiB, fixed stream
event/fragment bounds, token reservations, deadlines and egress approvals.
There is no truncation, retry, provider fallback or extension-selected wire limit.

The wire-overflow control now exceeds 1 MiB and still fails as an accounted
attempt with unavailable usage. The rejected-text control still records completed
inference and measured usage while refusing the extension result.

## Corrected-source local verification

| Check | Result |
| --- | --- |
| Build, format, warnings-as-errors compile, docs and CI policy | Passed |
| Focused model-call/invocation/artifact suite | 59 passed |
| Full source including actual macOS sandbox/filesystem checks | 1090 passed, 17 Linux-only exclusions; 398.2 seconds; strict cleanup probe enabled |
| Strengthened independent model proof with heavy framing | Source test passed; all nine proof groups passed in the extracted runtime |
| Standard bundled-package verifier | Passed with development tools hidden |
| Credential-free demo | Passed after authorized loopback access; initial sandbox TCP filesystem-lock refusal retained |

Runtime/native/test sources remained unchanged through the full suite. The
standalone proof was then strengthened to use the same heavy framing and verified
separately before installed execution. The new local archive SHA-256 is
`2a39c5694101543ad2ed544c5da913da676baac149a1f909b15ff1aab01bf882`.
The installed proof confirms unchanged archive and extracted host files. The
previous local archive was preserved separately with its original hash. This
is a local verification archive, not a published release. Hosted verification of
the corrected source remains required.

## After-repair tuning preserves the next failure

A separate, explicitly versioned four-request comparison used the same permitted
tuning inputs, old independent domain artifacts and 1024-token Qwen profiles
against the corrected host. Fixed return-category tracing identified a generation
limit on every call: two extraction requests, reranking and answer generation.
All four failed outcomes remain saved; no response was retried and cleanup was
confirmed. This run demonstrates the next constraint after the wire refusal,
not successful domain inference or semantic quality.

All four final provider usage observations were retained. Their reported input
counts were 220, 232, 259 and 574; each reported 1024 output tokens. The failed
requests retained their conservative reservations, booking the complete 16,384
input and output token limits and all four request slots. The budget was not
renewed. Costs remain unpriced. The earlier completed tuning answer and the new
failed answer both remain evidence of generation variability. Held-out data
remains sealed pending extraction/prompt, profile, lifecycle and evaluator work.
