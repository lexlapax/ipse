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

## Subsequent exact-commit Linux verification, 2026-10-19

The separate checkout at `51e21f3485c5333907864cb565da33889aa9552d` passes the full
Linux suite with native sandbox tests enabled: 1,272 pass and 17 are excluded in
658.7 seconds. The two optional `memory_scope` tests remain excluded while the
measurement design is reconsidered. Build, formatting, strict compilation,
documentation and CI policy checks pass. All six sequence tests, five listener
parser tests, seven public controls and both causal regression families pass.
The source checkout remains clean at the exact commit.

The initial archive collector expected the count from a run that also included
the two memory-scope tests. Its count assertion failed after the successful
suite. The corrected collector reads the actual summary, verifies the complete
1,289-test inventory and recorded inclusion/exclusion tags, and checks the public
cleanup and causal records. No tests were rerun for that collector correction.
The retained Linux evidence archive SHA-256 is
`120e2e87b0a56c44a62987fecf811e1378c5532dd19e2459c11c827b026d1a83`.
The locally retained copy has the same hash. These are synthetic controls with
zero inference requests and no model service or cgroup benchmark launch.

Hosted gates remain to be recorded separately for this unit. The earlier
sequencer's green gates do not cover the listener changes.

## Subsequent hosted result and PID namespace finding, 2026-10-19

The [hosted matrix for `51e21f3`](https://github.com/lexlapax/ipse/actions/runs/39353971227)
passes on Ubuntu and macOS. Both source jobs report 1,289 tests with zero
failures and 34 exclusions; macOS also skips the Linux-only listener case.
The source suites take 907.3 seconds on Ubuntu and 813.8 seconds on macOS.
The macOS native suite reports 36 tests, zero failures and six exclusions in
26.5 seconds. Package checks and every independent installed proof pass on
both platforms. These results cover that commit, not subsequent repairs.

A later independent audit found an uncovered identity assumption. Numeric
`Child.id()` follows the supervisor's PID namespace, while `/proc/PID/fd`
follows the namespace used by the procfs mount. An inherited ancestor procfs can
therefore inspect another process despite the direct child remaining unreaped.
An isolated live probe on the unmodified `51e21f3` helper reproduces a false `P`:
the selected child has ancestor PID 2134216 and local PID 2134212, while the
separately retained fixture at ancestor PID 2134212 owns socket inode 80548456.
The emitted fact names that local PID and the foreign socket inode. The probe
uses fresh user/PID namespaces, records the private counter and both identities,
makes zero HTTP requests, and confirms cleanup of its owned init and fixture.
Passing earlier gates does not close this finding.

The correction checks a bounded `/proc/self/status` before launch,
requiring exactly one positive `NStgid` value equal to the helper's process ID.
The same live mismatch probe against the corrected helper refuses with
`owned listener requires matching procfs and PID namespaces` and emits no `P`.
Six pure native tests pass, including malformed, duplicate, oversized and
multiple-namespace status controls. The corrected listener source SHA-256 is
`851af8ae12e6454307d95b596675861784552c933a9a27306fd7a5c73ebe6511`.

The final regression command now includes three live PID/procfs controls using
an uninstrumented helper. Inherited procfs must refuse before the selected
executable's marker, ordinary stdio must execute in that setup, and an owned
listener must succeed in a nested PID namespace with a privately mounted procfs.
All three pass on Linux and through the extracted package helper. The integrated
command also passes the existing sixteen network-namespace cases and both
output-loss controls. Missing namespace capabilities remain incomplete, never a
pass. Independent final source review of the whole unit and manuals has no
findings. The reviewer did not run tests.

The Linux focused suite passes 18 tests with 11 exclusions in 13.1 seconds.
The public API's seven controls pass in source and extracted-runtime execution,
including confirmed cleanup. The fresh package's standard verifier passes.
Package SHA-256 is
`657caa279e90036904b80d74e511f1b2205d3c561d33cb157ded427f1931cc0f`.
The first installed-check driver created its private evidence directory with
mode 0755. The verifier rejected that mode before fixture execution. Correcting
the directory to 0700 and rerunning only that exercise passes; the original
failure log remains in the evidence.

Root reconciled the before/after raw facts, both cleanup receipts, public
summaries and all three sets of PID controls. The retained evidence archive's
SHA-256 is
`4ff5ac09e56e66aaff320c847e501729dc414dadc63d53ccfe740ce2310cd9f4`.
The copied archive has the same hash locally. These are synthetic listener
checks with zero inference and no model service, systemd or cgroup launch.
The local macOS focused suite passes 17 tests with one Linux-only skip and 11
exclusions in 12.9 seconds. Changed Elixir tooling passes both current and 1.18
formatting. The complete macOS baseline passes 1,254 tests with one Linux-only
skip and 34 exclusions in 725.7 seconds. Build, full formatting, strict
compilation and the demo pass. The strict stdio probe remains enabled and
the per-test deadline stays at 60 seconds. The documentation check reports
257 Markdown files, 2,764 local links and zero errors. This record does not
claim a hosted result for the correction.
