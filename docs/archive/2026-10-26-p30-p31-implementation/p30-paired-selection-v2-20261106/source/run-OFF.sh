#!/bin/bash
set -euo pipefail
umask 077
printf '%s\n' 'OFF: one packaged paired actor requires a separate root release.' >&2
exit 78
base=/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-paired-v2-current-20261106-01
source "$base/runtime-bindings.sh"
pkg=${P30_PACKAGE:?fresh reviewed package required}
storage=/run/user/1000/ipse-p30-paired-v2-current-20261106-01
[ "$#" -eq 2 ]
descriptor=$1
digest=$2
mkdir -p "$base/evidence"
sha256sum --check --status "$base/inputs.sha256"
env -i PATH=/usr/bin:/bin HOME="$base/evidence/pre-home" RELEASE_TMP="$base/evidence/pre-tmp" LANG=C.utf8 LC_ALL=C.utf8 IPSE_PAIRED_PACKAGE="$pkg" IPSE_PAIRED_PTY="${P30_PTY:?reviewed PTY required}" IPSE_PAIRED_ARCHIVE="${P30_ARCHIVE:?fresh archive required}" IPSE_PAIRED_EX_UNIT="${P30_EX_UNIT:?matching ExUnit required}" ERL_FLAGS='+S 1:1 +A 1' "$pkg/bin/ipse" eval "System.argv([\"$descriptor\", \"$digest\"]); Code.eval_file(\"$base/guard.exs\")" > "$base/evidence/pre.log" 2>&1
awk '/MemAvailable:/ {exit !($2 >= 3145728)}' /proc/meminfo
[ "$(df -Pk /run/user/1000 | awk 'NR==2 {print $4}')" -ge 524288 ]
[ "$(stat -c '%u %a %F' /run/user/1000)" = "$(id -u) 700 directory" ]
operator=/tmp/ipse-operator-$(id -u)/input.lock
if [ -f "$operator" ]; then
  if fuser "$operator" > "$base/evidence/operator.pre" 2> "$base/evidence/operator.pre.err"; then exit 75; else [ "$?" -eq 1 ]; fi
  [ ! -s "$base/evidence/operator.pre" ] && [ ! -s "$base/evidence/operator.pre.err" ]
fi
[ ! -e "$storage" ]
mkdir -m 700 "$storage"
mkdir -m 700 "$storage/actor" "$storage/tmp" "$storage/env-home"
dd if=/dev/zero of="$storage/quota-probe" bs=1048576 count=32 conv=fsync status=none
[ "$(stat -c '%b' "$storage/quota-probe")" -ge 65536 ]
rm "$storage/quota-probe"
(set -C; printf 'one fresh packaged paired synthetic cohort; unknown stops; no replay\n' > "$base/evidence/actor.claim")
printf '%s\n' "$$" > "$base/evidence/launcher.pid"
date -u +%Y-%m-%dT%H:%M:%SZ > "$base/evidence/launch-requested-utc.txt"
clean=(env -i PATH=/usr/bin:/bin HOME="$storage/env-home" TMPDIR="$storage/tmp" RELEASE_TMP="$storage/tmp" LANG=C.utf8 LC_ALL=C.utf8 IPSE_PAIRED_PACKAGE="$pkg" IPSE_PAIRED_PTY="${P30_PTY:?reviewed PTY required}" IPSE_PAIRED_ARCHIVE="${P30_ARCHIVE:?fresh archive required}" IPSE_PAIRED_EX_UNIT="${P30_EX_UNIT:?matching ExUnit required}" ERL_FLAGS='+S 1:1 +A 1' IPSE_PAIRED_DESCRIPTOR="$descriptor" IPSE_PAIRED_DESCRIPTOR_SHA256="$digest" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0)
if "${clean[@]}" /bin/bash "$base/actor-phases.sh" "$storage/actor" > "$base/evidence/actor-private.log" 2>&1; then code=0; else code=$?; fi
printf '%s\n' "$code" > "$base/evidence/actor.exit"
exit "$code"
