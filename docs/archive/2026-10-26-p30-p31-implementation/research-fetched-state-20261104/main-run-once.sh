#!/usr/bin/env bash
set -euo pipefail
cd /home/lexlapax/projects/lexlapax/ipse
evidence="$PWD/_build/verification/research-fetch-main-integration-20261104-01"
test ! -e "$evidence/actual.claim"
for beam_dir in _build/test/lib/*/ebin; do find -H "$beam_dir" -maxdepth 1 -type f -print0; done | LC_ALL=C sort -z | xargs -0 sha256sum > "$evidence/runtime.sha256"
find priv -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum >> "$evidence/runtime.sha256"
git ls-files -z -- lib extensions test mix.exs mix.lock .formatter.exs > "$evidence/source-paths.nul"
printf '%s\0' extensions/knowledge/options/research-state-fetched.json test/extensions/knowledge/research_fetch_transfer_test.exs test/support/research_fetch_transfer_pure.exs test/support/research_fetch_transfer_session.exs >> "$evidence/source-paths.nul"
LC_ALL=C sort -zu "$evidence/source-paths.nul" | xargs -0 sha256sum > "$evidence/source.sha256"
sha256sum "$evidence/run-once.sh" > "$evidence/entry.sha256"
sha256sum --quiet -c "$evidence/runtime.sha256"
sha256sum --quiet -c "$evidence/source.sha256"
available=$(df -B1 --output=avail /dev/shm | tail -1 | tr -d ' ')
test "$available" -ge 268435456
fresh=$(mktemp -d /dev/shm/ipse-research-fetch-main-20261104-01.XXXXXXXX)
chmod 700 "$fresh"
mkdir "$fresh/home" "$fresh/tmp" "$fresh/mix"
chmod 700 "$fresh/home" "$fresh/tmp" "$fresh/mix"
printf '%s\n' "$fresh" > "$evidence/fresh-root.path"
dd if=/dev/zero of="$fresh/fsync-probe" bs=1048576 count=32 conv=fsync status=none
rm "$fresh/fsync-probe"
printf 'available_bytes=%s storage_32mib_fsync=pass native_operator_used=false\n' "$available" > "$evidence/storage.log"
printf 'ONE whole fetched Research test file; private Input entries checked in child; no operator claim\n' > "$evidence/actual.claim"
set +e
env -i PATH="$PATH" HOME="$fresh/home" IPSE_HOME="$fresh/home/.ipse" TMPDIR="$fresh/tmp" \
 MIX_HOME="$fresh/mix" MIX_ARCHIVES=/home/lexlapax/.mix/archives HEX_OFFLINE=1 \
 LANG=C.utf8 LC_ALL=C.utf8 ERL_FLAGS='+S 1:1 +A 1' ERL_CRASH_DUMP="$fresh/crash.dump" \
 IPSE_TEST_RESEARCH_FETCH_SESSION=1 IPSE_TEST_RESEARCH_FETCH_KEEP=1 IPSE_TEST_NATIVE_ROOT_APPROVAL=0 \
 IPSE_DOCUMENT_NATIVE_TMPDIR="$fresh/tmp" IPSE_RUNNER_PATH="$PWD/priv/ipse-runner" \
 mix test --no-compile --no-deps-check test/extensions/knowledge/research_fetch_transfer_test.exs > "$evidence/raw-private.log" 2>&1
result=$?
set -e
printf '%s\n' "$result" > "$evidence/test.status"
post_failure=0
for kind in runtime source entry; do
 set +e
 sha256sum --quiet -c "$evidence/$kind.sha256" > "$evidence/$kind.post.log" 2>&1
 code=$?
 set -e
 printf '%s\n' "$code" > "$evidence/$kind.post.status"
 if test "$code" -ne 0; then post_failure=1; fi
done
set +e
pgrep -af "$fresh" > "$evidence/process-after.log" 2>&1
process_after=$?
set -e
printf '%s\n' "$process_after" > "$evidence/process-after.status"
if test "$process_after" -ne 1 || test -s "$evidence/process-after.log"; then post_failure=1; fi
printf 'test_exit=%s integrity_failure=%s operator_Input=false retained_root=true\n' "$result" "$post_failure"
test "$post_failure" -eq 0
exit "$result"
