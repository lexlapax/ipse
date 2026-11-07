# Public backup identity refusal, 2026-11-07

This is historical synthetic verification, not a claim of complete migration
support. See the [current plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance).

The test seeds a small private synthetic Collection through trusted test setup,
then obtains the backup page and plan through the public Corpus command. It
checks a valid control before deliberately moving the source head under a
different key and updating the catalog's page hash. The logical head and catalog
contents otherwise match their original identities. The public restore validator
must refuse this rehashed key/head mismatch with
`collection_backup_incomplete_domain` after reading both origin-pinned results.
The test checks unchanged native status and root bytes, no mutating Collection
intent, Saved reconstruction and same-ID idle resume without replay.

The first attempt failed before the valid control: it tried to consume a saved
page from the same active Session, which the retained-source contract rejects.
That fixture and its result remain preserved. The corrected test closes each
producer Session, verifies Saved reconstruction, and creates a new Session for
the next operation; it does not replay the first fixture.

The fresh corrected run passed **one test with 81 excluded** in 18.7 seconds.
It built the public Corpus artifact from the test source, retained the artifact
and private synthetic fixture, and used no model. Independent host checks found
no selected test process, input-lock holder or listener on the test port. The
test source SHA-256 was
`f00be8b60348088928f5822e224b16271ee990c2f34bc13c3d95a97b1cdab434`.
The records were seeded by test helpers, not acquired through the public document
workflow. This control does not qualify general backup, mutation recovery,
installed use or the final whole-source baseline.
