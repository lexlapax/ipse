# Short native turnover continuation

Dated **2026-11-02**, based on `abcde0e` and the frozen files and logs in the
[receipt](native-turnover-pilot-20261102.json). This author-run smoke is a
prerequisite experiment, not the annual driver or P31C1a acceptance. The
[plan](../../plan.md) owns remaining work and the
[storage chapter](../../developer/knowledge-storage.md#populate-through-actual-native-statements)
owns the current procedure.

A fresh seven-note native seed was populated and signed-audited before the
continuation. The separately frozen [pilot source](native-turnover-pilot-20261102.exs)
then ran seven sequential native effects against that disposable fixture:

| Simulated day | Actual effects |
| --- | --- |
| 2 | Capture one ordinary note, correct another, forget a third, and supersede the current statement |
| 92 | Expire the corrected original and its replacement after their retained deadline |
| 368 | Expire the old temporal support after its 365-day historical deadline |

The parent exited 0 and all seven segments have individually fingerprinted
closure and log records. Before each child, it checked its frozen files,
unchanged original source journals, prior closures, current root and protected
control. It wrote an exclusive in-flight marker before dispatch and retained
that marker on an unconfirmed effect. These are fixture mechanics, not a
production recovery API. An attempted rerun after all seven segments refused
before dispatch; a subsequent read-only audit matched the preceding audit byte
for byte. This does not test an actual crash during an effect.

The [separate final audit](native-turnover-pilot-audit-20261102.exs) checked
the authenticated Collection and control without publication. The forgotten
note, both expired correction records and expired temporal history were absent.
Six remaining signed records had the expected values and categories: pin,
preference, three elapsed ordinary notes and the replacement current statement.
The elapsed notes remained stored with elapsed signed deadlines; this audit does
not itself test withholding them from inference. All five Session journals
reconstructed with signed release claims, the original seed sources remained
unchanged, and all 15 control operations were settled with zero model calls.
The final generation and control sequence were both 15, reflecting the eight
seed effects and seven continuation effects.

Final measured allocation was **847,872 bytes** for the Collection plus actual
control, identity, management and Session components, including **679,936 bytes**
of Session files and **57,344 bytes** for the Collection. The Collection's
accounted allocation including its separate control reserve was 23,126,016 bytes;
do not add that reserve a second time to the measured component sum. These are
post-run component samples, not a staged, process-tree or full-disk peak.

The first audit invocation refused before producing audit output because its
filename did not use the required prefix; the corrected name passed. The first pilot
initialization also refused before creating its directory or executing effects:
it compared the record hash with a different digest format. The retry used the
Collection's canonical encoding. The original failing logs remain in the
receipt; the failed pilot source version was not separately snapshotted. The
executed pilot printed an unused-alias warning and a static warning about the
dynamically loaded clock helper. Both are retained in its log, and no clean-build
or warnings-as-errors result is claimed for this scratch source.

This deliberately small, fixed sequence executed zero simulated main turns,
no maximum-sized records, no consent renewal, no imports or concurrent owners,
and none of the 10,000-change year. It creates no qualified semantic data or
provider result. The real annual continuation still needs a scalable driver,
actual 40-turn days and the remaining workload, fault, capacity and quality
checks. The existing 2,000-note audited population was not changed by this pilot.
