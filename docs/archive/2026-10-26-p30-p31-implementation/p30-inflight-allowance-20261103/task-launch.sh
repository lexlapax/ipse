#!/bin/bash
set -euo pipefail
set -C
umask 077
snapshot=/dev/shm/ipse-p30-concurrent-dcbb-20261103-01
cd "$snapshot"
for dir in "$snapshot" "$snapshot/task-home" "$snapshot/task-tmp"; do
  if [ ! -d "$dir" ] || [ -L "$dir" ] || [ "$(stat -c '%u:%a' "$dir")" != "$(id -u):700" ]; then exit 1; fi
done
for name in task-claim.txt task-one-shot.log task-postcheck.log task-completion.txt; do
  if [ -e "$name" ] || [ -L "$name" ]; then exit 1; fi
done
printf '%s  %s\n' 4ff00ee128a0868f4d40defc2c00f6d8b0ab449e65d767813accd24997685e92 task-inputs.sha256 12272067fe1ee36e155c887cddb4392ae9899c1864a3e1950ea70878752b3b5c task-build.sha256 8385efa2a6f70123cdd4680b1d35e0855d23753ea818ff0d0990738ba2454e48 task-source.sha256 888516357632299b5c93cc34b778b182d8b1b2ce2612bbaaf774ed8ed2925e08 task-deps.sha256 | sha256sum --quiet -c
for manifest in task-inputs.sha256 task-build.sha256 task-source.sha256 task-deps.sha256; do sha256sum --quiet -c "$manifest"; done
unset ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS ERL_AFLAGS ERL_ZFLAGS MIX_BUILD_PATH MIX_DEPS_PATH MIX_HOME MIX_ARCHIVES LD_PRELOAD LD_LIBRARY_PATH
for var in $(compgen -A variable IPSE_); do unset "$var"; done
export MIX_ENV=test HEX_OFFLINE=1 ERL_FLAGS='+S 2:2' TMPDIR="$snapshot/task-tmp" IPSE_HOME="$snapshot/task-home" IPSE_BUILD_COMMIT=dcbb07dd451f1402d28391b716b2b177e35331a7
printf '%s\n' 'one synthetic cross-process allowance attempt; do not replay uncertainty' > task-claim.txt
sync -f task-claim.txt
status=0
mix run --no-compile --no-deps-check --no-start task-entry.exs > task-one-shot.log 2>&1 || status=$?
post=0
for manifest in task-inputs.sha256 task-build.sha256 task-source.sha256 task-deps.sha256; do
  if ! sha256sum --quiet -c "$manifest" >> task-postcheck.log 2>&1; then post=1; fi
done
printf 'test_exit=%s\npostcheck_exit=%s\n' "$status" "$post" > task-completion.txt
sync -f task-completion.txt
if [ "$post" -ne 0 ]; then exit 125; fi
exit "$status"
