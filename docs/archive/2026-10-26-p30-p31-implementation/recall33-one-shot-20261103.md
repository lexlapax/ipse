# Strict 33-note recall attempt — 2026-11-03

This synthetic one-shot attempt did **not** complete the provider request or
qualify the 33-note journey. It used the isolated `bde96d0a` plus Worker v4
coalescing candidate described in the [combined review](worker-v4-coalescing-bde96-20261103.md),
not an installed package, live model, or annual workload. The earlier 2,000-note
cohort was not used.

The exact [fixture patch](recall33-one-shot-20261103/recall33-fixture.patch)
has SHA-256 `4ff8701b0e87d1d2d0f2ba8c60c7ae060847bcd9b25052ee886ca0810b783ae3`.
The [fixture source manifest](recall33-one-shot-20261103/recall33-fixture-source.sha256)
has SHA-256 `0361ff78edffa81f6b81d2a731d5e5d330cb2ed59034356f3943c3c0e20ce10d`;
the [unchanged candidate inputs](recall33-one-shot-20261103/recall33-unchanged-source.sha256)
are recorded separately. The combined review retains the exact candidate patch,
compiled-runtime/native-helper and bundled-artifact inventories. The
[post-check log](recall33-one-shot-20261103/recall33-post-check.log) reports
matching frozen input, build and bundle entries after the attempt. Those
inventories do not capture every possible toolchain or environment input.

The fixture created 33 reviewed literal notes in 33 synthetic source Sessions,
closed them, and withheld the first sorted note's original journal. It created
a new consuming Session and recorded a separate
[one-shot intent](recall33-one-shot-20261103/recall-one-shot-intent.json).
The source-reappearance hook was installed before that Session's prompt. The
fixture's listener was bound to an isolated loopback endpoint; its accept task
started after seeding. The fixture-only PTY and outer limits were 900 and 960
seconds. They did not enlarge the Worker or provider deadlines.

The [retained one-shot log](recall33-one-shot-20261103/recall33-one-shot.log)
reports failure, and the [completion record](recall33-one-shot-20261103/recall33-completion.txt)
records test exit 2 and post-check exit 0. The redacted
[consumer event projection](recall33-one-shot-20261103/consumer-event-projection.jsonl)
and [aggregate counts](recall33-one-shot-20261103/consumer-counts.json) show:

- All 37 recorded Worker-input results were delivered. Thirty-two Collection
  gets succeeded and one reported `collection_original_source_missing`.
- Before dispatch, a `context.publish` intent contained 32 `note_parts_v1`
  rows and partial coverage reporting 32 included and one unavailable. The
  following managed preflight projected 35 eligible dependency verdicts.
- An `inference_dispatch_intent` was followed by a failed measurement at
  15,799 ms, a failed partial request result at 15,800 ms, and a turn error.
  These events record no failure reason or timeout.
  The fixture reported that its loopback connection closed without request
  bytes; this does not prove a network-wide absence of activity.

The fixture did not receive a provider request, so its structured exact
key/revision/text assertions and idle-reopen/no-new-intent checks were not
reached. The context intent and its coverage do not prove those 32 notes reached
the model. No cause for the failed request is established.

The [before inventory](recall33-one-shot-20261103/recall-source-before.json)
records all 33 synthetic source journals and lock identities. A separate
read-only [comparison](recall33-one-shot-20261103/source-check.txt) found all
33 original journal device/inode/owner/hash values and lock device/inode/owner
values unchanged, with no matching `.held` paths. This is not a complete
Collection root/control or consumer-journal post-comparison. The fixture's
result and after-inventory files were absent. The full synthetic consumer
journal remains in volatile `/dev/shm`; its [hash](recall33-one-shot-20261103/volatile-consumer-sha256.txt)
is retained, but the redacted projection is not by itself a cryptographic proof
of every original journal event. Preserve the failed Session and do not replay
its uncertain work.

The [evidence manifest](recall33-one-shot-20261103/evidence.sha256) has SHA-256
`a6c04c03aa3e54c9bc44016bdbde8b42df6f8f3fff9a4fa21f246c4c3c4f98b5`.
All retained inputs and logs are synthetic. The exact consumer root is volatile;
the recorded evidence is a scoped failure receipt, not a successful recall,
live-use, or workload qualification.
