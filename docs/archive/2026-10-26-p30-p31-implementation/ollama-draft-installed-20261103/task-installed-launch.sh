#!/bin/sh
set -eu
cd /dev/shm/ipse-ollama-installed-f44-20261103-01
archive="$PWD/dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz"
proof=/dev/shm/ipse-ollama-draft-proof-f44-20261103-01
test ! -e "$proof"
test ! -L "$proof"
test "$(sha256sum task-source.sha256 | cut -d ' ' -f 1)" = 114fb1b372c78764fa9484681a7a389f51c9494598ed3a150aacb1c42701eda0
test "$(sha256sum dev/verification/ollama_draft_installed.exs | cut -d ' ' -f 1)" = dc77a3bb9fe1bc4b577740670921ff9b0418657d8419cdc185f3fa9a1580d4bf
test "$(sha256sum "$archive" | cut -d ' ' -f 1)" = 6c674c55981b85b8d11a2e093f948f0c20434817d365dee5703824fb03bc8c0c
set -C
sha256sum -c task-source.sha256 > task-logs/source-before-installed.log
set +e
env -u LD_PRELOAD -u LD_LIBRARY_PATH -u ERL_LIBS -u ERL_AFLAGS -u ERL_ZFLAGS -u ELIXIR_ERL_OPTIONS -u ELIXIR_OPTS -u MIX_ENV -u MIX_ARCHIVES -u MIX_BUILD_PATH -u MIX_DEPS_PATH -u IPSE_CONFIG -u IPSE_PROVIDER -u IPSE_MODEL -u IPSE_SANDBOX -u IPSE_RUNNER_PATH TMPDIR=/dev/shm IPSE_HOME="$PWD/task-home" ERL_FLAGS='+S 2:2' elixir dev/verification/ollama_draft_installed.exs "$archive" "$proof" 6c674c55981b85b8d11a2e093f948f0c20434817d365dee5703824fb03bc8c0c f44f2506de2de47a31c84f2b1b7617236c4d340f > task-logs/installed.log 2>&1
task_status=$?
set -e
test "$(sha256sum task-source.sha256 | cut -d ' ' -f 1)" = 114fb1b372c78764fa9484681a7a389f51c9494598ed3a150aacb1c42701eda0
sha256sum -c task-source.sha256 > task-logs/source-after-installed.log
test "$(sha256sum "$archive" | cut -d ' ' -f 1)" = 6c674c55981b85b8d11a2e093f948f0c20434817d365dee5703824fb03bc8c0c
exit "$task_status"
