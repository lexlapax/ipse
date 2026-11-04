#!/bin/bash
set -euo pipefail
snapshot=/home/lexlapax/projects/lexlapax/ipse/_build/verification/ipse-expiry-current-d3-20261104-02
protected=/dev/shm/ipse-expiry-renewal-native-d3-20261104-03
cd "$snapshot"
test ! -e evidence/renewal03/renewal-launch.claim
sha256sum --check --status evidence/renewal03/required-helpers.sha256
umask 077
mkdir -m 700 "$protected" "$protected/home" "$protected/tmp"
dd if=/dev/zero of="$protected/quota-probe" bs=1048576 count=4 conv=fsync status=none > evidence/renewal03/renewal-quota.log 2>&1
printf 'quota_write_sync_bytes=4194304\nquota_exit=0\n' >> evidence/renewal03/renewal-quota.log
rm "$protected/quota-probe"
sha256sum --check --status evidence/source-before.sha256
sha256sum --check --status evidence/runtime-final.sha256
sha256sum --check --status evidence/renewal03/renewal-fixtures.sha256
for task_env_key in ${!IPSE_@}; do unset "$task_env_key"; done
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS ERL_FLAGS LD_PRELOAD LD_LIBRARY_PATH MIX_BUILD_PATH MIX_DEPS_PATH
export HOME="$protected/home" IPSE_HOME="$protected/home/.ipse" TMPDIR="$protected/tmp"
runtime_args=()
for runtime_ebin in "$snapshot"/_build/test/lib/*/ebin; do
  if test "$(basename "$(dirname "$runtime_ebin")")" != ipse; then runtime_args+=(-pa "$runtime_ebin"); fi
done
runtime_args+=(-pa "$snapshot/clock-runtime/stdio-runtime/ipse/ebin")
test_exit=0
elixir --erl '+S 1:1 +A 1' "${runtime_args[@]}" evidence/renewal03/renewal-entry.exs > evidence/renewal03/renewal-native.log 2>&1 || test_exit=$?
post_exit=0
sha256sum --check --status evidence/source-before.sha256 || post_exit=1
sha256sum --check --status evidence/runtime-final.sha256 || post_exit=1
sha256sum --check --status evidence/renewal03/renewal-fixtures.sha256 || post_exit=1
sha256sum --check --status evidence/renewal03/required-helpers.sha256 || post_exit=1
sha256sum --check --status /home/lexlapax/projects/lexlapax/ipse/_build/verification/ipse-cache-current-ace41-20261103-01/evidence/deps-before.sha256 || post_exit=1
find "$snapshot/_build/test/lib/ipse/ebin" "$snapshot/priv" "$snapshot/clock-runtime/stdio-runtime/ipse" -type f -print0 | sort -z | xargs -0 sha256sum > evidence/renewal03/runtime-after-renewal.sha256
cmp evidence/runtime-final.sha256 evidence/renewal03/runtime-after-renewal.sha256 || post_exit=1
find "$snapshot/_build/test/lib" "$snapshot/deps" "$snapshot/mix-archives" "$snapshot/clock-runtime" -type l -printf '%p -> %l\n' | sort > evidence/renewal03/runtime-after-renewal.links
cmp evidence/runtime-final.links evidence/renewal03/runtime-after-renewal.links || post_exit=1
find lib extensions test native dev -type f -o -type l | sort > evidence/renewal03/source-input-pathset-after-renewal.txt
cmp evidence/source-input-pathset-final.txt evidence/renewal03/source-input-pathset-after-renewal.txt || post_exit=1
printf 'test_exit=%s\npostcheck_exit=%s\n' "$test_exit" "$post_exit" > evidence/renewal03/renewal-native-status.txt
exit "$test_exit"
