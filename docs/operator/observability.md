# Diagnostic capture

Capture is **off by default**. It sends allowlisted lifecycle metadata to selected
sink extensions, independently of journals, request usage, private subscribers and
visible-text clients. `/diagnostics` remains available with capture off.

## Select a local sink

Merge these fields into operator configuration, preserving existing entries.
Choose an absolute directory whose parent exists. The sink creates its leaf with
mode `0700`; existing leaves must be private directories, not symlink aliases.
Parent aliases are resolved before admission.

```json
{
  "version": 1,
  "observability": {"mode": "off"},
  "extension_trust": [
    {"artifact": "builtin:local-trace:1", "capabilities": ["observe.local"],
     "allow_project": false, "allow_children": false}
  ],
  "extensions": [
    {"instance": "trace", "artifact": "builtin:local-trace:1", "enabled": false,
     "options": {"directory": "/absolute/existing-parent/ipse-traces", "retained_leases": 4},
     "order": 30, "lifetime": "persistent"}
  ]
}
```

Inspect policy locally, then try the credential-free demo:

```sh
./bin/ipse config --extension trace --observability local
./bin/ipse demo --extension trace --observability local
```

Import/trust, instance selection and capture permission are separate. Mode `off`
initializes no sink, even if selected. Mode `local` without a sink creates no log
files. For persistent use, explicitly enable the instance and set policy to
`local`. Tool approvals remain independent.

## Policy and stop

`observability` is a top-level **operator-only** object; project configuration
cannot set it, even to `off`. Mode precedence is built-in `off`, operator file,
`IPSE_OBSERVABILITY`, then `--observability`. Other controls come from the file:

| Setting | Default | Accepted values |
| --- | --- | --- |
| `mode` | `off` | `off`, `local`, `export` |
| `groups` | All known groups | Unique subset of `session`, `prompt`, `context`, `model`, `stream`, `tool`, `approval`, `question`, `child`, `compaction`, `extension`, `turn`, `error` |
| `level` | `info` | `info` or `debug`; interim usage observations are debug metadata |
| `sample_every` | 1 | 1..1000; errors bypass sampling/level filtering, but obey category and capacity limits |
| `queue_events` | 256 | 1..256 queued/in-flight samples per sink |
| `event_bytes` | 16384 | 1024..16384 bytes per encoded sample |
| `file_bytes` | 10485760 | 16384..10485760 bytes per local file |
| `retained_files` | 2 | 1 or 2 files per local diagnostic lease |

Current sources are supported **committed journal facts**, not every proposed
group. Raw stream chunks, approval wait messages, hidden reasoning and arbitrary
runtime state are excluded. See the
[implemented vocabulary](../developer/lifecycle-events.md#internal-journal-source-and-prompt-views).

In chat, `/observability off` immediately revokes new samples and discards pending
delivery without waiting for a callback. An in-flight callback may finish;
previous transfers cannot be retracted. Cleanup settles separately. `/diagnostics`
shows current mode/limits, pending/admitted/delivered/dropped/filtered/error/failure
counts and sink readiness/closure. The original configuration manifest stays fixed;
the live snapshot reflects the stop. `/cancel` cancels work without disabling capture.

There is no in-session enable/export promotion or general hot reload. Use reviewed
flags/configuration for a new invocation. Mode flags/environment overrides do not
change the tool fingerprint; file edits still follow ordinary
[resume compatibility](configuration.md). Enabled resume creates fresh diagnostic
leases for new work and never replays old samples.

## Files, failures and export

The bundled sink writes private `slot-N.jsonl` files and optional `.jsonl.1`
backups inside `DIRECTORY/trace-ring-v1`, with mode `0600`. Its private
`catalog.json` maps resource IDs from `/diagnostics` to slots. Lines wrap shared
metadata events, preserving journal correlation without copying content hashes.

Sink option `retained_leases` is 1..32, default 4. Active writers hold their slots;
new writers reuse inactive slots in ring order, erasing those old slot logs. A full
ring refuses new writers instead of evicting active ones. Managed log data is
bounded by `retained_leases × retained_files × file_bytes`: defaults permit eight
files totaling at most **80 MiB**, plus small bounded control files. This is slot
retention, not an age/TTL policy. Journals are independent and are never pruned.

Writers sharing a directory must use identical file/rotation/lease limits.
Mismatch, corrupt catalogs and unsafe managed paths refuse without rewriting other
logs. Choose a fresh directory when changing limits. Earlier root-level
`RESOURCE_ID.jsonl` files remain outside the managed ring and its quota. For a fresh
aggregate bound, use a fresh directory or review and remove/move legacy files
separately. Unrelated operator files are never scanned or deleted.

At most four sinks coexist. Overload drops samples with visible counters; it never
drops mandatory recovery/usage facts or waits for a sink before inference.
Invalid replies, expiry, crashes and timeouts stop that sink with a fixed notice.
Inspect cleanup status: VM exit alone does not confirm complete descendant cleanup,
and explicit close reports uncertainty when appropriate. An idle active capture
gets up to 500 ms to settle during orderly shutdown; remaining samples are dropped.
The CLI uses this close path and reports cleanup failures separately from turn success.

Mode `export` additionally admits reviewed `observe.export` artifacts selected in
operator scope. It configures no collector by itself. Endpoints, authentication
and verified TLS belong to the explicitly configured adapter. No OTLP adapter is
shipped or live remote exporter verified. Only metadata crosses this host path;
reviewed worker code retains ordinary OS permissions, so these checks are not a
network sandbox.

Use the [developer contract](../developer/observability.md) for SDK details and
remaining tracing work. [Recovery](recovery.md) owns saved inspection and reviewed
handoff export; a private journal is not a sanitized trace.
