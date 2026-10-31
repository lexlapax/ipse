# Linux Session release-claim integration

Dated 2026-10-29. This is a focused integration under independent review, not
P30/P31 acceptance. The [plan](../../plan.md) is authoritative. The preceding
[pure contract](release-receipt-contract.md) and its independent reviews remain
historical. Managed correction and managed-result output remain gated.

New Linux fresh Session headers select `session_release_receipt_v1`. After
locked source verification and any validated torn-tail repair, every owner of
such a journal durably records a fresh owner marker before startup work. Close
records the conservative lifecycle closure and a signed-intent precursor while
the Writer and original lock remain held. The native header lock owner reports
its retained lock identity and checks it again at release. Only after dependent
cleanup, Writer termination, and the exact non-exportable helper's `U/unlocked`
and zero exit does the Session sign the intent. A pinned native publisher checks
the source and lock identities, exclusively creates a bounded private staging
file, syncs it, publishes without replacement, syncs the directory and returns
the exact `P/published` and zero exit. Lost or malformed responses leave close
unconfirmed; publication is not retried automatically. Synchronous filesystem
calls can outlast the response deadline. A sidecar may appear after the caller
loses its reply.

Diagnosis reads the current claim under a retained native Session lock, checks
the original journal and lock identity, latest owner and intent, helper digest,
private sidecar identity and signature, and confirms that inspection lock's
release. The `signed_release_claim` result describes what trusted host code
signed, not independent proof of the original helper event or a received
publication acknowledgment. It does not change the earlier unconfirmed
lifecycle closure or certify any previous owner's epoch. Unknown, malformed,
missing, active-owner, changed-helper, and later-owner cases remain unknown.
Like the underlying journal identity, this is a cooperative same-user boundary,
not protection against an attacker who rewrites both journal and sidecar or
inspects the owner's process memory. Older journals retain existing behavior;
legacy resumed Sessions write a new marker for an opted-in journal but their
generic lock release cannot produce this claim. Non-Linux behavior is not
qualified by these controls.

The standard matching-helper cohort passed three genuine Session cases:
clean close, signature and identity checks with later resume, lost lock-helper
reply and preserved torn-tail recovery. Eight signed-contract tests also passed.
The independently built test-hook helper passed three controls: Session death
after native unlock but before its response; death after durable sidecar
publication but before its response; and a separate BEAM VM reopening after the
original unlock and before the original owner publishes. In the last case the
old signature remained valid historical evidence but the new marker prevented
its selection as current, both while the second owner was active and after it
closed. The response-loss controls return unknown rather than assuming that an
effect did not happen. The helper hook is absent from the standard build.

An independent planning-MCP test found that the new owner marker preceded the
initial MCP epoch and was refused; its two [failed startup logs](evidence/release-receipt-integration/mcp-start-initial-failure.log)
are retained. The narrow repair accepts a valid opted-in owner marker without
granting MCP authority, preserves pending pre-start intent and refuses its
pairing with a start after the owner changes. Nil-session inspection derives the
session from the journal's source origin. The [focused replay control](evidence/release-receipt-integration/mcp-v2-test.log)
passed; actual planning-MCP verification is tracked separately by its owner.
The first [integration replay](evidence/release-receipt-integration/complete-session.log)
also exposed the generic action validator's refusal of the new operation ID;
the layout-gated, fully scanned event handling repaired it. The earlier failed
MCP compile is retained as well.

The exact [source snapshot](evidence/release-receipt-integration/source.tar),
[standard runtime](evidence/release-receipt-integration/runtime-final.sha256),
[hook runtime](evidence/release-receipt-integration/runtime-hook-final.sha256),
and [manifest](evidence/release-receipt-integration/manifest.sha256) identify
these local cohorts. Their copied base graphs are not a clean-checkout recipe.
Commands for the final helper and focused tests:

```sh
rustc --edition=2021 -D warnings native/ipse-runner.rs -o /tmp/ipse-release-standard-check
rustc --edition=2021 -D warnings --cfg ipse_session_release_test_hook native/ipse-runner.rs -o /tmp/ipse-release-hook-check
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-integration-final-sol-20261029/lib elixir -e 'Code.compiler_options(ignore_module_conflict: true); case Kernel.ParallelCompiler.compile_to_path(["_build/session-release-integration-final-sol-20261029/source/lib/ipse/runner.ex", "lib/ipse/session/lock.ex", "lib/ipse/session/release_receipt.ex", "lib/ipse/session/saved.ex", "lib/ipse/session/planning_mcp.ex", "lib/ipse/session.ex", "lib/ipse/extension/actions.ex"], "_build/session-release-integration-final-sol-20261029/lib/ipse/ebin", return_diagnostics: true) do {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("RELEASE_FINAL_COMPILE_OK"); result -> IO.inspect(result); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-loss-final-sol-20261029/lib elixir -e 'Code.compiler_options(ignore_module_conflict: true); case Kernel.ParallelCompiler.compile_to_path(["_build/session-release-loss-final-sol-20261029/source/lib/ipse/runner.ex"], "_build/session-release-loss-final-sol-20261029/lib/ipse/ebin", return_diagnostics: true) do {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("RELEASE_HOOK_FINAL_COMPILE_OK"); result -> IO.inspect(result); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-integration-final-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [line: 37, line: 180, line: 209]); Code.require_file("test/ipse/session/native_header_session_test.exs")'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-integration-final-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/release_receipt_test.exs")'
IPSE_RELEASE_HOOK_TEST=1 ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-loss-final-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [line: 225, line: 249, line: 282]); Code.require_file("test/ipse/session/native_header_session_test.exs")'
```

The standard [compile](evidence/release-receipt-integration/final-compile.log),
[Session results](evidence/release-receipt-integration/final-session.log),
[contract results](evidence/release-receipt-integration/final-contract.log),
and [owner-loss results](evidence/release-receipt-integration/hook-final-test.log)
are retained. Independent review must examine publication crash windows,
snapshot fencing, resource cleanup, limits and compatibility before this
section can be treated as qualified.
