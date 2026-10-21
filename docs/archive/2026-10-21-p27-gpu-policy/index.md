# P27 explicit NVIDIA evaluation policy, 2026-10-21

Historical implementation and diagnostic record for the increment after
`bfc388f4f01504f682a5881436221ab159146b0d`. P27 remains open. Current procedures
belong to [evaluation training](../../developer/knowledge-evaluation.md),
[testing](../../developer/testing.md) and the
[dependency inventory](../../developer/dependencies.md). Acceptance belongs to
[the plan](../../plan.md#p27-optional-research-graph-and-rag).

## Bind one explicit choice through the existing owners

The user reported that the GPU host had rebooted and Ollama should work again.
Read-only checks found a responding NVIDIA driver, version 615.78.08, on a
GeForce RTX 3060 Ti with 8192 MiB. No driver installation, host repair, existing
service change or model download occurred.

The previous service selection and portable declaration both required CPU-only
execution. Two independent design candidates and a cross-review selected the
existing `--resolution` input for an explicit NVIDIA choice. `Freeze` projects
only `nvidia_visible_mixed_v1` into the portable experiment. The local execution
seal binds one full physical GPU UUID. `ModelService` changes CUDA visibility,
retains all other isolation controls and admits positive partial residency on
every final resident model. The old version-one CPU selection remains supported.
No new CLI flag, package dependency or native collector was added.

Offline measured audit uses the same resident and capability validators as live
admission. It checks the sealed configuration digest, reconstructed environment,
selected models and retained observations. These checks establish neither
placement throughout the lifetime nor the placement of an absent model. The
approved resource metric remains kernel workload-charged RAM and excludes VRAM.

## Retain the scoped review and corrections

Two independent implementation reviews reproduced one defect: the new saved
inventory verifier accepted missing or malformed model capabilities. The repair
shares `model_row!/2` between live admission and offline audit, preserving exact
keys, selected digests, capability requirements and canonical model order.
Both correction reviews accepted valid evidence and rejected the reproduced
malformed cases, with no further findings in their scoped rereads. These were
source reviews and local probes, not whole-P27 or external acceptance.

A whole-document editorial review read the affected contributor chapters and
operator procedures. It corrected the installed service-case expectation to 26,
recorded the optional existing NVIDIA driver and inspection utility, made the
UUID example explicit and broadened the synthetic proof's device-placement
limitation. The private workload stayed sealed throughout.

The subsequent Linux public proof ran all 26 service cases, then failed because
its outer `Scenarios.validate!/3` still expected 21. This is an integration defect,
not a model or GPU failure. Its failed output is retained separately from later
verification. The correction now passes source and installed 26-case proofs.
A named boundary regression accepts the full population and rejects stale,
missing, duplicate and failed-case reports. A scoped correction review found no
further issue.

## Observe one exposed answer on the repaired GPU

The [trial result](exposed-trial.json) and
[allowlisted accounting summary](exposed-accounting.json) retain exactly one
already exposed lexical Q02 request. The trial used pinned `qwen3.5:9b`, verified
enabled default thinking, the unchanged production instructions/input/schema,
version-three 600000 ms allowance and 8192 output tokens. Its stopping rule
allowed one admission regardless of outcome, with no retry or automatic batch.

The first response decoded. Canonical accounting records 28620 ms, 1368 input
tokens and 445 output tokens. A separate reasoning-token count is unavailable.
The complete service lifetime took 47147 ms. Final residency reported model size
6152372875 bytes and VRAM size 4951900157 bytes, which is partial placement.
Policy audit passed. Session, native and staging cleanup were confirmed, and
source stayed unchanged.

This diagnostic used 439 inventoried source files with SHA-256
`25b3c422e18504a16ac9e030971caa44ee49b8f44e0f0efbe7195eb45d36034f`,
the uncommitted GPU candidate atop `bfc388f`. It is a viability observation,
not independent semantic grading, a quality comparison, a runtime forecast or
an exact memory comparison. No private inputs were opened.

The first preparation refused before build or inference because macOS metadata
doubled the source inventory. A fresh Git archive plus the exact tracked patch
reconstructed the intended source without that filesystem metadata. The refused
preparation remains separate and consumed no actual inference admission.

## Keep platform evidence attached to its source

The earlier [hosted run for bfc388f](https://github.com/lexlapax/ipse/actions/runs/39637377537)
passed Ubuntu and macOS, including their applicable native, package and installed
checks. It resolves the prior single-test watchdog gate. It predates this GPU
increment and does not certify its changed source.

The [verification receipt](verification.json) separates the original GPU
candidate from the subsequent proof-validator correction. The original macOS
full suite passed 1450 tests, with one skipped and 36 excluded, followed by the
demo. Supported-floor build, formatting, strict compile, 56 focused tests and
macOS native enforcement passed. A fresh package from the corrected snapshot
passed its installed package and model-call proofs; source and installed service
proofs confirmed unsupported-backend refusal before effects on macOS.

Linux's complete synthetic GPU audits and native-enabled full suite are still
running. Final source/config
freeze, all 350 first actual predictions, complete charged-RAM audit, independent
semantic review and individual strategy qualification remain open. No engine is
selected.
