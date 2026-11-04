#!/bin/bash
set -euo pipefail
set -C
proof=/dev/shm/ipse-word-larger-proof-20261103-01
candidate=/dev/shm/ipse-word-larger-candidate-20261103-01
cd "$candidate"
for path in "$proof/live-focused.claim" "$proof/live-focused.log" "$proof/live-focused.status"; do
  if [ -e "$path" ] || [ -L "$path" ]; then exit 1; fi
done
sha256sum --quiet -c "$proof/word-vertical-live.sha256"
sha256sum --quiet -c "$proof/live-source.sha256"
sha256sum --quiet -c "$proof/live-runtime.sha256"
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/live-focused-pre.files"
cmp "$proof/live-runtime.files" "$proof/live-focused-pre.files"
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/live-focused-pre.links"
cmp "$proof/live-runtime.links" "$proof/live-focused-pre.links"
printf '%s\n' 'one isolated exact-peer focused controls' > "$proof/live-focused.claim"
for name in $(compgen -e); do
  case "$name" in IPSE_*|MIX_*|HEX_*|ERL_FLAGS|ERL_AFLAGS|ERL_ZFLAGS|ERL_LIBS|ELIXIR_ERL_OPTIONS|ELIXIR_OPTS|LD_PRELOAD|LD_LIBRARY_PATH) unset "$name" ;; esac
done
export TMPDIR=/dev/shm IPSE_HOME="$candidate/task-build-home" MIX_HOME="$candidate/task-mix-home" HEX_HOME="$candidate/task-hex-home" ERL_FLAGS='+S 2:2'
set --
for beam_path in "$candidate"/_build/test/lib/*/ebin; do set -- "$@" -pa "$beam_path"; done
set +e
elixir "$@" "$proof/live-focused.exs" > "$proof/live-focused.log" 2>&1
test_status=$?
set -e
post_status=0
sha256sum --quiet -c "$proof/word-vertical-live.sha256" || post_status=1
sha256sum --quiet -c "$proof/live-source.sha256" || post_status=1
sha256sum --quiet -c "$proof/live-runtime.sha256" || post_status=1
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/live-focused-post.files"
cmp "$proof/live-runtime.files" "$proof/live-focused-post.files" || post_status=1
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/live-focused-post.links"
cmp "$proof/live-runtime.links" "$proof/live-focused-post.links" || post_status=1
printf 'test_exit=%s\npostcheck_exit=%s\n' "$test_status" "$post_status" > "$proof/live-focused.status"
if [ "$test_status" -ne 0 ] || [ "$post_status" -ne 0 ]; then exit 1; fi
