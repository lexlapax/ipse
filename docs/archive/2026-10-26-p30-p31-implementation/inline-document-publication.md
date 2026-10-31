# Bounded inline document publication — 2026-10-29

This historical component receipt follows the [namespace lexical index](namespace-lexical-index.md)
and [versioned chunk recipe](collection-chunking.md). Current behavior belongs in
the [developer manual](../../developer/knowledge-extensions.md) and
[operator Corpus manual](../../operator/corpus.md); the [plan](../../plan.md)
retains full P31C1b/F acceptance. This increment does not qualify populated
capacity, rebuild peaks, graph/vector population, migration, collection, ordinary
Word quality or actual-use admission for managed extension inputs.

## Transport and publication

DocumentStage advertises an exact version-one `document_store` feature marker in
its snapshot. The Collection client uses the new operations only after observing
that marker. An older host's unchanged summary selects the existing bounded
open/append/seal/commit path. No refused, failed or unknown inline effect causes
an automatic fallback or replay.

`value.put_inline` admits a complete UTF-8 JSON object of at most 8,192 original
bytes. The closed request carries its target, expected revision, complete original
byte count and SHA-256, data and expected native generation. Duplicate JSON keys,
extra fields, wrong hashes/counts and oversized objects refuse before writes.
The exact original bytes are retained in the existing document-value format;
whitespace is not normalized to manufacture a different digest. One existing
Collection CAS publishes the value.

`value.prepare_inline` additionally carries the existing reusable slot/epoch. One
CAS creates its sealed private header and ready value, with no intermediate part
records. The existing owner, exact epoch, target revision, expiry and consuming
multi-ref CAS remain authoritative. Preparing metadata leaves the selected source
and catalog unchanged. Final source publication still consumes its three refs in
one atomic CAS; namespace publication still consumes the index root and captured
catalog together. Stale or consumed epochs cannot publish again.

The client checks the complete SDK host-call envelope before selecting inline
transport. Escaped or larger values use existing bounded pages. The SDK's 16-KiB
object, 8-KiB string and depth limits, 512 reads/16 effects per invocation, 16 stage
slots, 8-ref commit, 8,192 live records and 32,768 native operations remain intact.
The new receipt grammar authenticates exact request-bound target, revision,
hash/count and stage completion fields; historical summaries remain valid.

DocumentStage also accepts a trusted host-only `publish_before_ms` option. It is
not a worker field or authority grant. Every native mutation receives the earlier
of that deadline and any protected stage expiry, through Collection's existing
Resources-owned continuation and final native `switch_before` check. Its scoped
process state is restored after the call. An already expired deadline refuses;
abort/reclaim remain possible for expired stages while preserving any actual-use
deadline. The caller's managed-input union and final actual-use admission remain
the separate integration owned by the host boundary work.

OTP maps, existing JSON validation, Collection CAS and native transaction deadline
facilities provide this increment. No dependency, background worker, new workflow
framework, filesystem authority or quota selector was introduced.

## Focused results and provenance

- `46838`: three native controls passed in 1.1 s: complete noncanonical 8-KiB
  object bytes, malformed request refusals, private two-value preparation and one
  consuming CAS, owner/epoch refusal, and deadline refusal.
- `46839`: two actual Session controls failed because CollectionStore's closed
  receipt grammar initially rejected the new feature marker. The failure log is
  retained; this was repaired with exact compatible old/new result shapes.
- `46840`: three actual Session controls passed in 41.0 s. Each small supplied
  source used six native mutations, versus eighteen on the original staged path;
  a two-source namespace build used seven. The selected index returned both exact
  cited sources. Oversized escaped source data used bounded append transport.
  Killing the actual Session after inline CAS but before receipt left a durable
  intent; inert resume neither replayed it nor changed native operation count.
- `46841`: the current client passed one actual Session control against the
  frozen older host/helper in 13.7 s. Without the feature marker, a small source
  used eighteen staged mutations and the larger source also remained readable.
- `46842`: two final focused controls passed in 27.1 s. The Session control adds
  forged inline hash/count/epoch/offset receipt refusal. The native control
  exercises a future trusted deadline, scoped cleanup and a later ordinary call.
  The exact tested worker artifact was retained under `_build`.

The two-source fixture measured 12 native operations before index construction
and 19 afterward, with 8 then 12 live records. Allocation was 53,248 then 69,632
bytes; these are observed before/after values, not measured peaks or capacity.
These fixture paths have no model service, embeddings, graph population or
inherited managed inputs.

The [manifest](inline-document-publication/manifest.json) pins sources, exact test
logs, worker and host BEAM hashes, helpers and earlier evidence. Build artifacts
remain under repository `_build`; isolated native fixture homes use actual `/tmp`
tmpfs. The current helper is the separately built `a51c2d…` cohort containing the
document profile and native transaction deadline operation. The older-host
compatibility control uses unchanged `e400…` evidence. Both are available-host
diagnostics under private fixture admission on Linux 7.2.11, not production kernel
admission or an installed/representative Word qualification. Failed compile output
from intentionally reloading modules is retained separately from the subsequent
strict compile with module-conflict handling; no undefined or other warnings were
accepted in the strict compile.
