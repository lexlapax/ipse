# V4 maximum-count fact append model — 2026-10-29

Historical development evidence following the [pinned-read model](shared-producer-v4-pinned-read.md);
the [plan](../../plan.md) owns acceptance. The current 34 relevant source/build
inputs match that frozen ancestor. No production source or artifact changed for
this control.

The synthetic model populated eight near-full segmented documents, 256 chunks
and 32 vector pages. It then supplied 32 valid, short synthetic facts per source
to the private append controller and followed its known continuations through
group completion. All 256 facts were counted, no stages remained, and the Job
cursor reached eight. Hydration used 414 reads; 37 append invocations peaked at
506 reads, within the unchanged 512-read per-invocation limit. The complete
test took 288.3 seconds wall time, of which 284.2 seconds was test execution.

This is a closed model with fabricated cited facts and compact fact fields. It
does not establish semantic fact extraction, maximum escaped fact widths,
Session journal capacity, callback deadlines, native publication, owner loss,
physical peak, or end-to-end selected generation. The run makes no live model
or service request. Its cost makes separate timing and stage-free handoff
qualification necessary; a per-invocation read count alone is insufficient.

The [manifest](shared-producer-v4-full-facts/manifest.json), SHA-256
`412fee7c4897d9775754525069dcf6478c5ab97dea52c180fea1da1fe786aa73`,
pins the exact fixture, launcher and log and identifies its frozen source
ancestor. The earlier one-fact and first-unit evidence remains unchanged.
