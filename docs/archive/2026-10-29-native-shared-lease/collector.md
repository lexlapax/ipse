# Inert native lease collector

Dated 2026-10-29. This is an isolated Linux building block, not admission to
use protected content. The correction and managed-result paths remain disabled.
The [plan](../../plan.md) remains authoritative.

The new `--lease-collect-v1` mode accepts an operation's ordered list of up to
131 expected lock identities and helper endpoints. It pins each helper with a
pidfd, compares the helper executable's inode with its own, checks Unix peer
PID and UID before sending the supplied one-use secret, and validates and owns
the received descriptors. Duplicate lock identities refuse. It holds the
descriptions until `C`, EOF or deadline in the original normal-flow controls.
The later [independent review](collector-independent-review.md) found that a
blocked stdout response could prevent EOF/deadline cleanup. The
[repaired cohort](#follow-up-bounded-response-and-exhaustion) uses nonblocking
response writes and has targeted backpressure controls.
The caller, not the collector, must establish secret freshness and one-use
operation binding. `L` only reports that the descriptors
were collected; it is not a liveness or authorization proof. `C` reports the
collector has closed its own copies, not that every holder has closed. The
mode cannot write to a terminal or worker destination.

The limit reflects `StoredSources` accepting up to 128 distinct proofs, each of
which can belong to a different inactive Session, while the consuming live
Session has its own separately held lock even when none of the proofs is local.
Identity and Consent add two more. The 131-lock test uses 128 source helpers,
one source-helper **stand-in** for that live lock, and two Transaction helpers.
It does not demonstrate a live Session handoff. A separate control exports two
different retained stack slots from the same Transaction helper.

The [focused controls](evidence/collector/collector-controls-v8.log) passed
for two retained descriptions, mismatched inode, a different executable,
duplicate identity, loss of the controlling input, and deadline expiration.
The [capacity control](evidence/collector/collector-capacity-v3.log) and
[same-Transaction control](evidence/collector/collector-nested-v1.log) passed.
The control-loss result is about releasing this inert collector's descriptions;
it does not establish output cancellation or an atomic owner-death boundary.

The [first compilation](evidence/collector/collector-compile-first.log) failed
because the new syscall declaration differed from an existing declaration; it
was corrected. The first focused runs exposed a buffered-stdin framing failure
([v2](evidence/collector/collector-controls-v2.log),
[v3](evidence/collector/collector-controls-v3.log)) and then a premature peer
close that could turn an acknowledgement into an unknown helper outcome
([v4](evidence/collector/collector-controls-v4.log)); the final controls use
direct nonblocking input and retain peers through collection.

The unignored [complete source snapshot](evidence/collector/source-v8.tar),
the [manifest](evidence/collector/manifest-v8.sha256), helper and fixture
binaries in `_build/shared-lease-sol-20261029/`, and the prior
[compiler and platform provenance](evidence/export/rustc-v9.txt) identify the
cohort. The focused build and test commands, run from the repository root on
the recorded Linux host with synthetic private homes, were:

```sh
rustc --edition=2021 -D warnings native/ipse-runner.rs -o _build/shared-lease-sol-20261029/ipse-runner-collector-v7
rustc --edition=2021 -D warnings dev/fixtures/transaction_lease_export.rs -o _build/shared-lease-sol-20261029/transaction-export-collector-v8
task_dir=$(mktemp -d /tmp/ipse-collector-v8-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-collector-v8 --collector-controls "$task_dir" _build/shared-lease-sol-20261029/ipse-runner-collector-v7
task_dir=$(mktemp -d /tmp/ipse-collector-131-v8-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-collector-v8 --collector-capacity "$task_dir" _build/shared-lease-sol-20261029/ipse-runner-collector-v7
task_dir=$(mktemp -d /tmp/ipse-collector-nested-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-collector-v8 --collector-nested "$task_dir" _build/shared-lease-sol-20261029/ipse-runner-collector-v7
```

These controls do not prove malformed ancillary cleanup in the actual collector,
same-executable process substitution defenses across `exec`, all-leases
operation binding, or deadline bounds for filesystem validation and response IO.
They do not prove that the process checks remain true after an `L` frame: death
can race any final observation. No output-capable admission or authenticated
final-holder completion exists. An already-running legacy `--lock` holder cannot
be migrated by closing and reacquiring: that would leave a gap. Future eligible
Sessions must acquire an export-capable lock from initial startup, or another
gap-free mechanism must be independently proved. The current Session still
uses the legacy holder.

## Follow-up: bounded response and exhaustion

The independent review identified a blocking `L` write in the original cohort.
The repaired collector sets stdout nonblocking and writes response frames while
polling the control input and the same collection deadline. The
[fault controls](evidence/collector/collector-faults-v2.log) exercised owner
loss during partial request parsing, connect retry, partial collection and a
test-hook-stalled real exporter. They filled the collector output socket before
launch, observed the collector reaching its response boundary, and verified
that both controller EOF and deadline expiration stopped the collector and
released its received lock. The hook exists only in the separately compiled
test helper. These are collector lifetime controls, not proof of terminal or
worker cancellation or of bounded filesystem calls.

The same control set imposed `RLIMIT_NOFILE=16`, obtained a successful first
transfer, then forced exhaustion. The fourth exporter reported `U` (unknown)
when its sent descriptor could not be acknowledged; after the collector and
original holders exited, the synthetic contenders acquired all locks. A
collector holding 131 leases retains 131 pidfds, 131 peer sockets and 131
received lock FDs: with only the standard three descriptors that is 396 open
FDs, before any inherited or transient descriptors. A 256-FD process limit is
therefore insufficient at full capacity. Sockets are retained because closing a
peer immediately after its ACK can race the exporter's ACK read and turn the
result unknown; no authenticated exporter-completion protocol exists yet.

The [repaired positive controls](evidence/collector/collector-repair-controls-v2.log),
[131-lock control](evidence/collector/collector-repair-capacity-v2.log) and
[nested Transaction control](evidence/collector/collector-repair-nested-v2.log)
also passed. The [unignored source snapshot](evidence/collector/repair-source-v2.tar)
and [hash manifest](evidence/collector/repair-manifest-v2.sha256) preserve the
cohort. The original v8 snapshot and failed controls above remain historical
evidence. Commands, run with the recorded compiler from the repository root:

```sh
rustc --edition=2021 -D warnings native/ipse-runner.rs -o _build/shared-lease-sol-20261029/ipse-runner-collector-repair-v1
rustc --edition=2021 -D warnings --cfg ipse_lease_export_test_hook native/ipse-runner.rs -o _build/shared-lease-sol-20261029/ipse-runner-collector-fault-v1
rustc --edition=2021 -D warnings dev/fixtures/transaction_lease_export.rs -o _build/shared-lease-sol-20261029/transaction-export-collector-repair-v2
task_dir=$(mktemp -d /tmp/ipse-collector-faults-v2-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-collector-repair-v2 --collector-faults "$task_dir" _build/shared-lease-sol-20261029/ipse-runner-collector-fault-v1
task_dir=$(mktemp -d /tmp/ipse-collector-repair-controls-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-collector-repair-v2 --collector-controls "$task_dir" _build/shared-lease-sol-20261029/ipse-runner-collector-repair-v1
task_dir=$(mktemp -d /tmp/ipse-collector-repair-131-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-collector-repair-v2 --collector-capacity "$task_dir" _build/shared-lease-sol-20261029/ipse-runner-collector-repair-v1
task_dir=$(mktemp -d /tmp/ipse-collector-repair-nested-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-collector-repair-v2 --collector-nested "$task_dir" _build/shared-lease-sol-20261029/ipse-runner-collector-repair-v1
```

Freshness and uniqueness of endpoint names and secrets remain obligations of a
future trusted host; this collector merely rejects all-zero values. Its peer
checks do not establish helper mode or rule out an `exec` after observation.
An incomplete response remains unconfirmed. There is still no all-leases
admission, payload or destination binding, output fence, authenticated
final-holder completion, or live legacy Session migration.

The later independent review confirmed the nonblocking response repair and
the recorded fault controls. It also identified an integration constraint:
`F_SETFL` changes the shared open-file description, so a caller must provide
dedicated private control descriptors rather than share them with an unrelated
terminal or process. The collector does not itself enforce that contract.

For a fresh-checkout reproduction of the focused fault controls, extract the
saved cohort rather than compiling whatever happens to be in the working tree.
The following was independently run on 2026-10-29; the
[result](evidence/collector/independent-repro-faults-46985.log) contains all
seven fault markers. The snapshot and log must be included in the eventual
commit; unignored files are not automatically tracked.

```sh
cohort=$(mktemp -d /tmp/ipse-collector-repro-XXXXXX)
mkdir "$cohort/out" "$cohort/faults"
tar -xf docs/archive/2026-10-29-native-shared-lease/evidence/collector/repair-source-v2.tar -C "$cohort"
rustc --edition=2021 -D warnings --cfg ipse_lease_export_test_hook "$cohort/native/ipse-runner.rs" -o "$cohort/out/ipse-runner-fault"
rustc --edition=2021 -D warnings "$cohort/dev/fixtures/transaction_lease_export.rs" -o "$cohort/out/fixture"
"$cohort/out/fixture" --collector-faults "$cohort/faults" "$cohort/out/ipse-runner-fault" > "$cohort/out/faults.log" 2>&1
```

The reproduction is limited to those fault controls; it does not repeat the
131-lock capacity run or establish a production output admission.
