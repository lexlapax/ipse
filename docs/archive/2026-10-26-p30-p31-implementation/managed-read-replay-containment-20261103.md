# Fail-closed replay of unclassified managed reads — 2026-11-03

This isolated candidate makes Saved reconstruction refuse a recorded generic
managed get or scan containing any nonempty value with no selected matching
literal recipe. Previously `ManagedReads.covered?/5` could accept such a value
under a version-3 root-only receipt even though the current live managed-read
path refuses it. Metadata-only indexes, empty gets and authenticated v4/v6
records retain their existing paths. The separately marked v7 pending shadow
assessment is unchanged.

This is an intentional compatibility change: an older, otherwise reconstructible
Session containing such a recorded pending proposal, override or unrelated
value now refuses reconstruction. It does not delete or rewrite the journal,
retry effects or establish that a provider previously received the value after
source loss. Histories without a managed-read receipt follow a separate legacy
path; the one-branch repair does not qualify every such history. The accompanying
operator recovery chapter describes preservation, inspection and a new task;
the developer chapter explains the recorded-receipt boundary.

The base was `f9ccb3136bf5546dcec9d77929b15d22cdd01afd`. The exact
[candidate patch](managed-read-replay-containment-20261103/candidate.patch),
[preimage hashes](managed-read-replay-containment-20261103/preimages.sha256),
[output hashes](managed-read-replay-containment-20261103/outputs.sha256)
and [verified overlay](managed-read-replay-containment-20261103/overlay/) contain
the one production module, focused tests and two reviewed manuals. The
[archived overlay manifest](managed-read-replay-containment-20261103/archived-overlay.sha256)
uses `.md.txt` for the historical manual copies and verifies all four files.
The
[evidence manifest](managed-read-replay-containment-20261103/manifest.sha256)
binds the logs, test harness, sanitized journal projection and source/build
inventories. The full source/build manifests identify both isolated trees; they
are not copies of every file. The scratch root is
`/dev/shm/ipse-managed-replay-f9cc.75XJZN6N`, which is volatile.

The retained synthetic consumer journal was created by the actual pre-containment
`fccaf35` runtime. Its main-model-selected worker returned a pending candidate;
the precise get action is linked by operation ID and result hash to a v3 read
receipt. The [sanitized projection](managed-read-replay-containment-20261103/synthetic-journal-projection.json)
contains event indices, synthetic identifiers and hashes, and a boolean tool
message marker; it omits the raw journal, candidate text and provider request.
The consumer and its original source journal were copied read-only into scratch,
and their full-file SHA-256 values were checked before and after. `Saved.restore`
on the genuine source journal succeeded in both trees. The
[unmodified f9 baseline](managed-read-replay-containment-20261103/baseline-history.log)
also reconstructed the consumer; the
[repaired candidate](managed-read-replay-containment-20261103/candidate-history.log)
refused it. These are pure Saved reconstruction checks on copies, not a live
resume or proof of present source ownership.

Both frozen trees and their native helpers built successfully with locked offline
dependencies, `MIX_ENV=test`, `TMPDIR=/dev/shm` and two BEAM schedulers. Project
compilation used warnings-as-errors; upstream dependency warnings appeared in
the logs. The [focused ManagedReads suite](managed-read-replay-containment-20261103/managed-reads-test.log)
passed nine tests, including pending/override/unrelated get and scan refusal,
a mixed valid-literal plus unclassified scan, empty get, metadata-only index,
and existing v4/v6 positive cases. A fresh synthetic bundled
[v7 assessment Session](managed-read-replay-containment-20261103/v7-positive.log)
passed its approved candidate journey. The code, tests, documentation drafts,
synthetic journal copies and compiled-artifact inventories matched their frozen
hashes afterward. Logs capture output; the environment, selected commands and
exit results are from the recorded execution rather than encoded by the logs.

The focused synthetic controls do not establish compatible live resume for old
unmarked histories, a previous provider disclosure, full-suite compatibility,
installed-package behavior or live-model quality. Original historical state
remains private and should be preserved for inspection rather than edited to
force reconstruction.
