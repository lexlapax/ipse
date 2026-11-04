#!/bin/bash
set -euo pipefail
umask 077
proof=/dev/shm/ipse-json-recall33-20261103-01
runtime=/dev/shm/ipse-json-current-20261103-01
cd "$proof"
test ! -e launch.claim
sha256sum --check --status fixture.sha256
cd "$runtime"
find lib _build/test/lib priv -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/runtime-before.sha256"
find _build/test/lib priv -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/runtime-before.links"
cd "$proof"
(set -C; printf '%s\n' 'one fresh synthetic strict33-note Session after measured canonical digest repair; no retry' > launch.claim)
sync -f launch.claim
mkdir -m 700 task-home fixture-tmp
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS ERL_FLAGS MIX_BUILD_PATH MIX_DEPS_PATH MIX_HOME MIX_ARCHIVES LD_PRELOAD LD_LIBRARY_PATH
unset OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY GEMINI_API_KEY XAI_API_KEY OPENROUTER_API_KEY
for task_env_key in ${!IPSE_@}; do unset "$task_env_key"; done
export TMPDIR="$proof/fixture-tmp" IPSE_HOME="$proof/task-home" IPSE_TEST_RECALL_MANY=1 IPSE_TEST_RECALL_KEEP=1 IPSE_TEST_RECALL_REQUIRE_SINGLE=1 IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS=5000
launch_arguments=()
for task_code_dir in "$runtime"/_build/test/lib/*/ebin; do launch_arguments+=(-pa "$task_code_dir"); done
set +e
elixir --erl '+S 2:2' "${launch_arguments[@]}" entry.exs > fixture-private.log 2>&1
launch_test_exit=$?
elixir --erl '+S 2:2' filter.exs < fixture-private.log > run.log
launch_filter_exit=$?
set -e
launch_post_exit=0
cd "$runtime"
find lib _build/test/lib priv -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/runtime-after.sha256"
find _build/test/lib priv -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/runtime-after.links"
cmp "$proof/runtime-before.sha256" "$proof/runtime-after.sha256" || launch_post_exit=1
cmp "$proof/runtime-before.links" "$proof/runtime-after.links" || launch_post_exit=1
cd "$proof"
sha256sum --check --status fixture.sha256 || launch_post_exit=1
printf 'test_exit=%s\nfilter_exit=%s\npostcheck_exit=%s\n' "$launch_test_exit" "$launch_filter_exit" "$launch_post_exit" > completion.txt
sync -f completion.txt
cat run.log completion.txt
test "$launch_post_exit" -eq 0
test "$launch_filter_exit" -eq 0
exit "$launch_test_exit"
