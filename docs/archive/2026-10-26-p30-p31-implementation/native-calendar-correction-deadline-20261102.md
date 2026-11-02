# Correct the native annual calendar's correction deadline

Dated **2026-11-02**, based on `3b14048` plus the source hashes in the
[receipt](native-calendar-correction-deadline-20261102.json). This author-run
preflight executes no native effects or model calls. The [plan](../../plan.md)
owns current status and the [storage chapter](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
owns the procedure.

The [previous calendar](native-annual-calendar-20261102.md) wrongly gave each
corrected replacement a new 90-day deadline, although the native normalizer
selects the earlier of its baseline and the original signed deadline. The old
value's history deadline was already preserved. This discrepancy inflated the
modeled live population and invalidates the previous claim that the selected
working calendar necessarily exceeds the record limit. It also invalidates the
dependent ordinary-sized logical-data overflow claim in the [layout assessment](notes-layout-assessment-20261102.md).
Both historical records retain their original calculations with correction notices.

The repaired calendar gives the replacement the original deadline. Tests check
every modeled correction, including a replacement whose deadline is strictly
earlier than a fresh 90-day deadline. The working choice remains 20 ordinary
additions per day, 40 planned turns per day and 10,000 extra mixed changes in a
balanced fixture split, beyond normal work. Intake and mix are not ratified.

| Pure modeled quantity | Previous model | Corrected model |
| --- | ---: | ---: |
| Elapsed reclamations | 6,859 | 7,972 |
| Initial and annual publications | 29,939 | 31,052 |
| Peak public records | 8,012 | 6,903 |
| Optimistic peak including anchor/live pages and format | 8,478 | 7,326 |

The 7,326 figure is a lower bound using optimistic row packing, not actual
occupancy or proof that the unchanged 8,192-record limit suffices. The model
leaves 1,716 of the 32,768 operation identities before imports, compaction,
recovery and other unplanned operations. The higher-intake fixture still
reports its 127-operation day-90 burst against the 100-operation daily limit;
it does not trim the workload. If all 6,903 peak public values reached 6 KiB,
their 42,412,032 bytes alone would exceed the 24-MiB logical-data limit. That
conditional calculation is not a maximum-sized native record test.

The [same pure layout probe](native-calendar-correction-deadline-20261102.exs)
was rerun on the corrected calendar and the same 1,348 closed native seed
values. At the final 6,878 public records, their projected same-shape values and
the two mandatory live-row hashes total at least 22,054,607 bytes, below 24 MiB
before anchors, clocks, wrappers and other overhead. This is not a capacity
pass: it assumes the observed 1,024-byte statement shapes for all relevant
values and excludes actual correction payloads and unmeasured metadata.
Synthetic 31,052-receipt states with 7,326 and 8,192 descriptors roundtrip
through the current block codec at 8,043,871 and 8,309,733 packed bytes,
respectively. These synthetic states do not represent a published annual store.
A 10,000-descriptor synthetic state is refused above the 8-MiB packed bound.

The earlier recommendation to raise storage ceilings was based in part on the
withdrawn projections and is withdrawn pending actual capacity evidence. No
storage profile or runtime limit changed. The independent physical zlib
roundtrip observation from the earlier assessment remains an observation of
the seed values, not proof of logical or physical capacity.

The focused standalone regression exited 0 with **8 passed**, seed `791847`.
It covers the seed and calendar without starting Ipse or running Mix alongside
the separate full-source suite. Documentation checking in a separate clean clone
passed for 1,058 Markdown files and 8,745 links. Its first run reported two
missing links because the new receipt and probe had not been copied into that
clone; copying those explicit files fixed the check. The receipt binds the
sources, raw outputs and geometry report. Actual 30/90/365-day execution, precise
storage allocation, maintenance, full-value bounds, recovery and independent
quality remain open.
