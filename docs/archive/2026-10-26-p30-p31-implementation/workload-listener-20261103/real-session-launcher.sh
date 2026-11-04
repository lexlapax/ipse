#!/bin/sh
set -eu
umask 077

proof=/dev/shm/ipse-listener-real-session-proof-20261103-01
root=/dev/shm/ipse-word-larger-candidate-20261103-01
listener=/dev/shm/ipse-workload-listener-20261103/dev/fixtures/synthetic_ollama.exs
entry=/dev/shm/ipse-listener-real-session-smoke-20261103.exs
runtime=/dev/shm/ipse-word-larger-proof-20261103-01/live-runtime.sha256
source=/dev/shm/ipse-word-larger-proof-20261103-01/word-vertical-live.sha256

mkdir "$proof"
printf '%s\n' 'one fresh synthetic Session; no replay' > "$proof/intent"
cd "$root"
sha256sum --check --status "$runtime"
sha256sum --check --status "$source"
sha256sum "$entry" "$listener" priv/ipse-runner > "$proof/pre.sha256"
IPSE_LISTENER_SMOKE_ROOT=$(mktemp -d /dev/shm/ipse-listener-session-XXXXXXXX)
export IPSE_LISTENER_SMOKE_ROOT
export TMPDIR=/dev/shm
unset LD_PRELOAD LD_LIBRARY_PATH ERL_FLAGS ERL_AFLAGS ERL_ZFLAGS ERL_LIBS ELIXIR_ERL_OPTIONS ERL_CRASH_DUMP
unset OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY GEMINI_API_KEY XAI_API_KEY OPENROUTER_API_KEY

set --
for path in _build/test/lib/*/ebin; do
  set -- "$@" -pa "$path"
done

set +e
elixir --erl '+S 2:2' "$@" "$entry" > "$proof/run.log" 2>&1
status=$?
sha256sum --check --status "$runtime"
runtime_status=$?
sha256sum --check --status "$source"
source_status=$?
sha256sum --check --status "$proof/pre.sha256"
entry_status=$?
set -e
printf 'command_status=%s runtime_post_status=%s source_post_status=%s entry_post_status=%s\n' \
  "$status" "$runtime_status" "$source_status" "$entry_status" | tee "$proof/status"
test "$status" -eq 0
test "$runtime_status" -eq 0
test "$source_status" -eq 0
test "$entry_status" -eq 0
