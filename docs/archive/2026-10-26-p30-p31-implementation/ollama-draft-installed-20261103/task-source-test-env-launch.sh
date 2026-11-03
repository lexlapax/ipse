#!/bin/sh
set -eu
cd /dev/shm/ipse-ollama-installed-f44-20261103-01
test "$(sha256sum task-source.sha256 | cut -d ' ' -f 1)" = 114fb1b372c78764fa9484681a7a389f51c9494598ed3a150aacb1c42701eda0
test "$(sha256sum task-source-accept-test.exs | cut -d ' ' -f 1)" = a5537cd554925668465646e3ca0ce0cc191b278c520a9ec3d0849a2b2b9af7ae
set -C
check_prod() {
  test "$(sha256sum task-test-runtime.sha256 | cut -d ' ' -f 1)" = 90795d5ba1c164d0406b7808243ddab81e6560253909fa7129730f63e454d451
  test "$(sha256sum task-test-paths.txt | cut -d ' ' -f 1)" = a8dd62494366b1925d5543af7088f8eab65987c4b323e94d697933ef5336aa23
  test "$(sha256sum task-test-links.txt | cut -d ' ' -f 1)" = 45aeb8b70faba5ef2fa0d3217215e462358e84e2643465f693186dca73e77cb4
  find _build/test/lib priv -type f -print | LC_ALL=C sort > "task-logs/test-paths-$1.txt"
  cmp task-test-paths.txt "task-logs/test-paths-$1.txt"
  find _build/test/lib priv -type l -printf '%p -> %l\n' | LC_ALL=C sort > "task-logs/test-links-$1.txt"
  cmp task-test-links.txt "task-logs/test-links-$1.txt"
  sha256sum -c task-test-runtime.sha256 > "task-logs/test-runtime-$1.log"
}
check_prod before
sha256sum -c task-source.sha256 > task-logs/source-before-test-env.log
set +e
env -u LD_PRELOAD -u LD_LIBRARY_PATH -u ERL_LIBS -u ERL_AFLAGS -u ERL_ZFLAGS -u ELIXIR_ERL_OPTIONS -u ELIXIR_OPTS -u MIX_ARCHIVES -u MIX_BUILD_PATH -u MIX_DEPS_PATH -u IPSE_CONFIG -u IPSE_PROVIDER -u IPSE_MODEL -u IPSE_SANDBOX -u IPSE_RUNNER_PATH -u IPSE_TEST_DRAFT_TRANSPORT -u IPSE_TEST_CLOCK_OFFSET_MS TMPDIR=/dev/shm IPSE_HOME="$PWD/task-home" MIX_HOME="$PWD/task-cache/mix" HEX_HOME="$PWD/task-cache/hex" HEX_OFFLINE=1 MIX_ENV=test ERL_FLAGS='+S 2:2' mix run --no-start --no-compile --no-deps-check task-source-accept-test.exs > task-logs/source-accept-test-env.log 2>&1
task_status=$?
set -e
test "$(sha256sum task-source.sha256 | cut -d ' ' -f 1)" = 114fb1b372c78764fa9484681a7a389f51c9494598ed3a150aacb1c42701eda0
sha256sum -c task-source.sha256 > task-logs/source-after-test-env.log
check_prod after
exit "$task_status"
