#!/bin/bash
set -euo pipefail
set -C
umask 077
snapshot=/dev/shm/ipse-word-disappear-e0-20261103-01
output=/dev/shm/ipse-word-installed-e0-20261103-01
archive="$snapshot/dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz"
cd "$snapshot"
for dir in "$snapshot" "$snapshot/task-home" "$snapshot/task-tmp"; do
  if [ ! -d "$dir" ] || [ -L "$dir" ] || [ "$(stat -c '%u:%a' "$dir")" != "$(id -u):700" ]; then exit 1; fi
done
for name in "$output" task-installed-claim.txt task-installed.log task-installed-result.txt task-installed-postcheck.log; do
  if [ -e "$name" ] || [ -L "$name" ]; then exit 1; fi
done
printf '%s  %s\n' 678b446a8351a9eed9a3ac6ce738064ce9981767842d7cf27dfef9fa60d0667d "$archive" 0624b6939d400df29a68d8b208803f26726c3478b71ca7be2225e101732b08ad test/support/documents_setup.exs a5eafcfdd8ca5ed4d35456ef642471dc1a252ad6699aba7658c3f046236947bd dev/verification/documents_setup_installed.exs a722713dec9ed270e1c1f7b05e6d232e4037fb82eba509111e2cc67c940167c2 task-source.sha256 | sha256sum --quiet -c
sha256sum --quiet -c task-source.sha256
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS MIX_BUILD_PATH MIX_DEPS_PATH MIX_ARCHIVES LD_PRELOAD LD_LIBRARY_PATH RELEASE_NODE RELEASE_COOKIE RELEASE_DISTRIBUTION RELEASE_ROOT RELEASE_BOOT_SCRIPT
for var in $(compgen -A variable IPSE_); do unset "$var"; done
export TMPDIR="$snapshot/task-tmp" IPSE_HOME="$snapshot/task-home" ERL_FLAGS='+S 2:2 +A 2'
printf '%s\n' 'one synthetic installed document verification; do not retry uncertain work' > task-installed-claim.txt
sync -f task-installed-claim.txt
status=0
elixir dev/verification/documents_setup_installed.exs "$archive" "$output" > task-installed.log 2>&1 || status=$?
post=0
printf '%s  %s\n' 678b446a8351a9eed9a3ac6ce738064ce9981767842d7cf27dfef9fa60d0667d "$archive" 0624b6939d400df29a68d8b208803f26726c3478b71ca7be2225e101732b08ad test/support/documents_setup.exs a5eafcfdd8ca5ed4d35456ef642471dc1a252ad6699aba7658c3f046236947bd dev/verification/documents_setup_installed.exs a722713dec9ed270e1c1f7b05e6d232e4037fb82eba509111e2cc67c940167c2 task-source.sha256 | sha256sum --quiet -c > task-installed-postcheck.log 2>&1 || post=$?
sha256sum --quiet -c task-source.sha256 >> task-installed-postcheck.log 2>&1 || post=$?
printf 'verifier_exit=%s\nsource_postcheck_exit=%s\n' "$status" "$post" > task-installed-result.txt
sync -f task-installed-result.txt
if [ "$post" -ne 0 ]; then exit 125; fi
exit "$status"
