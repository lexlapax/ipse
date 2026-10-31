# Host-owned managed read receipts

Dated **2026-10-28**, branch `codex/p30-p31`, following the uncommitted
[current-source read adapter](current-source-read.md). This is scoped engineering
evidence. The [plan](../../plan.md) owns status and the
[collection manual](../../developer/collection-sdk.md) owns current behavior.

The protected adapter now retains normalized dependencies through the actual
Session action commit. A private `extension_managed_read` callback validates the
current job, action, Registry lease and authorized worker/file-effect descendant.
`Session.ManagedReads` binds the exact bounded value, request, operation, Session,
pin/epoch and root; every literal requires its selected recipe and source-version
dependency. Scans also retain their exact root selection. Snapshot, empty and
nonliteral reads retain root observations. Dependencies never enter SDK replies.

The owner writes `managed_read_observed` before a successful action result and
replies only after both appends. A failed/unknown read publishes no receipt.
An interrupted receipt without a result remains an unconsumed historical prefix;
resume does not replay it. Fresh headers pin `managed_reads_v1`; a missing marker
keeps legacy history, while explicit null and unsupported markers refuse.

Existing `Actions.restore` owns the chronological reconstruction. An initial
separate draft parser was removed rather than maintaining another action state
machine. The owner checks duplicate/missing receipts, exact result bindings and
complete literal coverage, then derives every completed invocation's full read
union. `Saved.restore` and Session retain those output unions, including earlier
reads when reconstructing a pending extension question. Replay obtains no current
source/root/permission authority and performs no external IO.

The changed runtime owners are `extension/managed_read.ex`,
`extension/collection_call.ex`, `extension/collection/observed_read.ex`,
`extension/actions.ex`, `session/managed_reads.ex`, `session/invocation.ex`,
`session/saved.ex` and Session itself. The new pure controls are in
`test/ipse/session/managed_reads_test.exs`; actual native receipt/replay controls
extend `test/support/operator_assertion.exs`.

## Focused evidence

The existing `_build/operator-assertion-sol` graph uses the inherited private
test-only helper override on Linux 7.2.11. It does not admit that host in the
production profile or qualify installed/platform behavior. No live models,
accounts, downloads or release publication were used.

- Strict changed-module compilation passed. The initial native check **46711**
  failed because the existing Actions unknown-record guard rejected the new
  operation-bearing receipt; **46712** passed after integrating it into that
  existing owner. The failed log remains in the graph.
- **46713:** eight pure/native controls passed in 13.3 seconds, exit 0, including
  exact receipts, missing/duplicate/altered records and interrupted prefixes.
- [**46714**](managed-read-receipts/origin-and-receipts-46714.log): **22 passed**,
  13.7 seconds, exit 0, including the native receipt path and the audit's Writer
  origin/private-parent controls. Log SHA-256:
  `d33de837e3bbd0b5905b0bd26053fa839762d58e949f4a6ce72ccb0697babadb`.
- **46715:** four pure controls passed after adding literal-recipe/source-version
  completeness checks.
- [**46716**](managed-read-receipts/affected-actions-46716.log): **84 passed**,
  38.3 seconds, exit 0, covering affected existing mixed-action, invocation, Saved
  and collection Session contracts. The redacted journal-exhaustion error in its
  output belongs to the intended diagnosis/handoff test, not a suite failure.
  Log SHA-256:
  `6a336888f48ece15662e4798076d2ebfbf6c301eddef3d17b897c914a1b2288b`.
- [**46717**](managed-read-receipts/marker-46717.log): five pure controls passed
  after distinguishing missing legacy markers from explicit null/unknown values.

These focused checks do not replace the final full-source regression. No
aggregate suite was repeated for this increment.

## Audit repairs and remaining integration

The user authorized specific subagents on 2026-10-28. The source-path audit found
and repaired two actual lifetime defects: Writer cached reads did not recheck
the original canonical/private directory after startup; inactive source reads
did not prove their raw native lock owner remained alive. Writer now repeats
full origin checks on queries/appends and after sync. StoredSources monitors and
checks the owned lock before/after use and before release. Its separate two-test
native lease selection passed **46723**, including actual helper SIGKILL,
withheld callback output, unchanged source bytes and fresh reacquisition. These
are scoped repairs, not the requested final milestone audit.

Assistant/reference/summary inheritance, durable derived projections and final
egress/delivery barriers remain open. In particular, arbitrary worker output must
retain its complete read union even when its own publication changes that root.
A successful CAS does not prove that old read bytes stopped influencing its
prose. A later integration may separately expose a host-constructed historical
write-outcome fact bound to the exact committed action/normalization/receipt;
it must not silently refresh old observations or let workers discard them.

The capacity and Word agents are working on independent sections. All current
changes remain uncommitted with the prior journal-origin/native-assertion work.
Whole-manual final acceptance and the final adversarial review remain open.
