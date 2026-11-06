#!/bin/bash
set -euo pipefail
base=/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-paired-v2-current-20261106-01
source "$base/runtime-bindings.sh"
pkg=${P30_PACKAGE:?fresh reviewed package required}
pty=${P30_PTY:?reviewed PTY helper required}
[ "$#" -eq 1 ]
root=$1
for phase in setup read baseline selection candidate; do
  printf 'phase=%s requested_utc=%s\n' "$phase" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$base/evidence/phase-dispatch.txt"
  expression="System.argv([\"$root\", \"$phase\"]); Code.eval_file(\"$base/entry.exs\")"
  if "$pty" --assertion "$pkg/bin/ipse" eval "$expression" "$root" "save_managed_approval_cross_session_paired_$phase" > "$base/evidence/$phase-private.log" 2>&1; then code=0; else code=$?; fi
  printf '%s\n' "$code" > "$base/evidence/$phase.exit"
  [ "$code" -eq 0 ] || exit "$code"
done
