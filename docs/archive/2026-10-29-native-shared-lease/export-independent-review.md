# Independent review of the v5 native lease export

2026-10-29. This is a scoped source and evidence review of the
[unintegrated v5 export prototype](index.md#private-native-export-prototype),
not final P30/P31 acceptance. The reviewed source and artifact manifests
verified, and the inspected working-tree files matched that recorded cohort.
The focused controls support retaining a transferred flock after the exporter
dies. They do not establish a complete authenticated display or delivery path.

The review identified these unresolved requirements:

- The exporter authenticates the connecting recipient. The test receiver does
  not authenticate the listening helper or validate the received descriptor.
  A production sink needs a bound helper identity and operation, descriptor
  checks and protection against listener impersonation. Equal inode metadata
  alone does not prove the same open file description.
- The export-capable source-lock mode acquires a new lock and can create a
  missing lock file. It cannot export the open description held by a live legacy
  `--lock` helper. A real adoption path must preserve source/journal admission
  and avoid a release-and-reacquire gap for an already live Session.
- Control loss can occur after the final quiet check but before the success
  reply. The owner-loss control observed refusal before transfer; it does not
  establish atomic loss classification. A controlled boundary test and a
  separate owner-fenced all-leases admission are needed.
- The test receiver may leave delivered file descriptors open on malformed
  ancillary-data paths. A production receiver needs complete ownership and
  cleanup of every received descriptor, truncation handling and close-on-exec.
- The socket polling deadline does not bound every filesystem validation call.
  The precise v5 source snapshot and binaries reside under `_build`; the
  retained manifests and logs alone do not reconstruct that cohort after build
  cleanup. Preserve recoverable source and build provenance before relying on it
  as a durable independent-review receipt.

The guarded supersession and managed-result paths remain unavailable. Review
findings are being addressed before another qualification attempt; no result
here claims safe Session-source transfer, owner-fenced output or final lock close.
The subsequent [receiver and owner-loss follow-up](index.md#receiver-and-owner-loss-follow-up)
preserves the v5 source, adds test-receiver controls and reproduces the reported
control-loss race; its [separate review](export-follow-up-independent-review.md)
identified further evidence and fixture-boundary repairs.
