# Full-cohort integrated-day runner preflight, 2026-11-02

This historical preflight covers the proposed full-cohort runner's pure calendar
and restart guards. It does not establish a full-cohort run or milestone
acceptance. The [plan](../../plan.md) owns current scope; the separately retained
[seven-note smoke](integrated-final-smoke-20261102.md) remains distinct.

The tested isolated snapshot was commit
`a6ba4874e24734cddbab5ad8c41c16bee3527e2e` plus the three files in the
[source fingerprint manifest](integrated-full-day-preflight-20261102.sha256).
It used separate dependencies, build and home. The targeted files were formatted;
the native and bundled build and forced test compilation with warnings as errors
passed. The focused test command was:

```sh
mix test test/dev/knowledge/native_notes_integrated_full_test.exs --max-cases 1 --seed 791955
```

It reported **2 passed, 1 skipped**. The skipped test is the explicitly opted-in
2,000-note native run. No seed, live full initializer, full-day effect or Session
turn was executed in this preflight.

The same three files were subsequently checked in a fresh isolated snapshot of
`b10df4a556c097b686eecba1267e3d6425f0f8bc`, excluding duplicate `docs/archive`.
Its native/bundled build, test compilation with warnings as errors and focused
checks also passed: 2 passed, 1 skipped, seed 791956. The populated run started
after these checks and is separate from this preflight result.

The pure test computed the provisional 20-intake calendar and segmented its
28,952 annual effects one per segment under a 64,000,000-word process heap cap.
The encoded segment list occupied 6,450,200 bytes and its digest map 2,160,295
bytes. The test's post-encoding process-memory sample was 26,891,088 bytes; it is
not a peak. The actual initializer additionally holds the real seed records and
source metadata and may add a consent-renewal segment. Its memory, encoded
outputs and runtime remain unmeasured. The initializer's files are encoded and
decoded directly with Jason; the unrelated bounded-JSON API limits do not define
their allowed sizes. No existing heap, storage, or operation limit was increased.

The proposed first day freezes 20 ordinary additions, four corrections, two
forgets, four temporal updates and 27 additional mixed changes, interleaved in
four groups with 40 actual Session turns. This is a synthetic working fixture;
its intake and mix are not pilot-derived, ratified or established as
representative. The separate runner is designed to retain the fresh seed,
original sources, audit rows, per-effect and per-turn records and resource
samples, and to refuse automatic replay of an interrupted run. Those end-to-end
claims still require the unrun full test. Its 12-hour test timeout is a safety
guard, not a predicted runtime; a timeout leaves an interrupted or unknown run
whose process state and retained markers must be inspected without replay.
