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

At initial publication, Linux's complete synthetic GPU audits and native-enabled
full suite were still running. The following section records their terminal
results and the subsequent first private preparation refusal. No engine is selected.

## Preserve the first private preparation refusal

At `41314b7ac600b91b054355549585bd3c3ae8577f`,
[hosted run 39647137696](https://github.com/lexlapax/ipse/actions/runs/39647137696)
passed Ubuntu and macOS, including the applicable native, package and installed
checks. The corrected Linux snapshot passed 1498 tests with 19 excluded, all
26 source and installed model-service cases, and both source and installed
350-row synthetic GPU populations. Both populations passed complete native
execution/resource audits and retained unchanged source. Their scripted responses
and memory measurements do not establish real-model quality or resource use.

After those gates passed, only the independently committed corpus, questions and
manifest were staged at the frozen input location. Reference answers remained
sealed. The first private execution used source `41314b7` and local seal SHA-256
`c35b158ad87ad5da2f5954496777e261b05c624cff2a60210ff55fd37d085a1b`.
Its preparation process started, then refused with `native_authority` before the
domain claim, dataset read or inference. The native root and preparation receipts
confirm cleanup. There are no predictions. The public measure and read-only
audit commands both exited 1 with `measured_evidence_unavailable`, because the
prepared population file was absent. The observer's exit 0 records completed
observation, not successful execution. The failed seal remains preserved and
must never be replayed or have its claims reset.

Two independent investigations traced inconsistent command bytes to
`MeasuredExecution.validate_precompiled!/1`. It serialized module bindings from
an atom-keyed map without canonical ordering. Identical BEAM files generated
different bootstrap bytes in fresh VMs with different atom allocation histories.
A regression against the actual captured runtime reproduced the difference.
Sorting the unique bindings by module name makes that regression pass while
preserving role load order and every identity check. The synthetic proof also
needs the public reopen path before another private admission; the earlier proof
started measurement directly in its existing VM and missed that transition.

The repair is committed at `7bffee05e4ec9fa4730d608e0fa0cc7297b5a815`.
Local proofs used the same 439 runtime/tooling files, inventory SHA-256
`0caed5ca6e918f624130dff43bcdde5bfd33f39d5c04e62002f933f08b8f4cfe`.
Their documentation receipts can predate that commit; hosted CI checks its exact
checkout.
Both source and installed public-reopen proofs pass all 350 scripted rows,
complete native audits, scoring controls and refused replay. Their prediction
hashes match. The macOS baseline passes 1451 tests, with one skipped and 36
excluded, plus build, formatting, strict compile, demo and documentation checks.
The supported Elixir 1.18/OTP 27 exercise passes after repairing its isolated
snapshot's missing Git metadata; the failed setup receipt remains retained.

The native-enabled Linux full suite passes 1499 tests with 19 excluded in 957.7
seconds, followed by an unchanged source inventory. The
[exact-commit hosted checks](https://github.com/lexlapax/ipse/actions/runs/39656829334)
pass Ubuntu and macOS, including their applicable native, package and installed
proofs.

A fresh inert source/configuration seal was prepared without dataset members or
inference. After all gates passed, only the same committed corpus, questions and
manifest were installed for one new admission. Its seal SHA-256 is
`aa17f45e1a272c8b82cab45b14d075383546ece5e09fd91e4e4662e3e2f1b582`.
Native preparation admitted and completed; the first cell is running. Reference
answers remain sealed. The actual comparison still requires all 350 first
outcomes, complete charged-RAM audit and subsequent independent semantic review.

The [2026-10-22 terminal record](../2026-10-22-p27-private-comparison/index.md)
preserves the subsequent 350 first outcomes, audit-capacity failure and effective
context-window diagnosis. The admission state above is historical; the execution
is no longer running and P27 acceptance remains open.
