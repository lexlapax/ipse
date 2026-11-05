#!/usr/bin/env bash
set -euo pipefail
umask 077
printf '%s\n' 'OFF: known-closed03 assessment-only continuation needs root release.' >&2
exit 78
base=/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-selection-assessment-phased-20261105-03/assessment-only-01
helper=/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-selection-assessment-phased-20261105-03
sdk=/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-selection-assessment-phased-20261105-02/sdk/source
storage=/dev/shm/ipse-selection-assessment-phased-20261105-03
[ "$#" -eq 2 ]
descriptor=$1
digest=$2
printf '%s  %s\n' "$digest" "$descriptor" | sha256sum --check --status
sha256sum --check --status "$base/inputs.sha256"
phase=pre
trap 'code=$?; printf "phase=%s\nexit=%s\nautomatic_retry=false\n" "$phase" "$code" > "$base/evidence/pipeline-status.txt"' EXIT
[ -d "$storage/actor" ]
[ "$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)" -ge 2097152 ]
{
 date -u +%Y-%m-%dT%H:%M:%SZ
 awk '/^MemAvailable:|^SwapFree:/ {print}' /proc/meminfo
 df -Pk /dev/shm /tmp "$sdk"
 df -Pi /dev/shm /tmp "$sdk"
 for file in /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.max; do
  if [ -r "$file" ]; then printf '%s=' "$file"; cat "$file"; else printf '%s=unreadable\n' "$file"; fi
 done
} > "$base/evidence/capacity-pre.txt"
[ "$(df -Pk /dev/shm | awk 'NR==2 {print $4}')" -ge 32768 ]
operator=/tmp/ipse-operator-$(id -u)/input.lock
if [ -f "$operator" ]; then
 if fuser "$operator" > "$base/evidence/operator.pre" 2> "$base/evidence/operator.pre.err"; then exit 75; else [ "$?" -eq 1 ]; fi
 [ ! -s "$base/evidence/operator.pre.err" ]
fi
args=()
for directory in "$sdk"/_build/test/lib/*/ebin; do args+=(-pa "$directory"); done
args+=(-pa "$helper/helper-ebin")
clean=(env -i LC_ALL=C.utf8 LANG=C.utf8 PATH=/usr/bin:/bin HOME="$storage/env-home" IPSE_HOME="$storage/actor/home" TMPDIR="$storage/tmp" ERL_FLAGS='+S 1:1 +A 1' GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0)
cd "$sdk"
"${clean[@]}" /usr/bin/elixir "${args[@]}" "$base/guard.exs" pre "$descriptor" "$digest" > "$base/evidence/guard-pre.log" 2>&1
phase=claim
(set -C; printf 'one fresh assessment consumer of known-closed03 cohort; no setup/selection replay\n' > "$base/evidence/actor.claim")
printf '%s\n' "$$" > "$base/evidence/launcher.pid"
date -u +%Y-%m-%dT%H:%M:%SZ > "$base/evidence/launch-requested-utc.txt"
phase=assessment
if "${clean[@]}" /usr/bin/timeout --signal=TERM --kill-after=5s 180s "$helper/pty" --assertion /usr/bin/elixir "${args[@]}" "$base/entry.exs" "$storage/actor" save_managed_approval_cross_session_selection_assessment > "$base/evidence/actor-private.log" 2>&1; then actor_exit=0; else actor_exit=$?; fi
printf '%s\n' "$actor_exit" > "$base/evidence/actor.exit"
phase=post
if "${clean[@]}" /usr/bin/elixir "${args[@]}" "$base/guard.exs" post "$descriptor" "$digest" > "$base/evidence/guard-post.log" 2>&1; then post_exit=0; else post_exit=$?; fi
printf '%s\n' "$post_exit" > "$base/evidence/post.exit"
for attempt in 1 2 3 4 5; do
 if pgrep -f "beam.smp.*($helper|$storage|$sdk)|^$sdk/(priv|_build/test/lib/ipse/priv)/ipse-runner|^$helper/pty " > "$base/evidence/process.post"; then sleep 1; else [ "$?" -eq 1 ]; break; fi
 done
operator_exit=0
if [ -f "$operator" ]; then
 if fuser "$operator" > "$base/evidence/operator.post" 2> "$base/evidence/operator.post.err"; then operator_exit=75; else [ "$?" -eq 1 ]; fi
 [ ! -s "$base/evidence/operator.post.err" ] || operator_exit=75
fi
printf '%s\n' "$operator_exit" > "$base/evidence/operator.exit"
printf 'actor_exit=%s\npost_exit=%s\noperator_exit=%s\n' "$actor_exit" "$post_exit" "$operator_exit"
[ ! -s "$base/evidence/process.post" ]
if [ "$actor_exit" -eq 0 ] && [ "$post_exit" -eq 0 ] && [ "$operator_exit" -eq 0 ]; then phase=complete; else phase=failed; exit 1; fi
