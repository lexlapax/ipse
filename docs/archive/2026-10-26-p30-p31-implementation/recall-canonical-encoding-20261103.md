# Reduce canonical encoding work without changing saved hashes — 2026-11-03

This focused optimization preserves the existing digest contract while reducing
repeated JSON encoding during saved-source reconstruction. It does not establish
the cause of the earlier populated-recall failure or qualify a successful
33-note turn. The [plan](../../plan.md) owns remaining acceptance.

## Measured finding and change

Pure reconstruction of retained synthetic sources separated cache lookup,
SourceWindow, Saved and action validation. All 34 original source hashes matched
the earlier archived manifests before and after reading. A 32-event source's
Saved reconstruction called `Jason.encode!/1` 107,226 times; SourceWindow alone
was below 1.5 ms. Reusing SourceWindow would address a small fraction of this
measured cost and was not promoted.

`Ipse.JSON.digest/1` previously started a new encoder for every map key and
scalar, building intermediate strings recursively. It now recursively sorts
stringified map keys into the existing maintained `Jason.OrderedObject`, encodes
the resulting tree once to iodata and hashes that iodata. Array order, key
ordering, duplicate stringified-key pairs and scalar encoding stay unchanged.
Admission bounds and source/consent/current-use checks are unchanged. No
dependency or timeout was added.

One pair of runs on the retained split-source fixture reduced initial cache
fill across 33 sources from **2,911,223 to 2,292,894 microseconds (21.24%)**.
Median Saved reconstruction for its first source fell from 126,858 to 97,270
microseconds. The runs had different process startup/cache state; they are not
a statistical latency bound or proof that an earlier turn timed out. Their
original runtime was already compiled and was not rebuilt from current HEAD.
The [measurement receipt](recall-canonical-encoding-20261103/receipt.txt) and
exact scripts/logs retain that provenance and the finer component timings.

## Compatibility and current-source checks

The candidate matched the historical encoder on 260 nested/scalar/escaping/
Unicode/numeric/key-collision cases, five invalid-value cases and all 1,270
events across the 34 retained sources. Before/after historical digest manifests
both have SHA-256
`313924804702f834b8ebf37c4715723d98f9559430911ae46963bf9a60b35e57`.
The added durable regression also covers unsupported structs and retains the
existing golden digests. Source review checked Jason's ordered-pair encoding
and duplicate-key behavior against the pinned dependency.

A separate lean snapshot contains the complete current host source at
`6fbbd90f` plus only this optimization. It uses existing local dependency caches
and the unchanged native helper. `mix compile --force --no-deps-check
--warnings-as-errors` compiled all 195 host/bundled modules successfully; this
is not a fresh dependency/native build. The [focused log](recall-canonical-encoding-20261103/current-host/focused.log)
reports **39 passed in 1.6 seconds**, seed 592749: JSON, source replay cache,
SourceWindow including actual Session/replay controls, and Saved/handoff.
Source, helper, test and runtime inventories matched afterward; the
[status](recall-canonical-encoding-20261103/current-host/status) records both
exits as zero. HOME stayed inherited and IPSE_HOME was synthetic.

Two launcher-only attempts used reserved zsh variables and did not execute the
tests. A subsequent 39-test pass lacked valid test/runtime preinventories, so
it was preserved and repeated with complete inventories. The verified result
above is that final run. Earlier measurement setup also stopped on an atime
comparison and rejected an unsupported strict CLI flag; their evidence is
preserved. None of these attempts resumed an uncertain workload or called a
model service.

## Evidence and next gate

The [manifest](recall-canonical-encoding-20261103/evidence.sha256), SHA-256
`7c6b35411eeb5e11a95f9bd719e9fabebd9249ece035500bc61e12d1a81edf00`,
covers the measurement scripts/logs, candidate patch, promoted-source hashes and
current-host checks. All entries verify. The first measurement runtime inventory
is explicitly after-only; the current-host run has its own before/postchecks.
Raw synthetic source journals remain in their original volatile fixture roots.
The [documentation check](recall-canonical-encoding-20261103/current-host/docs-check.log)
passed in a tracked-only mirror with 1,137 Markdown files, 9,445 links and zero
errors; no new operator procedure is introduced by this internal optimization.

One [fresh strict 33-note control](recall-canonical-encoding-20261103/fresh33/summary.txt)
then failed before the synthetic provider received a request. Its dedicated
listener started after seeding with a 180-second accept bound; this did not
exercise the separate workload-listener repair. The selected provider timeout
stayed at 5,000 ms and ordinary Worker deadlines stayed unchanged. All 37 Worker
inputs were delivered, a managed preflight and dispatch intent were recorded,
and request measurement reported failure after 14,195 ms. Runtime inventories
and all 33 original journal/lock identities and content hashes matched afterward.
Neither complete recall assertions nor idle reopen was established.

The fixture consumed completion while skipping the Session's separate error
notification. Its retained evidence therefore cannot establish the underlying
typed error, an effective transport deadline, or a timeout cause from that whole
request duration. The next distinct diagnostic must capture that notification
before another experiment. The failed turn is not replayed. Full integrated
workload, resource peaks, annual turnover, final suite and adversarial audit
remain open.
