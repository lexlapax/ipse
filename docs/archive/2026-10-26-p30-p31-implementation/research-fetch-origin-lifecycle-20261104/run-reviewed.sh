#!/usr/bin/env bash
set -euo pipefail
umask 077
base=/home/lexlapax/projects/lexlapax/ipse/_build/verification/research-origin-actual-sdk-18e3-20261104-01
sdk=/home/lexlapax/projects/lexlapax/ipse/_build/verification/consent-knowledge-research-sdk-18e3-20261104-02
[ "$#" -eq 2 ]
descriptor=$1
digest=$2
printf '%s  %s\n' "$digest" "$descriptor" | sha256sum --check --status
sha256sum --check --status "$base/packet.sha256"
phase=claim
trap 'code=$?; printf "phase=%s\nexit=%s\nautomatic_retry=false\n" "$phase" "$code" > "$base/evidence/pipeline-status.txt"' EXIT
(set -C; printf 'one fresh ordinary Research lifecycle; no replay\n' > "$base/evidence/actor.claim")
sync -f "$base/evidence/actor.claim"
storage=/dev/shm/ipse-research-origin-sdk18e3-20261104-01
[ ! -e "$storage" ]
mkdir -m 700 "$storage"
mkdir -m 700 "$storage/actor" "$storage/tmp" "$storage/env-home"
dd if=/dev/zero of="$storage/own-quota-probe" bs=1048576 count=32 conv=fsync status=none
rm -- "$storage/own-quota-probe"
operator=/tmp/ipse-operator-$(id -u)/input.lock
if test -f "$operator"; then
  if fuser "$operator" > "$base/evidence/operator.pre" 2> "$base/evidence/operator.pre.err"; then exit 75; else [ "$?" -eq 1 ]; fi
  [ ! -s "$base/evidence/operator.pre.err" ]
fi
paths=()
for directory in "$sdk/source"/_build/test/lib/*/ebin; do paths+=(-pa "$directory"); done
paths+=(-pa "$base/helper-ebin")
clean=(env -i LC_ALL=C.utf8 LANG=C.utf8 PATH=/usr/bin:/bin HOME="$storage/env-home" IPSE_HOME="$storage/env-home/.ipse" TMPDIR="$storage/tmp" ERL_FLAGS='+S 1:1 +A 1' GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0)
cd "$sdk/source"
phase=pre
"${clean[@]}" /usr/bin/elixir "${paths[@]}" "$base/guard.exs" pre "$descriptor" "$digest" > "$base/evidence/guard-pre.log" 2>&1
phase=journey
if "${clean[@]}" /usr/bin/timeout --signal=TERM --kill-after=5s 180s /usr/bin/elixir "${paths[@]}" "$base/entry.exs" "$descriptor" "$digest" > "$base/evidence/actor-private.log" 2>&1; then actor_exit=0; else actor_exit=$?; fi
printf '%s\n' "$actor_exit" > "$base/evidence/actor.exit"
phase=post
if "${clean[@]}" /usr/bin/elixir "${paths[@]}" "$base/guard.exs" post "$descriptor" "$digest" > "$base/evidence/guard-post.log" 2>&1; then post_exit=0; else post_exit=$?; fi
printf '%s\n' "$post_exit" > "$base/evidence/post.exit"
for attempt in 1 2 3 4 5; do
  if pgrep -f "beam.smp.*($base|$storage|$sdk)|^$sdk/source/(priv|_build/test/lib/ipse/priv)/ipse-runner" > "$base/evidence/process.post"; then sleep 1; else [ "$?" -eq 1 ]; break; fi
done
if test -f "$operator"; then
  if fuser "$operator" > "$base/evidence/operator.post" 2> "$base/evidence/operator.post.err"; then operator_exit=75; else [ "$?" -eq 1 ]; operator_exit=0; fi
  [ ! -s "$base/evidence/operator.post.err" ] || operator_exit=75
else operator_exit=0; fi
printf '%s\n' "$operator_exit" > "$base/evidence/operator.exit"
printf 'actor_exit=%s\npost_exit=%s\noperator_exit=%s\n' "$actor_exit" "$post_exit" "$operator_exit"
[ ! -s "$base/evidence/process.post" ]
[ "$actor_exit" -eq 0 ] && [ "$post_exit" -eq 0 ] && [ "$operator_exit" -eq 0 ]
phase=complete
