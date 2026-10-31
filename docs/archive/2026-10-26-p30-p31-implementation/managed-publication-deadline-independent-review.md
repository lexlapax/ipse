# Independent review of publication-deadline follow-up

2026-10-29. This scoped review covers the frozen
[ordinary-publication deadline and question follow-up](managed-publication-deadline-followup.md),
not final P31C0. The reviewer verified all 18 source/artifact entries, 209
runtime BEAMs and helper hash; no broad tests were rerun.

For the tested Session paths, authenticated policy expiry is carried in the
same effect owner, nested deadlines take the minimum and restore previous state,
and root publication uses the native deadline-aware switch. The tests cover
both managed and unmanaged staging and a helper stopped before it processes
the switch. Extension-question recovery now checks the complete parent, has
actual interrupted recovery controls, and the A/B test directly asserts absence
of the candidate publication intent.

The native helper checks the clock immediately before rename, but that check
and the syscall are not atomic. A process can be stopped or descheduled between
them and rename after expiry. The existing stopped-helper test resumes it after
expiry before it processes the queued command; it does not cover that interval.
An actual controlled interposition and a defensible final-switch safety design
remain required. The literal-v4 A/B variant, source-owner death ordering, other
writer paths and the integrated adversarial audit also remain open.
