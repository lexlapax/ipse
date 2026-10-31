# Mint owned-transport experiment

This is an in-progress, unwired experiment, not P30/P31 acceptance evidence.
It combines a controlled owned child with a bounded Mint HTTP/1 transport and
an outer completion observation. It does not establish the current Session
policy/root barrier, and it must not be connected to inference until that
barrier, actual adapter binding and parsing, and publication ordering are
independently reviewed.

For plaintext BEAM-port sockets the experiment monitors the exact local port,
requires a matching port DOWN after Mint close, requires native completion in
the child, and waits for the owned child cleanup result. A post-send failure,
missing receipt, parse failure or uncertain cleanup stays unknown. This is
evidence of local port closure, not remote cancellation. Unsupported socket
types, including TLS sockets, refuse before admission and send no inference
payload; connection setup may already expose destination metadata. No live
provider or model quality was tested here.

The one-use reference binds a pending outer observation to its owner, selected
provider, model, kind and target, and rejects substitution and replay. It is
correlation under trusted same-BEAM host discipline, not proof that a child ran
or that a hostile host process honored the cleanup sequence. The actual cleanup
claim depends on `MintOwned` invoking completion only after the controlled
child result and port receipt. Extension inputs and JSON must not be treated as
authority to mint or complete such observations. The callbacks and raw URL,
headers and body are trusted host inputs; a future adapter must derive and bind
them from the admitted selection and buffer partial output until settlement.

On 2026-10-27 a private test graph compiled with warnings as errors and passed
39 focused transport, witness, ownership and synthetic-dispatch tests (seed
20270216). The normal native helper refused the registered positive dispatch
on this unqualified 7.2.11 kernel, which the test explicitly reported. A
separate disposable graph using a test-only kernel override passed two synthetic
registered/unregistered dispatch cases (seed 20270217). That override is not a
kernel qualification, production profile, or evidence of live inference.
An independent private graph passed 31 tests on the same source (seed 20270216)
and also reported the registered positive path as unsupported. Its separate
diagnostic reproduced owner-side reserve and completion without a child (one
test, seed 20270215). The reference therefore cannot authenticate a hostile
same-BEAM caller; the independent review found no additional demonstrated
component defect.

The tested code hashes were CompletionWitness
`52666cc39c1a054c652f10d9cd799160e22712007be2f3005d74767b172cb7a5`,
MintOwned `4217c24cf99ecd3879998d7b67bdcf9b072834b00b5ecd859c4c823cf74aeb75`,
and MintTransport `33a1ae152604fc37e6b811cc5cc19066d81b1e56da9ddcdf056a95ebc82a099a`.
After that run only the CompletionWitness explanatory comment changed; no
behavior changed. The current working tree is uncommitted and may evolve.

## Unwired Ollama embedding adapter

A subsequent experimental adapter derives the Ollama embedding target and
serialized request using the existing embedding implementation, uses fixed
JSON headers, and supplies hashes of those exact bytes to the host admission
callback alongside the send continuation. It buffers response chunks inside
the owned child and invokes the existing embedding parser before settlement;
it has no streaming publication callback. The requested model is bound in
the request, but the parser accepts a valid reported model name and cannot
prove which model the service actually used. The admission callback is not a
current-root policy implementation, and no Session route uses this adapter.

The module SHA-256 was
`1b126835722b4d71728ee52f8dd050ba5bce32abcef9187b50932aca56c6b96c`.
The private graph passed 32 adapter/ownership/transport tests (seed 20270219),
and four adapter tests including refusal and socket closure (seed 20270220).
Independent review passed the same four cases and found no additional
demonstrated defect. Its test snapshot differed only in formatting from the
subsequent formatted test file. These loopback fixtures do not establish live
model behavior or production-kernel qualification.

## Unwired text and decision adapters; Ollama framing repair

Experimental text and decision adapters now derive the native request using
the existing Ollama chat and System One compatible implementations. The text
adapter refuses configured credentials; the decision adapter supports only the
explicit compatible route. Both use fixed headers, provide the admission
callback with hashes of the actual serialized body and target, and buffer
until parsing and controlled cleanup settle. The callback still must enforce
current Session policy at the send continuation. The compatible route, like
the existing adapter, does not forward a configured API key.

An independent diagnostic reproduced a pre-existing live Ollama parser defect:
a frame following `done: true` could add text or a tool call to a completed
response. The shared parser now rejects nonempty frames after completion in
both live and buffered paths. Ollama's [streaming documentation](https://docs.ollama.com/api/streaming)
shows the completion marker on the final NDJSON frame. Tool continuation and
the original native parser remain in use. A private graph passed 106 provider,
conformance, decision and seam tests (seed 20270224), including incomplete,
post-terminal and duplicate-terminal frames. The source is not Session-wired;
TLS cleanup, current-root admission, and live model qualification remain open.

