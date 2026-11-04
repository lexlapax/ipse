#!/bin/bash
set -euo pipefail
set -C
proof=/dev/shm/ipse-word-larger-proof-20261103-01
candidate=/dev/shm/ipse-word-larger-candidate-20261103-01
cd "$candidate"
for path in "$proof/live-large.claim" "$proof/live-large.log" "$proof/live-large.status"; do
  if [ -e "$path" ] || [ -L "$path" ]; then exit 1; fi
done
printf '%s  %s\n' \
 '8907cfc464ab9400b4d96ae6d6902cfa8144c81f920e59d46c7edca58964976b' "$proof/word-vertical-live.sha256" \
 '0316176400d416360cef91f05da394c3058e9972a0a3ad23e8a508800230b0c2' "$proof/live-runtime.sha256" \
 '716baa98d4339fabc47034f71f1bac8e854e45914ea0f47fb0f1afd2185013a2' "$proof/live-large.exs" \
 '825fde3c2a775f293aaf70f2e6524a91f757711ae21ccb043b59e8f8942332dc' /dev/shm/ipse-word-guard-diagnostic-20261103-01/test/extensions/knowledge/document_acquisition_session_test.exs | sha256sum --quiet -c
sha256sum --quiet -c "$proof/word-vertical-live.sha256"
sha256sum --quiet -c "$proof/live-source.sha256"
sha256sum --quiet -c "$proof/live-runtime.sha256"
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/live-large-pre.files"
cmp "$proof/live-runtime.files" "$proof/live-large-pre.files"
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/live-large-pre.links"
cmp "$proof/live-runtime.links" "$proof/live-large-pre.links"
printf '%s\n' 'one isolated one fresh large Word Session' > "$proof/live-large.claim"
for name in $(compgen -e); do
  case "$name" in IPSE_*|MIX_*|HEX_*|ERL_FLAGS|ERL_AFLAGS|ERL_ZFLAGS|ERL_LIBS|ELIXIR_ERL_OPTIONS|ELIXIR_OPTS|LD_PRELOAD|LD_LIBRARY_PATH) unset "$name" ;; esac
done
export TMPDIR=/dev/shm IPSE_HOME="$candidate/task-build-home" MIX_HOME="$candidate/task-mix-home" HEX_HOME="$candidate/task-hex-home" ERL_FLAGS='+S 2:2' IPSE_TEST_WORD_SHIPPED=1 IPSE_TEST_WORD_KEEP=1 IPSE_DOCUMENT_NATIVE_TMPDIR=/dev/shm
set --
for beam_path in "$candidate"/_build/test/lib/*/ebin; do set -- "$@" -pa "$beam_path"; done
set +e
elixir "$@" "$proof/live-large.exs" > "$proof/live-large.log" 2>&1
test_status=$?
set -e
post_status=0
sha256sum --quiet -c "$proof/word-vertical-live.sha256" || post_status=1
sha256sum --quiet -c "$proof/live-source.sha256" || post_status=1
sha256sum --quiet -c "$proof/live-runtime.sha256" || post_status=1
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/live-large-post.files"
cmp "$proof/live-runtime.files" "$proof/live-large-post.files" || post_status=1
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/live-large-post.links"
cmp "$proof/live-runtime.links" "$proof/live-large-post.links" || post_status=1
printf 'test_exit=%s\npostcheck_exit=%s\n' "$test_status" "$post_status" > "$proof/live-large.status"
if [ "$test_status" -ne 0 ] || [ "$post_status" -ne 0 ]; then exit 1; fi
