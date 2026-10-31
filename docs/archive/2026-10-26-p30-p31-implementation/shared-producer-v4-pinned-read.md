# V4 pinned anchor reads and reservation — 2026-10-29

Historical evidence; the [plan](../../plan.md) owns acceptance. This follows
the [source-bound geometry](shared-producer-v4-bound-geometry.md), whose model
reached 509 reads and whose artifact predates this change.

The v4 worker now obtains its first anchor's native generation and reads later
anchors and the captured catalog page at that exact generation, without
refreshing the snapshot. The earlier guarded claim CAS still uses its separately
checked original epoch. The append preflight reserve increased from 16 to 24
control reads in addition to two passes over immutable prerequisites. That is
still a provisional bound pending a complete adversarial stage/geometry audit.

With eight near-full segmented sources, the 256-chunk synthetic model again
completed 32 vector pages and a private group append with one explicitly
supplied fact per source. Hydration used 414 reads; 37 append invocations
peaked at 506 reads. A 32-facts-per-source probe reached the first known
stage-free continuation, but did **not** finish that larger append. The first
probe incorrectly expected a budget refusal and is retained as a failed test;
the revised assertion records only the observed first unit. Neither case proves
public fact production, complete fact geometry, real Session journal handoffs,
physical peak or native selected-root reuse.

Eight focused progression/integrity model cases and four guard1/public-entry
model cases passed; the canonical corpus artifact built strictly. A fresh actual
public two-page Session with a synthetic loopback endpoint and empty old root
passed Saved reconstruction and confirmed close. Its journal has 1,510 events
and 4,617,140 bytes. Imported artifact digest:
`ff8273cef5d12713308336fd18e5a4c5b54affb4fe69a335d79ce25277bae02b`.
The native test does not cover private append or 256 chunks.

The [manifest](shared-producer-v4-pinned-read/manifest.json), SHA-256
`0292e6dcf8970d12152c631fc94d7f58a1c5b6c5227e88f7c4e2b7a2f85bf823`,
pins 77 source, artifact, synthetic evidence and log files. Independent review,
stale-generation and owner-loss native controls, full reservation proof, source
clock policy for fact inference, lifecycle, capacity and quality remain open.
