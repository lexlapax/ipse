#!/usr/bin/env bash
set -euo pipefail
umask 077
root=/home/lexlapax/projects/lexlapax/ipse
run="$root/_build/verification/ipse-source-port-close-boundary-20261104-03"
runtime="$root/_build/verification/ipse-p30-pending-current-use-20261104-01/execution-01"
cd "$root"
sha256sum --check --status "$run/inputs.sha256"
sha256sum --check --status "$runtime/runtime.sha256"
mkdir -m 700 "$run/private-home"
(set -C; printf 'only unobserved predefined indices10..64; earlier9 immediate observations unavailable/not repeated; no App/Input/TTY/consent/model\n' > "$run/actual.claim")
paths=()
for directory in "$runtime"/lib/*/ebin; do paths+=(-pa "$directory"); done
set +e
env -i PATH=/usr/bin:/bin LANG=C.utf8 LC_ALL=C.utf8 HOME="$run/private-home" ERL_FLAGS='+S 1:1 +A 1' elixir "${paths[@]}" "$run/observe.exs" > "$run/observations.log" 2>&1
test_status=$?
set -e
input_status=0
sha256sum --check --status "$run/inputs.sha256" || input_status=$?
runtime_status=0
sha256sum --check --status "$runtime/runtime.sha256" || runtime_status=$?
printf 'component_exit=%s\ninput_post=%s\nruntime_post=%s\n' "$test_status" "$input_status" "$runtime_status" > "$run/status.txt"
cat "$run/status.txt"
test "$test_status" -eq 0 && test "$input_status" -eq 0 && test "$runtime_status" -eq 0
