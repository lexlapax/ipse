# Explicit local model metadata inspection

2026-10-31, source increment based on `c7cb484`. This dated record covers bounded
metadata inspection, not P31D1 completion, provisioning, loaded-context
qualification or model quality. Current procedures belong to
[operator configuration](../../operator/configuration.md#inspect-an-installed-ollama-model)
and [configuration training](../../developer/configuration.md#inspect-local-model-metadata-before-selecting-a-route).

## Operator path and ownership

`model inspect --provider ollama --model NAME --base-url LOOPBACK_URL` reads an
explicitly selected installed model independently of the conversation file. It
uses the existing host URL policy, owned bounded HTTP, duplicate-safe JSON and
maintained schema validator. No dependency or native protocol was added.

Six metadata requests read version, installed tags, model details and current
residency, then recheck tags/version. The exact selected tag row must stay
unchanged. Missing/ambiguous identities, changed versions, resident-digest
mismatch, malformed/duplicate JSON and invalid declared numbers refuse without
retry. Each reply is bounded to 1 MiB/depth16, inventories to256 rows and
capabilities to32 labels; the complete scan uses a nonrenewing 1..30-second budget
with a10-second default. Cleanup can outlast the budget; late success is refused.

The report distinguishes architectural limits from service-reported loaded
context. An unloaded model retains `unverified_not_loaded`. Full canonical
metadata and optional template/parameter/license bytes are hash-bound. Diagnostic
labels reuse the existing safe renderer; arbitrary license text is not printed.
A returned license label remains a provider claim. A loopback address and these
observations prove neither request weights/backend nor offline execution.

The metadata reader belongs to the Ollama adapter, outside Session. Its CLI uses
no conversation worker, config writer, inference scheduler or model dispatch.
It does not widen protected notes permission or provide reusable effect authority.
Inspection must stay outside a provider completion observation; metadata HTTP
cannot witness inference completion.

The Corpus producer example also now selects a100000-ms embedding profile for its
registered service. The prior120000-ms profile exceeded the existing slot limit
and refused before dispatch. This changes the explicit example, without silently
narrowing any operator's saved profile or runtime deadline.

## Executed controls

- Focused metadata/CLI plus existing provider and conformance suites:
  **107 passed,0.6seconds**, `/tmp/ipse-model-inspection-tests-final4-20261031.log`.
- Standard isolated build:179 modules and all three inert bundles. Format,
  warnings-as-errors compile and credential-free demo passed.
  `/tmp/ipse-model-inspection-build-20261031.log` and
  `/tmp/ipse-model-inspection-demo-20261031.log`.
- Exact synthetic wire checks allow only metadata endpoints; positive scans
  make six requests. No generation, embedding or model acquisition endpoint is
  called. Separate controls cover changed tag/version, duplicate/aliased rows,
  mismatched resident state, malformed/overdeep JSON, invalid limits and unsafe
  upstream labels. The CLI leaves a separate malformed conversation file intact
  and creates no operator home.
- Real selected service metadata on Ollama0.40.13: both primary manifests match
  the [provisioning record](ollama-provisioning.json). The
  [embedding observation](local-model-inspection-embedding-20261031.json) declares
 1024dimensions and32768context; the
  [answer-model observation](local-model-inspection-answer-20261031.json)
  declares262144architectural context. **Neither model was loaded**, so effective
  context and inference readiness remain unverified. No model call, download or
  service setting change was requested.

The first focused run returned a bare `:error` for an invalid semantic version;
the reader now normalizes that to its fixed error tuple. The original8/9 log is
retained as `/tmp/ipse-model-inspection-tests-20261031.log`; subsequent focused
runs remain separate. The real observations are read-only service claims,
not independent model or offline qualification.

## Scope and remaining work

This work was isolated while the main checkout's full suite ran against frozen
`c7cb484`. It does not change or upgrade that suite's source claim. Main-checkout
integration, installed verification, protected model/job identity binding,
task-specific embedding formatting, explicit optional provisioning/recovery,
local-only egress proof and the remaining original goal stay open.
