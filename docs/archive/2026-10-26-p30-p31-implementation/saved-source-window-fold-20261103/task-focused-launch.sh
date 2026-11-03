#!/bin/sh
set -eu
cd /dev/shm/ipse-saved-window-18c748-20261103-01
set -C
check_inputs() {
  test "$(sha256sum task-source.sha256 | cut -d ' ' -f 1)" = 49d957786da045e64fb21768bc5508ca34b574123161906bcc9c0d4fa366702c
  test "$(sha256sum task-focused.exs | cut -d ' ' -f 1)" = e18d8929b85f14f2209c98f52b11c07a008643b26db469a6665e3cf7e1106e4f
  test "$(sha256sum task-runtime.sha256 | cut -d ' ' -f 1)" = 8e846418d4a082e346b841701a7add27262d7ba79607f3af1fe3549a8e3aa510
  test "$(sha256sum task-runtime-paths.txt | cut -d ' ' -f 1)" = c478f8b663e14a6064bb68313323444f08574f13e5746f780cc717ed4a402fc5
  test "$(sha256sum task-runtime-links.txt | cut -d ' ' -f 1)" = 45aeb8b70faba5ef2fa0d3217215e462358e84e2643465f693186dca73e77cb4
  sha256sum -c task-source.sha256 > "task-logs/source-$1.log"
  find _build/test/lib priv -type f -print | LC_ALL=C sort > "task-logs/runtime-paths-$1.txt"
  cmp task-runtime-paths.txt "task-logs/runtime-paths-$1.txt"
  find _build/test/lib priv -type l -printf '%p -> %l\n' | LC_ALL=C sort > "task-logs/runtime-links-$1.txt"
  cmp task-runtime-links.txt "task-logs/runtime-links-$1.txt"
  sha256sum -c task-runtime.sha256 > "task-logs/runtime-$1.log"
}
check_inputs before-tests
task_status=0
for task_case in window cache draft-cancel draft-accept source-loss output-loss revocation; do
  if env -u LD_PRELOAD -u LD_LIBRARY_PATH -u ERL_LIBS -u ERL_AFLAGS -u ERL_ZFLAGS -u ELIXIR_ERL_OPTIONS -u ELIXIR_OPTS -u MIX_ARCHIVES -u MIX_BUILD_PATH -u MIX_DEPS_PATH -u IPSE_CONFIG -u IPSE_PROVIDER -u IPSE_MODEL -u IPSE_SANDBOX -u IPSE_RUNNER_PATH -u IPSE_TEST_CLOCK_OFFSET_MS TMPDIR="$PWD/task-tmp" IPSE_HOME="$PWD/task-home" IPSE_KEEP_SHADOW_FIXTURES=1 MIX_HOME="$PWD/task-cache/mix" HEX_HOME="$PWD/task-cache/hex" HEX_OFFLINE=1 MIX_ENV=test ERL_FLAGS='+S 2:2' mix run --no-start --no-compile --no-deps-check task-focused.exs "$task_case" > "task-logs/$task_case.log" 2>&1; then
    :
  else
    task_status=$?
    break
  fi
done
check_inputs after-tests
exit "$task_status"
