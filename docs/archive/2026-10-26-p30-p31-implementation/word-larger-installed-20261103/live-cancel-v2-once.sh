#!/bin/bash
set -euo pipefail
set -C
proof=/dev/shm/ipse-word-larger-proof-20261103-01
candidate=/dev/shm/ipse-word-larger-candidate-20261103-01
cd "$candidate"
for path in "$proof/live-cancel-v2.claim" "$proof/live-cancel-v2.log" "$proof/live-cancel-v2.status"; do
  if [ -e "$path" ] || [ -L "$path" ]; then exit 1; fi
done
printf '%s  %s\n' \
 '8907cfc464ab9400b4d96ae6d6902cfa8144c81f920e59d46c7edca58964976b' "$proof/word-vertical-live.sha256" \
 '0316176400d416360cef91f05da394c3058e9972a0a3ad23e8a508800230b0c2' "$proof/live-runtime.sha256" \
 'a11075922dc4452433eb64df9b3ea89ddd7c7f1456220b80d1edb68a7d40fb9f' "$proof/live-cancel-v2.exs" \
 '488f7cb0ad17714820f91c8108d8618f1bbb71a6b54515793f7fe65451b2c943' /dev/shm/ipse-word-larger-proof-20261103-01/peer-cancel-fixture-v2.exs | sha256sum --quiet -c
sha256sum --quiet -c "$proof/word-vertical-live.sha256"
sha256sum --quiet -c "$proof/live-source.sha256"
sha256sum --quiet -c "$proof/live-runtime.sha256"
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/live-cancel-v2-pre.files"
cmp "$proof/live-runtime.files" "$proof/live-cancel-v2-pre.files"
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/live-cancel-v2-pre.links"
cmp "$proof/live-runtime.links" "$proof/live-cancel-v2-pre.links"
printf '%s\n' 'one isolated one fresh large Word Session' > "$proof/live-cancel-v2.claim"
for name in $(compgen -e); do
  case "$name" in IPSE_*|MIX_*|HEX_*|ERL_FLAGS|ERL_AFLAGS|ERL_ZFLAGS|ERL_LIBS|ELIXIR_ERL_OPTIONS|ELIXIR_OPTS|LD_PRELOAD|LD_LIBRARY_PATH) unset "$name" ;; esac
done
export TMPDIR=/dev/shm IPSE_HOME="$candidate/task-build-home" MIX_HOME="$candidate/task-mix-home" HEX_HOME="$candidate/task-hex-home" ERL_FLAGS='+S 2:2' IPSE_TEST_WORD_SHIPPED=1 IPSE_TEST_WORD_KEEP=1 IPSE_DOCUMENT_NATIVE_TMPDIR=/dev/shm
set --
for beam_path in "$candidate"/_build/test/lib/*/ebin; do set -- "$@" -pa "$beam_path"; done
set +e
elixir "$@" "$proof/live-cancel-v2.exs" > "$proof/live-cancel-v2.log" 2>&1
test_status=$?
set -e
post_status=0
sha256sum --quiet -c "$proof/word-vertical-live.sha256" || post_status=1
sha256sum --quiet -c "$proof/live-source.sha256" || post_status=1
sha256sum --quiet -c "$proof/live-runtime.sha256" || post_status=1
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/live-cancel-v2-post.files"
cmp "$proof/live-runtime.files" "$proof/live-cancel-v2-post.files" || post_status=1
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/live-cancel-v2-post.links"
cmp "$proof/live-runtime.links" "$proof/live-cancel-v2-post.links" || post_status=1
printf 'test_exit=%s\npostcheck_exit=%s\n' "$test_status" "$post_status" > "$proof/live-cancel-v2.status"
if [ "$test_status" -ne 0 ] || [ "$post_status" -ne 0 ]; then exit 1; fi
