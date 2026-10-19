# Peak-memory coverage investigation, 2026-10-19

Historical experiment record against `fb980a0`, before selecting or implementing
the comparison's memory instrumentation. The user requires exact peak memory.
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns acceptance;
the [evaluation training manual](../../developer/knowledge-evaluation.md) owns
current comparison procedures. This experiment does not close the resource gate.

## An outer receipt misses a completed Port child

The native probe touches 256 MiB in an owned child and waits for normal completion.
Its control reads the child's terminal `wait4` usage. Its second path launches the
same child through `System.cmd/3` in a fresh Elixir VM, then reads the outer native
receipt. Neither path samples RSS or performs inference.

| Runtime | Direct child peak, bytes | Outer receipt through BEAM, bytes | Large child peak missing |
| --- | --- | --- | --- |
| macOS, Elixir 1.20.3 / OTP 29 | 270,123,008 | 96,485,376 | yes |
| Serenity Linux, Elixir 1.20.4 / OTP 29 | 270,495,744 | 78,733,312 | yes |
| macOS, Elixir 1.18.5 / OTP 27, ERTS 15.2.7 | 270,106,624 | 97,517,568 | yes |

All three commands complete successfully. A successful command and an outer
kernel receipt therefore do not establish coverage of every completed Port
child. Wrapping the harness once would undercount this process population.
Cleanup confirmation, command outcome and measurement coverage need separate
evidence.

The earlier 64-MiB native control checks a direct child and a grandchild whose
parent waits for it. Both readings retain the allocation's high water.

| Platform | Empty process, bytes | Direct child, bytes | Waited grandchild, bytes |
| --- | --- | --- | --- |
| macOS | 1,703,936 | 68,829,184 | 68,829,184 |
| Serenity Linux | 2,285,568 | 69,136,384 | 69,140,480 |

The native control remains valid. Its complete wait chain cannot be assumed for
the Elixir path. These numbers describe kernel lifetime RSS high water, with
Linux values converted from KiB to bytes and macOS values already in bytes.
They do not measure simultaneous combined-process memory.

## Reproduce the bounded controls

The two [native wait-chain](probes/peak-rollup.rs) and
[Elixir Port](probes/peak-erts.rs) sources are byte-for-byte copies of the probes
used above. They use Rust's standard library and the system `wait4` interface on
macOS or Linux. The Port probe also requires Elixir on `PATH`.

Run from the repository root with the existing Rust and Elixir toolchains:

```sh
probe_dir=$(mktemp -d)
rustc --edition=2024 -O docs/archive/2026-10-19-p27-knowledge-packages/probes/peak-rollup.rs -o "$probe_dir/peak-rollup"
rustc --edition=2024 -O docs/archive/2026-10-19-p27-knowledge-packages/probes/peak-erts.rs -o "$probe_dir/peak-erts"
"$probe_dir/peak-rollup"
"$probe_dir/peak-erts"
rm -r "$probe_dir"
```

Each prints one JSON receipt. The native control asserts that both allocation
paths exceed its empty control by 32 MiB. The Port probe reports
`large_port_child_peak_missing`; it does not require the undercount to persist on
future runtimes. Compare the actual receipts and retain the runtime identity.
The experiment allocates its own memory and starts its own short-lived processes.
It does not use a model service, held-out data or comparison budgets.

| Probe | SHA-256 |
| --- | --- |
| `peak-rollup.rs` | `2961d72d1bdb356431aedfe28deb6e97fcbac62305988afc78b9eb5737a3b835` |
| `peak-erts.rs` | `28f29d38fde3019332eb3bdb86cec9908706b1b99d2daa885f44a666f1a6dc41` |

## Source inspection and limits

The investigation read the official tagged
[OTP 29.0.5 child setup](https://github.com/erlang/otp/blob/OTP-29.0.5/erts/emulator/sys/unix/erl_child_setup.c),
[OTP 29.0.5 spawn driver](https://github.com/erlang/otp/blob/OTP-29.0.5/erts/emulator/sys/unix/sys_drivers.c),
[OTP 27.3.4 child setup](https://github.com/erlang/otp/blob/OTP-27.3.4/erts/emulator/sys/unix/erl_child_setup.c),
and [OTP 27.3.4 spawn driver](https://github.com/erlang/otp/blob/OTP-27.3.4/erts/emulator/sys/unix/sys_drivers.c).
Their separate child-setup process waits for Port children and sends status over
a Unix socket. Its EOF path exits; the inspected spawn-driver stop function does
not wait. These observations help explain the coverage risk. The experiment is
the direct evidence of the undercount; inspecting two files does not prove every
runtime shutdown path. No upstream runtime was patched or rebuilt.

The requested metric scope still needs clarification. The largest individual
process's lifetime peak differs from the simultaneous combined-process peak.
No measurement contract, replacement native protocol or model-service lifecycle
is selected by this record. Future instrumentation must prove coverage of its
declared population and preserve ownership, cleanup and first-attempt accounting.
