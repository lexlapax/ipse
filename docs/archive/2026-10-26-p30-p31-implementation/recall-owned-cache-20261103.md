# Reuse source reconstruction across admitted inference scopes — 2026-11-03

The strict synthetic 33-source recall journey now passes with its selected
five-second provider limit unchanged. It sends all 32 eligible note bodies,
reports partial coverage for the temporarily missing original, and reopens idle
without replay. This closes that bounded gate, not the 2,000-note populated day,
annual workload, installed-package or complete P31 acceptance.

## Observe the actual scope boundary

After the [canonical encoding optimization](recall-canonical-encoding-20261103.md),
a fresh failing diagnostic captured the error notification the earlier fixture
had skipped. Its safe trace recorded 209 targeted records without truncating the
record buffer. The bounded ancestry map overflowed, so this is not a complete
process trace. The surfaced error hash matches the fixed unknown-service-outcome
message without an inner detail; it is not a typed timeout diagnosis.

The original task's cache reconstructed 32 source histories in 2,515,270
microseconds, then served 32 fresh-index hits. The transport's separate cache
reconstructed 32 histories again in 2,552,012 microseconds. Those latter folds
completed within the five-second controlled-work interval. The socket accepted
but closed before request bytes, and the current-wire/send continuation did not
run. Observed kills occur near that interval's end, but they do not show the
reporter's own `controlled_wait` timeout branch. Source inspection and retained
ancestry identify the additional inference-slot scope between the original task
and transport child. The [diagnostic summary](recall-owned-cache-20261103/diagnostic/summary.txt)
keeps these observations, scheduling limits and unknowns distinct.

## Preserve one owner for pure reconstruction

`InferenceSlots.start` now creates its scope through
`Resources.start_with_source_replay_cache/1`. The existing admitted coordinator
obtains or creates the original task scope's pure cache before the gate runs.
That original scope remains its sole owner. The inference-slot scope borrows
the capability, and authenticated controlled-child registration passes the
same borrowed capability onward. This avoids a second cold cache after the gate
has populated the first one.

Borrowers drop their reference at cleanup and never close or recreate a dead
borrowed cache. Ordinary independent scopes keep their existing ownership; a
parentless scope still owns its own cache. No caller-supplied index, new policy
grant, public configuration or worker/JSON capability is admitted. The full
Session ID and decoded-event digest remain the key, the original 128-entry/8-MiB
bounds remain, and returned indexes receive fresh query identities and secrets.
Every source use still rereads and locks its original journal, validates pages,
resolves proofs and checks current owners, source eligibility and permission.
No deadline, original-source lease or native guard changed.

## Verify current source and actual recall

The isolated candidate comes from `ace41c75` with only the reviewed Resources,
InferenceSlots and source-cache test changes. All 195 host/bundled source modules
compile with warnings as errors. Focused tests report **75 passed in 14 seconds**,
seed 0: 13 replay-cache, 25 inference-slot and 37 stored-source controls. They
cover three scope levels, warming after scope creation, fresh handles, changed
event bytes, foreign callers, dead borrowed caches, independent ownership,
borrower loss and original-owner loss with a suspended cache. Source, dependency,
runtime, helper and path/symlink inventories matched afterward.

The actual qualification uses the exact catalog and 77 artifact files from the
earlier diagnostic runtime, verified before and after copying. It does not rebuild
workers or claim an installed-package result. The host source is newly compiled;
the unchanged native helper is reused. Build state uses isolated task-owned
Mix/Hex/home locations and the already installed Hex archive, without fetching
dependencies. Protected synthetic Session state remains on the qualified tmpfs.

The [new untraced control](recall-owned-cache-20261103/qualification/summary.txt)
reports **one passed, four excluded**, with test,
filter and source/runtime postcheck exits all zero. It creates new sources and a
new consuming Session; no earlier unknown turn is resumed or replayed. One original
source disappears during selection and reappears before final preflight. The
fixture reconstructs every selected note from its contiguous parts, checks exact
keys, revisions, byte counts and complete text, and binds each part to its actual
successful read operation. It excludes the missing note and retains explicit
partial coverage even after reappearance. Strict Saved reconstruction, confirmed
close and same-ID idle reopen succeed with no new input, action, worker-input or
inference-dispatch intent. All 33 original journal/lock identities and journal
hashes remain unchanged. Its whole model-request measurement is 15,185 ms,
including managed preflight and other work; this is not a measurement of the
inner five-second transport interval or a comparative latency bound.

The [source-ownership chapter](../../developer/session-sources.md) integrates the
three-scope ownership and refusal contract. Its whole-document review preserves
the separate source, effect and native-owner explanations. The operator memory
chapter remains accurate: the change adds no command or new source authority.
The complete source/package/audit gates remain separate from these focused
checks. The [plan](../../plan.md) owns the next populated-workload and milestone
gates. The sibling evidence manifests pin the diagnostic, current-host checks
and qualification inputs and outcomes; raw private journals and terminal output
remain outside this archive.

The tracked-source documentation mirror, overlaid with this exact candidate,
passes `elixir dev/check-docs.exs`: 1,138 Markdown files, 9,456 local links and
manual/archive rules, zero errors. The mirror excludes unrelated private files.
