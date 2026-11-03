# Populated recall: synthetic seed and unresolved Worker input, 2026-11-03

Historical synthetic evidence; this is not an acceptance or release result. The
candidate did not complete the populated Session check. The retained [evidence
directory](populated-recall-d739-20261103-evidence/) contains the exact compact
receipts, logs, fixture sources, full synthetic pre/post file inventories and
their [checksums](populated-recall-d739-20261103-evidence/SHA256SUMS).

## Candidate and seed

The isolated source was commit `d739f4020b73a8784dc74079c7ed6eedf58ead2b`
plus the recall batching candidate identified in `v4-final-source.sha256`.
The snapshot's frozen build, source, fixture and critical-artifact inventories
are included. The seed intent records the loaded application directory, recall
module BEAM hashes, Runner and native-helper hashes, and Knowledge artifact
hashes. This was not an unmodified production build: the synthetic clock fixture
recompiled Runner with a controlled environment adapter. Its original and
instrumented source and BEAM identities are recorded in
`clock-runtime-identity.json`. No paid model was used.

On 2026-11-03 Pacific, the fresh seed completed 273 segments with 2,000
captures and 100 pin operations. Its audit verified 2,000 records: 1,800
ordinary, 100 pinned, 50 preference and 50 current. The audited seed took
8,345.746 seconds; the audit took 668.749 seconds. The seed process exited 0,
the in-flight marker was absent, its post-input inventory check passed, and all
five frozen manifest entry checks passed independently. The independent check's
console output is not archived here. The seed was a
fixture-only preparation; it did not execute a 40-turn day or qualify an annual
workload. The full synthetic root and journals remain under volatile
`/dev/shm/ipse-native-seed-recall-d739-20261103-01`; a reboot can remove them.

## First probe: stopped before child

The first one-shot probe wrote its intent and attempt file, then reported the
generic `directory_sync_unavailable` error while syncing the attempt's parent
`/dev/shm`. That directory is root-owned and mode 1777; the native helper
requires an owner-only directory. This is the source-supported leading
explanation, but the specific failing helper stage was not captured. The parent
exited 1 before invoking the child, and no child claim was created. A separate
read-only comparison found that all 4,803 seed files and eight evidence files
matched their pre-probe hashes, identities, owner and mode. That comparison's
console output and its pre-inventories are not included in this archive. The
failed marker and log were retained; this was not a Session or inference
attempt.

## Revised probe: actual Session, unknown outcome

The independently reviewed revised probe used a fresh owner-only output
directory and the audited seed's copied, clock-instrumented runtime. Its exact
probe and synthetic provider sources are archived. Its one-shot parent and
child claims and a distinct Session turn intent were written. The Session's
automatic recall produced 18 delivered Worker inputs, followed by a 19th input
with status `unknown`; the lifecycle result was unknown and the Session was
cancelled. Inspection of the full volatile journal found no
`inference_dispatch_intent`; the selective archived event projection does not
independently prove its absence. The child and parent
exited 1; no completion receipt was written. This outcome does not establish
the cause or prove a timeout, and it does not show that the batching candidate
fixed populated recall.

The post-check reported no changed or missing preexisting seed files, unchanged
seed evidence and authenticated root/control state, and exactly the allowed
new synthetic Session journal and lock. The verification subprocess exited 0.
The full before/after inventories and compact comparison are archived. The
synthetic journal itself remains in the volatile root, not in this archive;
its SHA-256 was
`2f6386fd96d0f46d23ce5cf7edae938edc0140cbe4ce6f6b541e90eb0b655f3d`.
`journal-events-redacted.jsonl` is a derived event-type/status-only view, not
the full journal, and is not cryptographically linked to that unavailable full
journal. The verifier log includes compile-time warnings that the
synthetic provider module was not yet defined when the probe was compiled;
the separately loaded provider and verification exit are recorded without
claiming those warnings explain the unknown input.

No prior uncertain effect or probe was replayed. Populated recall, an actual
40-turn day, annual acceptance, and a full integrated regression remain open.
