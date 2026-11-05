#!/bin/bash
set -euo pipefail
umask 077
printf '%s\n' 'OFF: paired synthetic workflow requires closed build inputs and root release.' >&2
exit 78
base=/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-paired-protected-workflow-20261105-03
sdk=/home/lexlapax/projects/lexlapax/ipse/_build/verification/retained-final-runtime-d548-20261105-02/source
storage=/dev/shm/ipse-p30-paired-protected-20261105-03
[ "$#" -eq 2 ]
descriptor=$1
digest=$2
sha256sum --check --status "$base/actor-inputs.sha256"
args=()
for directory in "$sdk"/_build/test/lib/*/ebin; do args+=(-pa "$directory"); done
args+=(-pa "$base/helper-ebin")
env -i PATH=/usr/bin:/bin HOME="$base/evidence/pre-home" LANG=C.utf8 LC_ALL=C.utf8 ERL_FLAGS='+S 1:1 +A 1' /usr/bin/elixir "${args[@]}" "$base/guard.exs" pre "$descriptor" "$digest" > "$base/evidence/pre.log" 2>&1
awk '/MemAvailable:/ {exit !($2 >= 3145728)}' /proc/meminfo
[ "$(df -Pk /dev/shm | awk 'NR==2 {print $4}')" -ge 524288 ]
operator=/tmp/ipse-operator-$(id -u)/input.lock
if [ -f "$operator" ]; then
  if fuser "$operator" > "$base/evidence/operator.pre" 2> "$base/evidence/operator.pre.err"; then exit 75; else [ "$?" -eq 1 ]; fi
  [ ! -s "$base/evidence/operator.pre" ] && [ ! -s "$base/evidence/operator.pre.err" ]
fi
[ ! -e "$storage" ]
mkdir -m 700 "$storage"
mkdir -m 700 "$storage/actor" "$storage/tmp" "$storage/env-home"
dd if=/dev/zero of="$storage/quota-probe" bs=1048576 count=32 conv=fsync status=none
rm "$storage/quota-probe"
(set -C; printf 'one fresh paired synthetic cohort; unknown stops; no replay\n' > "$base/evidence/actor.claim")
printf '%s\n' "$$" > "$base/evidence/launcher.pid"
date -u +%Y-%m-%dT%H:%M:%SZ > "$base/evidence/launch-requested-utc.txt"
clean=(env -i PATH=/usr/bin:/bin HOME="$storage/env-home" TMPDIR="$storage/tmp" LANG=C.utf8 LC_ALL=C.utf8 ERL_FLAGS='+S 1:1 +A 1' IPSE_PAIRED_DESCRIPTOR="$descriptor" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0)
cd "$sdk"
if "${clean[@]}" /bin/bash "$base/actor-phases.sh" "$storage/actor" > "$base/evidence/actor-private.log" 2>&1; then code=0; else code=$?; fi
printf '%s\n' "$code" > "$base/evidence/actor.exit"
exit "$code"
