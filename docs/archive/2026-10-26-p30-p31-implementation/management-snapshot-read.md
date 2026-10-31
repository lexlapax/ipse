# Retain an exact management control snapshot

Focused implementation evidence, 2026-10-29. The accepted
[management purpose](management-display-scope.md) permits faithful local target
review when capture is expired or revoked. Existing `with_existing_policy`
requires active capture; separately loading `existing_snapshot` releases the
control lock before a later callback. The [plan](../../plan.md) owns acceptance.
No display, management publication, capture or other runtime gate is enabled.
The [independent review](management-snapshot-read-independent-review.md) accepts
the exact v2 callback within those limits.

`Consent.with_existing_management_snapshot/5` retains the actual native control
lock around a trusted host callback. It checks an existing positive epoch and
the exact management digest of project/epoch/policy, returning only epoch/policy
to that callback. A revoked nil policy and an expired policy are inspectable;
neither becomes a live capture grant. Missing state, stale/substituted pins,
numeric aliases and nested control mutation refuse. The existing-only native
path creates, repairs and reclaims no control state, rechecks retained identities
and native ownership, and confirms release before returning known data.

Callbacks remain trusted host code, with no worker/SDK bridge. They may not run
inference, untrusted code or storage/service effects. Any later native ownership
or display coordination still needs its separate exact owner/target/operator
admission, complete lease set and qualified sink. This API grants no display,
source eligibility, publication or effect permission. Identity, target Collection
and management journal ownership remain distinct requirements. No production
Management caller uses this callback yet.

The common existing-only callback adapter also preserves `{:unknown, reason}`
instead of turning it into a generic read error. This applies to the existing
policy callback too. Known data still requires the final native checks and
confirmed release. An unknown callback bypasses the success-only checks, attempts
normal release and remains uncertain; it cannot become settled success.

## Focused evidence

The [initial manifest](management-snapshot-read/manifest.sha256), SHA-256
`c4e5e67128cde8c71b4d3f968f05fc27f493aa69cea33edc206032bd035be42e`,
pins the first source, corrected test, original invalid fixture, logs, copied
runtime and helper.47096 strict compile passed.47097 stopped all four cases
after their successful setup because the fixture used ExUnit's reserved `file`
context key; no product assertion ran. The corrected `control_file` fixture
passed all four in47098. This was a test defect, not a runtime repair.

The later v2 graph adds the uncertainty-preserving callback clause and fifth
test. Its [separate manifest](management-snapshot-read-v2/manifest.sha256)
with SHA-256 `01ccdeba3b75a58906000ac8836c6f25e3cca6a2d65f2a34a8aabb31805dab0c`
pins that exact source/test, two logs, runtime and unchanged helper.47099 strict
compile passed;47100 passed five cases in2.6s:

- Expired capture refuses consumer reading, while exact management inspection
  retains the real flock. An independent native revocation contender refuses
  until callback release; bytes remain unchanged, then revocation succeeds.
- Revoked state is inspectable only with its new exact epoch/fingerprint;
  stale, substituted and malformed management pins never enter the callback.
- Missing state remains absent; retained pending bytes, control data and empty
  accounting remain unchanged by inspection.
- Killing the actual native reader helper permits a new owner to revoke, but
  the paused old callback's snapshot returns unknown rather than stale success.
- Unknown callbacks remain unknown through management and existing-policy
  reads; same-callback control mutation refuses without changing bytes.

The graphs copy the frozen management-journal v3 runtime and recompile Consent
only. They do not incorporate later native tty changes or claim a fresh complete
source build. The fixtures use synthetic policies already expired at the actual
host clock; no clock is changed. Native controls use the qualified available
host `/tmp` context. No network, model, terminal display or knowledge publication
ran. All listed handles are terminal. Full caller integration, whole-source
checks and final adversarial audit remain required.
