#!/bin/sh
set -eu
umask 077
proof=/dev/shm/ipse-p30-inflight-eof-20261103-01
runtime=/dev/shm/ipse-word-larger-candidate-20261103-01
cd "$runtime"
sha256sum --check --status /dev/shm/ipse-word-larger-proof-20261103-01/live-runtime.sha256
sha256sum --check --status "$proof/product-source.sha256"
cd "$proof"
test ! -e intent
(set -C; printf '%s\n' 'one fresh synthetic in-flight allowance control; no replay' > intent)
sync -f intent
mkdir task-home task-tmp
chmod 700 task-home task-tmp
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS ERL_FLAGS LD_PRELOAD LD_LIBRARY_PATH
unset OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY GEMINI_API_KEY XAI_API_KEY OPENROUTER_API_KEY
export TMPDIR="$proof/task-tmp" IPSE_HOME="$proof/task-home"
set --
for path in "$runtime"/_build/test/lib/*/ebin; do set -- "$@" -pa "$path"; done
status=0
elixir --erl '+S 2:2' "$@" entry.exs > run.log 2>&1 || status=$?
post=0
cd "$runtime"
sha256sum --check --status /dev/shm/ipse-word-larger-proof-20261103-01/live-runtime.sha256 || post=1
sha256sum --check --status "$proof/product-source.sha256" || post=1
cd "$proof"
sha256sum --check --status inputs.sha256 || post=1
printf 'test_exit=%s\npostcheck_exit=%s\n' "$status" "$post" > status
sync -f status
test "$post" -eq 0
exit "$status"
