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

## Later private experiments

The [recovery follow-up](p31i-private-draft-recovery.patch), SHA-256
`4b3d9dd2142b573fc7c2f5c7334ff91642c9041179696adf4d107f626951253f`,
applies after the frozen prototype. It allows explicit repair of the missing
notice after restart while blocking prompts and exports until repair; it has not
received independent review. Its [focused log](p31i-private-draft-recovery.log),
SHA-256 `921b8d61dd259a7e4d6b8ed4f820765e77b6a1774db23c6bb3ddd2562c456277`,
records 34 passing tests, seed 20270124. The simulated boundary is not a
power-loss durability test.

The subsequent [boundary tightening](p31i-private-draft-recovery-boundary.patch),
SHA-256 `4d075ec41e398e8598f57e3049a90faff4f7f993b4b7b1f47d7c45d30f52082c`,
requires an interrupted withdrawal boundary to end at the reconstructed message
tail. The [focused log](p31i-private-draft-recovery-boundary.log), SHA-256
`85712ba04d976214d016e8422af828a97842a2033b4fcd7503b7d122b7d2cf93`,
records nine passing tests, seed 20270125. This follow-up also needs review.

The subsequent [multi-draft experiment](p31i-private-multidraft-failed.patch),
SHA-256 `bf8597f7994654e4f05ac19439a539d0912dd289407b4a7439bb817ec0c4926c`,
applies only after that recovery follow-up. It is a **failed experiment**, not
a repair. The [failure log](p31i-private-multidraft-failed.log), SHA-256
`9a5be51ff8a11171d0fb57c6b6654d1e973cf1c90ef7e51c445879f53394d3ce`,
records the test at `draft_vertical_test.exs:358`, seed 20270124: a second
cancelled draft causes replay to refuse its projection. The experiment is not
in the current private graph. Host reference lineage and safe compaction remain
unresolved, and the frozen patch's documented one-draft limit remains.

An independent later [rebase prototype](p31i-private-draft-rebase.patch),
SHA-256 `f0adf0e0d1ee7d3fcd8c709c57d806bac64b89eab18ebbf830bed78ee9f70b74`,
is again against commit `52652f8`, rather than the preceding patches. It retains
bounded draft intervals and adds an internal digest-bound projection event,
which Saved reconstructs before later compaction. The [test log](p31i-private-draft-rebase.log),
SHA-256 `b96e83774a1fb006827faa5928a99bc5640dfc82de0237c36ea866538f72583e`,
records 48 passing focused tests, seed 20270126, including an actual synthetic
Session compaction and resume. A reference in a withdrawn interval must match
the host's reference structure; replay separately validates its event lineage.
Opaque provider continuation and checkpoint material still refuse projection.
The rebase prototype is private and provisional, lacks operator attestation and
UI integration, and requires independent adversarial review. It does not close
P31I or establish live route quality or cross-crash native fencing.

The later [private terminal prototype](p31i-private-draft-terminal.patch),
SHA-256 `6435f1840a4e27a47d07eb998b00899fd260a531204ed857d9f94425a79b7410`,
is against `52652f8`. Its [test log](p31i-private-draft-terminal.log), SHA-256
`29f1caf79f05df90c74c55059fdc6fecd5b1fbfb04cc166330443f0f385fea46`,
records 72 focused passes with seed 20270129. Synthetic native PTY journeys cover
the private Terminal and Session paths for original input, single-line
replacement, rendered-code acceptance, and rejection of a forged witness.
Unwitnessed acceptance and version-1 acceptance replay are refused. This is not
evidence of a human tester, a live provider, or release readiness.

The private prototype still lacks multiline editing, draft questions and their
evidence lineage, complete source/effect coverage, and final independent audit.
Reference occurrence membership relies on the trusted Session and validated
journal, rather than proving occurrence chronology by itself. Opaque provider
continuation can make subsequent dispatch and resume fail closed, requiring an
explicit fresh-session recovery. The prototype has not been added to the shared
runtime or current operator manual.
