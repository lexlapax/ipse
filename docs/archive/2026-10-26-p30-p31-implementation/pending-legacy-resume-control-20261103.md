# Historical pending-read resume control — 2026-11-03

This synthetic investigation tests one possible boundary of the earlier
[generic pending-read disclosure](pending-source-containment-20261103.md).
It does not establish safe withdrawal after a compatible resume, measured
zero network traffic, or completion of P30 or P31.

The historical runtime was `fccaf35c0547cce178dfddfa0c45ee8f006121d4`, before
the containment change. The separate current runtime was
`131f67e5b715894bad27565c3d91e8a485486395`. Both compiled with
`MIX_ENV=test` and warnings-as-errors using matching, already-installed
dependencies, according to the recorded execution; their build logs are not
archived here. Source and compiled-artifact inventories were reported to match
before and after the runs, but those inventories are also not archived here.
Dependency compilation emitted upstream warnings. Native helpers were reported
built separately for both snapshots. The
[manifest](pending-legacy-resume-control-20261103/manifest.sha256) binds the
two failure logs and fixture overlays; the output logs do not themselves
encode all command-line flags or exit codes.

In each fresh synthetic fixture, the old runtime created a pending candidate
from a real Session source. A second old Session used a model-selected tool to
obtain the pending value through an ordinary managed get. Its exact action was
bound to a version-3 read receipt and the returned-value hash; the synthetic
candidate text appeared in the old provider's subsequent request. The second
Session was closed before the current-runtime attempt. During the latter, the
original source journal was held under a different pathname, and the fixture's
normal cleanup restored and checked the same source inode, lock inode and
source hash. The synthetic inputs and roots are separate from operator data.

The [first attempt](pending-legacy-resume-control-20261103/first.log) stopped
before current-runtime reconstruction: safe external-term decoding returned a
generic invalid-or-unsafe-term error. A later source review and an independent
synthetic ETF tag scan identified atom names absent from a fresh VM as the
likely cause; the error itself did not identify them. The scan is not archived
here. The failed attempt's
[helper](pending-legacy-resume-control-20261103/failed-helper.exs.txt) is
retained. The independently reviewed [fresh helper](pending-legacy-resume-control-20261103/fresh-helper.exs.txt)
uses a fixed compile-time atom list, a bounded read and safe decoding. Safe
decoding also accepts atoms already present in the VM; the file cannot create
new atoms through decoding. The second attempt used a newly created pair of
synthetic Sessions, not a retry of the first pair.

The [second attempt](pending-legacy-resume-control-20261103/fresh.log) passed
historical reconstruction and reached the current startup checks. The old
pinned extension identity was refused with `extension_admission_refused`.
Re-preparing the same artifact under the current host changed its host digest;
the linked Session then exited with `invalid_semantic_admission`. That linked
exit terminated the helper before it could assert the return, inspect its
listener or compare the consumer journal after the attempts. The enclosing
fixture restored and checked the original source and lock. Neither failure is
a passing end-to-end control.

The retained original synthetic roots are
`/dev/shm/ipse-collection-sdk-e3a68a4530f2cc2657061c2b74b8ad6d` and
`/dev/shm/ipse-collection-sdk-7509208ffdf50ea0174a0d46dfad05ff`; `/dev/shm`
is volatile. The [old-runtime fixture patch](pending-legacy-resume-control-20261103/old-fixture.patch)
is relative to `fccaf35`. The two refusal observations do not resolve whether
a historical root-only receipt could disclose stale pending-derived content
when a compatible Session is successfully resumed. That separate question
remains open.
