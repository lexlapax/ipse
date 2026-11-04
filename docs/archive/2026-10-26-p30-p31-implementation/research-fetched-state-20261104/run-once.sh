#!/usr/bin/env bash
set -euo pipefail
cd /home/lexlapax/projects/lexlapax/ipse
packet="$PWD/_build/verification/ipse-research-fetch-transfer-20261104-01"
evidence="$packet/execution-01"
mkdir "$evidence"
sha256sum --quiet -c "$packet/runtime.sha256"
sha256sum --quiet -c "$packet/source.sha256"
sha256sum "$packet/entry.exs" "$packet/run-once.sh" > "$evidence/entry.sha256"
find "$packet/runtime" "$packet/source" -mindepth 1 -printf '%p %y %l\n' | LC_ALL=C sort > "$evidence/pathset-before.txt"
available=$(df -B1 --output=avail /dev/shm | tail -1 | tr -d ' ')
test "$available" -ge 134217728
fresh=$(mktemp -d /dev/shm/ipse-research-fetch-transfer-20261104-01.XXXXXXXX)
chmod 700 "$fresh"
mkdir "$fresh/home" "$fresh/tmp"
chmod 700 "$fresh/home" "$fresh/tmp"
printf '%s\n' "$fresh" > "$evidence/fresh-root.path"
dd if=/dev/zero of="$fresh/fsync-probe" bs=1048576 count=32 conv=fsync status=none
rm "$fresh/fsync-probe"
printf 'available_bytes=%s storage_32mib_fsync=pass operator_Input=false\n' "$available" > "$evidence/storage.log"
cat "$evidence/storage.log"
printf 'fresh_root=%s\n' "$fresh"
beam_args=()
for beam_dir in "$packet"/runtime/lib/*/ebin; do beam_args+=(-pa "$beam_dir"); done
printf 'ONE fresh ordinary MCP and State Session cohort, no Input or retained root\n' > "$evidence/actual.claim"
set +e
(cd "$packet/source" && env -i PATH="$PATH" HOME="$fresh/home" IPSE_HOME="$fresh/home/.ipse" \
 LANG=C.utf8 LC_ALL=C.utf8 TMPDIR="$fresh/tmp" ERL_FLAGS='+S 1:1 +A 1' ERL_CRASH_DUMP="$fresh/crash.dump" \
 IPSE_TEST_RESEARCH_FETCH_SESSION=1 IPSE_TEST_RESEARCH_FETCH_KEEP=1 IPSE_TEST_NATIVE_ROOT_APPROVAL=0 \
 IPSE_DOCUMENT_NATIVE_TMPDIR="$fresh/tmp" IPSE_RUNNER_PATH="$packet/runtime/lib/ipse/priv/ipse-runner" \
 elixir "${beam_args[@]}" "$packet/entry.exs") > "$evidence/raw-private.log" 2>&1
result=$?
set -e
printf '%s\n' "$result" > "$evidence/test.exit"
post_failure=0
for kind in runtime source entry; do
 if test "$kind" = entry; then manifest="$evidence/entry.sha256"; else manifest="$packet/$kind.sha256"; fi
 set +e
 sha256sum --quiet -c "$manifest" > "$evidence/$kind.post" 2>&1
 code=$?
 set -e
 printf '%s\n' "$code" > "$evidence/$kind.post.exit"
 if test "$code" -ne 0; then post_failure=1; fi
done
find "$packet/runtime" "$packet/source" -mindepth 1 -printf '%p %y %l\n' | LC_ALL=C sort > "$evidence/pathset-after.txt"
set +e
cmp "$evidence/pathset-before.txt" "$evidence/pathset-after.txt" > "$evidence/pathset.post" 2>&1
pathset=$?
pgrep -af "$fresh" > "$evidence/process-after.log" 2>&1
process_after=$?
set -e
printf '%s\n' "$pathset" > "$evidence/pathset.post.exit"
printf '%s\n' "$process_after" > "$evidence/process-after.exit"
if test "$pathset" -ne 0 || test "$process_after" -ne 1 || test -s "$evidence/process-after.log"; then post_failure=1; fi
printf 'test_exit=%s integrity_failure=%s retained_root=true operator_Input=false\n' "$result" "$post_failure"
test "$post_failure" -eq 0
exit "$result"
