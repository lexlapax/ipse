# Public v4 two-page Session control — 2026-10-29

Historical implementation evidence; the [plan](../../plan.md) owns acceptance.
This control exercises a bounded vector path, not complete document production.
It follows the [v4 Host review](document-inline-v4-independent-review.md) and
the prior [worker checkpoint](checkpoint-20261029-restart.md).

Corpus now projects a version-2 worker continuation into the public
`generation_produce` command, restoring the original store selector and moving
the token out of coverage. Version 1 keeps its existing response path. A model
control passes an eleven-chunk page and its returned continuation through the
actual Corpus callback and synthetic Host; a separate model control assembles
both pages. For this fixture the maximum modeled **store** frame across both
writes and hydration is 12,758 bytes, and hydration uses 47 reads. This is not
a bound for every producer frame or the maximum 256-chunk case.

The fresh canonical artifact built strictly against the reviewed combined Host
graph. In a separate native Session, six synthetic public sources yielded eleven
chunks. The exact returned command advanced cursor 0 to 8; four then two local
synthetic embedding requests produced two ready pages. Public inspection found
both, the previously empty selected root stayed unchanged, Saved reconstruction
passed before and after confirmed close, and the retained journal has 1,704
events and 5,012,675 bytes. Artifact digest was
`33511e825cb6b86da7c490c1ca5b88dffe6bd6d17d635e28b9f682e7a3b082ab`.
This is not live model, populated-old-root, fact production, publication, full
capacity, failure-recovery or quality evidence.

The first attempt failed at loopback admission with `eperm` before Session
startup. The approved next attempt used relative Erlang dependency paths and
returned an unknown extension callback on the first source invocation, with no
host action journaled. Its original Session and journal are retained; the
invocation was not replayed. The successful attempt used absolute dependency
paths and an independent fresh home. The launcher diagnosis is consistent with
worker startup in the artifact directory; it is not a separate proof of every
cause of the unknown callback.

The [manifest](shared-producer-v4-public-session/manifest.json), SHA-256
`a69dd0ad2d6a15b2414e766c79b49938423d830915e941c678b155cf9259ebe2`,
pins 78 copied source, artifact, synthetic journal, output and log files. The
artifact and Host graph remain distinct from subsequent work. Exact retained
homes are named in the evidence metadata. The model measurement was corrected
after the native fixture: the earlier checkpoint's 239 bytes covered hydration
only. The complete producer still needs facts, safe group completion, worst-case
geometry, maintenance, migration, independent review and broader qualification.
