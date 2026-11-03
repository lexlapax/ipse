# Synthetic egress diagnostic, 2026-11-03

A fresh instrumented 33-note Session failed, and its marker analysis was
**inconclusive**. A prior, separately seeded three-note control passed and
validated the positive marker chain. This diagnostic does not identify the
cause of the earlier [combined-source failure](recall33-combined-dcbb-20261103.md)
or qualify a 33-note or populated journey.

## Setup and limits

The disposable test host was built from commit
`dcbb07dd451f1402d28391b716b2b177e35331a7`, with the generic batching
candidate withdrawn and the archived strict synthetic fixture patch applied.
The test-only host adds markers at managed Session admission and transport
boundaries. They contain monotonic timestamps, process and synthetic job
references, allowlisted result classes and listener byte counts; they do not
record request bodies or credentials. The host changes and fixture instrumentation
are archived as evidence only and are not a proposed product patch. Marker
writes and acknowledgments can perturb scheduling and deadline outcomes, so
these timings are not equivalent to an uninstrumented build.

The launchers used fresh owner-only synthetic fixture roots, source Sessions and
consent, left `HOME` unchanged, cleared relevant inherited VM/loader overrides,
and fingerprinted the test source, dependencies, compiled runtime and bundles.
They used the normal Worker deadlines and an explicit 5,000 ms provider timeout;
the longer PTY and ExUnit bounds cover fixture setup only. Project compile with
warnings as errors succeeded. Dependency compilation emitted third-party
warnings and updated the generated telemetry Rebar `source.dag` cache; both
pre- and post-build fingerprints and the first failed comparison were retained.
The captured fixture log intentionally contains only root/status lines and a
failure label, not the full test transcript or exception details. No attempt
was retried.

## Small control

One fresh three-note Session passed the existing fixture. Its offline marker
validator found one Session owner/job, matching gate and send producer barriers,
a same-process transport chain, acknowledged listener bytes and zero dropped
markers. Source, dependency, runtime and bundle postchecks passed. A separate
offline analyzer classified the marker chain as a local Mint send return with a
listener-received body. Three offline negative controls, each derived from
redacted control markers, returned inconclusive when the transport barrier or
listener terminal was removed or the send marker duplicated. These controls
validate the instrumentation only; they are not 33-note evidence.

## Fresh strict attempt

The separate strict fixture created 33 synthetic source Sessions and recorded
its one-shot intent before the prompt. The test failed; its output filter passed,
the analyzer returned `classification=inconclusive`, and the source and runtime
postchecks passed. Independent read-only comparison found all 33 distinct source
journals and lock files had their original device/inode/owner identities and
journal hashes, with no held journal path.

The redacted markers show a successful gate and then entry into managed-current
use for the same Session owner/job on the transport process. The listener
reported its initial read closed without bytes. The gate interval was about
2.797 seconds; listener closure was about 4.992 seconds after current-use entry
in this instrumented run. No current result, send result, transport terminal
state, or send/transport producer barrier was captured before the sink closed.
There were zero reported dropped markers, but those missing terminal barriers
mean the capture is incomplete. The markers therefore cannot establish why the
task or connection ended, whether an unrecorded later request call occurred, or
whether a product deadline was responsible. No uninstrumented timing or causal
claim follows from the proximity to the configured timeout.

The [evidence manifest](egress-diagnostic-dcbb-20261103/evidence.sha256) has
SHA-256 `150ee1597ea23660f93932ae042d6808844588be6f0694beebb90393f5f20e80`
and covers the exact test-only sources, launchers, manifests, redacted markers,
checks and results. The full built runtime and fixture roots remain in volatile
synthetic storage rather than this archive; the manifests alone cannot verify
those artifacts after they disappear. The [current plan](../../plan.md) owns
milestone status.
