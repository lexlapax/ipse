# Developing bounded diagnostic capture

Diagnostic capture helps explain runtime behavior without becoming recovery
storage or an action dependency. It defaults to off. Session projects committed
facts into allowlisted metadata; independent owned channels deliver samples to
selected sink workers. Mandatory journal/accounting and separately granted private
feeds keep their own guarantees when capture stops or drops data.

Read `lib/ipse/observability/config.ex`, `resources.ex`, `channel.ex`, and
`event.ex`, followed by `lib/ipse/builtins/local_trace.ex`. The
[operator manual](../operator/observability.md) owns configuration and stop procedures.

## Trace a sample and its lease

`Observability.Config` resolves operator-only mode/policy. `Resources` owns
intent/ready/closed leases. Each `Channel` owns worker, finite queue, and counters.
`Journal.append_observed/3` commits recovery evidence exactly once with an optional
source. Failure to obtain a source increments unsupported/refused observation
state rather than losing the mandatory append. Off bypasses optional projection.

Before a sink starts, Session syncs `diagnostic_sink_intent` with fresh resource,
activation identity, stage, and full bounded policy. Channel registers/initializes
the worker outside Session; Session syncs ready before draining. Samples during
startup share finite capacity. Closed receipts retain intent digest and actual
cleanup result. Receipts are mandatory private recovery facts; sampled events are
optional delivery.

Only new supported records after enrollment are offered. Headers/history are not
replayed. Enabled resume creates fresh leases while old incomplete resources stay
historical unknown. Capture can enroll runtime epoch/wait recording; stopping
sample delivery does not stop that already enrolled journal source. Logical close
is recorded after cleanup and need not reach the sink being closed.

## Implement an acknowledgment-only sink

An artifact declares exactly one of `observe.local` or `observe.export` with normal
identity/options/runtime/trust/expiry validation. Export also requires operator
instance scope. Off/import/inspection execute no sink. Project configuration cannot
set capture policy. A callback receives:

| Field | Meaning |
| --- | --- |
| `api_version` | 1 |
| `handle` | Host resource ID, 32 lowercase hex characters |
| `event` | Wrapper with version 1, sequence, elapsed ms, group, level, shared metadata event |
| `limits` | Pinned `file_bytes` and `retained_files` |

Reply using the real wrapper values:

```elixir
%{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"],
  "event_id" => payload["event"]["event"]["event_id"],
  "sequence" => payload["event"]["sequence"]}
```

No action proposal, prompt transform, model call, or context publication is accepted.
Callbacks/initialization have five-second deadlines and 16 KiB SDK object bounds.
Source IDs remain shared with lifecycle metadata. Private text, content hashes,
raw endpoints, credentials, state, and arbitrary business assertions refuse.

Sequence counts attempted observations, so unsupported/filter/drop positions leave
gaps. Elapsed time is monotonic from capture start, not operation duration or wall
clock. Model/wait durations retain their own saved facts and process epochs.
A group name does not imply every internal stage emits a source.

## Bound work before mailbox admission

At most four channels coexist. Atomic reservation bounds queued plus in-flight
callbacks before mailbox admission. Operator policy uses these ranges:

| Field | Default | Range |
| --- | --- | --- |
| `mode` | `off` | `off`, `local`, `export` |
| `level` | `info` | `info`, `debug` |
| `sample_every` | 1 | 1–1,000 |
| `queue_events` | 256 | 1–256 |
| `event_bytes` | 16,384 | 1,024–16,384 |
| `file_bytes` | 10,485,760 | 16,384–10,485,760 |
| `retained_files` | 2 | 1–2 |

Groups are a unique selected subset of session, prompt, context, model, stream,
tool, approval, question, child, compaction, extension, turn, and error.
Category/level/sample refusal increments `filtered`; size/capacity/revoked pending
work increments `dropped`; unsupported projection is separate. Errors bypass
sampling/level but still obey category/size/capacity. Sink IO/acks run outside
Session; mandatory fsync can still delay Session independently.

Invalid reply, timeout, crash, or expiry closes that sink while agent work proceeds.
`Session.stop_observability/1` immediately revokes new admission and discards pending
work. An in-flight transfer can finish and cannot be retracted. Explicit idle close
gives capture up to 500 ms to settle, then runs bounded parallel cleanup.
Concurrent close paths reuse one cleanup lease. A worker publishes its actual
native cleanup result before exiting, including callback failure/timeout. Death
without a receipt remains unconfirmed and can cause Session close to fail.

## Understand local ring retention

`builtin:local-trace:1` writes owner-only JSONL in a private `trace-ring-v1` leaf
under an existing canonical parent. `retained_leases` is 1–32, default 4. A persistent
directory advisory lock serializes catalog writes; each active worker holds a slot
lock. New workers choose the next free slot, reset only known files, and atomically
publish its resource binding. Full rings refuse; active writers are never evicted.
Lock files stay in place after OS lock release.

Participants must match file/rotation/lease limits exactly. Each slot has at most
two files, each at most 10 MiB. Managed data is bounded by
`retained_leases × retained_files × file_bytes`, 80 MiB with defaults. Catalog and
replacement scratch each fit 16 KiB; bounded slot names avoid arbitrary directory
scans/deletion. Path types, owner, permissions, hardlinks, schema, and policy are
validated. Corrupt/mismatched state refuses without repair or limit migration.
Legacy root logs/unrelated files are neither adopted nor deleted.

Death during first catalog publication can leave an incomplete ring. Capture then
refuses even if worker OS cleanup was confirmed. Select a fresh directory for a
new session after reviewing old files; resume does not reconstruct the catalog.
Trace recycling never deletes session journals. Retention is not an age policy,
private-history deletion, or a durable trace archive.

## Diagnose with synthetic data

Start with the off/privacy/pressure fixtures in `test/observability_test.exs`.
Compare "failed callback with confirmed worker cleanup" to "interrupted first
catalog publish". One concerns a cleanup receipt; the other concerns persistent
ring validity. Treating them as the same error can discard a valid cleanup result.

```sh
mix test test/observability_test.exs --trace
./bin/ipse extension check --config priv/conformance-operator.json --fixture priv/conformance-demo.json --extension annotation --no-project-config --developer-trace --trace-ms 1000 --trace-events 32
```

The suite uses synthetic local workers and no collector/account. The conformance
command traces only exported `Session.handle_call/3` and `handle_info/2` on its new
synthetic Session. `Ipse.DeveloperTrace` uses isolated OTP 27+ trace sessions and
arity-only events, with no arguments/messages/state/returns/PIDs. Unsupported OTP
refuses instead of using global legacy tracing.

One VM sample is in flight at a time; calls while disarmed are uncounted gaps.
Reports always say `sampling: one_in_flight`, `complete: false`. Limits are
1–5,000 ms and 1–128 stored samples, defaults 1,000/32. An independent watchdog
stops at deadline/dependency death, subject to scheduler availability. Cleanup
errors fail conformance. This is dispatch sampling, not a complete timeline or
latency profiler, and flags apply only to `extension check`.

Use existing source-debugger tooling in a development checkout with synthetic
tests for breakpoints. Breakpoints alter scheduling and can expire ordinary
deadlines. Formatted status redaction does not protect raw `:sys.get_state`,
messages, or debugger locals. No debugger listener or distributed node is enabled.
Remote OTLP exporters and richer viewers are unimplemented optional adapters;
adding one requires explicit endpoints/credentials/TLS and dependency review.
