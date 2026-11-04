# Dense Corpus manifest boundary — 2026-11-04

This is a historical investigation and isolated candidate qualification record.
The [extension authoring chapter](../../developer/extensions.md#bind-the-manifest-to-immutable-bytes)
and [operator procedure](../../operator/extensions.md#import-a-reviewed-artifact)
own current usage. This record does not establish complete-source, installed,
platform or milestone acceptance.

## First failing boundary

The combined main source suite's public-selected Corpus cases stopped while
building `corpus/collection-dense`, before artifact import, Session creation,
source approval or inference. The same boundary also stopped the shared-producer
read-only setup case. Sanitized retained exception metadata identifies
`MatchError` at `extensions/knowledge/build.exs:125`: the final aggregate manifest
must fit 16,384 bytes. The standard four shipped bundle builds did not cover
this separately selected dense preset. The combined source was identified by
the frozen product/test patch SHA-256
`5fda38ab5c506c83df6124430deb206d82bcf420e4b131edcae3d5e72b026260`;
the retained input fingerprints bind the exact builder, SDK and helper bytes
used by this narrower investigation.

One explicitly authorized build-only diagnostic reproduced that failure against
the complete frozen main SDK. A second authorized source-derived diagnostic
printed numeric sizes immediately before the same unchanged assertion:

| Encoded section | Bytes |
| --- | ---: |
| Complete manifest | 16,397 |
| Aggregate bound | 16,384 |
| Excess | 13 |
| Exports: eight commands and six tools | 11,497 |
| Exact file inventory: 27 files | 4,046 |
| Options schema | 394 |
| Capabilities | 159 |
| Runtime | 69 |

The catalog validated successfully. Both failed diagnostics left no final output
or temporary build stage, and source/SDK fingerprints remained unchanged. They
used an isolated HOME/output and one scheduler/async thread, without starting an
application, worker, native helper, terminal, provider or model. No source,
expiry or approval guard was reached or changed.

## Minimal candidate and actual checks

The reviewed candidate shortens seven description literals representing six
distinct descriptors. It retains the current/cited, explicit source-ID,
supplied shared projection, catalog-bound namespace, explicit fact, guarded
vector and producer-progress meanings. Operation choices remain unchanged in
the exact action enums. Every schema, export, capability, helper and numerical
limit remains unchanged; no backend or document reader is removed.

One actual candidate build used the original builder on a task-owned bounded
source copy and the complete frozen SDK. It passed with a **16,183-byte** manifest,
**201 bytes** of headroom and the same **27-file** inventory. Actual
`Artifact.decode/1`, protected `Artifact.import/2` into a private task cache and
`Artifact.lookup/2` passed. Import used the existing preflighted native advisory
lock/unlock helper; no application, extension worker, terminal or inference ran.
There were no lingering lock Ports or build stages.

A manifest over 16,384 bytes and an ordinary SDK object over 16 KiB still
refused. Plain-object depth twelve, 128-member and 8-KiB string constraints,
catalog/schema bounds, duplicate-key checks, inventory hashes and source guards
were not modified. Main source, SDK, dependencies and helper fingerprints
matched before and after. The task copy's artifact digest was
`109dcde62860d1d18dd867dedf18fbb1e867308a6d1d42565d6a4bfdc97d987e`;
that digest is not a claim of deterministic rebuild identity from another path.

The verification launcher first failed to parse before copying inputs or starting
a build/helper. Its retained log distinguishes that setup-only error from the
single actual candidate control. The correction retried no effect.

## Evidence and remaining qualification

The [evidence manifest](dense-corpus-manifest-20261104/manifest.sha256) identifies
the reviewed wording patch, original and derived diagnostic receipts, candidate
verification launcher/receipt, source/runtime fingerprints and the preserved
launcher failure. The wording patch SHA-256 is
`f1e4f0b20ce2b0565d55e8b63a7858a983c5d919eb0c61fd736a2cfaeae1500f`.
The actual candidate verification receipt SHA-256 is
`90b7d7b266c60e3ee95cacca1983b2b9214f487920723a7be8153fa1f8d193ed`.

The affected public Session journeys still require focused reruns on the final
integrated source. A successful inert build/import is not source-change,
source-expiry, model-selection, producer or citation qualification. The failed
full suite and its original evidence remain retained rather than relabeled.

Whole-document review covered the operator and developer extension chapters and
the Knowledge package entry point. The existing 16-KiB manifest explanation,
separate trust/selection/effect ownership and unknown/no-replay recovery remain
correct. The package entry point's stale blanket implementation claim was
replaced with a pointer to the authoritative supported-flow procedure; no limit
or workflow expansion was documented.
