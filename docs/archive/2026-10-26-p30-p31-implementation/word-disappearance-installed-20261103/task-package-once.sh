#!/bin/bash
set -euo pipefail
set -C
umask 077
snapshot=/dev/shm/ipse-word-disappear-e0-20261103-01
cd "$snapshot"
for dir in "$snapshot" "$snapshot/task-home" "$snapshot/task-tmp" "$snapshot/task-hex" "$snapshot/task-mix" "$snapshot/task-cargo"; do
  if [ ! -d "$dir" ] || [ -L "$dir" ] || [ "$(stat -c '%u:%a' "$dir")" != "$(id -u):700" ]; then exit 1; fi
done
for name in task-package-claim.txt task-package.log task-package-result.txt task-package-postcheck.log; do
  if [ -e "$name" ] || [ -L "$name" ]; then exit 1; fi
done
printf '%s  %s\n' 0624b6939d400df29a68d8b208803f26726c3478b71ca7be2225e101732b08ad test/support/documents_setup.exs a5eafcfdd8ca5ed4d35456ef642471dc1a252ad6699aba7658c3f046236947bd dev/verification/documents_setup_installed.exs c6be0ff68446834973ed443028e318f86782ee9f6061b9fd911da419184f86c0 mix.lock 0544b905357f85c4a47c939b6de03f202d10ed2789bb2dde4659d60ed5b2c9b3 native/ipse-pdf/Cargo.lock | sha256sum --quiet -c
printf '%s  %s\n' a722713dec9ed270e1c1f7b05e6d232e4037fb82eba509111e2cc67c940167c2 task-source.sha256 | sha256sum --quiet -c
sha256sum --quiet -c task-source.sha256
if [ "$(readlink docs/archive/2026-10-26-p30-p31-implementation/native-shell-unknown-cleanup/shell-source/docs)" != '../../../..' ]; then exit 1; fi
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS MIX_BUILD_PATH MIX_DEPS_PATH MIX_ARCHIVES LD_PRELOAD LD_LIBRARY_PATH RUSTFLAGS RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER CARGO_ENCODED_RUSTFLAGS CARGO_BUILD_TARGET CARGO_TARGET_DIR
for var in $(compgen -A variable IPSE_); do unset "$var"; done
export MIX_ENV=prod HEX_OFFLINE=true CARGO_NET_OFFLINE=true ERL_FLAGS='+S 2:2 +A 2'
export IPSE_BUILD_COMMIT=e0daa8119c5da949c886f1c36715eaace04e0455 IPSE_BUILD_PDF=1 IPSE_HOME="$snapshot/task-home"
export TMPDIR="$snapshot/task-tmp" MIX_HOME="$snapshot/task-mix" HEX_HOME="$snapshot/task-hex" CARGO_HOME="$snapshot/task-cargo"
printf '%s\n' 'one isolated default PDF-enabled offline package build' > task-package-claim.txt
sync -f task-package-claim.txt
status=0
./dev/package.sh > task-package.log 2>&1 || status=$?
post=0
printf '%s  %s\n' a722713dec9ed270e1c1f7b05e6d232e4037fb82eba509111e2cc67c940167c2 task-source.sha256 | sha256sum --quiet -c > task-package-postcheck.log 2>&1 || post=$?
sha256sum --quiet -c task-source.sha256 >> task-package-postcheck.log 2>&1 || post=$?
if [ "$(readlink docs/archive/2026-10-26-p30-p31-implementation/native-shell-unknown-cleanup/shell-source/docs)" != '../../../..' ]; then post=1; fi
printf 'package_exit=%s\nsource_postcheck_exit=%s\n' "$status" "$post" > task-package-result.txt
sync -f task-package-result.txt
if [ "$post" -ne 0 ]; then exit 125; fi
exit "$status"
