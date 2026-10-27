# Native operator-sidecar component

Dated **2026-10-26**. Engineering evidence for an internal increment after
`6c26080`; the [plan](../../plan.md) owns milestone status and the
[knowledge training chapter](../../developer/knowledge-extensions.md) owns current
developer guidance. This is not a standalone setup or release acceptance record.

`Knowledge.Contracts` supplies closed structural schemas for ordinary capture,
pending proposals and four separate retention choices. The independent builder
emits a 14,599-byte `operator.json`, included in the manifest's hashed file list.
Generic `Artifact.read_declared/4` first verifies the installed artifact and then
rechecks the selected declared data file's bounds and digest without loading code.
It refuses traversal, undeclared files, excessive caller limits and changed files,
including unrelated declared payload changes.

The schemas use the existing host JSON Schema subset. Capture excludes pin and
history categories, all objects reject unknown properties, evidence contains one
bounded stable proof, and retention choices have distinct exact policy shapes.
These are structural guards only: they do not authenticate proof JSON, recompute
claim/evidence lineage, authorize operator choices or enforce temporal relations.
Trusted normalization/current eligibility and guided standalone activation remain
open. No model inference, operator setup write or active Session selection ran.

## Verification provenance

Private source/runtime `/tmp/ipse-native-operator-contracts-20261026-01` copied the
complete native capture checkpoint, then replaced only Artifact, builder, Contracts
and the focused tests. It retains a private helper with digest
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
No shared helper was rebuilt. The runtime is not the concurrently evolving full
branch and does not establish integrated inference/reference acceptance.
The [source, runtime and artifact inventory](operator-sidecar-sources.json)
binds the measured private graph and independently built artifact.

- Strict compile: 117 modules, zero warnings; receipt
  `/tmp/ipse-native-operator-contracts-01-strict.log`.
- Focused Contracts, Records and Bundles tests: **16 passed**, seed **941911**,
  0.2 seconds; receipt `/tmp/ipse-native-operator-contracts-01-tests.log`.
- Actual independent native artifact build passed; output
  `/tmp/ipse-native-operator-contract-artifact-20261026-01`, receipt
  `/tmp/ipse-native-operator-contracts-01-build.log`.
- Actual Elixir 1.18.5 formatting: **490 files, zero differences**; receipt
  `/tmp/ipse-native-operator-contracts-01-format118.log`. Host OTP is 29; this is
  not an OTP 27 compile claim.
- Documentation checker: **493 Markdown files, 4,464 local links, zero errors**;
  receipt `/tmp/ipse-native-operator-contracts-01-docs.log`.

Tests check actual capture output against the schemas, extra fields, file-path
proofs, duplicate evidence, capture pin/history attempts, retention cross-choice
substitution, inert declared-file reads and changed installed payloads. Full-suite,
installed packaging, live model and adversarial integrated acceptance remain open.
