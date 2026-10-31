# Independent review of the inert lease collector

2026-10-29. This review covers the frozen [inert collector](collector.md), not
a production output sink or completed P31. Its source and evidence manifest
verified locally. The recorded controls cover two leases, a synthetic maximum
of 131 leases, two slots from one Transaction helper, several refusals, and
owner loss or expiry after the complete set was collected.

The reviewer found a concrete cleanup defect: the collector writes its `L`
response through blocking stdout before waiting for cancellation or expiry.
If that pipe is full, it can remain blocked while holding locks after control
input closes or the deadline passes. The earlier normal-flow owner-loss and
expiry controls do not establish bounded cleanup under this backpressure.

Other requirements remain open:

- The maximum case retains about 131 pidfds, 131 peer sockets and 131 received
  descriptors, plus stdio and transient opens. An effective descriptor budget
  must be measured, and low-limit failure must prove cleanup of partial work.
- The collector rejects all-zero names and secrets but does not establish their
  randomness, freshness or one-use operation binding. A trusted caller must
  supply and bind those properties.
- The owner-loss control acts after collection. Parsing, connection, partial
  transfer and a stalled exporter need separate bounded cleanup controls.
- Matching the observed helper executable and PID is not a complete guarantee
  against later exec or process changes. Payload, destination, admission and
  final-holder close are not bound by this inert collector.

The backpressure issue and these limits are being addressed before another
qualification attempt. Supersession and managed-result delivery remain gated.

The subsequent independent review of the repaired cohort confirmed that
nonblocking response writes observe the control input and collection deadline.
The full-output tests exercise both EOF and expiry, and the low-limit case
records a partial transfer as unknown and verifies eventual cleanup. Its
manifest verified locally. A [fresh-extraction reproduction](collector.md#follow-up-bounded-response-and-exhaustion)
then rebuilt the saved cohort and passed the seven targeted fault controls.
The capacity run was not repeated. The source archive remains untracked until
the eventual commit, and `F_SETFL` requires dedicated control descriptors because
its effect is shared with other holders of the same open-file description.
This follow-up does not establish output admission or final-holder close.
