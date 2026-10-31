# Final root fence for group append — 2026-10-29

Historical implementation evidence following [split metadata staging](shared-producer-v4-split-append.md);
the [plan](../../plan.md) owns acceptance. This is a private group-append
repair, not full knowledge or release qualification.

The final append continuation previously inspected its prepared Job and catalog
stages and checked immutable prerequisites at a fixed generation, but did not
recheck the selected root after those inspections. A root mutation in that gap
could leave the append acting on an older captured root. It now stats the exact
captured root revision and hash, or confirms its absence, at the generation used
for final prerequisite checks. The existing generation-pinned atomic commit
refuses any later intervening mutation. The extra stat is included in the
existing provisional control-read reserve.

A protocol control changes the root after both stage inspections and confirms
refusal before commit. A direct native DocumentStage fixture also injects a root
write at that boundary: the subsequent stale-generation stat refuses, the Job
cursor remains zero, and both original metadata stages remain. A separate fresh
native fixture completes the ordinary atomic append. The clean run retained the
normal store at `/tmp/ipse-split-append-338a6eec9d3b8dae24984851ca59ef96` and
the interposed store at `/tmp/ipse-split-append-ef97280af260d03134d9193f5c7f9abd`.
An earlier run passed both cases but emitted a test clause-order warning; its
log and stores are retained. These controls use native storage directly, not a
Session owner-loss or wide native producer journey.

The 256-chunk, 256-wide-escaped-fact synthetic group completed with the extra
root check: 44 private append invocations, 410 hydration reads and a maximum of
464 reads in an append invocation. Test execution took 269.3 seconds. The
strict artifact build and focused compatibility controls passed. This does not
prove maximum escaped citation/metadata widths, callback deadlines, Session
journal handoffs, physical peak, actual model quality, or complete reservation
and crash-boundary safety.

The [manifest](shared-producer-v4-final-root-fence/manifest.json), SHA-256
`3fab85bf84d664ba9e16f67de309b440f850a871a84f7ddfec618e7c5a6283a6`,
pins 76 source, artifact, fixture and log files. Its dense artifact was not rerun
in a public native Session after this narrow fence; the direct native controls
compiled the current source against the recorded Host graph. No live model call
or quota change ran. Independent review and the remaining P30/P31 gates are open.
