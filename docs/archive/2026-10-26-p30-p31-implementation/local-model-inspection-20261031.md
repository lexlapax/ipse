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

## Installed package verification

A clean checkout at `dd0ceb93587753e4a9d1e98f12048941994ed6dc` built the standard
PDF-enabled Linux archive, with52 bundled documents and no missing targets:

```text
ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz
SHA256 08523e3bbe45f8866d1fee31206afcb6c9fdb236645eae1049236952d99699a3
```

The generic installed-package verifier passed all controls, including private
setup, doctor, demo, helpers/locks, MCP/delegation/extensions, historical results
and the synthetic explicit-Memory workload. Its final report records unchanged
release inventories and no system development toolchain on runtime PATH. Log:
`/tmp/ipse-model-inspection-package-verify-20261031.log`, SHA256
`754abb08f6e85ab0e40efb5f640ec4860ee9b824696d2f06e1e9867f850389b2`.

A separate actual packaged CLI control inspected the selected primary embedding
model and refused a nonloopback URL. The [structured receipt](local-model-inspection-installed-20261031.json)
records the exact build/archive, selected manifest, six metadata requests and zero
inference calls. The release files and separate malformed conversation
configuration remained unchanged; no operator home was created. Runtime PATH
contained utility symlinks and bundled ERTS tools, without system Elixir, Mix,
Rust or Cargo. This control uses a cooperative live local service, not a model
request attestation or offline proof. Both primary models remained unloaded.

The executed harness and output remain respectively at
`/tmp/ipse-model-inspection-installed-proof-20261031.exs` and
`/tmp/ipse-model-inspection-installed-proof-20261031`; report SHA256
`3daf55b552ef0db893212a50f6bff821c69a6868c1272508ebde0a30e21c64c2`.
No model acquisition, inference, service reconfiguration or release publication
was performed. This additive record does not replace the first focused failures
or turn installed metadata inspection into full D1 acceptance.

## Scope and remaining work

This work was isolated while the main checkout's full suite ran against frozen
`c7cb484`. It does not change or upgrade that suite's source claim. Main-checkout
integration, protected model/job identity binding,
task-specific embedding formatting, explicit optional provisioning/recovery,
local-only egress proof and the remaining original goal stay open.
