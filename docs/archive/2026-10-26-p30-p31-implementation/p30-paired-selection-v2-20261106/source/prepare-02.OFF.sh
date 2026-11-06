#!/bin/bash
set -euo pipefail
umask 077
printf '%s\n' 'OFF: packaged fixture preparation requires root review.' >&2
exit 78
base=/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-paired-v2-current-20261106-01
source "$base/runtime-bindings.sh"
pkg=${P30_PACKAGE:?fresh reviewed package required}
descriptor="$base/descriptor.OFF.json"
sha256sum --check --status "$base/inputs.sha256"
sha256sum --check --status "$base/ex-unit-inputs.sha256"
cmp "$base/ex-unit-paths.txt" <(find "${P30_EX_UNIT:?matching ExUnit required}" -printf '%y %P\n' | sort)
[ ! -e "$base/preparation-current-02" ]
mkdir -m 700 "$base/preparation-current-02"
out="$base/preparation-current-02"
mkdir -m 700 "$out/home" "$out/tmp"
clean=(env -i PATH=/usr/bin:/bin HOME="$out/home" TMPDIR="$out/tmp" RELEASE_TMP="$out/tmp" LANG=C.utf8 LC_ALL=C.utf8 IPSE_PAIRED_PACKAGE="$pkg" IPSE_PAIRED_PTY="${P30_PTY:?reviewed PTY required}" IPSE_PAIRED_ARCHIVE="${P30_ARCHIVE:?fresh archive required}" IPSE_PAIRED_EX_UNIT="${P30_EX_UNIT:?matching ExUnit required}" ERL_FLAGS='+S 1:1 +A 1')
finish() {
  primary=$?
  trap - EXIT
  set +e
  sha256sum --check --status "$base/inputs.sha256" > "$out/inputs.post.log" 2>&1; inputs=$?
  tar -dzf "${P30_ARCHIVE:?fresh archive required}" -C "$pkg" > "$out/archive.post.log" 2>&1; archive=$?
  sha256sum --check --status "$base/ex-unit-inputs.sha256" > "$out/ex-unit.post.log" 2>&1; exunit=$?
  find "${P30_EX_UNIT:?matching ExUnit required}" -printf '%y %P\n' | sort > "$out/ex-unit-paths.post"
  cmp "$base/ex-unit-paths.txt" "$out/ex-unit-paths.post"; exunit_paths=$?
  if [ -f "$base/prepared-current-02/descriptor.review-false.json" ]; then
    compiled="$base/prepared-current-02/descriptor.review-false.json"
    digest=$(sha256sum "$compiled" | cut -d' ' -f1)
    "${clean[@]}" "$pkg/bin/ipse" eval "System.argv([\"$compiled\", \"$digest\"]); Code.eval_file(\"$base/guard.exs\")" > "$out/guard.post.log" 2>&1; post=$?
  else post=78; fi
  pgrep -f "[b]eam.smp.*($base|$pkg)|^$pkg/lib/ipse-0.1.0/priv/ipse-runner" > "$out/process.post" 2> "$out/process.post.err"; process=$?
  if [ -n "${bounded_group:-}" ]; then ps -eo pid=,pgid= | awk -v owned="$bounded_group" '$2 == owned {print $1}' > "$out/group.post"; else : > "$out/group.post"; fi
  operator=/tmp/ipse-operator-$(id -u)/input.lock
  if [ -f "$operator" ]; then fuser "$operator" > "$out/operator.post" 2> "$out/operator.post.err"; input=$?; else input=1; : > "$out/operator.post"; : > "$out/operator.post.err"; fi
  printf 'primary=%s\ninputs=%s\narchive=%s\nexunit=%s\nexunit_paths=%s\nprepared_post=%s\nprocess=%s\ninput=%s\n' "$primary" "$inputs" "$archive" "$exunit" "$exunit_paths" "$post" "$process" "$input" > "$out/status.txt"
  [ "$primary" -eq 0 ] && [ "$inputs" -eq 0 ] && [ "$archive" -eq 0 ] && [ "$exunit" -eq 0 ] && [ "$exunit_paths" -eq 0 ] && [ "$post" -eq 0 ] && [ "$process" -eq 1 ] && [ "$input" -eq 1 ] && [ ! -s "$out/group.post" ] && [ ! -s "$out/process.post" ] && [ ! -s "$out/process.post.err" ] && [ ! -s "$out/operator.post" ] && [ ! -s "$out/operator.post.err" ] && exit 0
  exit 1
}
trap finish EXIT
awk '/MemAvailable:/ {exit !($2 >= 3145728)}' /proc/meminfo
setsid /usr/bin/timeout --signal=TERM --kill-after=10s 35s "${clean[@]}" "$pkg/bin/ipse" eval "Code.prepend_path(\"${P30_EX_UNIT:?matching ExUnit required}/ebin\"); Code.require_file(\"$base/prepare.exs\"); Ipse.Test.PackagedPairedPreparation.run(\"$descriptor\")" > "$out/private.log" 2>&1 &
bounded_group=$!
printf '%s\n' "$bounded_group" > "$out/group.pid"
wait "$bounded_group"
