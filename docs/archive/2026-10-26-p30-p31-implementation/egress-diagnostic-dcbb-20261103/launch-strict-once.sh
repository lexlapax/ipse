#!/bin/bash
export TMPDIR=/dev/shm
set -euo pipefail
set -C
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS MIX_BUILD_PATH MIX_DEPS_PATH MIX_HOME MIX_ARCHIVES LD_PRELOAD LD_LIBRARY_PATH
snapshot=/dev/shm/ipse-egress-marks-dcbb-20261103-01
proof=/dev/shm/ipse-egress-marks-proof-dcbb-20261103-01
for dir in "$snapshot" "$proof" "$proof/strict-home"; do
  if [ ! -d "$dir" ] || [ -L "$dir" ] || [ "$(stat -c '%u:%a' "$dir")" != "$(id -u):700" ]; then exit 1; fi
done
for name in strict.claim strict.log strict-analysis.log strict-sources.log strict-postcheck.log strict-completion.txt strict-build-before.sha256 strict-priv-before.sha256 strict-build-after.sha256 strict-priv-after.sha256; do
  if [ -e "$proof/$name" ] || [ -L "$proof/$name" ]; then exit 1; fi
done
cd "$snapshot"
[ -z "${IPSE_RUNNER_PATH+x}" ]
printf '%s  %s\n' \
  3139225420054e423448e3184dc3c98f38e404c7af8c6c65afe0068400584b9f "$proof/source-final.sha256" \
  fcdfbc8fe9dda4cdaedccc2688f5fc58d9ddf5010a87f5ed4c77a7997828cf00 "$proof/deps-final.sha256" \
  feafa5e6bb28b99353d58ea97bd36c447df6f6cb75ef26aeb2e18fc7cc25b179 "$proof/build-final.sha256" \
  d9c496e3c126170f617d021953bf3062f9bbaf256b5a171c87582770bb5469f5 "$proof/priv-final.sha256" \
  0fd4d0bba5ed1485c2b2946b960bc794f61a74e491f5e2113f70f65710af605c "$proof/exunit-strict.exs" \
  5dfa5dade9b58d0e8fe7ecc13a65f6fd4aec048a585c8052105cf7865eebb057 "$proof/filter-small.exs" \
  0f26010df68f614ea1a936e75d374989d4331ce390c53d93de0a8d3d3927f5e2 "$proof/analyze-strict.exs" \
  04adcb14b579474ec951a97de445e4c6cacb7d54f97b5efdb935a98e35c5e416 "$proof/verify-sources.exs" | sha256sum --quiet -c
sha256sum --quiet -c "$proof/source-final.sha256"
sha256sum --quiet -c "$proof/deps-final.sha256"
sha256sum --quiet -c "$proof/build-final.sha256"
sha256sum --quiet -c "$proof/priv-final.sha256"
find _build/test/lib -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/strict-build-before.sha256"
find priv -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/strict-priv-before.sha256"
cmp "$proof/build-final.sha256" "$proof/strict-build-before.sha256"
cmp "$proof/priv-final.sha256" "$proof/strict-priv-before.sha256"
for var in $(compgen -A variable IPSE_); do unset "$var"; done
export MIX_ENV=test ERL_FLAGS='+S 2:2' IPSE_HOME="$proof/strict-home"
export IPSE_BUILD_COMMIT=dcbb07dd451f1402d28391b716b2b177e35331a7
export IPSE_TEST_RECALL_MANY=1 IPSE_TEST_RECALL_REQUIRE_SINGLE=1 IPSE_TEST_RECALL_KEEP=1 IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS=5000 IPSE_TEST_RECALL_TIMING=0
printf 'one fresh strict synthetic diagnostic; do not retry on uncertainty\n' > "$proof/strict.claim"
sync -f "$proof/strict.claim"
set +e
mix run --no-compile --no-deps-check --no-start "$proof/exunit-strict.exs" 2>&1 | elixir "$proof/filter-small.exs" > "$proof/strict.log"
statuses=("${PIPESTATUS[@]}")
set -e
test_status=${statuses[0]}
filter_status=${statuses[1]}
analysis_status=2
sources_status=2
mapfile -t roots < <(sed -n 's/^NATIVE_RECALL_FIXTURE_ROOT=//p' "$proof/strict.log")
if [ "$filter_status" -eq 0 ] && [ "${#roots[@]}" -eq 1 ]; then
  fixture=${roots[0]}
  if [[ "$fixture" =~ ^/dev/shm/ipse-native-recall-[0-9a-f]{32}$ ]] && [ -d "$fixture" ] && [ ! -L "$fixture" ] && [ "$(stat -c '%u:%a' "$fixture")" = "$(id -u):700" ]; then
    if [ -f "$fixture/egress-marks.jsonl" ] && [ ! -L "$fixture/egress-marks.jsonl" ]; then
      elixir -pa _build/test/lib/jason/ebin "$proof/analyze-strict.exs" "$fixture/egress-marks.jsonl" > "$proof/strict-analysis.log" 2>&1 && analysis_status=0 || analysis_status=$?
    fi
    if [ -f "$fixture/recall-source-before.json" ] && [ ! -L "$fixture/recall-source-before.json" ]; then
      elixir -pa _build/test/lib/jason/ebin "$proof/verify-sources.exs" "$fixture" > "$proof/strict-sources.log" 2>&1 && sources_status=0 || sources_status=$?
    fi
  fi
fi
post=0
{
  printf '%s  %s\n' \
    0fd4d0bba5ed1485c2b2946b960bc794f61a74e491f5e2113f70f65710af605c "$proof/exunit-strict.exs" \
    5dfa5dade9b58d0e8fe7ecc13a65f6fd4aec048a585c8052105cf7865eebb057 "$proof/filter-small.exs" \
    0f26010df68f614ea1a936e75d374989d4331ce390c53d93de0a8d3d3927f5e2 "$proof/analyze-strict.exs" \
    04adcb14b579474ec951a97de445e4c6cacb7d54f97b5efdb935a98e35c5e416 "$proof/verify-sources.exs" | sha256sum --quiet -c &&
  sha256sum --quiet -c "$proof/source-final.sha256" &&
  sha256sum --quiet -c "$proof/deps-final.sha256" &&
  sha256sum --quiet -c "$proof/build-final.sha256" &&
  sha256sum --quiet -c "$proof/priv-final.sha256" &&
  find _build/test/lib -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/strict-build-after.sha256" &&
  find priv -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/strict-priv-after.sha256" &&
  cmp "$proof/build-final.sha256" "$proof/strict-build-after.sha256" &&
  cmp "$proof/priv-final.sha256" "$proof/strict-priv-after.sha256"
} > "$proof/strict-postcheck.log" 2>&1 || post=$?
printf 'test_exit=%s\nfilter_exit=%s\nanalysis_exit=%s\nsources_exit=%s\npostcheck_exit=%s\n' "$test_status" "$filter_status" "$analysis_status" "$sources_status" "$post" > "$proof/strict-completion.txt"
sync -f "$proof/strict-completion.txt"
[ "$test_status" -eq 0 ] && [ "$filter_status" -eq 0 ] && [ "$analysis_status" -eq 0 ] && [ "$sources_status" -eq 0 ] && [ "$post" -eq 0 ]
