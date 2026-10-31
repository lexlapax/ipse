# Inactive Host-to-Session share and settlement — 2026-10-29

This checkpoint extends the reviewed [Session operation seal](session-operation-barrier-independent-review.md). It does not enable protected output, supersession, management review or worker-result delivery. The [plan](../../plan.md) owns acceptance.

The Host now has private adapters for beginning a Session seal, exporting its actual retained lock description to a named native recipient, settling that transfer and thawing the Writer, or cancelling before transfer. The Session accepts these operations only from the original active task with the matching job and opaque capability. It sends the guard requests asynchronously and keeps ordinary Session operations sealed throughout the pending operation; Writer remains frozen until guard-confirmed thaw. Export acknowledgement is a transfer result, not output admission. A post-transfer abort, failed request, owner loss, unsolicited event or late reply quarantines the operation with an unconfirmed result. Settlement requires the existing native recipient close handshake; Writer thaw follows a confirmed guard settlement. The original five-second monotonic setup deadline gates export and settlement requests and every successful phase reply. Pre-export cancellation and post-settlement thaw may still initiate cleanup after that deadline; a late reply quarantines Session instead of returning success or resuming ordinary work, even if physical cleanup completed. This does not prove deadline enforcement for terminal writes, later human input or the complete future multi-lease operation.

These are inactive same-VM host primitives, not worker or SDK commands. The production Host has **no call site invoking them**. In particular, recipient bytes are supplied by the trusted future Host caller; this section does not prove the future collector manifest, operation-to-payload binding or recipient-mode admission. It uses one Session lock, not the four management leases or the larger source set. No terminal writes occur. A dead BEAM task is not proof that a native process or output has stopped.

## Focused controls

The fixture builds and imports a real synthetic extension artifact through the normal Artifact, Config and Registry path. A genuine selected identity, independent worker, owned Host task and journaled active action are used. To reach the inactive adapter without enabling a production call site, the test compiles a **test-only instrumented Host** into a separate copied runtime graph. Its single rendezvous is immediately after the genuine action is admitted and before its effect; a test process directs only the synthetic probe. The production Host BEAM and the instrumented source and BEAM are retained separately. The fixture's late-reply case additionally changes the Session deadline through `:sys.replace_state` to force the scheduling boundary; it does not establish a live terminal deadline.

The final standard selection passed **3 tests**: real task/job/action and selected-identity binding including altered-intent and foreign-caller refusal, cancellation with the actual Host and worker while Writer is suspended, and the forced late Writer reply. The final permitted-context Unix socket selection passed **3 tests**: real Host-to-native-recipient transfer and authenticated close before thaw; post-transfer cancellation with a stopped recipient remaining the last flock holder until it resumes and exits; and wrong lock inode causing quarantine. The previously affected Session seal selection passed **5 tests** on the final uninstrumented Session graph. No model, network, terminal, aggregate or other-platform test ran. Exported-but-unacknowledged effects remain unknown; no journal action is automatically replayed.

The [evidence](evidence/session-host-share/) retains exact source tar, uninstrumented and instrumented Host BEAMs, the helper, each selected worker artifact, full inventories of both runtime graphs, and focused logs. The initial fixture failed Registry admission because the in-memory instrumented Host had no on-disk identity for the host digest; the corrected isolated test graph writes and loads its own instrumented BEAM. A zero-test selection and all intermediate logs are retained. The current Journal includes the separately reviewed metadata alias repair; this does not requalify the prior frozen Journal cohort.

The final source builds and test commands used the repository root and matching copied graph:

```sh
ERL_FLAGS='+S 4' ERL_LIBS="$PWD/_build/session-host-share-sol-20261029/lib" \
  elixir -e 'Code.compiler_options(warnings_as_errors: true, ignore_module_conflict: true); out = "_build/session-host-share-sol-20261029/lib/ipse/ebin"; case Kernel.ParallelCompiler.compile_to_path(["lib/ipse/journal.ex", "lib/ipse/session.ex", "lib/ipse/extension/host.ex"], out) do {:ok, _, []} -> IO.puts("SESSION_HOST_SHARE_COMPILE_OK"); other -> IO.inspect(other); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS="$PWD/_build/session-host-share-v2-sol-20261029/lib" \
  elixir -e 'Code.compiler_options(warnings_as_errors: true, ignore_module_conflict: true); out = "_build/session-host-share-v2-sol-20261029/lib/ipse/ebin"; case Kernel.ParallelCompiler.compile_to_path(["lib/ipse/session.ex"], out) do {:ok, _, []} -> IO.puts("SESSION_HOST_SHARE_V2_COMPILE_OK"); other -> IO.inspect(other); System.halt(1) end'
IPSE_SHARE_HOST_ARTIFACT_EVIDENCE=/tmp/ipse-share-host-fixture-standard \
  IPSE_SHARE_HOST_SOURCE_EVIDENCE=/tmp/ipse-share-host-instrumented-v2.ex ERL_FLAGS='+S 4' \
  ERL_LIBS="$PWD/_build/session-host-share-probe-v2-sol-20261029/lib" \
  elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/share_host_job_test.exs")'
IPSE_SHARE_HOST_ARTIFACT_EVIDENCE=/tmp/ipse-share-host-fixture-sockets \
  IPSE_SHARE_HOST_SOURCE_EVIDENCE=/tmp/ipse-share-host-instrumented-v2.ex ERL_FLAGS='+S 4' \
  ERL_LIBS="$PWD/_build/session-host-share-probe-v2-sol-20261029/lib" \
  elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [native_sandbox: true]); Code.require_file("test/ipse/session/share_host_job_test.exs")'
```

The artifact output paths must be absent before each fixture run. Socket controls ran with the approved local Unix-socket permission. The probe graph is a copy of the uninstrumented graph and is intentionally modified by the fixture; it must not be substituted for the production Host graph.

## Remaining work

Actual Host control ownership and immutable payload/recipient construction, two EOF-only owner controls, authenticated all-lease admission, native tty and forked reader/guardian closure, per-write admission, fixed safe redraw, complete 4-lease closure and thaw, current policy/facts revalidation, live one-use approval and actual management integration remain necessary. The generic 132-distinct-lease route remains outside the present 131 limit. These controls do not prove the uninstrumented user journey or authorize opening any gate.
