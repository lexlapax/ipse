# Owned loopback listener review, 2026-10-19

Historical implementation and verification record after `ee825bc`. Current
procedures belong to the [runtime training manual](../../developer/runtime-capabilities.md#check-a-directly-owned-local-listener)
and [native protocol](../../../native/README.md#observe-an-owned-loopback-listener).
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns milestone
acceptance. This generic protocol does not select a benchmark measurement backend
or establish complete evaluator/model coverage.

## Associate the endpoint with its directly owned process

The optional Linux stdio mode observes an exact IPv4 loopback listening tuple in
the supervisor's network namespace, associates its inode with the retained direct
child's descriptors, and checks the tuple again. The supervisor emits the native
P fact while it still owns that child. Child stdout remains opaque O data.
The fact is one observation; it does not guarantee subsequent availability or
confinement. Ordinary process-group cleanup retains its existing limits.

The public Runner option rejects malformed selections, unsupported platforms,
relative executable paths and incompatible sandbox policy before execution.
Ordinary stdio keeps its existing frame contract. The generic API creates no
durable attempt record; its caller owns intent and outcome persistence.

## Review the complete native and integrated paths

The first whole-native review found two identity errors. Reading the child's
network-namespace TCP table could associate a private unreachable listener with
an unrelated caller endpoint. An output-delivery error could reap the direct
child while a numeric proc-path inspection remained pending. The repairs use the
supervisor's TCP table and retain the unreaped child on that error path.

Root reproduced both defects using separately instrumented diagnostic copies.
The namespace barrier holds inspection until the fixture actually reports its
private listener ready. Eight reverted-source cases publish a false P fact;
eight repaired diagnostic cases and eight unmodified repaired-production cases
publish none. The unrelated caller-side fixture receives no request. Raw case
records confirm actual namespace readiness rather than relying on the compact
summary alone.

The output-loss probe closes only the supervisor's stdout while retaining its
owner input and holding an inspection pending. At the actual error-path wait
decision, the original path has reaped the killed child. The repaired path still
retains it unreaped. The diagnostic observer adopts and reaps only its own child
after helper exit. Instrumented sources are distinct from production sources.

Two subsequent independent contexts reviewed the complete integrated native,
Runner, verifier, fixture, CI and documentation unit. They established no further
production defect, but both found that the checked-in controls could miss the
two repaired paths. One also found the protocol manual's incorrect promise of
durable attempt retention. The wording is corrected, and checked-in diagnostic
tooling now reproduces both paths through temporary source copies and deliberate
reversals. Review found a further race in the diagnostic PID publication: the
observer could read an empty newly created file. The hook now completes a
temporary file before publishing it with an atomic rename.

Both contexts then reviewed the entire final unit and reported no open findings.
Root's corrected-tool execution passes all sixteen actual-ready namespace cases
and both output-loss controls. Unavailable namespace facilities produce an
explicit incomplete result rather than a pass. An independent evidence read
reconciles the raw namespace frames, all generated diagnostic-source and helper
hashes, and the retained output-loss records. Production source remains unchanged
by the tool. These contexts use the same model and do not establish model
diversity. Lead execution is separate from review.

## Exercise the public source and installed APIs

The Linux public verifier passes seven controls with two synthetic metadata
requests and zero inference requests. It covers directly owned and occupied
listeners, wildcard and delegated listeners, forged output, missing-listener
timeout and ordinary-mode compatibility. Every owned fixture has confirmed
Runner cleanup. The occupied server remains available after candidate refusal,
and receives a request only for the subsequent positive control.

Linux focused source tests pass 18 tests with 11 exclusions. macOS focused tests
pass 17 tests, skip the Linux-only case and retain 11 exclusions. Malformed and
unsupported selections create no execution marker. Five native parser tests
pass on Linux. The combined initial native/public evidence archive SHA-256 is
`8d0aefadf4abf0c478143825339de7f5164e415b69515e96951ca7af80c49379`.
Root independently checked the seven public controls and all 24 namespace cases
before archiving their records. The copied archive has the same hash locally.

An isolated Linux package build and extracted-runtime verifier pass. The installed
Runner passes the same seven controls with confirmed cleanup and zero inference.
Package SHA-256 is
`ef7a5246570023e4e80469254171d80f7b588b20669573e9bec368d330122d30`.
The fixture is compiled by the host before the release exercise. The installed
release uses its own runtime and helper; no model service or systemd is involved.

The final diagnostic/installed evidence archive SHA-256 is
`f86029214c3a396a28b8d4db6e884e76a256149da8efce75fc6edc1465b5c2a5`.
The independently reconciled copy has the same hash locally.

The complete macOS source suite passes 1,254 tests with one Linux-only skip and
34 explicit exclusions in 735.5 seconds. The strict stdio probe is enabled and
the 60-second per-test deadline is unchanged. Changed Elixir files also pass
the Elixir 1.18 formatter check.

The macOS native suite passes 30 tests with six exclusions in 25.0 seconds, and
four standalone Rust policy tests pass. Build, full formatting, strict compilation,
the demo, CI policy and documentation checks pass. The fresh macOS package and
extracted-runtime verifier pass. Its package SHA-256 is
`5bade8d0ddc39dc9462cb97a012ebf0eeb625fcf50421e42bf58069a910296f9`.
The installed public API and direct native mode both refuse the unsupported
listener capability before executing the selected command.

Exact-commit full Linux and hosted gates remain to be recorded separately for
this unit. The earlier sequencer's green gates do not cover the listener changes.
These results do not close P27's
held-out quality, exact aggregate memory, complete resource or engine-selection
gates. The user has reopened the memory definition and Linux/systemd backend
choice. Previous interrupted attempts and unknown liabilities remain unchanged.
