#!/usr/bin/env bash
set -euo pipefail
cd /home/lexlapax/projects/lexlapax/ipse
evidence="$PWD/_build/verification/research-main-integration-20261104-01"
test ! -e "$evidence/actual.claim"
cp _build/verification/root-pair-main-integration-20261104-01/runtime-after-build.sha256 "$evidence/runtime.sha256"
for beam_dir in _build/test/lib/*/ebin; do
  find -H "$beam_dir" -maxdepth 1 -type f -print0
done | LC_ALL=C sort -z | xargs -0 sha256sum >> "$evidence/runtime.sha256"
git ls-files -z -- lib extensions test mix.exs mix.lock .formatter.exs > "$evidence/source-paths.nul"
printf '%s\0' test/support/research_managed_coexistence.exs test/support/research_managed_wire.exs >> "$evidence/source-paths.nul"
LC_ALL=C sort -zu "$evidence/source-paths.nul" | xargs -0 sha256sum > "$evidence/source.sha256"
sha256sum "$evidence/run-once.sh" > "$evidence/entry.sha256"
sha256sum --quiet -c "$evidence/runtime.sha256"
sha256sum --quiet -c "$evidence/source.sha256"
set +e
fuser "/tmp/ipse-operator-$(id -u)/input.lock" > "$evidence/operator-before.log" 2>&1
operator_before=$?
set -e
printf '%s\n' "$operator_before" > "$evidence/operator-before.status"
test "$operator_before" -eq 1
test ! -s "$evidence/operator-before.log"
available=$(df -B1 --output=avail /dev/shm | tail -1 | tr -d ' ')
test "$available" -ge 268435456
fresh=$(mktemp -d /dev/shm/ipse-research-main-20261104-01.XXXXXXXX)
chmod 700 "$fresh"
mkdir "$fresh/home" "$fresh/tmp" "$fresh/mix"
chmod 700 "$fresh/home" "$fresh/tmp" "$fresh/mix"
printf '%s\n' "$fresh" > "$evidence/fresh-root.path"
dd if=/dev/zero of="$fresh/fsync-probe" bs=1048576 count=32 conv=fsync status=none
rm "$fresh/fsync-probe"
printf 'available_bytes=%s required_bytes=268435456 storage_32mib_fsync=pass\n' "$available" > "$evidence/storage.log"
printf 'ONE official main mixed H1 case with exact error and zero-unknown assertions\n' > "$evidence/actual.claim"
set +e
env -i PATH="$PATH" HOME="$fresh/home" IPSE_HOME="$fresh/home/.ipse" \
  LANG=C.utf8 LC_ALL=C.utf8 TERM="${TERM:-xterm-256color}" TMPDIR="$fresh/tmp" \
  RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" \
  MIX_HOME="$fresh/mix" MIX_ARCHIVES=/home/lexlapax/.mix/archives HEX_OFFLINE=1 \
  ERL_FLAGS='+S 2:2 +A 1' ERL_CRASH_DUMP="$fresh/crash.dump" \
  IPSE_TEST_RESEARCH_MIXED=1 IPSE_TEST_RESEARCH_KEEP=1 IPSE_TEST_NATIVE_ROOT_APPROVAL=0 \
  IPSE_DOCUMENT_NATIVE_TMPDIR="$fresh/tmp" IPSE_RUNNER_PATH="$PWD/priv/ipse-runner" \
  mix test --no-compile --no-deps-check --only mixed_h1_coexistence:true \
  test/extensions/knowledge/research_transfer_test.exs > "$evidence/raw-private.log" 2>&1
result=$?
set -e
printf '%s\n' "$result" > "$evidence/test.status"
post_failure=0
for kind in runtime source entry; do
  set +e
  sha256sum --quiet -c "$evidence/$kind.sha256" > "$evidence/$kind.post.log" 2>&1
  check=$?
  set -e
  printf '%s\n' "$check" > "$evidence/$kind.post.status"
  if test "$check" -ne 0; then post_failure=1; fi
done
set +e
fuser "/tmp/ipse-operator-$(id -u)/input.lock" > "$evidence/operator-after.log" 2>&1
operator_after=$?
pgrep -af "$fresh" > "$evidence/process-after.log" 2>&1
process_after=$?
set -e
printf '%s\n' "$operator_after" > "$evidence/operator-after.status"
printf '%s\n' "$process_after" > "$evidence/process-after.status"
if test "$operator_after" -ne 1 || test -s "$evidence/operator-after.log" || test "$process_after" -ne 1 || test -s "$evidence/process-after.log"; then post_failure=1; fi
printf 'test_exit=%s integrity_failure=%s retained_root=true\n' "$result" "$post_failure"
test "$post_failure" -eq 0
exit "$result"
