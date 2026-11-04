#!/usr/bin/env bash
set -euo pipefail
umask 077
root=/home/lexlapax/projects/lexlapax/ipse
base="$root/_build/verification/ipse-p30-pending-current-use-20261104-01"
run="$base/execution-02"
runtime="$base/execution-01"
cd "$root"
sha256sum --check --status "$run/inputs.sha256"
sha256sum --check --status "$run/runtime.sha256"
sha256sum --check --status "$run/original-runtime.sha256"
[ -z "$(find "$runtime/lib" -type l -print -quit)" ]
state=$(mktemp -d /dev/shm/ipse-p30-pending-deadline-XXXXXX)
chmod 700 "$state"
mkdir -m 700 "$state/tmp" "$state/home"
printf '%s\n' "$state" > "$run/state-root.txt"
dd if=/dev/zero of="$state/owned-quota-probe" bs=1048576 count=32 conv=fsync status=none
rm -- "$state/owned-quota-probe"
(set -C; printf 'one fresh own-deadline P30 case; output-revocation excluded; complete private app closure; no automatic retry\n' > "$run/actual.claim")
sync -- "$run/actual.claim" "$run"
paths=()
for directory in "$runtime"/lib/*/ebin; do paths+=(-pa "$directory"); done
if env -i PATH=/usr/bin:/bin:/home/lexlapax/.cargo/bin LANG=C.utf8 LC_ALL=C.utf8 HOME="$state/home" IPSE_HOME="$state/home/.ipse" TMPDIR="$state/tmp" RUSTUP_HOME=/home/lexlapax/.rustup MIX_ENV=test ERL_FLAGS='+S 2:2 +A 2' elixir "${paths[@]}" "$run/entry.exs" > "$run/raw-private.log" 2>&1; then
  test_status=0
else
  test_status=$?
fi
input_status=0
sha256sum --check --status "$run/inputs.sha256" || input_status=$?
runtime_status=0
sha256sum --check --status "$run/runtime.sha256" || runtime_status=$?
original_runtime_status=0
sha256sum --check --status "$run/original-runtime.sha256" || original_runtime_status=$?
find "$runtime/lib" \( -type f -o -type l \) -print | LC_ALL=C sort > "$run/runtime-pathset.post.txt"
pathset_status=0
cmp -s "$run/runtime-pathset.txt" "$run/runtime-pathset.post.txt" || pathset_status=$?
printf 'test_exit=%s\ninputs_post=%s\nprivate_runtime_post=%s\noriginal_runtime_post=%s\nprivate_pathset_post=%s\n' "$test_status" "$input_status" "$runtime_status" "$original_runtime_status" "$pathset_status" > "$run/status.txt"
cat "$run/status.txt"
if [ "$input_status" -ne 0 ] || [ "$runtime_status" -ne 0 ] || [ "$original_runtime_status" -ne 0 ] || [ "$pathset_status" -ne 0 ]; then exit 74; fi
exit "$test_status"
