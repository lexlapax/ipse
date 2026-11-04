#!/usr/bin/env bash
set -euo pipefail
cd /home/lexlapax/projects/lexlapax/ipse
packet=_build/verification/ipse-recall33-strict-sources-20261104-01
runtime="$PWD/_build/verification/ipse-research-transfer-20261104-01/runtime"
evidence="$packet/actual-01"
mkdir "$evidence"
sha256sum --quiet -c "$packet/runtime.sha256"
sha256sum --quiet -c "$packet/fixture.sha256"
find "$runtime/lib" -type f -print0 | sort -z | xargs -0 sha256sum > "$evidence/runtime.sha256"
find "$runtime/lib" -type l -printf '%p -> %l\n' | sort > "$evidence/runtime.links"
find "$packet/candidate" -type f -print0 | sort -z | xargs -0 sha256sum > "$evidence/fixture.sha256"
sha256sum "$packet/entry.exs" "$packet/run-actual-01.sh" > "$evidence/entry.sha256"
set +e
fuser "/tmp/ipse-operator-$(id -u)/input.lock" > "$evidence/operator-before.log" 2>&1
operator_before=$?
set -e
printf '%s\n' "$operator_before" > "$evidence/operator-before.exit"
test "$operator_before" -eq 1
test ! -s "$evidence/operator-before.log"
run_root=$(mktemp -d /dev/shm/ipse-recall33-strict-20261104-01.XXXXXXXX)
chmod 700 "$run_root"
printf '%s\n' "$run_root" > "$evidence/root.path"
mkdir "$run_root/tmp" "$run_root/operator-home"
chmod 700 "$run_root/tmp" "$run_root/operator-home"
dd if=/dev/zero of="$run_root/storage-probe" bs=1048576 count=32 conv=fsync status=none
rm "$run_root/storage-probe"
printf 'storage_32mib_fsync=pass\n' > "$evidence/storage.log"
printf 'one fresh strict33 actual\n' > "$evidence/one-attempt.claim"
set +e
env -i PATH="$PATH" LANG=C.utf8 LC_ALL=C.utf8 TERM="${TERM:-xterm-256color}" HOME="$run_root/operator-home" IPSE_HOME="$run_root/operator-home/.ipse" TMPDIR="$run_root/tmp" \
  RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" \
  IPSE_RUNNER_PATH="$runtime/lib/ipse/priv/ipse-runner" \
  ERL_CRASH_DUMP="$run_root/erl_crash.dump" IPSE_TEST_NATIVE_ROOT_APPROVAL=0 IPSE_RECALL_STRICT_ACTUAL=1 IPSE_TEST_RECALL_KEEP=1 ERL_FLAGS='+S 2:2 +A 2' \
  elixir -pa "$runtime/lib/*/ebin" "$packet/entry.exs" actual > "$evidence/private.log" 2>&1
result=$?
set -e
printf '%s\n' "$result" > "$evidence/test.exit"
post_failure=0
for kind in runtime fixture entry; do
  if sha256sum --quiet -c "$evidence/$kind.sha256" > "$evidence/$kind.post" 2>&1; then
    printf '0\n' > "$evidence/$kind.post.exit"
  else
    printf '1\n' > "$evidence/$kind.post.exit"
    post_failure=1
  fi
done
find "$runtime/lib" -type f -print0 | sort -z | xargs -0 sha256sum > "$evidence/runtime.after.sha256"
find "$runtime/lib" -type l -printf '%p -> %l\n' | sort > "$evidence/runtime.after.links"
find "$packet/candidate" -type f -print0 | sort -z | xargs -0 sha256sum > "$evidence/fixture.after.sha256"
for kind in runtime.sha256 runtime.links fixture.sha256; do
  before="$evidence/$kind"
  case "$kind" in
    runtime.sha256) after="$evidence/runtime.after.sha256";;
    runtime.links) after="$evidence/runtime.after.links";;
    fixture.sha256) after="$evidence/fixture.after.sha256";;
  esac
  if cmp "$before" "$after" > "$evidence/$kind.pathset.post" 2>&1; then
    printf '0\n' > "$evidence/$kind.pathset.post.exit"
  else
    printf '1\n' > "$evidence/$kind.pathset.post.exit"
    post_failure=1
  fi
done
set +e
fuser "/tmp/ipse-operator-$(id -u)/input.lock" > "$evidence/operator-after.log" 2>&1
operator_after=$?
pgrep -af "$run_root" > "$evidence/process-after.log" 2>&1
process_after=$?
set -e
printf '%s\n' "$operator_after" > "$evidence/operator-after.exit"
printf '%s\n' "$process_after" > "$evidence/process-after.exit"
if test "$operator_after" -ne 1 || test -s "$evidence/operator-after.log" || test "$process_after" -ne 1 || test -s "$evidence/process-after.log"; then post_failure=1; fi
printf 'cohort_exit=%s integrity_failure=%s fresh_root_retained=true\n' "$result" "$post_failure"
test "$post_failure" -eq 0
exit "$result"
