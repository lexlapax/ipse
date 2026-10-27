# Open independent review findings, 2026-10-27

Historical working record; the [plan](../../plan.md) owns current status. These
reviews are partial and do not constitute the requested final adversarial audit.
They inspected the uncommitted SDK-v3 and egress prototypes alongside the
committed source, without executing native publication tests.

## Managed first publication

The first-root witness records a verified historical publication, not continued
root freshness. The reviewed contract activates Identity after child locks are
released. Ordinary authorized SDK writes acquire the outer Identity lock, so
the review did not establish an exposed concurrent-writer bypass. Direct trusted
Core calls to Collection have different authority and are not evidence that a
worker can bypass that lock. A deterministic competing-Session test must still
pause after postproof, verify that a second authorized writer cannot publish
before Identity activation, and verify the historical first-root binding after
a later write. Native Identity lock acquisition uses nonblocking `flock`, so a
contending attempt may refuse rather than wait.

A later disposable-graph diagnostic inserted a test-only pause after the first
postproof view closed. The competing authorized Session was refused on Identity
lock contention and did not advance the collection; after activation a third
Session advanced it while the historical first-root entry remained unchanged.
The [single-test output](kernel-7.2.11/compete-diagnostic.log) reports one pass
and 22 exclusions, seed 20261229. The [historical instrumentation](kernel-7.2.11/compete-instrument.exs)
is retained for inspection, not as a runnable project test; it modified only a
private graph and hard-codes that temporary path. Its SHA-256 is
`57641b2cc1d438fd51fc87a186f99877c5602c57465100350406d2df9dec13e7`;
the output SHA-256 is
`1f2122039237b517e30f675f2d1c70f46e4e3224a8643533bfaf4bb9c7184fd2`.
This used the same unqualified test-only 7.2.11 helper described below and
instrumented source, so it is neither a supported-host pass nor an unchanged-source
regression test. A durable unchanged-source test remains open.

The postproof opens the format MAC and compares changed records' operation,
revision and value hashes to the captured host normalizer output. It does not
independently reopen each changed-page MAC. The developer manual was corrected
to make that distinction. Corruption and substitution of changed pages, native
owner loss after postproof and during activation, and failure of final Consent
settlement remain to be exercised at those exact boundaries.

One subsequent owner-loss control was added to the uncommitted Session test.
Its first ordinary run refused during setup on the unsupported kernel, before
the fault hook. A separate disposable graph compiled a private helper with a
test-only exception for the exact host release `7.2.11-arch1-1` and rebuilt its
private application to bind that helper. The selected synthetic test then
passed **1 test, 21 excluded** (seed 20261227), closing the Collection native
owner at the first post-publication read and observing a durable generation,
prepared Identity, unknown outcome, retained liability and inert resume. See
the [test output](kernel-7.2.11/postproof-experimental.log) and
[private compile output](kernel-7.2.11/postproof-experimental-compile.log).
The test source SHA-256 is
`4eb6a410e54f356956efb738e3a7b61ee2040d3436b3bd5561b6152806dbb0e9`;
the private helper SHA-256 is
`05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`.
The log SHA-256 is
`22b0d576c7678be2fabee82e5b0ff2fb5718ea33b13f349c9455a46a2f732bea`.
This is a functional diagnostic under an **unqualified test override**, not a
supported-host pass or evidence that the production profile is safe. It does not
cover a post-close competing Session or owner loss during Identity activation.

## Inference egress prototype

The uncommitted gate executes before `Finch.stream_while`, which can subsequently
wait for connection checkout, DNS, connection, TLS or proxy setup. A policy or
source change during that wait can therefore precede sending request bytes. The
existing local transport tests establish only their named direct controls, not a
final current-authority barrier. The gate also reports a wire-body digest to its
verifier without independently binding it to a host-derived expected body, and
the existing Session source snapshot is not an authoritative managed-root read.
Registered and unregistered paths both need coverage. No Session integration or
claim of protected inference egress follows from the prototype.

