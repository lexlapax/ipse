#!/bin/bash
set -euo pipefail
snapshot=/home/lexlapax/projects/lexlapax/ipse/_build/verification/ipse-cache-current-ace41-20261103-01
protected=/dev/shm/ipse-cache-current-focused-ace41-20261103-01
cd "$snapshot"
for task_env_key in ${!IPSE_@}; do unset "$task_env_key"; done
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS ERL_FLAGS LD_PRELOAD LD_LIBRARY_PATH MIX_BUILD_PATH MIX_DEPS_PATH
export HOME="$protected/operator-home" IPSE_HOME="$protected/ipse-home" TMPDIR="$protected/tmp"
test_exit=0
elixir --erl '+S 2:2' evidence/focused.exs > evidence/focused.log 2>&1 || test_exit=$?
post_exit=0
sha256sum --check --status evidence/source-before.sha256 || post_exit=1
sha256sum --check --status evidence/runtime-before.sha256 || post_exit=1
sha256sum --check --status evidence/helper-before.sha256 || post_exit=1
sha256sum --check --status evidence/deps-before.sha256 || post_exit=1
find _build/test/lib deps -type l -printf '%p -> %l\n' | LC_ALL=C sort > evidence/runtime-after.links
cmp evidence/runtime-before.links evidence/runtime-after.links || post_exit=1
: > evidence/source-after.links
while IFS= read -r task_link_line; do task_link_file=${task_link_line%% -> *}; printf '%s -> %s\n' "$task_link_file" "$(readlink "$task_link_file")" >> evidence/source-after.links; done < evidence/source-before.links
cmp evidence/source-before.links evidence/source-after.links || post_exit=1
printf 'test_exit=%s\npostcheck_exit=%s\n' "$test_exit" "$post_exit" > evidence/status
cat evidence/status
exit "$test_exit"
