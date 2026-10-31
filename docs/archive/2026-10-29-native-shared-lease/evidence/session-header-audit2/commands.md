# Header audit follow-up commands

Run at the repository root. The three copied `_build` graphs retain their
independently pinned helper binaries and prerequisite BEAM modules; they are
local evidence, not a fresh-checkout bootstrap. Each graph's `Runner` source
was copied under `lib/ipse/lib/ipse/runner.ex` before compilation so its helper
pin was computed from that graph's own `lib/ipse/priv/ipse-runner`.

```sh
rustc --edition=2021 -D warnings native/ipse-runner.rs -o _build/session-header-audit2-native-sol-20261029/ipse-runner-standard
rustc --edition=2021 -D warnings --cfg ipse_session_header_test_hook native/ipse-runner.rs -o _build/session-header-audit2-native-sol-20261029/ipse-runner-interposition
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-audit2-sol-20261029/lib elixir -e 'Code.compiler_options(ignore_module_conflict: true); case Kernel.ParallelCompiler.compile_to_path(["_build/session-header-audit2-sol-20261029/lib/ipse/lib/ipse/runner.ex", "lib/ipse/session/lock.ex", "lib/ipse/session.ex", "lib/ipse/journal.ex"], "_build/session-header-audit2-sol-20261029/lib/ipse/ebin", return_diagnostics: true) do {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("HEADER_AUDIT2_STRICT_COMPILE_OK"); result -> IO.inspect(result); System.halt(1) end'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-audit2-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/header_deadline_test.exs")'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-audit2-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/native_header_session_test.exs")'
IPSE_HEADER_SESSION_RACE=1 ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-audit2-race-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/native_header_session_loss_test.exs")'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-audit2-old-sol-20261029/lib elixir dev/verification/session_header_old_helper.exs
IPSE_HOME=/tmp/ipse-header-audit2-demo/home ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-audit2-sol-20261029/lib elixir -e 'Ipse.CLI.main(["demo", "--cwd", "/tmp/ipse-header-audit2-demo/work", "--state-dir", "/tmp/ipse-header-audit2-demo/state"])'
```

The interposition and old-helper graphs used the same compiler command with
their own graph paths. The demo used an existing private synthetic home, state
directory and workspace; create them with mode 0700 before repeating it. Its
helper is not the historical older helper. The interposition helper's forced
rename failure is not an actual unsupported-filesystem test.
