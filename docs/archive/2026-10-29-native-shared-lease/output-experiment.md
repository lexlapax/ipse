# Leased pipe output experiment

Dated 2026-10-29. The ordinary native helper refuses `--lease-output-v1`;
this is not a supported feature, Session integration, or P30/P31 acceptance.
The [current plan](../../plan.md) remains authoritative. Both affected user
paths stay disabled.

A test-only build can run an experimental native pipe writer. It receives a
bounded immutable payload, operation ID, expected destination and owner pipe
identities and ordered lease identities on its Host control. It collects the
leases using the prior collector checks, reports collection, then waits for a
separate activation with the exact ID. It polls the Host and a separate owner
control and the exporter pidfds during bounded writes; it closes its destination
and lease copies before reporting a completed or unconfirmed outcome. This
protocol assumes a trusted caller supplies an authentic, fresh operation and
the exact control and destination descriptors. A synthetic pipe used as the
owner control does not prove that a real BEAM Session or Host owns that pipe.

The [focused controls](evidence/output/output-controls-v4.log) observed exact
successful output after activation; refused a wrong activation or wrong pipe
identity; and exercised synthetic owner loss before activation, partial output
under owner or Host loss, exporter loss, and deadline expiry with a small pipe.
The [negative race](evidence/output/output-race-v4.log) stopped the writer after
its last owner check and before a write, closed the owner control, then resumed
it. The write still occurred. A later check returned `U` rather than a completed
outcome, but retained leases and an unknown receipt do not prevent the byte from
being emitted after owner death. The unmodified helper therefore rejects the
mode; compiling the experimental mode requires `ipse_lease_output_experiment`.

An exact Session-owned Port can eventually close a native control pipe on BEAM
process death, but that closure and a write to a different destination are not
one atomic kernel action. A VM pidfd identifies the whole VM and cannot identify
an individual Session or Host. A possible direction is to make the Session the
sole recipient and forwarding actor and prove that the exact native lease holders
remain live through its onward operation; neither that lifetime nor the actual
worker pipe handoff is established. Already-buffered destination bytes also need
an explicit delivery and cancellation contract. No polling, link, monitor, prior
ACK, or retained-lock observation in this experiment solves those boundaries.

The [source snapshot](evidence/output/source-v6.tar),
[artifact and log hashes](evidence/output/manifest-v6.sha256), compiler and
[platform provenance](evidence/export/platform-v9.txt) preserve the tested
cohort. Earlier controls are retained: the first fixture build failed on a moved
value, the first expiry case allowed the entire payload to fit in the pipe, and
one selection accidentally included the test-hook-only race in an ordinary
experimental helper. The final fixture uses a 4096-byte pipe for backpressure
and selects the race only when explicitly requested. The ordinary helper's
[refusal](evidence/output/output-disabled-v3.log) exited nonzero. The shared
collector still passed a [two-lock control](evidence/output/collector-shared-v3.log)
and [131-lock stand-in control](evidence/output/collector-cap-shared-v3.log).

Commands run from the repository root on the recorded Linux host, using private
synthetic directories:

```sh
rustc --edition=2021 -D warnings native/ipse-runner.rs -o _build/shared-lease-sol-20261029/ipse-runner-output-disabled-v3
rustc --edition=2021 -D warnings --cfg ipse_lease_output_experiment native/ipse-runner.rs -o _build/shared-lease-sol-20261029/ipse-runner-output-experiment-v3
rustc --edition=2021 -D warnings --cfg ipse_lease_output_experiment --cfg ipse_lease_export_test_hook native/ipse-runner.rs -o _build/shared-lease-sol-20261029/ipse-runner-output-race-v3
rustc --edition=2021 -D warnings dev/fixtures/transaction_lease_export.rs -o _build/shared-lease-sol-20261029/transaction-export-output-v6
_build/shared-lease-sol-20261029/ipse-runner-output-disabled-v3 --lease-output-v1
task_dir=$(mktemp -d /tmp/ipse-output-final-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-output-v6 --leased-output "$task_dir" _build/shared-lease-sol-20261029/ipse-runner-output-experiment-v3
task_dir=$(mktemp -d /tmp/ipse-output-race-final-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-output-v6 --leased-output "$task_dir" _build/shared-lease-sol-20261029/ipse-runner-output-race-v3 9
```

The controls were run outside the sandbox because its socket restrictions
prevented the earlier native fixture. Actual Session and Host death, terminal
output, worker delivery, 131-lease writer capacity, and complete authenticated
final-holder closure have not been demonstrated.
