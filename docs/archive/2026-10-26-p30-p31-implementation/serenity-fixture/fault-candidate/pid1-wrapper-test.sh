#!/bin/sh
# No-device Docker test: PID 1 stays alive while its exact direct child dies.
set -u
/tmp/ipse-owner-supervisor-experiment /work/test > /work/test/supervisor.out 2> /work/test/supervisor.err &
pid=$!
i=0
while [ ! -s /work/test/supervisor.out ]; do
 if [ "$i" -ge 50 ]; then printf 'SUPERVISOR_NOT_ARMED\n'; exit 2; fi
 sleep 0.1
 i=$((i+1))
done
kill -9 "$pid" || exit 3
wait "$pid" 2>/dev/null || :
i=0
while ! grep -q '^stop-sent unknown$' /work/test/guardian.receipt 2>/dev/null; do
 if [ "$i" -ge 50 ]; then printf 'GUARDIAN_OUTCOME_UNKNOWN\n'; exit 4; fi
 sleep 0.1
 i=$((i+1))
done
printf 'PID1_WRAPPER_GUARDIAN_SIGNALLED_UNKNOWN\n'
