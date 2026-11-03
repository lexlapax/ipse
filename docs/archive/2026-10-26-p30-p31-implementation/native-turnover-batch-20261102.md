# Batch the native turnover smoke with compensated clock anchors

Dated **2026-11-02**, based on `4e43b81` plus the frozen scripts, inputs and
closure hashes in the [receipt](native-turnover-batch-20261102.json). This is
an author-run fixed smoke prototype, not the annual driver or P31C1a acceptance.
The [plan](../../plan.md) owns status and the
[storage chapter](../../developer/knowledge-storage.md#populate-through-actual-native-statements)
owns the procedure.

The [first prototype](native-turnover-batch-v1-20261102.exs) continued a fresh,
signed-audited seven-note seed through the same seven native lifecycle effects
as the [earlier pilot](native-turnover-pilot-20261102.md), in three batches of
four, two and one effects. One invocation closed the first batch; a fresh
invocation verified the prior closures once and completed the other two. Each
child checked the immediate prior closed state, authenticated its actual target
through the existing host paths, used a retained lock and wrote an in-flight
marker before effects. An independent [signed final-state audit](native-turnover-batch-audit-v1-20261102.exs)
passed. A completed-run attempt refused before dispatch, and a second audit
matched the first byte for byte.

The [second prototype](native-turnover-batch-v2-20261102.exs) used another
fresh seed and four batches: two batches on simulated day 2, two expiries on day
92, and one expiry on day 368. The first and second batches ran in separate
parent and child processes. Their saved day-2 anchor had the identical SHA-256
before and after restart. The [audit](native-turnover-batch-audit-v2-20261102.exs)
checked each input/closure, the retained day anchors, ordered virtual timestamps,
the final signed records and control state, and five saved Sessions. The final
generation and control sequence were 15. Another completed-run attempt refused,
and a repeated audit was byte-identical.

The anchor uses the [compensated clock plan](native-calendar-clock-anchor-20261102.md).
For this smoke, the initial prior-time bound is current unshifted real time plus
the last seed-day offset. That is conservative only if the real clock did not
step backwards between seed closure and the observation; this assumption is
recorded in the prototype manifest and has not been independently proven.
The actual stdio clock fixture was checked in each child. The runs executed no
main turns or model requests. Their source uses a fixed seven-effect plan and
prints compile-time warnings for dynamically loaded clock functions; no clean
warnings-as-errors result is claimed for the scratch scripts.

The experiments cover clean shutdown and restart after confirmed batches. They
do not establish active-effect loss, concurrent restarts, power-loss durability,
long-duration clock stability, maximum-value or annual capacity, or the
10,000-change workload. A scalable driver still needs the full calendar, actual
turns, quota and recovery controls, measured performance and review before the
audited 2,000-note seed is changed. No runtime permission, provider or storage
limit changed.
