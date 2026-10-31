# V4 selected-root immutable reuse repair — 2026-10-29

Historical model evidence; the [plan](../../plan.md) owns acceptance. This
follows the [public two-page Session](shared-producer-v4-public-session.md),
whose artifact predates this repair. The new artifact has not been exercised
in a native Session.

A new synthetic Collection model control produces a page, assembles a group
with explicit synthetic facts, appends it, finalizes a version-2 selected root,
and starts a new Job. A forged old ready row naming a page outside that root
refuses before storage or inference. The valid row passes selected-root
membership, but the first run then refused after inference: `value_write` had
correctly reused identical immutable page bytes and returned a read-style row
without a `key`; the producer expected the key in every response. It left the
new claim pending instead of publishing ready. That run is a synthetic model,
not a native store or an effect to replay.

The producer now supplies the exact already-requested page key only when the
Collection row omits it, then checks key, hash and length together. A supplied
wrong key still fails. The repaired control completes the selected-root case,
preserves the selected root, and confirms no immutable page write occurs. It
also keeps the forged-membership refusal. Four focused model cases passed:
selected-root reuse, same-Job terminal reuse, two-page progression and unknown
effects. The strict candidate artifact build passed. The diagnostic copies
remove a rescue only in a private in-memory compilation to locate the mismatch;
production refusal behavior was not weakened.

The [manifest](shared-producer-v4-selected-reuse/manifest.json), SHA-256
`c9551be5d1ed53ddff9e66fc63655c9b71571b554b40f3f562de5d25dac7448f`,
pins 73 source, artifact, diagnostic and log files. The initial failed control
and both diagnostic failures are retained. This does not establish native
selected-root reuse, independent audit, general migration, fact production or
full capacity. Preserve unknown actual effects and do not infer replay authority
from these model results.