Before the fix the independent live diagnostic returned `finishedlate` and a
tool call when a valid completed frame was followed by a second text/tool frame
(one diagnostic test, seed 20270223). After the fix the live adapter returns
`Ollama stream contained data after its completion marker.` and does not emit
the late text or return the tool call. Empty lines remain accepted after the
marker. Earlier streaming events may already have been emitted before a later
framing error; the buffered experimental seam publishes no result on error.
Valid terminal-frame native thinking and tool calls remain in provider
continuation data, as exercised by the seam test. As before, a terminal frame
with a length stop is rejected as incomplete.

The reviewed working-source SHA-256 values were Ollama
`5fd8ae0a7454da69630a8377ac324e270db73c0853194c7a751b6801bbffe48b`,
MintBuffered `8fbc83ed4af2f85d0bc9709f7674bb6b62b6d5cd567dd9d2ce8b9eb362e6a657`,
MintText `f545aaeebd4e9d59a11028e2bf86a58c40f9ba9924483134f3f96a75b11a7c7c`,
MintDecision `d7751fcba4fff3be4fead630951c9cb4cf5fc5cf75901242e94838180aab2c6f`,
and independently reviewed seam test
`c27dffc7837741907fc597ffc7a104525b550739aa924403a41513c4bd4ec1b5`.
The independent exact-source graph passed 95 tests (seed 20270225), including
inverted reproductions for late tool calls and duplicate terminal markers; it
found no additional demonstrated component defect. A later test-only addition
explicitly checked blank lines and continuation (six seam tests passed, seed
20270225); its formatted SHA-256 is
`3b0bb1aea46916991b9d96430925fa9142d55182665a5c6775b55f00e032e163`.

The separately reviewable [standalone live fix](ollama-terminal-standalone.patch)
contains only the production terminal guard and its focused test, based on
commit `af5c590b35fa08ae639ddbd289b86dceb1b8bcc4`. Its patch SHA-256 is
`452d5c97990f0028314709a081b7ca1f70fc652fa2944358fe1718a038a6b00c`;
the [test source](ollama-terminal-standalone-test.exs) has SHA-256
`b6b8a6f4591a676f1b6a162bff99e4b207a4ef66a40ca61952e14f31b97e1b3a`.
The resulting standalone Ollama source SHA-256 is
`d8cc26924317612ad744b590a935805c4b76f639a1bd9287937c9d075ddd0172`.
The patch dry-ran cleanly against a fresh archive of that commit. A different
fresh private graph strictly compiled 134 project files and passed 99 tests
(seed 20270226), including the standalone test, provider and conformance
suites. The standalone patch has no experimental Mint dependencies. An
independent fresh graph applied the exact patch, verified the resulting hashes,
strictly compiled with the existing private native helper, and passed 99
terminal, conformance and completion-witness tests (seed 20270227).

## Host-view wire binding experiment

The unwired `Session.InferenceWire` derives target and serialized-body digests
from trusted host views for main, compaction, text helper, Ollama embedding and
local compatible decision requests. It compares a closed, typed fact set to the
facts provided at the adapter's send continuation. It is not called by a Session
route and is not a permission grant. Matching bytes do not bind the request phase,
model-service reservation, runtime parsing settings, source snapshot, policy,
consent, root lifetime or recipient; a future send barrier must validate those
separately and retain the necessary authority through the send. Synthetic tests
exercise phase restrictions, mutations, refusal, and compare host derivation to
real loopback bytes for each supported adapter.

The frozen source SHA-256 is
`a87e4b8dd4d1071f4a6e2f581b191c23da9cfc3ae6e9367067f94c70e92478bd`;
the pure binding test is
`6132ddfdaa7770f1e28f9a103450931177d85af5af3e2412e5897a252e7e6d40`.
The embedding and text/decision adapter tests have hashes
`cf9e3002e327a201d366c01f0d4fa53b0a596c9bfdf8681f56e79c65ec58dfc1` and
`933925b5f354e3c65a9b3d01f2201cfaa97722f134d9e050c6fda4c1b060f01f`.
The private graph passed 13 tests (seed 20270229); the preserved
[author rerun](inference-wire-author-rerun.log) has SHA-256
`7364a4f9e0d81a84803d724d115c01d36d5ac68ca971dc677597711a8367190d`.
An independent private graph passed those 13 cases and reproduced that phase,
native dimensions and timeout are not bound by wire equality. None of this
evidence qualifies live models, TLS socket cleanup, or the current host kernel.

After that run, tests added captured loopback bytes for compaction and helper
text, an explicit example of identical hashes across different phases and
native embedding dimensions/timeouts, and `Turn.dispatch_view` reconstruction
from synthetic compaction state. The unchanged module and these final tests
passed 16 cases (seed 20270302); the
[author log](inference-wire-author-final.log) SHA-256 is
`139cebf360b4185eda1ac54c5ab4243c017278efd954264244e62cfcc8676d5f`.
Final binding-test SHA-256 is
`51f337121b548a4da149c058ea7c7b5d8f5ffe30c5ec48488db361f28c02d770`,
and final text/decision test SHA-256 is
`25f9625524e2c23d9321b65105fb1cd83b8e1786df8e33b2c85e532b66ccc4e7`.
Those captured requests are not end-to-end Session dispatch tests; the final
test-only additions were not independently rerun.
