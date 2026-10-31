# Independent review of the native export follow-up

2026-10-29. This review covers the recorded v9 development fixture and
owner-loss experiment in the [follow-up](index.md#receiver-and-owner-loss-follow-up),
not a production sink or P30/P31 acceptance.

The source and artifact manifest verified locally, and the inspected source
matched the saved cohort. The fixture checks the helper PID and UID before
sending its secret, takes ownership of delivered descriptors before validating
the frame, and checks metadata and close-on-exec. Its controls cover malformed
frames, extra descriptors, truncated ancillary data, wrong inode and a
substitute listener. The separate test hook reproduces the owner-loss race in
both helper modes; it was absent from the retained ordinary helper binary.
This is evidence of the race, not a liveness repair. Executable identity, PID
reuse, exact open-description provenance and live Session migration remain
integration requirements.

Three further issues remained when reviewed:

- The source tarballs used an ignored `*.tar.gz` suffix and were not tracked;
  without explicit preservation their archive links would be absent in a fresh
  checkout. The source must be saved in a recoverable, unignored form.
- Exact v9 compilation and test invocations were not in the archive; the
  platform and hashes alone do not fully describe how to reproduce the cohort.
- The fixture frame reader polls only before the first byte, then uses blocking
  reads for the rest of the frame. A partial header or body can exceed the
  nominal deadline indefinitely. Reuse for fault injection needs bounded reads
  against one absolute deadline and a partial-frame stall control.

The user-facing supersession and managed-result paths remain disabled. None of
these fixture results admits a sink, proves final close, or establishes an
owner-fenced all-leases admission.

## v10 verification and reproduction repair

A subsequent independent review verified that the v10 fixture uses nonblocking
reads with one deadline over the header and body. Its recorded controls cover
partial-header and partial-body stalls and a complete frame; they do not
separately cover a zero-byte stall or trickled input. The v5 and v9 source
archives are unignored, their manifests verify locally, and the v5 archive
matches the frozen source tree. They are still untracked until included in the
eventual commit.

The review also found that the recorded v9 commands compiled the now-newer
working-tree fixture rather than the archived one. A fresh
[reproduction recipe](evidence/export/commands-v9.md#reproduce-from-the-saved-cohort)
now extracts the archived cohort and compiles both helper variants and the
fixture from it. An independent run in `/tmp/ipse-v9-independent-repro-46984`
passed the [receiver](evidence/export/independent-v9-receiver.log) and
[real-helper](evidence/export/independent-v9-valid.log) controls and reproduced
both [owner-loss race markers](evidence/export/independent-v9-race.log). It does
not qualify a production sink or atomic owner-death fence.
