#!/bin/bash
set -euo pipefail
set -C
umask 077
snapshot=/dev/shm/ipse-p30-pending-installed-5c-20261103-01
output=/dev/shm/ipse-p30-pending-installed-output-20261103-01
archive=/dev/shm/ipse-word-disappear-e0-20261103-01/dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS MIX_BUILD_PATH MIX_DEPS_PATH MIX_ARCHIVES MIX_HOME MIX_ENV HEX_HOME LD_PRELOAD LD_LIBRARY_PATH RELEASE_NODE RELEASE_COOKIE RELEASE_DISTRIBUTION RELEASE_ROOT RELEASE_BOOT_SCRIPT
for var in $(compgen -A variable IPSE_); do unset "$var"; done
cd "$snapshot"
for dir in "$snapshot" "$snapshot/task-home" "$snapshot/task-tmp"; do
  if [ ! -d "$dir" ] || [ -L "$dir" ] || [ "$(stat -c '%u:%a' "$dir")" != "$(id -u):700" ]; then exit 1; fi
done
for name in "$output" task-claim.txt task-installed.log task-result.txt task-postcheck.log; do
  if [ -e "$name" ] || [ -L "$name" ]; then exit 1; fi
done
printf '%s  %s\n' 8d9cb09e3a5587d732f86e5a4d01c46682803d079618c9ddd57016d7a38bd60f task-inputs.sha256 678b446a8351a9eed9a3ac6ce738064ce9981767842d7cf27dfef9fa60d0667d "$archive" 0ed5edde8edca1af66578f1f8ca6055a7280e1080bfd0c0d711e9b3d815f95ed "$archive.sha256" | sha256sum --quiet -c
sha256sum --quiet -c task-inputs.sha256
export TMPDIR="$snapshot/task-tmp" IPSE_HOME="$snapshot/task-home" ERL_FLAGS='+S 2:2 +A 2'
printf '%s\n' 'One synthetic installed pending assessment batch; do not retry an uncertain result.' > task-claim.txt
sync -f task-claim.txt
status=0
elixir dev/verification/pending_shadow_installed.exs "$archive" "$output" > task-installed.log 2>&1 || status=$?
post=0
printf '%s  %s\n' 8d9cb09e3a5587d732f86e5a4d01c46682803d079618c9ddd57016d7a38bd60f task-inputs.sha256 678b446a8351a9eed9a3ac6ce738064ce9981767842d7cf27dfef9fa60d0667d "$archive" 0ed5edde8edca1af66578f1f8ca6055a7280e1080bfd0c0d711e9b3d815f95ed "$archive.sha256" | sha256sum --quiet -c > task-postcheck.log 2>&1 || post=$?
sha256sum --quiet -c task-inputs.sha256 >> task-postcheck.log 2>&1 || post=$?
printf 'verifier_exit=%s\nsource_archive_postcheck_exit=%s\n' "$status" "$post" > task-result.txt
sync -f task-result.txt
if [ "$post" -ne 0 ]; then exit 125; fi
exit "$status"
