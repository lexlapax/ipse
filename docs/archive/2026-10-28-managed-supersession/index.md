# Typed literal supersession component

Dated 2026-10-28. This is focused P31C1a component evidence, not milestone,
Session-source integration, endurance, installed-use, or release qualification.
The [plan](../../plan.md) remains authoritative.

## Boundary and clocks

`ManagedLifecycle.prepare_supersession/5` prepares exact review facts for a
fresh, distinct literal and a current observed predecessor. The trusted owner
must separately authenticate the replacement source, hold its real source lease
and current capture policy, journal the intent, and perform the native review.
Preparation is neither source authority nor a consent grant. A production
Session caller holding that lease is not implemented by this component.
That caller must also retrieve and journal the complete consumed native review
receipt while its permit is live; the compact Core receipt retains only its hash.

`NormalizerV3.supersede/3` rechecks the pinned recipe and constraints, exact
source members, selected old signed pages, root, revision, facts, capture expiry,
and supplied policy fingerprint inside the held Collection callback. It spends
one exact native review permit, and prepares both public changes and signed
metadata in one typed Core transaction. Current Session capture integration must
hold and revalidate real source and consent authority through that transaction;
the caller-supplied fixtures in these tests do not provide that guarantee.

Ordinary correction preserves the predecessor's existing deadline as both its
history deadline and a ceiling on the successor's original baseline. Temporal
supersession admits a reviewed current literal and keeps predecessor support for
365 days from native confirmation, or indefinitely for an existing pin. The old
anchor retains its original clocks and binds the successor key and value hash;
the old live row becomes noncurrent history. The new first admission is the
actual Core admission clock, never the predecessor's clock. The final native
switch is fenced by the earliest finite old, new, history and capture deadline.
The component refuses same-text successors and does not promote a worker choice
or renew an ordinary clock from a new phrasing.

The typed Core path allows up to eight non-deleting signed sidecars, while the
existing worker-facing path keeps its prior bounds. A local cache returns only
identical successful real reads from the same held callback, so the existing
32-unit read budget counts actual read calls. Combined encoded normalized
request, review facts and normalization receipt are limited to 64 KiB; the
receipt remains limited to 2 KiB. Compact receipt references preserve the
full key, expected revision and value hash for each sidecar.

## Focused verification

The isolated graph `_build/lifecycle-sol-20261028` was copied from the frozen
`_build/managed-expiry-sol-20261028` graph and recompiled only for the affected
modules. Strict compilation had no compile or runtime warnings. The retained
native helper is SHA-256
`113df584e83b7749a11a72509092cb9c2b32d6fdc3fcf91b0181335f5f8c2550`.
Temporary homes and stores were on the admitted `/tmp` tmpfs. The native tests
ran outside the command sandbox because the native storage profile needs its OS
facilities; source receipts and backdated admissions were explicit trusted
fixtures rather than live Session evidence.

- A focused run passed three pure history controls and one native test covering
  ordinary and temporal publications, exact signed predecessor closure, the
  successor hash, original clocks, noncurrent history, once-only native review,
  and refusal of missing source or expired capture before review consumption.
- A delayed native switch control held the staged transaction past the capture
  deadline. It observed an unconfirmed publication, unchanged root, no operation
  receipt, a still-current predecessor and no successor.
- A signed Planner component fixture forced two full leaves in each tree to
  split into eight sidecars. Its directory/read callback was synthetic.
- An additional actual native Core transaction used a small synthetic signed
  seed to force the same four splits. It published eight sidecars and verified
  the predecessor's signed closure and the current successor. It measured 25
  actual callback read units, a 1,772-byte receipt, and 21,440 encoded bytes for
  the combined request, facts and receipt. Filler rows were synthetic and did
  not establish source provenance or a population workload.

The eight-reference receipt shape with maximum-width keys, revisions, clocks
and hashes encodes to 1,913 bytes. This is a synthetic width bound, separate
from the 1,772-byte receipt measured in the actual focused publication.

These checks do not provide an authenticated historical-use API, source lease
integration, consent/Session management caller, full adversarial semantic
review, 30/90-day workloads, annual turnover or the 10,000-cycle acceptance run.
The separate encoded maximum in the frozen graph is a planning bound, not an
actual native workload measurement.
