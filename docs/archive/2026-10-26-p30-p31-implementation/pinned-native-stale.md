# Pinned document reads and intervening native commits — 2026-10-29

Historical focused evidence for the [pinned reader](shared-producer-v4-pinned-read.md);
the [plan](../../plan.md) owns acceptance. The domain Collection client is
driven against actual native `DocumentStage` storage in a fresh synthetic home,
without a Session, provider or remote inference.

The test stores a 7,011-byte JSON value, starts `value_read_at` at generation 1
and obtains its stat. An independent write advances the native generation to 2;
the pending read at generation 1 refuses, and the client reports a refused
operation rather than refreshing the snapshot. It then starts an
`object_read` with exact logical hash, length, revision and generation 2. After
the first page, a second write advances generation to 3; the remaining read
refuses and no partial value is returned. A retained read confirms the original
value and revision at generation 3. This exercises native interposition between
calls, not concurrent Session ownership loss or a full producer journey.

The first fresh fixture reached both expected refusals but its final inspection
asserted the wrong witness field, so the callback returned unknown. It made no
subsequent mutation. The corrected independent fixture passed. Both stores are
retained at `/tmp/ipse-pinned-read-1ce1e5e3e88a34692288f3a67a1d8cd1` and
`/tmp/ipse-pinned-read-0a382c81669fd07f6f55f96a78635f49` respectively.
Do not replay their operations.

The [manifest](pinned-native-stale/manifest.json), SHA-256
`a6573f3a1ddfa400075f23d89b0ec7423af66c1c586796160e658748f9641eb1`,
pins the current fixture, launcher and both logs. It references the separately
frozen producer/Host ancestor; no live account or paid inference ran.
