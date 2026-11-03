#!/bin/bash
set -euo pipefail
set -C
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS MIX_BUILD_PATH MIX_DEPS_PATH MIX_HOME MIX_ARCHIVES LD_PRELOAD LD_LIBRARY_PATH
snapshot=/dev/shm/ipse-recall33-combined-dcbb-20261103-01
proof=/dev/shm/ipse-recall33-combined-preflight-dcbb-20261103-01
entry_hash=684c5002f69a075c64d56f48207744b2451ec8e1304de067e28846a049d3f4ca
for dir in "$snapshot" "$proof" "$snapshot/task-home"; do
  if [ ! -d "$dir" ] || [ -L "$dir" ] || [ "$(stat -c '%u:%a' "$dir")" != "$(id -u):700" ]; then exit 1; fi
done
for name in launch.claim one-shot.log postcheck.log completion.txt build-before.sha256 priv-before.sha256 build-after.sha256 priv-after.sha256; do
  if [ -e "$proof/$name" ] || [ -L "$proof/$name" ]; then exit 1; fi
done
cd "$snapshot"
[ -z "${IPSE_RUNNER_PATH+x}" ]
printf '%s  %s\n' \
  664c2f4a55b2079a05da47614a12b74d1ec607ab582d3a5a577e7412069ce9e2 "$proof/source.sha256" \
  25909bf415e15e8b8e620bccdf3e8d2a3d3baafae06ddeff8e674678ff9e405e "$proof/deps-post.sha256" \
  61a79efff4b788203df9a11c48244fd2def8fd90bc0cc775b5064d910c927bd7 "$proof/build.sha256" \
  7ce8a7ed6362a0af423b6afc56a60443a603d16f4f60f2dc59b4e467ee16cb2e "$proof/priv.sha256" \
  "$entry_hash" "$proof/exunit-one-shot.exs" | sha256sum --quiet -c
sha256sum --quiet -c "$proof/source.sha256"
sha256sum --quiet -c "$proof/deps-post.sha256"
sha256sum --quiet -c "$proof/build.sha256"
sha256sum --quiet -c "$proof/priv.sha256"
find _build/test/lib -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/build-before.sha256"
find priv -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/priv-before.sha256"
cmp "$proof/build.sha256" "$proof/build-before.sha256"
cmp "$proof/priv.sha256" "$proof/priv-before.sha256"
for var in $(compgen -A variable IPSE_); do unset "$var"; done
export MIX_ENV=test ERL_FLAGS='+S 2:2' TMPDIR=/dev/shm IPSE_HOME="$snapshot/task-home"
export IPSE_BUILD_COMMIT=dcbb07dd451f1402d28391b716b2b177e35331a7
export IPSE_TEST_RECALL_MANY=1 IPSE_TEST_RECALL_REQUIRE_SINGLE=1 IPSE_TEST_RECALL_KEEP=1 IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS=5000 IPSE_TEST_RECALL_TIMING=0
printf 'one fresh synthetic strict Session attempt; do not retry on uncertainty\n' > "$proof/launch.claim"
sync -f "$proof/launch.claim"
status=0
mix run --no-compile --no-deps-check --no-start "$proof/exunit-one-shot.exs" > "$proof/one-shot.log" 2>&1 || status=$?
post=0
{
  printf '%s  %s\n' "$entry_hash" "$proof/exunit-one-shot.exs" | sha256sum --quiet -c &&
  sha256sum --quiet -c "$proof/source.sha256" &&
  sha256sum --quiet -c "$proof/deps-post.sha256" &&
  sha256sum --quiet -c "$proof/build.sha256" &&
  sha256sum --quiet -c "$proof/priv.sha256" &&
  find _build/test/lib -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/build-after.sha256" &&
  find priv -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/priv-after.sha256" &&
  cmp "$proof/build.sha256" "$proof/build-after.sha256" &&
  cmp "$proof/priv.sha256" "$proof/priv-after.sha256"
} > "$proof/postcheck.log" 2>&1 || post=$?
printf 'test_exit=%s\npostcheck_exit=%s\n' "$status" "$post" > "$proof/completion.txt"
sync -f "$proof/completion.txt"
[ "$post" -eq 0 ] || exit 125
exit "$status"
