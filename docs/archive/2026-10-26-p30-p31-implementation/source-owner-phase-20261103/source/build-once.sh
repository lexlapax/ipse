#!/bin/bash
set -euo pipefail
export TMPDIR=/dev/shm
while IFS= read -r name; do case "$name" in IPSE_*) unset "$name" ;; esac; done < <(compgen -e)
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS MIX_BUILD_PATH MIX_DEPS_PATH MIX_ARCHIVES LD_PRELOAD LD_LIBRARY_PATH ERL_FLAGS MIX_HOME HEX_HOME
export ERL_FLAGS='+S 2:2' MIX_ENV=test MIX_OFFLINE=1 HEX_OFFLINE=1
export IPSE_BUILD_COMMIT=f44f2506de2de47a31c84f2b1b7617236c4d340f
snapshot=/dev/shm/ipse-source-phase-f44-20261103-01
cache_source=/home/lexlapax/projects/lexlapax/ipse/.document-default-package-JSTWB1
export MIX_HOME="$snapshot/phase-fixture/offline/mix" HEX_HOME="$snapshot/phase-fixture/offline/hex" IPSE_HOME="$snapshot/phase-fixture/offline/ipse"
cd "$snapshot"
[ ! -e deps ] && [ ! -L deps ] && [ ! -e _build ] && [ ! -L _build ] || exit 1
[ ! -e phase-fixture/offline ] && [ ! -L phase-fixture/offline ] || exit 1
[ ! -e phase-fixture/build.claim ] && [ ! -L phase-fixture/build.claim ] || exit 1
check_source() {
  printf '%s  %s\n' c475a44fc89d5c6067b9eb98b6bfe993f860ac032a930bdd92bf8538b04fb873 phase-fixture/all-source.files | sha256sum -c >/dev/null &&
  printf '%s  %s\n' 7fab8eff0fb7b6286a46735a373737b35ee5ee63980774adb36e8b9d559484d4 phase-fixture/all-source.symlinks | sha256sum -c >/dev/null &&
  printf '%s  %s\n' 5a1de2262b98f1ced417accf702c97d8cbcab301f6b9e4fca731693632bd2a0c phase-fixture/all-source.sha256 | sha256sum -c >/dev/null &&
  cut -c 67- phase-fixture/all-source.sha256 | cmp - phase-fixture/all-source.files &&
  sha256sum -c phase-fixture/all-source.sha256 >/dev/null &&
  LC_ALL=C find . \( -path ./phase-fixture -o -path ./deps -o -path ./_build -o -path ./priv/extension-bundles -o -path ./priv/ipse-runner -o -path ./priv/ipse-pdf -o -path ./priv/ipse-pdf-notices \) -prune -o -type f -print | LC_ALL=C sort | cmp - phase-fixture/all-source.files &&
  LC_ALL=C find . \( -path ./phase-fixture -o -path ./deps -o -path ./_build -o -path ./priv/extension-bundles -o -path ./priv/ipse-runner -o -path ./priv/ipse-pdf -o -path ./priv/ipse-pdf-notices \) -prune -o -type l -printf '%p\t%l\n' | LC_ALL=C sort | cmp - phase-fixture/all-source.symlinks
}
check_source
cmp mix.lock "$cache_source/source/mix.lock"
set -o noclobber
printf 'one-shot build\n' > phase-fixture/build.claim
mkdir -m 700 phase-fixture/offline "$MIX_HOME" "$HEX_HOME" "$IPSE_HOME"
# The source is a previous synthetic installed-package fixture, not an independent dependency attestation.
copy_cache() {
  local origin=$1 destination=$2 tag=$3
  [ -d "$origin" ] && [ ! -L "$origin" ] || exit 1
  (cd "$origin"; LC_ALL=C find . -type f -print | LC_ALL=C sort) > "phase-fixture/$tag.files"
  (cd "$origin"; LC_ALL=C find . -type l -printf '%p\t%l\n' | LC_ALL=C sort) > "phase-fixture/$tag.symlinks"
  (cd "$origin"; while IFS= read -r path; do sha256sum "$path"; done < "$snapshot/phase-fixture/$tag.files") > "phase-fixture/$tag.sha256"
  cp -a "$origin/." "$destination/"
  (cd "$destination"; sha256sum -c "$snapshot/phase-fixture/$tag.sha256" >/dev/null)
  (cd "$destination"; LC_ALL=C find . -type f -print | LC_ALL=C sort) | cmp - "phase-fixture/$tag.files"
  (cd "$destination"; LC_ALL=C find . -type l -printf '%p\t%l\n' | LC_ALL=C sort) | cmp - "phase-fixture/$tag.symlinks"
}
mkdir -m 700 deps
copy_cache "$cache_source/source/deps" "$snapshot/deps" deps
copy_cache "$cache_source/home/.mix" "$MIX_HOME" mix-cache
copy_cache "$cache_source/home/.hex" "$HEX_HOME" hex-cache
{ elixir --version; rustc --version; } > phase-fixture/toolchain.log
sh dev/build-native.sh
mix deps.compile
mix compile --force --warnings-as-errors
mix run --no-start dev/build-bundles.exs
check_source
# Dependencies must remain the same copied bytes; Mix/Hex caches can acquire task-local state.
(cd deps; sha256sum -c "$snapshot/phase-fixture/deps.sha256" >/dev/null)
(cd deps; LC_ALL=C find . -type f -print | LC_ALL=C sort) | cmp - phase-fixture/deps.files
(cd deps; LC_ALL=C find . -type l -printf '%p\t%l\n' | LC_ALL=C sort) | cmp - phase-fixture/deps.symlinks
LC_ALL=C find _build/test/lib priv -type f -print | LC_ALL=C sort > phase-fixture/runtime.files
LC_ALL=C find _build/test/lib priv -type l -printf '%p\t%l\n' | LC_ALL=C sort > phase-fixture/runtime.symlinks
while IFS= read -r path; do sha256sum "$path"; done < phase-fixture/runtime.files > phase-fixture/runtime.sha256
cut -c 67- phase-fixture/runtime.sha256 | cmp - phase-fixture/runtime.files
sha256sum -c phase-fixture/runtime.sha256 >/dev/null
printf 'build completed\n' > phase-fixture/build.completed