A subsequent local diagnostic reproduced the connection-wait gap with a
loopback TLS server: the gate accepted while a synthetic policy was enabled,
the server paused before its TLS handshake, the test disabled that policy, and
the server then received the previously admitted fixture body. The focused
private-graph run reported **7 passed**, including this deliberate reproduction
of the defect, using seed 20261225; its [output](kernel-7.2.11/egress-gate-tests.log)
does not establish a security pass. It used Elixir 1.20.4/OTP 29 and the
uncommitted prototype: gate source SHA-256
`8f3db327dadc7fc9fdf4109c3048db89f3cd95d14a23bb5ce6e28bcf6a7a0d1d`,
transport source `3e408c926489e059dd6e5e9f754be63a18a738c63506c997620d4ff14faca38f`,
and test source `8197559debc553d788a8dd81254537c7effe2bf62946a61f3c41cccaa7053e1c`.
The output SHA-256 is
`1577310c04ec059519dea5533b82cf43fd117ac1f20ee449d5e3fe0386eff01b`.

After that reproduction, the uncommitted gate was tightened to require the
caller's expected body hash and reject a mismatch before invoking its verifier.
The updated direct gate, witness, embedding and decision transport regression
run passed 30 tests (seed 20261228); the deliberate TLS reproduction still
passes because the timing gap remains. This comparison does not establish that
the expected hash comes from the Session's admitted input, and the gate is not
yet installed on Session inference paths.

One possible maintained seam is Mint's public connect followed by a final check
and request, but direct Mint use would need a declared dependency, bounded
response and lifetime handling, equivalent TLS and proxy behavior, and failure,
cancellation and connection-wait tests. Connection setup itself can expose
destination metadata. A concurrent-revocation linearization rule and current
root validation are required regardless of transport; a narrow timing interval
alone is not a proof. This is a design lead, not an approved or implemented fix.

## Linux 7.2.11 qualification

Independent static review compared the downloaded upstream v7.2.10 and v7.2.11
`fs/btrfs/file.c`, `fs/btrfs/extent_io.c`, `fs/btrfs/ordered-data.c`,
`mm/shmem.c`, `mm/filemap.c`, and `fs/stat.c` copies and found each pair
byte-identical. The reviewed Btrfs successful buffered-write path moves new
delayed-allocation accounting to inode accounting under the same inode lock used
by `getattr`; the reviewed tmpfs non-VMA buffered-write path under the tested
mount and global policy does not select huge orders. These observations do not
authenticate the running Arch kernel or establish the complete allocation bound.

In particular, Btrfs error cleanup can clear `EXTENT_DELALLOC_NEW` without the
successful transfer to inode bytes. The timing of page and extent reclamation
relative to that clear needs a complete trace and isolated writeback and
allocation failure tests. This is an unresolved proof gap, not a demonstrated
defect. The earlier successful-write kill probe cannot establish that property.
The user authorized continuing qualification on 7.2.11; the profile remains
unchanged and fail-closed. A private user/mount namespace can mount a disposable
tmpfs here, but `/dev/loop-control` and `/dev/mapper/control` were absent in the
checked environment. No Btrfs fault injection was attempted on the user's
filesystem. See the [recovery record](kernel-profile-recovery.md) for the
source and preliminary probe provenance. A later
[partial-write diagnostic](kernel-7.2.11/partial-probe.md) observed stable counts
after a completed or size-limit-failed write, but did not inject Btrfs I/O
failure or interrupt a write system call.

## P30 fixture recheck

An independent isolated graph repeated ten P30-focused suites with seed
20261226 and max-cases 2. The [output](p30b-recheck-2026-10-27.log) reports
**53 passed**, exit 0, using local fixtures only. It covered decision types,
wire transports, configuration, usage, Session and replay controls, and the
pure Knowledge decision policy. The log SHA-256 is
`62334bf68b8902f603b065b8ea8ebc4f9aec731bd060fba8d04c54565404ff01`.

The run used `MIX_ENV=test`, `mix test --no-compile`, copied BEAM outputs from
the reconstructed graph, and a private copy of the helper. It included the
uncommitted egress prototype and did not independently establish source-to-BEAM
identity for the complete graph. It was not the clean fixed-source P30B baseline,
a live-engine qualification, a protected helper test, or a final egress test.
The selected suites were `test/ipse/decision_test.exs`,
`test/ipse/provider/decision_test.exs`,
`test/ipse/provider/decision_transport_test.exs`,
`test/ipse/config/decisions_test.exs`,
`test/ipse/config/decision_loading_test.exs`,
`test/ipse/usage/decision_test.exs`,
`test/ipse/extension/decision_call_test.exs`,
`test/ipse/extension/decision_capability_test.exs`,
`test/ipse/extension/decision_session_test.exs`, and
`test/extensions/knowledge/decision_policy_test.exs`.
