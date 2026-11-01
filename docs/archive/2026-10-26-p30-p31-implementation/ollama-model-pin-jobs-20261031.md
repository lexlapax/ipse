# Cooperative model checks around registered Ollama jobs

Dated **2026-10-31**, based on `0b9c5f3` plus the source inventory in the
[receipt](ollama-model-pin-jobs-20261031.json). This is historical implementation
evidence. Current procedures belong to the
[operator configuration chapter](../../operator/configuration.md#check-an-ollama-model-around-each-job)
and [contributor training chapter](../../developer/configuration.md#hold-a-model-check-through-registered-inference).
The [plan](../../plan.md) owns remaining milestone acceptance.

## Implemented boundary

An operator-owned named Ollama text or embedding profile can select an optional
closed `ollama_model_pin`: version 1, explicit
`cooperative_service_metadata` trust boundary, expected full manifest and metadata
hashes, runtime version and minimum loaded context. Optional
`ollama_context_tokens` now also works for embeddings. Unsupported providers,
project definitions, invalid types and a requested context below the minimum
refuse. No new top-level setting, environment/CLI override, dependency, native
protocol, provider choice, provisioning or automatic migration is introduced.

The existing bounded read-only model inspector checks metadata before and after
an inference job under the existing registered shared-service slot. Each scan
has six requests, 1 MiB per response and a maximum ten seconds, narrowed by the
existing job deadline. The registered-service deadline remains at most 100000 ms;
the checks never extend it. A successful job therefore makes twelve metadata
requests plus one inference request. A changed manifest, full metadata digest,
runtime, capability or exact response model refuses generated output. Loaded
context can be absent/smaller before inference loads the requested model, but
must meet the minimum afterward. No retry or alternate endpoint runs.

Metadata remains the service's cooperative claim. These checks establish neither
immutable weights for a request nor continuous context placement, input fit,
no silent truncation, exclusive daemon ownership or offline execution. Other
clients remain outside Ipse's service slots. These limitations are explicit in
both the profile field and operator procedure.

Preflight runs before the inference Budget reservation and sends no prompt.
Postflight runs after the native completion witness and measured usage settlement,
before the existing private buffer can release text, tools or vectors. A completed
but rejected response retains its measured charges and can settle the service;
an interrupted native request remains unknown. The original source/permission
and final managed-publication gates still apply. A process-private scope is
explicitly carried into existing controlled native children; it is not serialized
permission or a worker-provided proof.

Pinned inference requires a matching saved named execution selection. Dropping
the runtime pin or changing the selected pin refuses, including idle resume
before journal repair. Profile inspection stays offline. Embedding selection
retains its exact prior version-1 digest when optional fields are absent;
present context/pin uses version 2 with their full canonical values. Separate
explicit bounded rebuild is required to adopt that changed identity.

## Verification and first outcomes

The final controls cover actual registered Session text, separately compiled SDK
text/embedding, an existing controlled Mint child, preflight mismatch without
prompt egress or inference reservation, postflight manifest/runtime/template/
context/residency mismatch, withheld tool batches/workspace effects, no vector
publication, retained measured token charges and unchanged idle resume. HTTP
responses are synthetic. Native storage positives ran on the qualified available
Linux/tmpfs profile; unsupported environments are explicitly distinguished.

Before the last vector-specific addition, the 22-file regression cohort passed
**185 tests in 41.2 seconds**. A separate legacy configuration/provider conformance/
service-ledger cohort passed **153 tests in 14.3 seconds**. The final four-file
model-pin controls passed **23 tests in 10.6 seconds**. Exact final-control,
build, formatting, strict compile, demo, policy and documentation outcomes are
retained in the receipt. The complete documented pin configuration was extracted
and inspected through the actual CLI without inference or operator-home creation.
The operator Configuration and Extensions chapters and contributor Configuration
chapter were reviewed as whole documents; current embedding-context guidance was
reconciled with profile, wire and selection behavior.

Original development failures are retained: the first compile found a local
`binding/1` name conflict; a Session fixture selected a nil ID from the wrong event;
a preflight fixture attempted JSON encoding of HTTP tuples; the new SDK refusal
fixture initially expected `error` instead of the existing `failed` outcome label.
Each was corrected without weakening production refusal or completion accounting.
Sandboxed Mix test/CLI attempts also refused their TCP lock; approved loopback
reruns did not weaken TLS or tests. The receipt identifies those logs separately.

This increment makes no live model request or download. Allowances remain
ChatGPT 238/300 conservatively charged and local 2/1000 charged. The earlier direct
local chat smoke's false completion witness remains unchanged; its harness used
no registered service and therefore created no unresolved service reservation.
This distinction does not promote that response to witnessed completion or refund
its allowance. Whole-current-source acceptance, installed pin journeys, live
primary-pair/context qualification and independent quality remain open. The latest
[completed whole run](full-suite-e86b1b8-20261031.md) is still the negative earlier
revision result; focused passes are not subtracted from its failures.
