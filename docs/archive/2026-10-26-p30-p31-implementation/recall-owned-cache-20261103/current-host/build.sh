#!/bin/bash
set -euo pipefail
snapshot=/home/lexlapax/projects/lexlapax/ipse/_build/verification/ipse-cache-current-ace41-20261103-01
cd "$snapshot"
for task_env_key in ${!IPSE_@}; do unset "$task_env_key"; done
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS LD_PRELOAD LD_LIBRARY_PATH MIX_BUILD_PATH MIX_DEPS_PATH HEX_API_KEY HEX_UNSAFE_HTTPS
export MIX_ENV=test MIX_HOME="$snapshot/mix-home" HEX_HOME="$snapshot/hex-home" MIX_ARCHIVES="$snapshot/mix-archives" HEX_OFFLINE=1 ERL_FLAGS='+S 2:2' HOME="$snapshot/build-home" IPSE_HOME="$snapshot/build-home/.ipse" IPSE_BUILD_COMMIT=ace41c750fd534bce2bcad1a20377a30cc8479cd
mix format lib/ipse/session/resources.ex lib/ipse/inference_slots.ex test/ipse/session/source_replay_cache_test.exs > evidence/format.log 2>&1
mix compile --force --no-deps-check --warnings-as-errors > evidence/compile.log 2>&1
