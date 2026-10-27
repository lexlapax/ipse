# P30 source and transport checks in the CLI

Historical component evidence, 2026-10-27. These checks used the working tree,
including the uncommitted inference and managed-collection candidates, and a
fresh isolated Mix build at `/tmp/ipse-cli-compile-check`. The [manifest](SHA256SUMS)
records the checked library, bundled and knowledge source files, the selected
tests and Mix files. Dependencies and test support files are not frozen by this
manifest; this is not a complete reproducible release graph.

`MIX_ENV=test MIX_BUILD_PATH=/tmp/ipse-cli-compile-check ERL_FLAGS='+S 2:2' mix
compile --warnings-as-errors` succeeded. The sandboxed first attempt was refused
because Mix could not acquire its TCP lock; the successful attempt used the
authorized loopback-capable execution environment. Dependency compilation emitted
warnings from `elixir_uuid` and `jsonschex`; the project compilation succeeded.

With the same build, `mix test --no-compile` passed 30 tests across
`test/ipse/decision_test.exs`, `test/ipse/provider/decision_test.exs`,
`test/ipse/usage/decision_test.exs` and
`test/extensions/knowledge/decision_policy_test.exs`, seed 20261106. A separate
run of `test/ipse/provider/decision_transport_test.exs` passed five tests, seed
20261107. Both used `--max-cases 1` and the standard excluded platform tags.
The transport tests used local loopback fixtures, not a live decision service.
Results are from the tool transcript rather than an archived raw log.

These checks do not establish the full P30 baseline, live account eligibility,
consumer integration, quality experiments or P31 completion. The inference
transport candidate was present during compilation but remains unwired and
requires separate integration and security review.
