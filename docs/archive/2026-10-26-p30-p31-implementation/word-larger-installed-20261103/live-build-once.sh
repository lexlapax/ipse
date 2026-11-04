#!/bin/bash
set -euo pipefail
set -C
proof=/dev/shm/ipse-word-larger-proof-20261103-01
candidate=/dev/shm/ipse-word-larger-candidate-20261103-01
cd "$candidate"
for path in "$proof/live-build.claim" "$proof/live-build.log" "$proof/live-build.status"; do
  if [ -e "$path" ] || [ -L "$path" ]; then exit 1; fi
done
printf '%s  %s\n' '58d14a9a6bff6390e225a196f9834d0e09be77e77c052d424dd12b2a2198de15' "$proof/live-source.sha256" '503469018f4c457e8c230d6340316283436b296c4cb0b442c762475842504191' "$proof/peer-runtime.sha256" | sha256sum --quiet -c
sha256sum --quiet -c "$proof/live-source.sha256"
sha256sum --quiet -c "$proof/peer-runtime.sha256"
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/live-build-pre.files"
cmp "$proof/peer-runtime.files" "$proof/live-build-pre.files"
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/live-build-pre.links"
cmp "$proof/peer-runtime.links" "$proof/live-build-pre.links"
find lib native extensions test dev priv -type f ! -path 'priv/ipse-runner' ! -path 'priv/ipse-pdf' ! -path 'priv/extension-bundles/*' -print | LC_ALL=C sort > "$proof/live-source-pre.files"
cmp "$proof/live-source.files" "$proof/live-source-pre.files"
printf '%s\n' 'one isolated peer-reader build' > "$proof/live-build.claim"
for name in $(compgen -e); do
  case "$name" in IPSE_*|MIX_*|HEX_*|ERL_FLAGS|ERL_AFLAGS|ERL_ZFLAGS|ERL_LIBS|ELIXIR_ERL_OPTIONS|ELIXIR_OPTS|LD_PRELOAD|LD_LIBRARY_PATH) unset "$name" ;; esac
done
export TMPDIR=/dev/shm MIX_HOME="$candidate/task-mix-home" HEX_HOME="$candidate/task-hex-home" IPSE_HOME="$candidate/task-build-home" MIX_OFFLINE=1 HEX_OFFLINE=1 MIX_ENV=test ERL_FLAGS='+S 2:2' IPSE_BUILD_PDF=0
set +e
mix compile --warnings-as-errors > "$proof/live-build.log" 2>&1
build_status=$?
set -e
post_status=0
sha256sum --quiet -c "$proof/live-source.sha256" || post_status=1
find lib native extensions test dev priv -type f ! -path 'priv/ipse-runner' ! -path 'priv/ipse-pdf' ! -path 'priv/extension-bundles/*' -print | LC_ALL=C sort > "$proof/live-build-post.files"
cmp "$proof/live-source.files" "$proof/live-build-post.files" || post_status=1
find lib native extensions test dev priv -type l ! -path 'priv/extension-bundles/*' -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/live-build-post.links"
cmp "$proof/live-source.links" "$proof/live-build-post.links" || post_status=1
printf 'build_exit=%s\npostcheck_exit=%s\n' "$build_status" "$post_status" > "$proof/live-build.status"
if [ "$build_status" -ne 0 ] || [ "$post_status" -ne 0 ]; then exit 1; fi
find _build/test/lib priv/extension-bundles -type f -print | LC_ALL=C sort > "$proof/live-runtime.files"
xargs -d '\n' sha256sum < "$proof/live-runtime.files" > "$proof/live-runtime.sha256"
find _build/test/lib priv/extension-bundles -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/live-runtime.links"
