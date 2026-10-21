# Explicit memory measurement

The bundled working/persistent memory extensions use local explicit notes and
lexical retrieval. See [operator setup](../../docs/operator/memory.md) and the
[extension contract](../../docs/developer/memory.md) before using real data.
Neither extension is selected by running this measurement in another session.

From a built source checkout:

```sh
mix run scripts/measure-memory.exs
```

The command delegates to `Ipse.Development.Experiments.Memory` in
`dev/experiments/memory.exs`. It creates isolated temporary operator, project and
session directories and removes them afterwards. It explicitly enables persistent project notes only in
those fixtures, uses approved synthetic commands, and raises if any provider
inference is attempted. It runs 100 seeded records and 100 queries across two
projects and three sessions per project, including source updates, expired notes,
forgotten notes and absent answers. Expired-state setup is a deliberate fixture
write at an old timestamp; it is not a live waiting/clock test. Separate regression
tests cover write conflicts, delayed work, scope, permissions, collection and
unchanged resume. The installed package verifier runs the same corpus using only
the packaged runtime, with the system development toolchain absent from PATH.

To run that same experiment through the shared source or installed host boundary:

```sh
elixir scripts/verify.exs source memory \
  --sdk _build/dev/lib/ipse/ebin --input examples/memory/corpus.json
elixir scripts/verify.exs installed memory \
  --archive /absolute/path/to/ipse-runtime.tar.gz --input examples/memory/corpus.json
```

Replace the archive placeholder with a compatible package for your host. The
common verifier compiles the trusted experiment before starting the selected
runtime and checks unchanged corpus and executable inventories. Its `package`
scenario includes the same memory assertions alongside broader CLI checks.

`corpus.json` is frozen synthetic data, not a scraped or human-evaluated dataset.
Its SHA-256 is reported so later corpus edits cannot be mistaken for the same
measurement. Queries deliberately use exact policy markers. Reported recall@5,
retrieval/abstention and exact byte-span scores are fixture results, not semantic
answer or citation-quality benchmarks and not a Zero-Mem comparison. No model,
encoder, database, API key or network service is required. Model cost is absent
because model dispatch is forbidden; unmeasured future services are not free.

The JSON result also reports p50/p95 end-to-end command latency, current state
file bytes, observed VM-memory samples and the actual runtime/scheduler count.
Those samples are not a peak-memory bound; timings are not portable promises.
The tool returns at most five results, so nDCG@10 is not measured. Consult the
[verification record](../../docs/archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks)
for source and installed results with their exact scope and remaining gates.
