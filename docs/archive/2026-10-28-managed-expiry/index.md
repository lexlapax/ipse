# Authenticated ordinary-note expiry

Dated **2026-10-28**. This is a bounded C1a component increment following
[typed retention](../2026-10-28-managed-retention/index.md) and its
[native publication deadline fence](../2026-10-28-retention-publication-deadline/index.md).
The [plan](../../plan.md) remains authoritative for delivery status. This record
does not qualify 30/90-day turnover, annual continuation or the 10,000-cycle mix.

## Exact reducing operation

`ManagedLifecycle.prepare_expiry/3` prepares a single exact stored ordinary-note
deletion from an authenticated managed observation and a host clock. It creates
no permission, source assertion or native review. The facts bind the current
root, original public value/revision/hash, effective signed retention metadata,
project/namespace/management epoch context, exact deadline and checked time.
The caller journals these facts and reserves one protected management operation.
Expired or revoked capture permission does not itself prevent reducing expired
derivatives; the existing project and separate current management boundary remain
mandatory. There is no worker API or idle scheduler.

`NormalizerV3.expire/3` runs only inside the actual managed Collection callback
with the actual DomainAuth capability. It reopens the selected signed format,
anchor and live pages, reconstructs the literal under its exact recipe and
compares all facts with the current witness. The effective category must be
ordinary and its finite deadline must have elapsed. Preparation and Core both
refuse unexpired notes, pins, preferences and current assertions. A self-consistent
JSON-shaped expiry target does not establish stored metadata or publication
authority. No original-source access is required to remove its expired derivative.

The single native transaction removes the public note and its live index entry.
It leaves the anchor record, original first admission, original baseline and
native retention choice byte-for-byte intact. The existing destructive floor
advances. Same-support automatic recapture cannot obtain a new admission clock,
and an older-floor backup cannot restore the removed note. Persistent evidence
or another record's policy is not changed.

The existing planner and Core limits remain: at most 32 charged callback reads,
three sidecar changes for this live deletion, at most two nonnull sidecars and
one retained-revision sidecar deletion, and a normalization receipt of at most
2 KiB. Worker record clocks are ignored. The receipt has
`kind:managed_literal_expiry`, actual checked time, original first/deadline/policy,
exact action digest and metadata changes. It has no `native_review_sha256`.
Current host authority, conservative accounting and deferred settlement are
owned by the separate Consent/management caller, not granted by these facts.

## Focused evidence

The isolated graph is `_build/managed-expiry-sol-20261028`, copied from the frozen
deadline graph. Only ManagedRetention, ManagedLifecycle and NormalizerV3 were
recompiled. [Strict compilation](compile.log) has no compile or runtime warnings.
The unchanged production-profile helper remains
`113df584e83b7749a11a72509092cb9c2b32d6fdc3fcf91b0181335f5f8c2550`.
Actual stores, homes and workspaces used the admitted `/tmp` tmpfs mount; no
helper override, production clock replacement, new dependency or native source
change was used. Source receipts and backdated admissions are explicit trusted
fixtures, not live Session provenance.

[First focused run](section-46805.log) passed two pure clock controls and failed
the native case after successful expiry: its assertion compared the entire
`get` response, including the necessarily changed generation/floor, rather than
the unchanged anchor record. The failed small store and log remain. Only that
assertion was repaired; no production change was needed.

[Affected native retry](section-46806.log) passed one case in 0.6 seconds, 39
excluded, with seed 46805. A fresh isolated store obtains four signed notes
through the actual existing V3 publication API. Checks cover:

- Actual expired ordinary deletion and public absence, original admission/choice
  anchor preservation, bounded receipt and destructive-floor advancement.
- Unexpired ordinary, preference and current-note refusal, plus pure pinned and
  finite native-choice expiry boundaries.
- Core refusal of a nil DomainAuth capability, substituted target, altered
  metadata and a checked time beyond the fresh Core clock, including recomputed
  action digests. Refusals leave the selected root unchanged.
- Actual refusal of same-support recapture after expiry and of an older-floor
  import. Intent is journaled before mutation; the successful result is appended
  afterward. No uncertain effect is replayed.

These are actual native storage/control publications with synthetic source and
clock inputs. This section does not execute a complete standalone CLI journey,
source-authenticated production Session, suppression compaction, correction,
history minting, pending/history expiry, import adoption, full population or
endurance workload. Those remain separate implementation/qualification steps.
The existing operation-receipt/floor-lineage cap also remains finite and must be
included in the complete turnover controller's accounting.
