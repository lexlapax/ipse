#!/bin/sh
set -eu
cd /dev/shm/ipse-ollama-installed-f44-20261103-01
test "$(sha256sum task-source.sha256 | cut -d ' ' -f 1)" = 114fb1b372c78764fa9484681a7a389f51c9494598ed3a150aacb1c42701eda0
test "$(sha256sum task-source-accept.exs | cut -d ' ' -f 1)" = f57cde6b93d22870c065b28449a1833cc9c5eaab97aa4d280a826ecb2249332e
set -C
check_prod() {
  test "$(sha256sum task-prod-runtime.sha256 | cut -d ' ' -f 1)" = 2681b105bd2e972b9bf5dd2880d98542141018d4353f5f3ee9f156bf465627bf
  test "$(sha256sum task-prod-paths.txt | cut -d ' ' -f 1)" = 3e662c5114452720558b92c03e4b290e13aa37e967a0664221e7f197589674b1
  test "$(sha256sum task-prod-links.txt | cut -d ' ' -f 1)" = 3bf549ca80f843a2ec628eaad40bb7d2b95262785429cf39d4ad8982f16e099b
  find _build/prod/lib priv -type f -print | LC_ALL=C sort > "task-logs/prod-paths-$1.txt"
  cmp task-prod-paths.txt "task-logs/prod-paths-$1.txt"
  find _build/prod/lib priv -type l -printf '%p -> %l\n' | LC_ALL=C sort > "task-logs/prod-links-$1.txt"
  cmp task-prod-links.txt "task-logs/prod-links-$1.txt"
  sha256sum -c task-prod-runtime.sha256 > "task-logs/prod-runtime-$1.log"
}
check_prod before
sha256sum -c task-source.sha256 > task-logs/source-before-test.log
set +e
env -u LD_PRELOAD -u LD_LIBRARY_PATH -u ERL_LIBS -u ERL_AFLAGS -u ERL_ZFLAGS -u ELIXIR_ERL_OPTIONS -u ELIXIR_OPTS -u MIX_ARCHIVES -u MIX_BUILD_PATH -u MIX_DEPS_PATH -u IPSE_CONFIG -u IPSE_PROVIDER -u IPSE_MODEL -u IPSE_SANDBOX -u IPSE_RUNNER_PATH -u IPSE_TEST_DRAFT_TRANSPORT -u IPSE_TEST_CLOCK_OFFSET_MS TMPDIR=/dev/shm IPSE_HOME="$PWD/task-home" MIX_HOME="$PWD/task-cache/mix" HEX_HOME="$PWD/task-cache/hex" HEX_OFFLINE=1 MIX_ENV=prod ERL_FLAGS='+S 2:2' mix run --no-start --no-compile --no-deps-check task-source-accept.exs > task-logs/source-accept.log 2>&1
task_status=$?
set -e
test "$(sha256sum task-source.sha256 | cut -d ' ' -f 1)" = 114fb1b372c78764fa9484681a7a389f51c9494598ed3a150aacb1c42701eda0
sha256sum -c task-source.sha256 > task-logs/source-after-test.log
check_prod after
exit "$task_status"
