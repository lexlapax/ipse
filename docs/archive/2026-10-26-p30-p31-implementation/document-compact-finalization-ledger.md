# Compact public finalization ledger — 2026-10-29

This additive closed-model run uses the new explicit public
`response: "compact_v1"` projection after the
[legacy whole-recipe ledger](document-whole-recipe-ledger.md) was frozen.
Legacy source, counts and artifacts remain unchanged. This is a new-code
finalization from a known synthetic shared-appended checkpoint, not replay of
native effects or a repeated acquisition/initial/rebuild recipe. The
[plan](../../plan.md) remains authoritative; full capacity, public production,
safe Session handoff and migration are still open.

The [manifest](document-compact-finalization-ledger/manifest.json) pins the
executed developer source, new artifact identities, chronological diagnostics,
new complete public outputs, comparison and retained model/trace hashes.
Compiled artifacts and checkpoints stay under `_build`. The parent-supplied
artifact `_build/generation-progress-corpus-sol-20261029` has manifest SHA-256
`004654fe41ab870398d806d51ad72fa5ef6d0e5b1396133deac8a43a933e72b0`.
Comparing executable BEAM code digests against the frozen Root2 artifact shows
only Corpus and Job changed; other binary-file hash differences reflect build
metadata. The unchanged frozen Root2 host graph supplies SDK/Core validators.
This is not a current all-source runtime build.

Manifest SHA-256:
`31bc1edfc68842076f7115e27abf2348304be27fd79120ea6fef4a652b229ee2`.
Five source snapshots, five logs, three reports, twelve retained input/output
hashes and twenty-five artifact-file hashes are pinned. Read-only `47132`
verified all fifty-one rows, including the immutable legacy ancestor, with
zero hash/size failures. No passing controller was rerun for the freeze.

The developer encoder now accepts an explicit response option. It puts the
same public response flag in every continuation and calls the package's real
`Job.compact_result` before dropping its private continuation field, exactly
as Corpus does. It also optionally retains complete new public outputs for
later checks; the old legacy trace retained counts only. The option does not
alter Collection requests, quotas, native authority or Job mutation behavior.

`47121` (handle `47392`) completed with exit 0. It starts from the retained
`47083` shared-appended model, uses fresh synthetic action IDs strictly above
1,000,000, runs one inspection followed by finalization, and retains all 655
complete public objects in `compact-finalization-47121/public-results.jsonl`.
No native effects, model calls or downloads occur. `47130` independently reduces
these saved records through the real ResultPublication encoder without running
the controller again.

| Finalization-only quantity | Frozen full response | New explicit compact response |
| --- | ---: | ---: |
| Replies | 654 | 654 |
| Inline replies | 334 | 654 |
| SDK2 paged replies | 320 | 0 |
| Encoded document bytes | 10,719,368 | 907,489 |
| Largest document | 39,764 B | 1,797 B |
| Output begin/chunk/seal events | 3,344 | 0 |
| Retained result-source slots | 320 | 0 |

All new complete worker reply frames are at most 1,839 bytes. The compact
result preserves progress/digests and exact continuation without repeatedly
exporting the whole durable job. The comparison asserts all 5,277 selected
record descriptors, native-model generation 19,640, final map byte counts and
revisions are exactly equal to the legacy run. Descriptor digest is
`dd5de4d15e4467ac6e92324593d90da89ffce802eabd27959816c5225d43dfdf`.

The underlying controller totals are exactly equal: 2,375 modeled mutations,
49,656 reads and 655 invocations including the extra checkpoint inspection;
the maximum host request frame remains 13,561 bytes. Excluding inspection,
104,036 action events and 161,950,045 modeled request/outcome bytes already
exceed one 100,000-event / 128 MiB Session before its other records. Compact
output removes the paged-result-source bottleneck in this trace, not the need
for explicit durable boundaries or full native/history accounting.

Every paired request has the same operation, payload hash/count, original
parts, offsets and encoded sizes. Fresh stage epochs and operation IDs cause
some complete request digests to differ. The first reducer (`47129`) incorrectly
required those request digests to match; it failed a pure comparison before
effects. The corrected reducer retains and classifies those differences and
asserts exact selected canonical records instead. The original diagnostic and
source are preserved; the controller was not restarted for this correction.

This new run proves the synthetic finalization presentation cost under the
explicit option. It does not establish actual full-profile Session journal
bytes, inference provenance, public bounded shared production, cross-Session
stage adoption, GC/export/import, representative Word quality or installed-host
capacity. It changes no quota or existing full-response default. No aggregate
suite was run.
