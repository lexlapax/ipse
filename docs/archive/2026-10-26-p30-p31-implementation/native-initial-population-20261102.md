# Closed native initial population — 2026-11-02

This author-run checkpoint uses publisher source frozen at
`5331e60b9772c44131c054978c8f0d4428cbc2d6`. The parent process exited zero after
273 closed segments, with 2,000 native statement captures and 100 separate
native pin publications. The [metrics script](native-initial-population-20261102.exs)
and [numerical receipt](native-initial-population-20261102.json) summarize the
closed synthetic cohort. The [plan](../../plan.md) owns remaining acceptance;
the [storage chapter](../../developer/knowledge-storage.md#populate-through-actual-native-statements)
owns the procedure.

The last closed checkpoint reports 2,000 public notes, 2,150 total Collection
records including metadata, generation and floor 2,100, and 6,716,634 logical
data bytes. The represented note values are at most 3,129 encoded bytes in this
controlled run; the separate 6-KiB maximum-record gate is not established.

Collection allocation is 9,773,056 bytes. Actual control, identity, management
and original Session allocations bring the measured component sum to
134,131,712 bytes, of which original Sessions account for 122,515,456 bytes.
The largest sampled post-segment sum is the same. The Collection staging peak,
including its reserved control allowance, is 32,935,936 bytes; that reserve
must not be added again to the actual-component sum. Post-segment BEAM memory
peaked at 79,503,384 bytes. Neither sample is an entire process-tree or disk
peak, and installed artifacts, the frozen SDK and benchmark oracle are excluded.

The 2,000 capture samples have p95 3,973,481 microseconds for the complete
automated `/remember` interaction, including native input and review. This is
not the local publication p95 or a reference-hardware latency result.

The metrics script rechecked all 273 parent closure markers, report/log
fingerprints and 727 frozen runtime files. A separate full signed-record audit
was running when this checkpoint was recorded; its eventual outcome belongs in
a subsequent record. The source journals remain the original retained files.

This checkpoint establishes no annual turnover, 10,000-change workload,
maximum payload, concurrent owners, offline/import/compaction, human evaluation,
installed platform, overall memory peak, quality or final milestone acceptance.
The publisher allowed no model request. The storage-budget decision and
independent quality-case authorship remain open.
