#!/usr/bin/env bash
set -euo pipefail
cd /home/lexlapax/projects/lexlapax/ipse
packet="$PWD/_build/verification/ipse-research-managed-coexistence-20261104-01"
cohort="$packet/cohort-04"
runtime="$packet/cohort-01/runtime"
evidence="$cohort/execution-01"
mkdir "$evidence"
sha256sum --quiet -c "$cohort/runtime.sha256"
sha256sum --quiet -c "$cohort/source.sha256"
find "$runtime" "$cohort/source" -mindepth 1 -printf '%p %y %l\n' | LC_ALL=C sort > "$evidence/pathset-before.txt"
sha256sum "$cohort/entry.exs" "$cohort/run-once.sh" > "$evidence/entry.sha256"
set +e
fuser "/tmp/ipse-operator-$(id -u)/input.lock" > "$evidence/operator-before.log" 2>&1
operator_before=$?
set -e
printf '%s\n' "$operator_before" > "$evidence/operator-before.exit"
test "$operator_before" -eq 1
test ! -s "$evidence/operator-before.log"
available=$(df -B1 --output=avail /dev/shm | tail -1 | tr -d ' ')
test "$available" -ge 268435456
fresh=$(mktemp -d /dev/shm/ipse-mixed-h1-wire-07c-20261104-04.XXXXXXXX)
chmod 700 "$fresh"
mkdir "$fresh/home" "$fresh/tmp"
chmod 700 "$fresh/home" "$fresh/tmp"
printf '%s\n' "$fresh" > "$evidence/fresh-root.path"
dd if=/dev/zero of="$fresh/fsync-probe" bs=1048576 count=32 conv=fsync status=none
rm "$fresh/fsync-probe"
printf 'available_bytes=%s required_bytes=268435456 storage_32mib_fsync=pass\n' "$available" > "$evidence/storage.log"
cat "$evidence/storage.log"
printf 'fresh_root=%s\n' "$fresh"
beam_args=()
for beam_dir in "$runtime"/lib/*/ebin; do beam_args+=(-pa "$beam_dir"); done
printf 'ONE fresh mixed H1 native seed and two consumer paths\n' > "$evidence/actual.claim"
set +e
(cd "$cohort/source" && env -i PATH="$PATH" HOME="$fresh/home" IPSE_HOME="$fresh/home/.ipse" \
  LANG=C.utf8 LC_ALL=C.utf8 TERM="${TERM:-xterm-256color}" TMPDIR="$fresh/tmp" \
  RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" \
  ERL_FLAGS='+S 1:1 +A 1' ERL_CRASH_DUMP="$fresh/crash.dump" \
  IPSE_TEST_RESEARCH_MIXED=1 IPSE_TEST_RESEARCH_KEEP=1 IPSE_TEST_NATIVE_ROOT_APPROVAL=0 \
  IPSE_DOCUMENT_NATIVE_TMPDIR="$fresh/tmp" IPSE_RUNNER_PATH="$runtime/lib/ipse/priv/ipse-runner" \
  elixir "${beam_args[@]}" "$cohort/entry.exs") > "$evidence/raw-private.log" 2>&1
result=$?
set -e
printf '%s\n' "$result" > "$evidence/test.exit"
post_failure=0
for kind in runtime source entry; do
  if test "$kind" = entry; then manifest="$evidence/entry.sha256"; else manifest="$cohort/$kind.sha256"; fi
  set +e
  sha256sum --quiet -c "$manifest" > "$evidence/$kind.post" 2>&1
  check=$?
  set -e
  printf '%s\n' "$check" > "$evidence/$kind.post.exit"
  if test "$check" -ne 0; then post_failure=1; fi
done
find "$runtime" "$cohort/source" -mindepth 1 -printf '%p %y %l\n' | LC_ALL=C sort > "$evidence/pathset-after.txt"
set +e
cmp "$evidence/pathset-before.txt" "$evidence/pathset-after.txt" > "$evidence/pathset.post" 2>&1
pathset=$?
fuser "/tmp/ipse-operator-$(id -u)/input.lock" > "$evidence/operator-after.log" 2>&1
operator_after=$?
pgrep -af "$fresh" > "$evidence/process-after.log" 2>&1
process_after=$?
set -e
printf '%s\n' "$pathset" > "$evidence/pathset.post.exit"
printf '%s\n' "$operator_after" > "$evidence/operator-after.exit"
printf '%s\n' "$process_after" > "$evidence/process-after.exit"
if test "$pathset" -ne 0 || test "$operator_after" -ne 1 || test -s "$evidence/operator-after.log" || test "$process_after" -ne 1 || test -s "$evidence/process-after.log"; then post_failure=1; fi
printf 'test_exit=%s integrity_failure=%s retained_root=true\n' "$result" "$post_failure"
test "$post_failure" -eq 0
exit "$result"
