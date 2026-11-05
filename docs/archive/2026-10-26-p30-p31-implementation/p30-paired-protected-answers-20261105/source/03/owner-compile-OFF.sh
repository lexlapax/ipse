#!/bin/bash
set -euo pipefail
umask 077
printf '%s\n' 'OFF: one-owner strict compilation awaits root review.' >&2
exit 78
base=/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-paired-protected-workflow-20261105-03
sdk=/home/lexlapax/projects/lexlapax/ipse/_build/verification/retained-final-runtime-d548-20261105-02/source
out="$base/owner-compile-01"
[ "$#" -eq 0 ]
[ ! -e "$out" ]
mkdir -m 700 "$out"
mkdir -m 700 "$out/home" "$out/tmp"
args=()
for directory in "$sdk"/_build/test/lib/*/ebin; do args+=(-pa "$directory"); done
clean=(env -i PATH=/usr/bin:/bin HOME="$out/home" TMPDIR="$out/tmp" LANG=C.utf8 LC_ALL=C.utf8 ERL_FLAGS='+S 1:1 +A 1' GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0)
primary=
bounded_pid=
bounded_group=
finish() {
  observed=$?
  trap - EXIT
  set +e
  if [ -z "$primary" ]; then primary=$observed; fi
  if [ ! -e "$out/primary.exit" ]; then printf '%s\n' "$primary" > "$out/primary.exit"; fi
  sha256sum --check --status "$base/owner-compile-inputs.sha256" > "$out/input-post.log" 2>&1
  input_post=$?
  "${clean[@]}" /usr/bin/elixir "${args[@]}" "$base/owner-compile-check.exs" post > "$out/sdk-post.log" 2>&1
  sdk_post=$?
  operator=/tmp/ipse-operator-$(id -u)/input.lock
  if [ -f "$operator" ]; then fuser "$operator" > "$out/operator.post" 2> "$out/operator.post.err"; operator_post=$?; else operator_post=1; : > "$out/operator.post"; : > "$out/operator.post.err"; fi
  pgrep -f "[b]eam.smp.*($base|$sdk)|^$sdk/(priv|_build/test/lib/ipse/priv)/ipse-runner|^$base/.*pty " > "$out/process.post" 2> "$out/process.post.err"
  process_post=$?
  ps -e -o pid=,pgid= | awk -v group="$bounded_group" 'group!="" && $2==group {print $1}' > "$out/group.post"
  printf 'primary=%s\ninputs=%s\nsdk=%s\noperator=%s\nprocess=%s\napp_started=false\nactor_released=false\nretained_access=false\nautomatic_retry=false\n' "$primary" "$input_post" "$sdk_post" "$operator_post" "$process_post" > "$out/status.txt"
  final=$primary
  if [ "$final" -eq 0 ]; then
    if [ "$input_post" -ne 0 ] || [ "$sdk_post" -ne 0 ] || [ "$operator_post" -ne 1 ] || [ "$process_post" -ne 1 ] || [ -s "$out/operator.post" ] || [ -s "$out/operator.post.err" ] || [ -s "$out/process.post" ] || [ -s "$out/process.post.err" ] || [ -s "$out/group.post" ]; then final=1; fi
  fi
  date -u +%Y-%m-%dT%H:%M:%SZ > "$out/finish-utc.txt"
  exit "$final"
}
interrupted() {
  trap - INT TERM
  set +e
  if [ -z "$primary" ] || [ "$primary" -eq 0 ]; then primary=130; fi
  if [ -n "$bounded_pid" ]; then
    if [ "$bounded_group" = "$bounded_pid" ]; then kill -TERM -- -"$bounded_group" 2>/dev/null; else kill -TERM "$bounded_pid" 2>/dev/null; fi
    sleep 10
    if [ "$bounded_group" = "$bounded_pid" ]; then kill -KILL -- -"$bounded_group" 2>/dev/null; fi
    wait "$bounded_pid" 2>/dev/null
  fi
  exit "$primary"
}
trap finish EXIT
trap interrupted INT TERM
printf '%s\n' "$$" > "$out/launcher.pid"
date -u +%Y-%m-%dT%H:%M:%SZ > "$out/launch-requested-utc.txt"
{
  awk '/^(MemAvailable|SwapFree):/ {print}' /proc/meminfo
  df -Pk "$base"
  df -Pi "$base"
  for path in /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.max; do
    if [ -r "$path" ]; then printf '%s=' "$path"; cat "$path"; else printf '%s=unavailable\n' "$path"; fi
  done
} > "$out/resources.txt"
awk '/MemAvailable:/ {exit !($2 >= 3145728)}' /proc/meminfo
[ "$(df -Pk "$base" | awk 'NR==2 {print $4}')" -ge 524288 ]
operator=/tmp/ipse-operator-$(id -u)/input.lock
if [ -f "$operator" ]; then
  if fuser "$operator" > "$out/operator.pre" 2> "$out/operator.pre.err"; then exit 75; else [ "$?" -eq 1 ]; fi
  [ ! -s "$out/operator.pre" ] && [ ! -s "$out/operator.pre.err" ]
fi
sha256sum --check --status "$base/owner-compile-inputs.sha256"
(set -C; printf 'one fixture-owner compile plus unchanged-six/artifact qualification; no actor\n' > "$out/build.claim")
sync -f "$out/build.claim"
cd "$sdk"
setsid /usr/bin/timeout --signal=TERM --kill-after=10s 60s "${clean[@]}" /usr/bin/elixir "${args[@]}" "$base/owner-compile-check.exs" qualify > "$out/build-private.log" 2>&1 &
bounded_pid=$!
printf '%s\n' "$bounded_pid" > "$out/bounded.pid"
for attempt in 1 2 3 4 5; do
  bounded_group=$(ps -o pgid= -p "$bounded_pid" | tr -d '[:space:]')
  [ "$bounded_group" = "$bounded_pid" ] && break
  sleep .1
done
printf '%s\n' "$bounded_group" > "$out/bounded.pgid"
if [ "$bounded_group" != "$bounded_pid" ]; then primary=125; kill -TERM "$bounded_pid" 2>/dev/null; wait "$bounded_pid" || true; exit "$primary"; fi
if wait "$bounded_pid"; then primary=0; else primary=$?; fi
printf '%s\n' "$primary" > "$out/primary.exit"
exit "$primary"
