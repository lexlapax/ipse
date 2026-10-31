# Independent review of managed audit repairs

2026-10-29. This scoped review covers the frozen
[managed audit repair cohort](managed-audit-repairs.md), not final P31C0.
The reviewer verified all 30 manifest entries, 209 runtime BEAM hashes and the
helper hash, and checked that the inspected frozen files match. No broad tests
were rerun.

The reviewed code refuses the identified managed State and service actions,
suppresses tainted pending questions from subscriber notifications, `Session.info`
and answer continuation, and rejects the reproduced stale v3-root A/current-source
B publication case. Ordinary capture and ordinary pending-question recovery
have the scoped controls recorded in the repair receipt.

The review found a remaining publication deadline gap: ordinary capture checks
consent before storage, but the final native root switch is not bound to that
consent deadline. A delayed staging operation can therefore cross expiry;
generation CAS alone does not fence time. An actual delayed-publication control
and native final-switch deadline are required.

The extension-question recovery helper checked matching parent IDs without
requiring the full parent objects to match. A reachable honest-journal bypass
was not established, but the stronger stated binding needs implementation and
negative tests. The stale-root A/B test did not directly assert the absence of
the candidate intent even though the record described it; add that assertion or
narrow the claim. The actual interrupted-question controls exercised native
questions, while extension questions had pure classification only. The literal-v4
A/B variant remains untested. These gaps and their repairs are not established
by the initial sixteen controls.
