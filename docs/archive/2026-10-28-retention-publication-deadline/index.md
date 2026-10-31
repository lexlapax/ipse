# Retention publication deadline fence

Dated **2026-10-28**. This is trusted synthetic component evidence following
[typed retention](../2026-10-28-managed-retention/index.md) and the
[document storage boundary](../2026-10-26-p30-p31-implementation/document-store-boundary.md).
The [plan](../../plan.md) remains authoritative for delivery status. This section
supersedes the earlier retention component's missing final-switch clock check;
it does not retroactively change the earlier helper or CLI receipts.

## Native publication boundary

The trusted retention normalizer preserves the original admission clocks and
returns `publish_before_ms`, the minimum of the old effective deadline and the
new finite deadline. Null represents two unbounded deadlines. Collection scopes
this host-produced value around that managed mutation, restoring its previous
process context afterward. Worker request schemas accept no deadline field.
Session-only forgetting and ordinary Collection publications retain their
existing behavior.

The existing retained native transaction implements a separate `T` root switch.
Its payload is exactly 58 bytes: an unsigned big-endian deadline, one 41-byte
pending basename and `root.json`. Deadlines must be positive JSON-safe integers.
Truncated/trailing payloads, invalid UTF-8, other targets and malformed integers
refuse. After the existing private-file, retained identity and sync checks, the
native owner compares the actual wall clock immediately before `renameat`.
Equality or expiry returns code 8 before attempting rename. Clock acquisition
failure refuses. The ordinary `S` protocol remains unchanged.

An expired pointer switch does not roll back previously installed immutable
objects or the staged pointer. Collection therefore retains an unknown result
after staging, even though this native refusal proves the root rename was not
attempted. The consumed review cannot be reused. Preserved journals and exact
operation/root inspection are the recovery boundary; no automatic retry occurs.
This check uses the existing trusted host wall clock, not a clock rollback or
physical fault qualification.

## Focused controls

The isolated graph is `_build/retention-deadline-sol-20261028`. It copies the
frozen C1b host graph and recompiles only Runner, Transaction (including its
nested modules), Collection and NormalizerV3. Runner pins the new private helper
with SHA-256
`113df584e83b7749a11a72509092cb9c2b32d6fdc3fcf91b0181335f5f8c2550`.
The helper retains the production exact Linux `7.2.11-arch1-1` tmpfs profile;
all actual fixture homes, workspaces, state and temporary directories were on
the admitted `/tmp` mount. Shared `priv`, preceding helpers, evidence graphs and
capacity stores were not changed. No environment helper override is used.

- [Native parser/switch control](native-unit.log): one exact Rust case passed,
  71 excluded. It checks elapsed/equal-time refusal, zero and oversized integers,
  truncated/trailing bytes, invalid UTF-8, wrong target, unchanged root/pending
  bytes on refusal, retained identity and a successful live switch.
- [Affected focused controls](section-46804.log): two tests passed, one excluded,
  in 12.5 seconds with seed 46803. One direct protocol case checks ordinary
  switching, host-side malformed requests, the exact native expiry result,
  unchanged selected bytes and successful current publication.
- The other case uses two fresh retained-note stores and actual native review.
  It first publishes a six-second duration, then holds a pin's final staged
  pointer beyond that old deadline. A separate store first pins the note, then
  holds a two-second duration beyond its new deadline. The hold occurs after
  normalization at the existing root-staged telemetry boundary. Both actual
  native switches refuse; exact old root bytes remain, the attempted operation
  is absent, and consumed permits cannot be used again. Read-only journal
  loading leaves the retained file inventory unchanged. Sources and past
  admission clocks are explicit synthetic fixtures, not live Session provenance.
- Focused formatting and diff-whitespace checks passed. Strict initial source
  compilation produced no source diagnostics; its development compiler call
  emitted an Elixir API deprecation warning. The Transaction-only repair compile
  reports no compile or runtime warnings.

## Preserved failures and limits

The first setup stopped before copying a runtime because its destination parent
did not yet exist. The repaired setup and both logs remain. An initial Rust
filter omitted the full exact test name and selected zero cases; it is not a
passing qualification.

[First focused batch](section-46803.log) failed both cases. Native `T` success
replies were missing from the Controller's closed reply-tag list. A possible
successful rename consequently produced unknown and stopped the test. The
native retention fixture/store was retained; the first standalone protocol
fixture's original `on_exit` removed its own ephemeral directory. That cleanup
was removed before the affected retry so future protocol uncertainty remains
inspectable. The repair adds exactly the `T` reply tag. Only the affected cases
were rerun, using fresh stores and the same helper. No unknown call was replayed.

This section does not run an actual standalone CLI retention journey with the
new helper, a complete product Session resume journey, full turnover, 4,000-note
capacity, document population/rebuild, physical fault injection or any aggregate
suite. Earlier CLI receipts remain explicitly pre-fence evidence. The existing
available-host Btrfs refusal remains unchanged.
