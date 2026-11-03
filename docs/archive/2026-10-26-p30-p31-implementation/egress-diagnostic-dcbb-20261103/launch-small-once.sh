#!/bin/bash
export TMPDIR=/dev/shm
set -euo pipefail
set -C
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS MIX_BUILD_PATH MIX_DEPS_PATH MIX_HOME MIX_ARCHIVES LD_PRELOAD LD_LIBRARY_PATH
snapshot=/dev/shm/ipse-egress-marks-dcbb-20261103-01
proof=/dev/shm/ipse-egress-marks-proof-dcbb-20261103-01
for dir in "$snapshot" "$proof" "$snapshot/task-home"; do
  if [ ! -d "$dir" ] || [ -L "$dir" ] || [ "$(stat -c '%u:%a' "$dir")" != "$(id -u):700" ]; then exit 1; fi
done
for name in small.claim small.log small-validation.log small-postcheck.log small-completion.txt small-build-before.sha256 small-priv-before.sha256 small-build-after.sha256 small-priv-after.sha256; do
  if [ -e "$proof/$name" ] || [ -L "$proof/$name" ]; then exit 1; fi
done
cd "$snapshot"
[ -z "${IPSE_RUNNER_PATH+x}" ]
printf '%s  %s\n' \
  3139225420054e423448e3184dc3c98f38e404c7af8c6c65afe0068400584b9f "$proof/source-final.sha256" \
  fcdfbc8fe9dda4cdaedccc2688f5fc58d9ddf5010a87f5ed4c77a7997828cf00 "$proof/deps-final.sha256" \
  feafa5e6bb28b99353d58ea97bd36c447df6f6cb75ef26aeb2e18fc7cc25b179 "$proof/build-final.sha256" \
  d9c496e3c126170f617d021953bf3062f9bbaf256b5a171c87582770bb5469f5 "$proof/priv-final.sha256" \
  7d78c7e075bb2e16ab9a0fa2798be5ce2c2c638cbe6ba407bf19815a06c5defb "$proof/exunit-small.exs" | sha256sum --quiet -c
printf '%s  %s\n' 5dfa5dade9b58d0e8fe7ecc13a65f6fd4aec048a585c8052105cf7865eebb057 "$proof/filter-small.exs" | sha256sum --quiet -c
sha256sum --quiet -c "$proof/source-final.sha256"
sha256sum --quiet -c "$proof/deps-final.sha256"
sha256sum --quiet -c "$proof/build-final.sha256"
sha256sum --quiet -c "$proof/priv-final.sha256"
find _build/test/lib -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/small-build-before.sha256"
find priv -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/small-priv-before.sha256"
cmp "$proof/build-final.sha256" "$proof/small-build-before.sha256"
cmp "$proof/priv-final.sha256" "$proof/small-priv-before.sha256"
for var in $(compgen -A variable IPSE_); do unset "$var"; done
export MIX_ENV=test ERL_FLAGS='+S 2:2' IPSE_HOME="$snapshot/task-home"
export IPSE_BUILD_COMMIT=dcbb07dd451f1402d28391b716b2b177e35331a7 IPSE_TEST_RECALL_KEEP=1
printf 'one fresh three-note synthetic diagnostic; do not retry on uncertainty\n' > "$proof/small.claim"
sync -f "$proof/small.claim"
set +e
mix run --no-compile --no-deps-check --no-start "$proof/exunit-small.exs" 2>&1 |
  elixir "$proof/filter-small.exs" > "$proof/small.log"
statuses=("${PIPESTATUS[@]}")
set -e
test_status=${statuses[0]}
filter_status=${statuses[1]}
validation_status=1
mapfile -t roots < <(sed -n 's/^NATIVE_RECALL_FIXTURE_ROOT=//p' "$proof/small.log")
if [ "$test_status" -eq 0 ] && [ "$filter_status" -eq 0 ] && [ "${#roots[@]}" -eq 1 ]; then
  fixture=${roots[0]}
  if [[ "$fixture" =~ ^/dev/shm/ipse-native-recall-[0-9a-f]{32}$ ]] && [ -d "$fixture" ] && [ ! -L "$fixture" ] && [ "$(stat -c '%u:%a' "$fixture")" = "$(id -u):700" ] && [ -f "$fixture/egress-marks.jsonl" ] && [ ! -L "$fixture/egress-marks.jsonl" ]; then
    elixir -pa _build/test/lib/jason/ebin mark-fixture/validate-small.exs "$fixture/egress-marks.jsonl" > "$proof/small-validation.log" 2>&1 && validation_status=0 || validation_status=$?
  fi
fi
post=0
{
  printf '%s  %s\n' 5dfa5dade9b58d0e8fe7ecc13a65f6fd4aec048a585c8052105cf7865eebb057 "$proof/filter-small.exs" | sha256sum --quiet -c &&
  sha256sum --quiet -c "$proof/source-final.sha256" &&
  sha256sum --quiet -c "$proof/deps-final.sha256" &&
  sha256sum --quiet -c "$proof/build-final.sha256" &&
  sha256sum --quiet -c "$proof/priv-final.sha256" &&
  find _build/test/lib -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/small-build-after.sha256" &&
  find priv -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$proof/small-priv-after.sha256" &&
  cmp "$proof/build-final.sha256" "$proof/small-build-after.sha256" &&
  cmp "$proof/priv-final.sha256" "$proof/small-priv-after.sha256"
} > "$proof/small-postcheck.log" 2>&1 || post=$?
printf 'test_exit=%s\nfilter_exit=%s\nvalidation_exit=%s\npostcheck_exit=%s\n' "$test_status" "$filter_status" "$validation_status" "$post" > "$proof/small-completion.txt"
sync -f "$proof/small-completion.txt"
[ "$post" -eq 0 ] && [ "$test_status" -eq 0 ] && [ "$filter_status" -eq 0 ] && [ "$validation_status" -eq 0 ]
