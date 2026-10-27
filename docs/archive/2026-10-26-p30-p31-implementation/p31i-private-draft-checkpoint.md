# Private P31I draft prototype checkpoint

Historical development evidence, 2026-10-27. This is an incomplete, private
prototype, not the implemented product or an acceptance claim. Current scope
and status are in the [plan](../../plan.md); current usage is in the
[operator manual](../../operator/index.md).

The [frozen patch](p31i-private-draft-prototype.patch) is against commit
`52652f8` and has SHA-256
`37e794657fe7f052ca1542b99d4b90e00c4bfcd3f1489ae42dbf4016b9b25be7`.
Its separately retained [Session test](p31i-private-draft-vertical-test.exs)
and [projection test](p31i-private-draft-projection-test.exs) are also included
in the patch. The [focused test log](p31i-private-draft-test.log), SHA-256
`a525729204c01cb302ebac3066165e32783817bc2a214c2d05ba65a382360e6d`,
records 34 passing tests with seed 20270123 after strict compilation. The
private graph used an isolated build and synthetic provider; no live model or
native-storage qualification is implied.

The slice tests cancellation and accepted-intent withdrawal from subsequent
model inputs and the source window, stale revisions, authority ceilings, and
restart from simulated journal truncation boundaries. Opaque draft continuation
and required compaction fail closed. There is only one draft per session, and
compaction remains blocked after it. If a crash occurs between cancellation and
the separate notice write, replay currently refuses the session rather than
repairing it. The tests do not prove power-loss durability.

The prototype lacks witnessed operator acceptance, draft questions and evidence,
general extension and MCP integration, live-provider qualification, usability
review, and completed independent adversarial review. It must not be exposed as
a user-facing feature or treated as a complete P31I implementation.

Focused command, from the private graph after compilation:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/session/draft_vertical_test.exs test/ipse/session/draft_projection_test.exs test/ipse/session/draft_ceiling_test.exs test/ipse/session/execution_mode_test.exs test/ipse/session/extension_mode_test.exs test/ipse/session/source_window_test.exs test/ipse/session/saved_test.exs --seed 20270123 --max-cases 1
```
