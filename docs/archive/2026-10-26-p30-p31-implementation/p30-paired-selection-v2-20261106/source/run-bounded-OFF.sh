#!/bin/bash
set -uo pipefail
umask 077
printf '%s\n' 'OFF: bounded packaged paired actor requires root release.' >&2
exit 78
base=/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-paired-v2-current-20261106-01
source "$base/runtime-bindings.sh"
pkg=${P30_PACKAGE:?fresh reviewed package required}
storage=/run/user/1000/ipse-p30-paired-v2-current-20261106-01
[ "$#" -eq 2 ] || exit 2
descriptor=$1
digest=$2
mkdir -p "$base/evidence"
posts() {
  primary=$?
  trap - EXIT
  env -i PATH=/usr/bin:/bin HOME="$base/evidence/post-home" RELEASE_TMP="$base/evidence/post-tmp" LANG=C.utf8 LC_ALL=C.utf8 IPSE_PAIRED_PACKAGE="$pkg" IPSE_PAIRED_PTY="${P30_PTY:?reviewed PTY required}" IPSE_PAIRED_ARCHIVE="${P30_ARCHIVE:?fresh archive required}" IPSE_PAIRED_EX_UNIT="${P30_EX_UNIT:?matching ExUnit required}" ERL_FLAGS='+S 1:1 +A 1' "$pkg/bin/ipse" eval "System.argv([\"$descriptor\", \"$digest\"]); Code.eval_file(\"$base/guard.exs\")" > "$base/evidence/post.log" 2>&1
  post=$?
  pgrep -f "[b]eam.smp.*($base|$storage|$pkg)|^$pkg/lib/ipse-0.1.0/priv/ipse-runner|^${P30_PTY:?reviewed PTY required} " > "$base/evidence/process.post" 2> "$base/evidence/process.post.err"; process=$?
  if [ -f "$base/evidence/bounded-group.pid" ]; then owned=$(cat "$base/evidence/bounded-group.pid"); ps -eo pid=,pgid= | awk -v owned="$owned" '$2 == owned {print $1}' > "$base/evidence/group.post"; else : > "$base/evidence/group.post"; fi
  operator=/tmp/ipse-operator-$(id -u)/input.lock
  if [ -f "$operator" ]; then fuser "$operator" > "$base/evidence/operator.post" 2> "$base/evidence/operator.post.err"; input=$?; else input=1; : > "$base/evidence/operator.post"; : > "$base/evidence/operator.post.err"; fi
  printf 'primary=%s\npost=%s\nprocess=%s\ninput=%s\n' "$primary" "$post" "$process" "$input" > "$base/evidence/bounded-status.txt"
  if [ "$primary" -eq 0 ] && [ "$post" -eq 0 ] && [ "$process" -eq 1 ] && [ "$input" -eq 1 ] && [ ! -s "$base/evidence/process.post" ] && [ ! -s "$base/evidence/process.post.err" ] && [ ! -s "$base/evidence/group.post" ] && [ ! -s "$base/evidence/operator.post" ] && [ ! -s "$base/evidence/operator.post.err" ]; then exit 0; else exit 1; fi
}
trap posts EXIT
printf '%s\n' "$$" > "$base/evidence/outer-launcher.pid"
date -u +%Y-%m-%dT%H:%M:%SZ > "$base/evidence/outer-launch-requested-utc.txt"
setsid /usr/bin/timeout --signal=TERM --kill-after=10s 450s /bin/bash "$base/run-reviewed.sh" "$descriptor" "$digest" > "$base/evidence/outer-private.log" 2>&1 &
group=$!
printf '%s\n' "$group" > "$base/evidence/bounded-group.pid"
wait "$group"
exit $?
