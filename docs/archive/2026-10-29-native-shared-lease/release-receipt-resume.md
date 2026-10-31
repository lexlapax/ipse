# Linux resumed Session release claims

Dated 2026-10-29. This focused follow-up to the [fresh Session integration](release-receipt-integration.md)
is awaiting independent review. It does not establish P30/P31 acceptance or
enable managed output. The [plan](../../plan.md) remains authoritative.

On Linux, a journal explicitly carrying `session_release_receipt_v1` and at
least one valid previous release intent can start a new owner using the
`--session-resume-v1` native lock from its first acquisition. This mode opens an
existing protected lock file without creating one, refuses header creation and
export, and returns the retained device and inode. After the original journal
origin is verified under that lock, the host checks that the retained lock
matches the latest validated historical intent before repairing a torn tail or
appending a fresh owner marker. No live lock is released and reacquired to
enable the framed mode.
The resumed owner records its own intent, obtains its own framed release and
publishes its own signed claim. A new owner does not change a prior lifecycle
closure or turn an old sidecar into a current claim.

If no earlier intent exists, the v1 owner markers do not identify the original
lock inode. Such a journal keeps the existing legacy resume path; its close is
unconfirmed and records a conservative lifecycle closure, without a new claim.
Older headers without the receipt layout also keep their legacy behavior and are
not rewritten or upgraded. Unsupported framed helpers refuse rather than
falling back. This retains the cooperative same-user boundary and does not prove
anything about non-Linux platforms. A stopped lifecycle recorder, missing
acknowledgment, or lost publication remains unknown as in the prior record.

The [standard control](evidence/release-receipt-resume/final-test.log) passed
seven focused cases covering fresh and resumed clean claims, unchanged header and
journal inode, torn-tail repair, no-prior-intent and unmarked legacy behavior,
missing and substituted lock refusal, native loss, and refusal to create a
header through the resume helper. The [separate helper-hook control](evidence/release-receipt-resume/race-final.log)
passed two actual controls: a second BEAM VM resumed between the original lock
release and original sidecar publication, and a resumed owner died after unlock
but before its native reply. The former published a distinct newer claim; the
latter returned unknown and created no new sidecar. An [older pinned helper](evidence/release-receipt-resume/old-test2.log)
refused its unknown resume command without changing the journal. The first
[missing-lock test](evidence/release-receipt-resume/test.log) failed because the
fixture did not trap its intentionally failed linked startup; the repaired
fixture passed and the original failure remains.

The [source snapshot](evidence/release-receipt-resume/source.tar),
[standard runtime](evidence/release-receipt-resume/runtime-standard.sha256),
[hook runtime](evidence/release-receipt-resume/runtime-race.sha256),
[old-helper runtime](evidence/release-receipt-resume/runtime-old.sha256), and
[manifest](evidence/release-receipt-resume/manifest.sha256) preserve the local
cohorts. They copy the previously inventoried graph and are not a fresh-checkout
build recipe. The old-helper graph uses the earlier independently pinned helper;
its source is in the prior header evidence. The final focused commands were:

```sh
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-resume-v2-sol-20261029/lib elixir -e 'Code.compiler_options(ignore_module_conflict: true); case Kernel.ParallelCompiler.compile_to_path(["lib/ipse/session.ex"], "_build/session-release-resume-v2-sol-20261029/lib/ipse/ebin", return_diagnostics: true) do {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("RELEASE_RESUME_V2_COMPILE_OK"); result -> IO.inspect(result); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-resume-v2-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [line: 37, line: 227, line: 242, line: 265, line: 293, line: 359, line: 383]); Code.require_file("test/ipse/session/native_header_session_test.exs")'
IPSE_RELEASE_HOOK_TEST=1 ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-resume-race-v2-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [line: 458, line: 511]); Code.require_file("test/ipse/session/native_header_session_test.exs")'
IPSE_OLD_RESUME_GRAPH=_build/session-release-resume-old-sol-20261029/lib ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-resume-v2-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [line: 322]); Code.require_file("test/ipse/session/native_header_session_test.exs")'
```

The standard helper was built with `rustc --edition=2021 -D warnings
native/ipse-runner.rs`; the test helper adds `--cfg
ipse_session_release_test_hook`. Runner was compiled from the graph's copied
source against its matching helper pin. The prior fresh integration and this
resume extension both require review of their publication and owner-loss
semantics before any milestone is marked complete.
