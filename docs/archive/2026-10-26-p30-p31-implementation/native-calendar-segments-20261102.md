# Bound native calendar segments before execution

Dated **2026-11-02**, based on `d4ec4d5` plus the source and output hashes in the
[receipt](native-calendar-segments-20261102.json). The [plan](../../plan.md) owns
acceptance and the [storage chapter](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
owns the procedure. This pure preflight executes no native operation or turn.

The corrected action calendar can now be divided into ordered, day-local
segments of at most one to eight effects. If an action targets a note created
earlier in its proposed segment, the segment ends first. This allows a future
driver to close the creating segment before resolving and authenticating that
target. Flattening the segments preserves every planned action and its order.
Quota excess remains attached to every segment of the affected day; segmentation
does not make an over-quota day executable. Aliases do not grant authority.

For the unratified 20-item working intake, the 28,952 annual effects after the
2,100-effect seed become **3,784 segments** at a maximum of eight, or **7,351**
at four. The 14,600 main turns are planned, not executed. At working intake 40,
the eight-effect option retains all 34,877 annual effects in 4,529 segments and
reports one over-quota day. These are plan sizes, not runtime or capacity results.

The [seven-effect pilot](native-turnover-pilot-20261102.md) rechecks every older
closure before each new effect. Applying that exact repeated-scan strategy to
thousands of segments would grow quadratically. A scalable continuation should
check all prior closed records when resuming, then carry a bounded incremental
checkpoint during one run. It must still authenticate each real source and
target, bind the actual prior root/control, durably record intent before effect,
retain unknown outcomes and refuse automatic replay. This is direction for a
driver, not an implemented or reviewed recovery protocol.

The selected seed/calendar tests exited 0 with **11 passed**, seed `791859`,
including a dependent create/correct/forget chain and the retained over-quota
day. Formatting and warnings-as-errors compilation passed. The CLI outputs are
retained in the receipt. No pilot effect, 30/90/365-day run, resource peak,
semantic evaluation or 10,000-change acceptance is implied.
