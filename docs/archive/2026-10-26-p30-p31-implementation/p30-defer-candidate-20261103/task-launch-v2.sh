#!/bin/bash
set -euo pipefail
umask 077
cd /dev/shm/ipse-p30-defer-f1d84-20261103-01
printf '%s  %s\n' \
  3e3c0fe70585228b7f95dcdbaf7ad5a5ae518c7c22b6ab0fadd4a9b6ae6df505 task-source.sha256 \
  1072b85316e65bd460a7801162d6d0b9242fe03c4e291127fd43d6c2e10c7b94 task-runtime.sha256 \
  45aeb8b70faba5ef2fa0d3217215e462358e84e2643465f693186dca73e77cb4 task-runtime-links.txt \
  998a82d421d1a8e35a54abc555cf28d1165d4d7a82da074931c7096401b2cfa1 task-direct-exunit-v2.exs | sha256sum -c -
for path in task-runtime/tmp-v2 task-runtime/ipse-home-v2 task-v2.claim task-v2.log task-v2-source-pre.log task-v2-source-post.log task-v2-runtime-pre.log task-v2-runtime-post.log task-v2-links-post.txt; do
  [[ ! -e "$path" && ! -L "$path" ]] || exit 1
done
sha256sum -c task-source.sha256 > task-v2-source-pre.log
sha256sum -c task-runtime.sha256 > task-v2-runtime-pre.log
find _build/test/lib priv -type l -printf '%p -> %l\n' | LC_ALL=C sort | cmp task-runtime-links.txt -
mkdir -m 700 task-runtime/tmp-v2 task-runtime/ipse-home-v2
set -C
: > task-v2.claim
exec 3>task-v2.log
set +e
env -u LD_PRELOAD -u LD_LIBRARY_PATH -u ERL_LIBS -u ELIXIR_ERL_OPTIONS -u ELIXIR_OPTS -u MIX_ARCHIVES -u IPSE_RUNNER_PATH -u IPSE_PROVIDER -u IPSE_MODEL -u IPSE_CONFIG -u IPSE_SANDBOX -u IPSE_TEST_CLOCK_OFFSET_MS MIX_ENV=test HEX_OFFLINE=1 MIX_HOME="$PWD/task-runtime/mix" HEX_HOME="$PWD/task-runtime/hex" IPSE_HOME="$PWD/task-runtime/ipse-home-v2" TMPDIR="$PWD/task-runtime/tmp-v2" ERL_FLAGS='+S 2:2' IPSE_KEEP_SHADOW_FIXTURES=1 mix run --no-start task-direct-exunit-v2.exs >&3 2>&1
test_status=$?
sha256sum -c task-source.sha256 > task-v2-source-post.log
source_status=$?
sha256sum -c task-runtime.sha256 > task-v2-runtime-post.log
runtime_status=$?
find _build/test/lib priv -type l -printf '%p -> %l\n' | LC_ALL=C sort > task-v2-links-post.txt
links_status=$?
cmp task-runtime-links.txt task-v2-links-post.txt || links_status=1
printf 'test_exit=%s source_post=%s runtime_post=%s links_post=%s\n' "$test_status" "$source_status" "$runtime_status" "$links_status"
if [[ "$source_status" != 0 || "$runtime_status" != 0 || "$links_status" != 0 ]]; then exit 1; fi
exit "$test_status"
