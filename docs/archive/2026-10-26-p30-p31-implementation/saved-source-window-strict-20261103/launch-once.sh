#!/bin/bash
set -euo pipefail
set -C
umask 077
export TMPDIR=/dev/shm
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS MIX_BUILD_PATH MIX_DEPS_PATH MIX_HOME MIX_ARCHIVES HEX_HOME LD_PRELOAD LD_LIBRARY_PATH ERL_FLAGS
snapshot=/dev/shm/ipse-recall33-saved-window-20261103-01
proof=/dev/shm/ipse-recall33-saved-window-proof-20261103-01
for dir in "$snapshot" "$proof" "$snapshot/task-home"; do
  if [ ! -d "$dir" ] || [ -L "$dir" ] || [ "$(stat -c '%u:%a' "$dir")" != "$(id -u):700" ]; then exit 1; fi
done
for name in launch.claim one-shot.log postcheck.log completion.txt runtime-before-paths.txt runtime-before-links.txt runtime-after-paths.txt runtime-after-links.txt; do
  if [ -e "$proof/$name" ] || [ -L "$proof/$name" ]; then exit 1; fi
done
cd "$snapshot"
pins() {
  printf '%s  %s\n' \
    d94243978e4483b388f6d95bcf4707a05127940ac30d8d37dd57c3db69d4b672 "$proof/candidate.patch" \
    4ff8701b0e87d1d2d0f2ba8c60c7ae060847bcd9b25052ee886ca0810b783ae3 "$proof/strict-fixture.patch" \
    49d957786da045e64fb21768bc5508ca34b574123161906bcc9c0d4fa366702c "$proof/tested-source.sha256" \
    a06c00004c46a11265c7376a91e82b7156b15f089ba10ae76586a0cf64cbd9a0 "$proof/fixture-source.sha256" \
    8e846418d4a082e346b841701a7add27262d7ba79607f3af1fe3549a8e3aa510 "$proof/tested-runtime.sha256" \
    c478f8b663e14a6064bb68313323444f08574f13e5746f780cc717ed4a402fc5 "$proof/tested-runtime-paths.txt" \
    45aeb8b70faba5ef2fa0d3217215e462358e84e2643465f693186dca73e77cb4 "$proof/tested-runtime-links.txt" \
    742756163a022c614e55820094acf62a8dc94194484b594760e5a87efda15dda "$proof/exunit-one-shot.exs" | sha256sum --quiet -c
}
inventory() {
  sha256sum --quiet -c "$proof/fixture-source.sha256" &&
  sha256sum --quiet -c "$proof/tested-runtime.sha256" &&
  find _build/test/lib priv -type f -print | LC_ALL=C sort | cmp - "$proof/tested-runtime-paths.txt" &&
  find _build/test/lib priv -type l -printf '%p -> %l\n' | LC_ALL=C sort | cmp - "$proof/tested-runtime-links.txt"
}
pins
inventory
find _build/test/lib priv -type f -print | LC_ALL=C sort > "$proof/runtime-before-paths.txt"
find _build/test/lib priv -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/runtime-before-links.txt"
for var in $(compgen -A variable IPSE_); do unset "$var"; done
export ERL_FLAGS='+S 2:2' IPSE_HOME="$snapshot/task-home" IPSE_BUILD_COMMIT=18c748fc30ed09438ebdaaaf6d6d13b8e970cbcf
export IPSE_TEST_RECALL_MANY=1 IPSE_TEST_RECALL_REQUIRE_SINGLE=1 IPSE_TEST_RECALL_KEEP=1 IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS=5000 IPSE_TEST_RECALL_TIMING=0
set --
for beam_path in "$snapshot"/_build/test/lib/*/ebin; do
  if [ ! -d "$beam_path" ] || [ -L "$beam_path" ]; then exit 1; fi
  set -- "$@" -pa "$beam_path"
done
printf 'one fresh synthetic strict Session attempt; do not retry on uncertainty\n' > "$proof/launch.claim"
sync -f "$proof/launch.claim"
status=0
elixir "$@" "$proof/exunit-one-shot.exs" > "$proof/one-shot.log" 2>&1 || status=$?
post=0
{
  pins && inventory &&
  find _build/test/lib priv -type f -print | LC_ALL=C sort > "$proof/runtime-after-paths.txt" &&
  find _build/test/lib priv -type l -printf '%p -> %l\n' | LC_ALL=C sort > "$proof/runtime-after-links.txt" &&
  cmp "$proof/tested-runtime-paths.txt" "$proof/runtime-after-paths.txt" &&
  cmp "$proof/tested-runtime-links.txt" "$proof/runtime-after-links.txt"
} > "$proof/postcheck.log" 2>&1 || post=$?
printf 'test_exit=%s\npostcheck_exit=%s\n' "$status" "$post" > "$proof/completion.txt"
sync -f "$proof/completion.txt"
[ "$post" -eq 0 ] || exit 125
exit "$status"
