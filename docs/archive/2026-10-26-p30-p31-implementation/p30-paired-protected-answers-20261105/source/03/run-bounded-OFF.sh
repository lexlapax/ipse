#!/bin/bash
set -uo pipefail
umask 077
printf '%s\n' 'OFF: bounded paired workflow has no actor release.' >&2
exit 78
base=/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-paired-protected-workflow-20261105-03
sdk=/home/lexlapax/projects/lexlapax/ipse/_build/verification/retained-final-runtime-d548-20261105-02/source
storage=/dev/shm/ipse-p30-paired-protected-20261105-03
[ "$#" -eq 2 ] || exit 2
descriptor=$1
digest=$2
mkdir -p "$base/evidence"
posts() {
  primary=$?
  args=()
  for directory in "$sdk"/_build/test/lib/*/ebin; do args+=(-pa "$directory"); done
  args+=(-pa "$base/helper-ebin")
  env -i PATH=/usr/bin:/bin LANG=C.utf8 LC_ALL=C.utf8 HOME="$base/evidence/post-home" ERL_FLAGS='+S 1:1 +A 1' /usr/bin/elixir "${args[@]}" "$base/guard.exs" post "$descriptor" "$digest" > "$base/evidence/post.log" 2>&1
  post=$?
  printf '%s\n' "$post" > "$base/evidence/post.exit"
  pgrep -f "[b]eam.smp.*($base|$storage|$sdk)|^$sdk/(priv|_build/test/lib/ipse/priv)/ipse-runner|^${sdk%/source}/clock-runtime/pty " > "$base/evidence/process.post" 2> "$base/evidence/process.post.err"
  process=$?
  if [ -f "$base/evidence/bounded-group.pid" ]; then
    owned_group=$(cat "$base/evidence/bounded-group.pid")
    ps -eo pid=,pgid= | awk -v owned="$owned_group" '$2 == owned {print $1}' > "$base/evidence/group.post"
  else : > "$base/evidence/group.post"; fi
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
