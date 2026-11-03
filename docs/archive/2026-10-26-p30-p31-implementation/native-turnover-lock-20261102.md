# Test the turnover pilot's ownership and interruption boundary

Dated **2026-11-02**, based on `a5aa2ca` plus the frozen scripts and logs in the
[receipt](native-turnover-lock-20261102.json). This author-run scratch experiment
uses separate seven-note synthetic stores; it is not the annual driver, a
production recovery API or P31C1a acceptance. The [plan](../../plan.md) owns
remaining work and the [storage chapter](../../developer/knowledge-storage.md#populate-through-actual-native-statements)
owns the current workflow.

The [first candidate](native-turnover-lock-v1-20261102.exs) added a retained
native lock and synced the in-flight marker, report and closure files and their
directories. Capture and correction closed, but standalone forgetting returned
an unconfirmed management result: placing the outer Session lock in the same
process conflicted with the management path's own cleanup scope. The marker was
retained. A read-only inspection found the root and control equal to the last
closed segment; this observation does not convert the unconfirmed outcome into
a proven absence of all effects. Restart refused before dispatch, and the
fixture remains untouched for inspection. No runtime boundary was changed.

In the [second candidate](native-turnover-lock-v2-20261102.exs), standalone
management runs in a separately tracked peer, keeping its existing owner and
cleanup scope. On a fresh seed, all seven capture, correction, forgetting,
supersession and expiry effects closed. The same signed final-state audit as the
[earlier pilot](native-turnover-pilot-20261102.md) passed: the expected four
removed records were absent, six remaining signed records had the expected
values/categories, five Sessions reconstructed, and root/control both reached
sequence 15. The measured final component sum was 847,872 bytes; it is not a
staged or full process-tree peak.

The [controlled fault variant](native-turnover-lock-fault-20261102.exs) used a
third fresh seed. After the first capture and its Session had completed, but
before the driver wrote its report or closure, the child recorded a hold point
and was killed with SIGKILL. The parent exited 1 and retained the synced in-flight
marker. A [read-only inspection](native-turnover-lock-inspect-20261102.exs)
found exactly one new visible record, generation/control sequence 9, and three
reconstructable saved Sessions. Restart exited 1 at the marker before dispatch;
a second inspection produced the same root and result bytes. The first
inspection invocation failed read-only because its scan omitted a required
operation identifier; its log remains, and the corrected inspection passed.

This demonstrates a specific post-effect, pre-report interruption and replay
refusal. It does not prove behavior when an effect or native helper is still
running, concurrent restart, filesystem or power-loss durability, scalable
checkpointing, or an annual workload. The separate-worker arrangement and these
scratch scripts need integration, failure controls and review before use on the
audited 2,000-note store. No model request, runtime permission, storage limit or
production code changed.
