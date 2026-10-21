# Capture diagnostic metadata

Use diagnostic capture when investigating session behavior without exporting
conversation text. Capture is off by default. `/diagnostics` works without it.
Journals, usage accounting, private subscribers, and visible-text clients are
separate mechanisms.

## Configure a private local trace

Choose an absolute leaf directory whose parent already exists. The sink creates
the leaf with mode `0700`; an existing leaf must be private and cannot be a
symlink. Save this complete example as an operator file, replacing the directory:

```json
{
  "version": 1,
  "observability": {"mode": "off"},
  "extension_trust": [{
    "artifact": "builtin:local-trace:1",
    "capabilities": ["observe.local"],
    "allow_project": false,
    "allow_children": false
  }],
  "extensions": [{
    "instance": "trace",
    "artifact": "builtin:local-trace:1",
    "enabled": false,
    "options": {
      "directory": "/absolute/existing-parent/ipse-traces",
      "retained_leases": 4
    },
    "order": 30,
    "lifetime": "persistent"
  }]
}
```

Inspect and exercise it with the credential-free scripted demo:

```sh
ipse config --config /private/path/trace.json --no-project-config --extension trace --observability local
ipse demo --config /private/path/trace.json --no-project-config --extension trace --observability local
```

The demo creates its own temporary workspace and performs the usual file/shell
probe, without a model service. Expect sink metadata and private trace files in
the configured directory. Import/trust, instance selection, and capture policy
are separate. Mode `off` starts no sink even when selected; `local` without a sink
creates no log. For persistent capture, explicitly enable the instance and change
the file policy to `local` for a fresh session.

## Inspect and stop capture

For a real task, launch with the same configuration and your chosen provider:

```sh
ipse chat --provider chatgpt --config /private/path/trace.json --no-project-config \
  --extension trace --observability local --cwd /path/to/project
```

This uses real subscription requests after task submission. In chat:

```text
/diagnostics
/observability off
/diagnostics
```

The snapshot shows mode, limits, sink readiness/closure, counts for pending,
admitted, delivered, dropped, filtered, and failed samples, and cleanup status.
Stopping revokes new samples and discards pending delivery immediately. An
in-flight callback may finish and earlier transfers cannot be retracted. Cleanup
settles separately. `/cancel` cancels task work but does not disable capture.

There is no in-session enable or promotion to export. Use reviewed configuration
or flags in a new invocation. An enabled resume creates a fresh diagnostic lease
and new resume metadata; it does not replay old samples. Mode flag/environment
overrides do not change the tool fingerprint, while file edits retain ordinary
source-identity compatibility checks.

## Set metadata and retention limits

`observability` is operator-only. Precedence for mode is default `off`, file,
`IPSE_OBSERVABILITY`, then `--observability`. Projects cannot set it, even to off.
Other controls come from the file:

| Setting | Default | Allowed values |
| --- | --- | --- |
| `mode` | `off` | `off`, `local`, `export` |
| `groups` | All known groups | Unique subset of known group names |
| `level` | `info` | `info`, `debug` |
| `sample_every` | 1 | 1..1000 |
| `queue_events` | 256 | 1..256 per sink |
| `event_bytes` | 16384 | 1024..16384 encoded bytes |
| `file_bytes` | 10485760 | 16384..10485760 bytes |
| `retained_files` | 2 | 1 or 2 per diagnostic lease |

Known groups are `session`, `prompt`, `context`, `model`, `stream`, `tool`,
`approval`, `question`, `child`, `compaction`, `extension`, `turn`, and `error`.
Current supported sources are committed journal facts, not every possible event
in those groups. Errors bypass sampling/level filters but still obey categories
and capacity. Debug can include interim usage metadata.

Capture excludes raw stream chunks, prompts/results, approval arguments,
question text, hidden reasoning, and arbitrary runtime state. Wait metadata
records observed process-local elapsed time, not downtime inferred after a crash.
Enrolled source facts remain in the private journal after a sink stops.

## Locate files and handle ring failures

The local sink writes mode-`0600` `slot-N.jsonl` files and optional `.jsonl.1`
backups under `DIRECTORY/trace-ring-v1`. Its private `catalog.json` maps diagnostic
resource IDs to slots. `retained_leases` ranges from 1 to 32, default 4. Active
writers hold slots; later writers reuse inactive slots in ring order and erase
those old logs. A full ring refuses new writers rather than evicting active ones.

Managed log bytes are bounded by
`retained_leases × retained_files × file_bytes`. Defaults permit eight files and
80 MiB, plus bounded control files. This is slot retention, not age-based expiry.
Journals are never pruned. Earlier root-level resource logs are outside this ring
quota; review/move them separately or use a fresh directory for a fresh bound.
Unrelated files are not scanned or deleted.

Writers sharing a directory must agree on file/rotation/lease limits. Changed
limits, unsafe paths, corrupt catalogs, or an interrupted first catalog write
can refuse later capture. Preserve the files, select a fresh private directory,
and start a new session. Resume does not repair an incomplete ring. Do not remove
a live writer's data to reclaim a slot.

At most four sinks coexist. Overload drops samples with visible counters rather
than delaying inference or dropping mandatory recovery/usage facts. Invalid
replies, expiry, crash, or timeout closes the sink. A failed callback can have
confirmed cleanup when the native helper supplies its receipt. VM exit alone is
insufficient. Orderly close allows up to 500 ms for idle capture to settle, then
drops remaining samples; final logical-close delivery to that sink is not assured.

## Share or export deliberately

Review even metadata before sharing because it contains correlation identities
and operational facts. A private journal is not a sanitized trace.
Mode `export` additionally allows explicitly trusted `observe.export` artifacts
selected in operator scope. It configures no collector by itself. No OTLP adapter
is shipped. The reviewed adapter owns endpoints, authentication, and verified TLS.
Trusted worker code retains ordinary OS permissions, so metadata contracts are
not a network sandbox.

For a reproducible extension bug, prefer a synthetic
[conformance fixture](../developer/extensions.md#turn-the-hook-into-a-repeatable-scenario) with no account data.
Developer dispatcher tracing is a separate bounded diagnostic, not attachment to
an existing private session. Use [Recovery](recovery.md) for saved-session
inspection and handoff.
