# Native operator reconciliation of an inference reservation

2026-10-31, source increment based on `533280d` plus the additive full-suite
receipt at `2d93628`. The runtime ledger and reconciliation API already existed;
this adds their operator entrypoint. It does not qualify owned-daemon recovery,
installed delivery or complete P31D1. Current instructions belong to
[service configuration](../../operator/configuration.md#serialize-a-shared-inference-service),
[recovery](../../operator/recovery.md#reconcile-an-unresolved-inference-reservation)
and [configuration training](../../developer/configuration.md#trace-registered-service-admission-and-reconciliation).

## Operator and authority path

`inference status [--json]` reports bounded service/queue/recent metadata from the
protected operator ledger. An absent tree returns the pure empty ledger without
creating a home. Existing trees retain the Store's lock, layout and housekeeping
checks; this is not a promise of zero physical writes. Symlink roots refuse.
Neither command loads conversation configuration, starts a Session nor sends
inference. Malformed unrelated conversation configuration remains untouched.

`inference reconcile SERVICE_ID RESERVATION_ID REVISION` requires an existing
exact active reservation and the current global ledger revision. The native
terminal displays the home, workspace, full stored aliases, active metadata and
reconciliation reason. Only a fresh exact `reconcile CODE` observation can create
the UI's receipt hash. Piped input, stale codes and `--yes` refuse. No raw receipt
or serialized observation can be supplied through command arguments.

The command calls the existing `InferenceSlots.reconcile/6` once. That API takes
the service lease, rechecks the exact ID/revision under its protected transaction
and retains the operator-reconciliation receipt. It stops no daemon, replays no
request and adds no SDK/native protocol or dependency. The operator independently
establishes remote quiescence; neither a free lock nor `/api/ps` proves it. An
unknown result remains unknown and requires status inspection, not automatic
retry. Unrelated ledger changes also invalidate the displayed revision.

## Executed source controls

- Four non-terminal CLI controls pass: fresh-state no-creation, malformed
  conversation-config isolation and redirected-root refusal, unsupported flags/
  noncanonical selection refusal, plus actual protected status with unchanged
  ledger bytes. `/tmp/ipse-inference-cli-preflight4-20261031.log` reports
  **4 passed,1 excluded**.
- Complete CLI selection: **5 passed,2.8 seconds**,
  `/tmp/ipse-inference-cli-native2-20261031.log`. Its synthetic PTY case executes
  five separate private scenarios: exact confirmation, cancellation, stale code,
  pipe refusal and concurrent global revision. It checks actual protected ledger
  outcomes, retained lock inodes, no conversation/config creation and replay
  refusal after a confirmed reconciliation. The service lease is actually
  acquired/released before a synthetic unresolved marker is prepared. No real
  daemon work is performed by these controls.
- Standard build passes:180 host modules and three inert bundles. Format,
  warnings-as-errors compile and credential-free demo pass. Logs use the
  `/tmp/ipse-inference-cli-{build,format,compile-final,demo}-20261031.log` names.
- The exact new complete service-configuration example validates through
  `ipse config`, with a fresh private home left absent and no inference:
  `/tmp/ipse-inference-cli-example-20261031.log`.

The first protected-status fixture accidentally nested its home inside the
workspace and correctly received `service_state_unavailable`; it now uses sibling
directories. Preserve `/tmp/ipse-inference-cli-preflight3-20261031.log`. The first
native fixture attempted to inspect a service lock before ever acquiring that
lease and failed before operator input. It now establishes/releases the actual
lease before asserting retained inode identity. Preserve
`/tmp/ipse-inference-cli-native-20261031.log`. Neither repair weakens a runtime
condition or changes a positive test into a refusal pass.

The affected configuration and recovery chapters were reviewed as task-oriented
manuals, with registry prerequisites, current context limits, complete command
forms, native confirmation, unknown outcomes and protected-filesystem limits.
Audience entrypoints link the owning procedures. The source controls are native
synthetic terminal automation, not a human/Arch/macOS or live shared-daemon
qualification. Installed verification and a complete candidate regression remain
open; the separate [c7cb484 baseline](full-suite-c7cb484-20261031.md) still has58
failures and excludes this isolated increment. Full P30/P31 and final audit/
reviewer handoff remain incomplete.
