# Leased terminal deadline rounding, 2026-11-03

This receipt concerns an isolated candidate based on commit
`b48b34c3aec99f330ac7bd75e17afbe1a33ca5e6`; it is not evidence of a completed
acceptance journey or an integrated release. The candidate and its synthetic
logs are retained at `.terminal-rounding-b48.ILja5INM` in the repository root.
The snapshot was extracted from that commit without the duplicated archive and
used separate task home, temporary and build paths. No paid service was used.
The three exact reviewed overlays were later copied into the worktree for this
checkpoint; full integrated-source verification remains open.

The candidate reserves one millisecond when converting both display and overall
review deadlines to native milliseconds and refuses when no positive time
remains. A deterministic fractional-boundary test demonstrates the prior
rounding overrun under an equal-rate clock model. It also checks negative, zero,
one-millisecond, ordering and overflow cases. This repairs the proven rounding
issue; it does **not** establish that BEAM and native monotonic clocks have the
same rate or suspend behavior. That wider clock assumption remains open.

## Candidate fingerprints

| Path in snapshot | SHA-256 |
| --- | --- |
| `lib/ipse/runner/leased_terminal.ex` | `c309aacb689dce96966c57772935f4fbcc05d127415157c517b2679e1c3d36e2` |
| `test/ipse/runner/leased_terminal_deadline_test.exs` | `9975fcbe8b3165c2e30cc8e65cc8f667018dc0d21b7f2f4d85771df942934408` |
| `native/README.md` | `36d0b596f4c5662e8b4385d5b85243b8987f2ab1e2f9ac19739dd973bc43ae9c` |

After the tests, whole-document review corrected the native guide's transaction
quota and host-flow link, and updated the developer Session and testing guides.
The final `native/README.md` hashes to
`891f131b62d6e219635bd2d3cd44e0e704d2b03af31f3f4a54a9c17053d9bd8c`;
the tested runtime and test files remain byte-identical to the table. A sanitized
git-backed documentation check passed 1,108 Markdown files and 9,101 links.

## Checks and retained outcomes

The changed Elixir files passed `mix format --check-formatted`; test-environment
`mix compile --warnings-as-errors` passed with local TCP access. The initial
sandboxed compile failed before compilation because Mix could not open its
local TCP lock; `final-compile.log` preserves that failure and
`final-compile-tcp.log` the successful retry.

The focused deadline file passed two tests (`deadline-unit.log`). Two existing
native PTY synthetic review controls passed independently: grouped source
(`terminal-review-group.log`, one passed, 82 excluded) and active source
(`terminal-review-active.log`, one passed, 82 excluded). An existing genuine
synthetic Session supersession scenario passed after offline bundles were
built (`terminal-review-real-ready.log`, one passed, 12 excluded). It used a
fresh synthetic root; it does not prove the unfinished same-reply acceptance
path. Earlier fresh attempts stopped before review because the workspace
filesystem did not support project identity (`terminal-review-real.log`) and
the command reported `extension_bundle_unavailable`
(`terminal-review-real-tmpfs.log`). The underlying reason for the latter was
not independently established; the bundles were then built before the passing
fresh run. Neither failed root was resumed or reused.
The native helper, PTY driver and offline extension bundles were built locally.
The final candidate also passed `./dev/build.sh` with offline dependencies
(`final-build.log`).

The full integrated suite remains a later gate. The logs and exact source and
log hashes are listed in the snapshot's `terminal-rounding-manifest.sha256`;
the evidence is synthetic and the temporary test roots were cleaned by their
fixtures. The manifest and retained snapshot are local inspection artifacts,
not a replacement for a final integrated-source test.
