#!/bin/bash
set -euo pipefail
set -C
proof=/dev/shm/ipse-word-larger-proof-20261103-01
candidate=/dev/shm/ipse-word-default-fixture-20261103-01
cd "$candidate"
for path in "$proof/default-fixture.claim" "$proof/default-fixture.log" "$proof/default-fixture.status"; do
  if [ -e "$path" ] || [ -L "$path" ]; then exit 1; fi
done
printf '%s  %s\n' \
 '48e4b77d702f180b9a999110f018d93814b73025a7cd22b4740dd77e18f0b7b6' "$proof/default-fixture-source.sha256" \
 '0316176400d416360cef91f05da394c3058e9972a0a3ad23e8a508800230b0c2' "$proof/live-runtime.sha256" \
 '9ff707bb07f2bd562c192d4c36975e1e794a7a6b02d2996202c8ce2f104789a9' "$proof/default-fixture-entry.exs" \
 '2d5a33910e95b5a7d96060b1fe68d62fb5683d90040d46370262890da8bdc342' test/extensions/knowledge/document_acquisition_session_test.exs | sha256sum --quiet -c
sha256sum --quiet -c "$proof/default-fixture-source.sha256"
sha256sum --quiet -c "$proof/default-fixture-source.sha256"
sha256sum --quiet -c "$proof/live-runtime.sha256"
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/default-fixture-pre.files"
cmp "$proof/live-runtime.files" "$proof/default-fixture-pre.files"
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/default-fixture-pre.links"
cmp "$proof/live-runtime.links" "$proof/default-fixture-pre.links"
printf '%s\n' 'one isolated four fresh opt-in Word Sessions' > "$proof/default-fixture.claim"
for name in $(compgen -e); do
  case "$name" in IPSE_*|MIX_*|HEX_*|ERL_FLAGS|ERL_AFLAGS|ERL_ZFLAGS|ERL_LIBS|ELIXIR_ERL_OPTIONS|ELIXIR_OPTS|LD_PRELOAD|LD_LIBRARY_PATH) unset "$name" ;; esac
done
export TMPDIR=/dev/shm IPSE_HOME="$candidate/task-build-home" MIX_HOME="$candidate/task-mix-home" HEX_HOME="$candidate/task-hex-home" ERL_FLAGS='+S 2:2' IPSE_TEST_WORD_KEEP=1 IPSE_DOCUMENT_NATIVE_TMPDIR=/dev/shm
set --
for beam_path in "$candidate"/_build/test/lib/*/ebin; do set -- "$@" -pa "$beam_path"; done
set +e
elixir "$@" "$proof/default-fixture-entry.exs" > "$proof/default-fixture.log" 2>&1
test_status=$?
set -e
post_status=0
sha256sum --quiet -c "$proof/default-fixture-source.sha256" || post_status=1
sha256sum --quiet -c "$proof/default-fixture-source.sha256" || post_status=1
sha256sum --quiet -c "$proof/live-runtime.sha256" || post_status=1
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/default-fixture-post.files"
cmp "$proof/live-runtime.files" "$proof/default-fixture-post.files" || post_status=1
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/default-fixture-post.links"
cmp "$proof/live-runtime.links" "$proof/default-fixture-post.links" || post_status=1
printf 'test_exit=%s\npostcheck_exit=%s\n' "$test_status" "$post_status" > "$proof/default-fixture.status"
if [ "$test_status" -ne 0 ] || [ "$post_status" -ne 0 ]; then exit 1; fi
