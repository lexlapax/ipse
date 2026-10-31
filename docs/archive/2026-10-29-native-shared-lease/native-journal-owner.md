# Native-owned Session journal mutations

Dated 2026-10-29. This focused repair is awaiting independent review; it is not
P30/P31 acceptance. The [plan](../../plan.md) remains authoritative, and managed
output remains gated. Earlier [fresh](release-receipt-integration.md) and
[resume](release-receipt-resume.md) evidence is historical: the independent
[review](release-receipt-integration-independent-review.md) reproduced a
native-lock-loss race in those cohorts.

The Session process could be paused after verifying a resumed lock. Killing the
real helper then allowed an independent contender to acquire the flock while the
Session's tracked file peer nevertheless appended a new owner marker. A BEAM
monitor or another liveness check cannot fence a queued write against that race.
The retained original probe is in the [review evidence](evidence/release-receipt-review/).

For the versioned Linux fresh/resume layout, Elixir still owns JSON encoding,
quota admission, event ordering and lifecycle policy. Writer now sends each
bounded opaque JSONL line to the native process that retains the Session flock.
The helper stages bounded chunks, checks the retained and named lock, journal
inode, protection and expected size, then writes and fsyncs the line itself.
The tracked Writer does not report success or dispatch an effect until the
native response is confirmed. A timeout, partial response, helper loss or
interrupted write is unknown and is not automatically replayed. If the owner
dies during a native syscall, that helper retains the flock while the syscall
is in progress; no BEAM file-server peer is assumed to have stopped merely
because its caller died. Tracked read-only work prepares torn-tail repair, and
the same native lock owner validates and performs the bounded truncate or final
newline write and sync. The previous header transfer bounds remain unchanged.

New Linux headers record the retained lock device and inode before header
publication. A later owner opens the existing lock without creating it and
matches the header anchor and any prior intent before doing work. This permits
recovery even when the first owner died before its first release intent. An
older opted-in header lacking both anchor and intent refuses active resume;
unmarked legacy journals keep their prior paths and do not gain this guarantee.
Direct inactive/legacy Writer and repair entry points refuse the versioned
layout, rather than writing around the native owner. No old header is rewritten.
Native release publication now checks the admitted 128 MiB whole-journal bound,
separate from the 16 MiB single-header transfer bound.

The [matching startup-loss control](evidence/native-journal-owner/v6-start-loss.log)
uses the reviewer's same rendezvous: after the real helper is killed and a real
contender holds the flock, startup refuses and the journal remains unchanged.
The [hook controls](evidence/native-journal-owner/final-hook.log) cover helper
death before append, Session death after native write but before sync while a
contender is excluded, and helper death before torn-tail repair. The
[focused Session controls](evidence/native-journal-owner/v5-test.log) cover
normal fresh/resumed close, matching original identities, crash recovery via
the new header anchor, refusal of unanchored older opted-in headers, unchanged
legacy headers, and missing/substituted locks. The separate
[large-journal and policy controls](evidence/native-journal-owner/final-fencing.log)
cover two 8.5 MB records in one journal larger than 16 MiB, a signed release
claim, quota sealing, authorization, inactive-entry refusal and valid
unterminated-record repair. The [credential-free demo](evidence/native-journal-owner/demo.log)
completed in a synthetic workspace. The separately compiled
[old-helper control](evidence/native-journal-owner/old-test.log) refused framed
resume without an unsafe fallback. Earlier failed compile, fixture and chunk
boundary controls are retained with their subsequent passing runs.

The exact [source snapshot](evidence/native-journal-owner/source.tar),
[standard](evidence/native-journal-owner/runtime-standard.sha256),
[test-hook](evidence/native-journal-owner/runtime-hook.sha256),
[combined-hook](evidence/native-journal-owner/runtime-combined.sha256),
[old-helper](evidence/native-journal-owner/runtime-old.sha256) inventories, and
[manifest](evidence/native-journal-owner/manifest.sha256) identify these local
cohorts. They are copies of prior graphs, not a clean-checkout build recipe.
The commands below describe the recorded incremental builds; intermediate source
versions differ from the final snapshot and are represented by their logs, not
claimed to be recoverable from that snapshot.
The standard helper was built with `rustc --edition=2021 -D warnings
native/ipse-runner.rs`; the hook helper additionally uses `--cfg
ipse_native_journal_test_hook`. Runner is compiled against the matching copied
helper pin. Focused commands:

```sh
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-native-journal-sol-20261029/lib elixir -e 'Code.compiler_options(ignore_module_conflict: true); case Kernel.ParallelCompiler.compile_to_path(["_build/session-native-journal-sol-20261029/source/lib/ipse/runner.ex", "lib/ipse/session/lock.ex", "lib/ipse/journal.ex", "lib/ipse/journal/writer.ex", "lib/ipse/session.ex"], "_build/session-native-journal-sol-20261029/lib/ipse/ebin", return_diagnostics: true) do {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("SESSION_NATIVE_JOURNAL_COMPILE_OK"); result -> IO.inspect(result); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-native-journal-v4-sol-20261029/lib elixir -e 'Code.compiler_options(ignore_module_conflict: true); case Kernel.ParallelCompiler.compile_to_path(["lib/ipse/journal.ex", "lib/ipse/journal/writer.ex"], "_build/session-native-journal-v4-sol-20261029/lib/ipse/ebin", return_diagnostics: true) do {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("NATIVE_JOURNAL_V4_COMPILE_OK"); result -> IO.inspect(result); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-native-journal-v5-sol-20261029/lib elixir -e 'Code.compiler_options(ignore_module_conflict: true); case Kernel.ParallelCompiler.compile_to_path(["lib/ipse/session/lock.ex", "lib/ipse/session.ex"], "_build/session-native-journal-v5-sol-20261029/lib/ipse/ebin", return_diagnostics: true) do {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("NATIVE_JOURNAL_V5_COMPILE_OK"); result -> IO.inspect(result); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-native-journal-v6-sol-20261029/lib elixir -e 'Code.compiler_options(ignore_module_conflict: true); case Kernel.ParallelCompiler.compile_to_path(["lib/ipse/journal.ex"], "_build/session-native-journal-v6-sol-20261029/lib/ipse/ebin", return_diagnostics: true) do {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("NATIVE_JOURNAL_V6_COMPILE_OK"); result -> IO.inspect(result); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-native-journal-v7-sol-20261029/lib elixir -e 'Code.compiler_options(ignore_module_conflict: true); case Kernel.ParallelCompiler.compile_to_path(["lib/ipse/cli/errors.ex"], "_build/session-native-journal-v7-sol-20261029/lib/ipse/ebin", return_diagnostics: true) do {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("NATIVE_JOURNAL_ERRORS_COMPILE_OK"); result -> IO.inspect(result); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-native-journal-v7-sol-20261029/lib elixir dev/fixtures/session_journal_lock_loss.exs
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-native-journal-v7-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/native_journal_fencing_test.exs")'
IPSE_NATIVE_JOURNAL_HOOK_TEST=1 ERL_FLAGS='+S 4' ERL_LIBS=_build/session-native-journal-v6-hook-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [line: 140, line: 187, line: 242]); Code.require_file("test/ipse/session/native_journal_fencing_test.exs")'
```

The native test hooks are not present in the ordinary helper. Compatibility and
recovery on non-Linux systems are not established by these controls. A signed
release claim still does not prove that a lost publication reply was received,
and no claim retroactively cleans an earlier epoch. Independent review must
examine source and syscall failure boundaries, exported capabilities, protocol
ordering, resource cleanup and the precise support scope before qualification.
