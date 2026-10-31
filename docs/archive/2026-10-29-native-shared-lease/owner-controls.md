# Inert native Session and Host owner controls — 2026-10-29

This scoped checkpoint builds on the [accepted Host-to-Session share](session-host-share-independent-review.md) and [guarded terminal design](guarded-terminal-integration-independent-review.md). It does not activate protected output. The [plan](../../plan.md) owns acceptance.

The Linux helper has a dedicated one-use sender and an inert observer. The actual BEAM owner opens a pinned native Port; its stdin is a dedicated read-only pipe. The sender emits `R` once its actual descriptor is ready. After the owner supplies the fresh operation, Session/Host role, pinned recipient PID, private abstract address and secret, the sender authenticates the peer, checks the operation and role, and transfers that actual read end with `SCM_RIGHTS`. The receiver validates the sender PID/UID/executable, pidfd, close-on-exec FD, FIFO type, access mode and the host-supplied device/inode before acknowledging. `T` indicates transfer only. Neither `R`, `T` nor receiver readiness grants output or proves continued owner liveness.

After transfer neither helper consumes the owner pipe. EOF, unexpected input, errors and the receiver's observation of the sender helper pidfd or peer failure are sticky loss. The owner must not send any cancellation byte: closing its Port makes the actual pipe EOF visible to every read-end holder. The sender and receiver each have a bounded setup window; blocking kernel or filesystem calls are not claimed to have a hard wall-clock bound. The small Runner adapter can only configure or close a Port connected to its current BEAM process, and a successful configuration result means only that bytes were queued. Same-VM host code remains trusted. The caller must actually observe `R` before selecting the descriptor identity and sending a request; the current adapter does not itself implement that asynchronous Session state machine.

The native ancillary receiver was factored into a common raw FD receiver and the existing regular-file lease checks retained in its wrapper. This change does not itself authorize an arbitrary recipient, prove an executable's selected helper mode, bind a terminal payload or replace the later operation-wide deadline and complete lease manifest.

## Focused evidence

The final Session graph's **7 tests passed**: actual Session death while the VM stays alive, actual handoff-helper death while Session stays alive, one live BEAM write end for the matching pipe, foreign-owner refusal, unexpected post-transfer byte, wrong role and operation, wrong peer PID, owner death after a real bound listener, and direct Session-owned Port closure while Writer was suspended. A separate **one-test** control observed stalled sender termination at its setup deadline. The actual selected-artifact/worker Host fixture passed **one test** in its separately instrumented Host graph: ordinary Session cancellation killed the genuine Host task and its directly owned Port, and the inert recipient observed loss while Session stayed alive. The earlier lease collector's affected native transfer/close selection passed **3 tests** after the receiver extraction.

Session opens and sends in these tests through `:sys.replace_state` solely to execute the private API in the real Session owner; trace observes its readiness. The Host test's retained source inserts a test-only rendezvous at the real admitted-action boundary. Neither is a production Session or Host call site. In particular, **production Session cancellation is not yet wired to close a separately Session-owned control Port**. The direct close test demonstrates the owner API with a suspended Writer; it does not claim the missing cancellation wiring. No native tty, guardian/reader fork, actual protected writes, whole-operation deadline or all-copy close was exercised. The generic 132-description route remains above the present 131 limit.

The [evidence](evidence/owner-controls/) contains all native source needed to build the final helper, Runner and test source, final helper and two earlier helper binaries, both runtime inventories, test-only instrumented Host source/BEAM, exact selected worker artifact and focused logs. The v2 run had an intermittent sender pre-exec identity refusal; v3's bounded executable check addressed that but a genuine Host run still exposed a pipe-identity-before-exec race. The final `R` frame is observed before identifying the source FD. Those historical failures are preserved; exact complete v2/v3 source snapshots were not frozen, so their binaries and logs are historical diagnostics rather than reproducible source cohorts. No passing aggregate or model test was rerun.

Final compilation and selected tests (from the repository root, with the archived source restored into the matching copied graph):

```sh
rustc --edition=2021 -D warnings -O native/ipse-runner.rs -o /tmp/ipse-owner-control-v4-helper
ERL_FLAGS='+S 4' ERL_LIBS="$PWD/_build/owner-control-v4-sol-20261029/lib" \
  elixir -e 'Code.compiler_options(warnings_as_errors: true, ignore_module_conflict: true); out = "_build/owner-control-v4-sol-20261029/lib/ipse/ebin"; case Kernel.ParallelCompiler.compile_to_path(["_build/owner-control-v1-source/lib/ipse/runner.ex"], out) do {:ok, _, []} -> IO.puts("OWNER_CONTROL_RUNNER_COMPILE_OK"); other -> IO.inspect(other); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS="$PWD/_build/owner-control-v4-sol-20261029/lib" \
  elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [native_sandbox: true]); Code.require_file("test/ipse/session/owner_control_test.exs")'
IPSE_SHARE_HOST_ARTIFACT_EVIDENCE=/tmp/ipse-owner-control-host-v4-artifact \
  IPSE_SHARE_HOST_SOURCE_EVIDENCE=/tmp/ipse-owner-control-host-v4-instrumented.ex ERL_FLAGS='+S 4' \
  ERL_LIBS="$PWD/_build/owner-control-host-v4-sol-20261029/lib" \
  elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [owner_control_host: true]); Code.require_file("test/ipse/session/share_host_job_test.exs")'
```

The Runner source copy must be placed at `_build/owner-control-v1-source/lib/ipse/runner.ex` with the final helper at that source root's `priv/ipse-runner` before its compile, to bind the helper digest. Both runtime graphs must contain that same helper; the Host fixture writes its instrumented BEAM only into the separate Host graph. The artifact output path must be absent. Unix socket tests ran with approved local socket permission.

Production Session/Host control opening, strict asynchronous frame state, operation-wide timeout, poisoned cancellation closure, recipient mode and all-lease authentication, native matched tty writes, forked reader/guardian FD inheritance and closure, and current-policy one-use effect admission remain to implement and independently test. No user-facing gate changes follow from this receipt.
