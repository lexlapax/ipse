# First pinned primary-pair Session jobs

Dated **2026-10-31**, committed source `1d014f6` and its matching rebuilt runtime.
This historical functional control follows the
[cooperative model-pin implementation](ollama-model-pin-jobs-20261031.md).
Current setup belongs to the
[operator manual](../../operator/configuration.md#check-an-ollama-model-around-each-job);
the [plan](../../plan.md) owns remaining qualification. The
[sanitized receipt](local-pinned-jobs-20261031.json) retains hashes and numerical
outcomes without answer text, hidden reasoning or vector coordinates.

## Declared route and first outcomes

Before metadata or inference, the private harness declared two maximum inference
attempts, no retries, at most 48 metadata requests, 100000-ms job deadlines and the
previously reviewed primary-model metadata/manifest identities. Both profiles
requested 8,192 context tokens and required at least 8,192 after successful inference.
The answer profile explicitly selected `reasoning_effort: none` and a 32-token
output cap. No model, service configuration or billing route was substituted.

The first preparation stopped at artifact import: it used a nonexistent
`artifact/embedding` subdirectory instead of the single-artifact builder's root.
It had completed read-only metadata scans but created no Session, call-charge
file or inference request. The corrected continuation retained the original
declaration, source inventory and metadata, then imported the actual artifact
root. No failed inference was replayed and no preflight observation was replaced.

The first real request used the separately compiled public embedding example,
ordinary import/trust/configuration and an explicitly selected
`qwen3-embedding:0.6b-q8_0` profile. The registered job passed both metadata scans
and published one 1024-dimensional float32 vector. The separate worker then
reconstructed all 4,096 bytes through two coordinate pages and checked its digest;
its final result was successful. The post-job inspection reported 8,192 loaded
context tokens and the expected full manifest.

A separate ordinary main Session selected the pinned `qwen3.5:4b` profile with
effects denied. Its single admitted request returned the exact requested
five-byte synthetic answer, without tools. Both model checks passed; post-job
inspection again reported 8,192 context tokens and the expected manifest. The older
direct adapter smoke's false witness is preserved; this control used the ordinary
Provider/Session path and did not reinterpret that earlier response.

Both requests have completed/final journal outcomes, matching reported model
names, one booked request each and zero unsettled/unknown budget liabilities.
The same service ledger had one then two recent settlements, with no active
reservation after either job. Saved reconstruction passed after confirmed close;
idle resume and another confirmed close added no inference admission. Original
workspace/tool effects were absent. The code/native/example/development sources,
compiled BEAMs and helper inventory matched before and after the control.

## Limits and accounting

Charge **2 additional local calls: 4 of 1,000 charged, 996 remaining**. ChatGPT remains
238 of 300 conservatively charged, 62 remaining. No model downloads, daemon stop,
manual settlement or allowance refunds occurred. The earlier smoke used no
registered service; read-only checks found no service tree in its root or the
default operator home before this first local registered control. A private
qualified tmpfs operator home was therefore not used to bypass an existing
unresolved marker.

The 48 metadata requests are a declared programmatic upper bound, not measured
outgoing-wire counts. Native metadata remains cooperative service evidence,
without immutable per-request weight attestation, exclusive daemon ownership or
offline proof. The residency sizes in the receipt are service claims, not peak
resource measurements. This is source-checkout evidence with synthetic content,
not installed-package, long-input, retrieval usefulness, independent quality or
full D1/F acceptance. No performance percentiles are inferred from these two calls.
