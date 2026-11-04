#!/bin/bash
set -euo pipefail
set -C
proof=/dev/shm/ipse-word-larger-proof-20261103-01
candidate=/dev/shm/ipse-word-combined-tests-20261103-01
cd "$candidate"
for path in "$proof/combined.claim" "$proof/combined.log" "$proof/combined.status"; do
  if [ -e "$path" ] || [ -L "$path" ]; then exit 1; fi
done
printf '%s  %s\n' \
 '91b4af67b874d7de9b835328659e9d04995257775b1be007ef653035563cd807' "$proof/combined-source.sha256" \
 '0316176400d416360cef91f05da394c3058e9972a0a3ad23e8a508800230b0c2' "$proof/live-runtime.sha256" \
 'ba05de2f0e7434fc6b136b6af5c66a7c1926611ff585d84fbdca5319b6db143f' "$proof/combined-entry.exs" \
 'ad204c095ad99b827d00cf6eb9efbbf0f7fd8e601d46dafe19d78e199ae45542' test/extensions/knowledge/document_acquisition_session_test.exs | sha256sum --quiet -c
sha256sum --quiet -c "$proof/combined-source.sha256"
sha256sum --quiet -c "$proof/combined-source.sha256"
sha256sum --quiet -c "$proof/live-runtime.sha256"
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/combined-pre.files"
cmp "$proof/live-runtime.files" "$proof/combined-pre.files"
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/combined-pre.links"
cmp "$proof/live-runtime.links" "$proof/combined-pre.links"
printf '%s\n' 'one isolated four fresh opt-in Word Sessions' > "$proof/combined.claim"
for name in $(compgen -e); do
  case "$name" in IPSE_*|MIX_*|HEX_*|ERL_FLAGS|ERL_AFLAGS|ERL_ZFLAGS|ERL_LIBS|ELIXIR_ERL_OPTIONS|ELIXIR_OPTS|LD_PRELOAD|LD_LIBRARY_PATH) unset "$name" ;; esac
done
export TMPDIR=/dev/shm IPSE_HOME="$candidate/task-build-home" MIX_HOME="$candidate/task-mix-home" HEX_HOME="$candidate/task-hex-home" ERL_FLAGS='+S 2:2' IPSE_TEST_WORD_SHIPPED=1 IPSE_TEST_WORD_KEEP=1 IPSE_DOCUMENT_NATIVE_TMPDIR=/dev/shm
set --
for beam_path in "$candidate"/_build/test/lib/*/ebin; do set -- "$@" -pa "$beam_path"; done
set +e
elixir "$@" "$proof/combined-entry.exs" > "$proof/combined.log" 2>&1
test_status=$?
set -e
post_status=0
sha256sum --quiet -c "$proof/combined-source.sha256" || post_status=1
sha256sum --quiet -c "$proof/combined-source.sha256" || post_status=1
sha256sum --quiet -c "$proof/live-runtime.sha256" || post_status=1
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/combined-post.files"
cmp "$proof/live-runtime.files" "$proof/combined-post.files" || post_status=1
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/combined-post.links"
cmp "$proof/live-runtime.links" "$proof/combined-post.links" || post_status=1
printf 'test_exit=%s\npostcheck_exit=%s\n' "$test_status" "$post_status" > "$proof/combined.status"
if [ "$test_status" -ne 0 ] || [ "$post_status" -ne 0 ]; then exit 1; fi
