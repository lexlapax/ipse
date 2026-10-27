# Immutable collection correctness and physical planning checkpoint

Dated investigation, **2026-10-26**. This records an internal, unshipped component
and a failed physical import-capacity gate. It does not complete P31C1a or C1b.
Follow the [current plan](../../plan.md), [frozen contracts](contracts.md),
[qualification protocol](qualification.md#storage-and-performance), and
[implementation index](index.md). The earlier [component investigation](storage-component.md)
preserves preceding formats, failed drivers and historical batched measurements;
the format and ownership details below replace those earlier component details
at this checkpoint. Immutable receipt blocks are the next proposed repair.

## Trace the internal ownership boundary

`Ipse.Extension.Collection.execute/4` takes a host-selected protected operator
root, admitted project digest, closed request map and immutable operation ID.
It grants no worker filesystem authority and is not exposed through the SDK.
The host still owns intent journaling, exact source/artifact/project admission,
semantic permissions, consent epochs and unresolved liabilities. Pure retention
belongs to `IpseKnowledge.Notes`; storage never infers content or selects a policy.

Lock order is ProjectIdentity → Consent → Collection. Entry rejects reentry and
reverse order before creating a file-effect worker. One actual native transaction
owner holds the complete lock stack and performs staging, immutable installation,
allocation checks, root selection and reclamation. Reads return only after lease
check and release. Lost ownership makes the result unknown; a retained successful
operation ID returns its original receipt and never enters another publication.
The [native contract](../../../native/README.md#publish-protected-state-through-its-lock-owner)
describes the OS boundary. These trusted-core capabilities are not authentication
against arbitrary hostile same-VM code.

Version-3 generations keep lossless compact receipt rows in a hashed immutable
manifest. Local generations are contiguous and never reset. Imported receipts
retain their original explicit generation and optional receipt fields. Canonical
Base64url is checked by decode/re-encode equality. Floats, duplicate IDs,
noncanonical aliases and generation gaps refuse. Values are bounded canonical
JSON maps in immutable content-addressed files.

The complete value limit is 6 KiB. Active, staged and checkpoint logical references
share a 24-MiB envelope: identical `{record key, content hash}` references count
once, while distinct keys still count separately even when they share one blob.
Status exposes active, staged, checkpoint and combined logical totals separately.
The 64-MiB managed allocated-file envelope reserves 22 MiB for control: 18 MiB for
Consent and 4 MiB for the complete shared identity root. Collection therefore has
42 MiB, including old/new manifests, immutable objects, pending files, directory
blocks and retained locks. Each control owner independently enforces its budget.
Filesystem-wide journal/allocator overhead is outside this allocated-file metric.

The native profile admits only the explicitly reviewed Linux 7.2.10 Btrfs and
tmpfs conditions. It obtains actual allocation units and rejects unsupported
kernel/filesystem/hugepage policies. It reserves twice each new file's rounded
length before receiving payload. This is not a universal 4-KiB estimate or an
APFS/ext4/other-kernel qualification. Successful native integration tests assume
this profile; unsupported-platform behavior and CI/runtime portability remain
readiness gates, not platform passes inferred from exclusions.

## Follow complete migration and its applied proof

Generation-bound `export` pages 32 records; `export.operations` pages 128 original
semantic receipts. `export.plan` returns a bounded metadata plan containing sorted
key/hash/byte rows and compact lossless receipts. This is an internal large host
message, not an ordinary 32-KiB SDK frame.

The closed version-3 descriptor binds project, generation, floor, exact counts,
byte total, record digest, operation digest and ordered applied floor lineage.
Each lineage ID resolves to its complete immutable receipt, with strictly
increasing floor. Its digest and final anchor are checked. Merely possessing an
inspected alias is insufficient: an aborted import must not claim to have applied
the source's destructive changes. Incoming applied lineage must extend the entire
current prefix, and actual source operation pages must contain every claimed
lineage member. Conflicting receipts for the same ID refuse.

`import.open` fences ordinary writers. Without a complete plan it conservatively
reserves every possible new source ID, remaining record/operation pages and
terminal/checkpoint-removal identities. With a plan it verifies complete metadata
and exact ancestry first, admits only genuinely new aliases, marks the operation
stream complete and stores at most 256 hashes of expected record pages. Values
must match those hashes before publication. A substituted page refuses unchanged.
Source aliases admitted by a successful open/page remain known after abort.

Every nonterminal publication reserves an additional complete prospective abort
manifest and pointer before accepting bytes. The complete planned import also
preflights every missing object, two maximum generation manifests and the abort
publication using the unchanged native allowance. Plans above the native
256-file-size command bound currently refuse; no smaller unchecked estimate
substitutes for the full plan.

`import.commit` validates all declared data and operation digests before atomic
selection. Same-floor adoption can retain one checkpoint. A later destructive
publication invalidates it; rollback requires the matching floor/anchor/applied
lineage. Abort retains inspected IDs but never adopts source lineage. The small
128-change `import` operation remains a separate merge, not full migration.
Raw legacy floor-zero state can upgrade on a successful write. Nonzero legacy
state without explicit applied proof and older typed descriptors refuse unchanged;
the implementation does not invent destructive ancestry. Released-format
P26/P27 migration still needs its separately reviewed adapter.

Hashes bind content and integrity; they do not authenticate an arbitrary forged
backup. The trusted host must admit its exact source. Domain suppression and
retention overrides must survive replacement independently of incoming content;
generic storage does not supply that knowledge policy.

## Preserve the failing and repaired controls

The initial production focused run passed 26 of 27 checks; its sole failure exposed
a nil/strict-`or` bug in the Consent reverse-order entry guard. The repaired target
passed. Three subsequent actual regressions all failed before repair:

- Near 32,768 retained IDs, import could consume terminal capacity and permanently
  fence both commit and abort.
- A numerically newer divergent backup could restore a forgotten record.
- Active and distinct staged raw values could exceed 24 MiB despite physical dedup.

The [three failing controls](storage-v3-regressions-before.log) preserve that
pre-repair output. After the narrow repairs the focused set passed 30 of 30 checks.
A further test actually reproduced the [aborted-alias ancestry bypass](storage-v3-abort-alias-before.log)
before the ordered applied proof was added. Near-capacity terminal reservation then passed independently:
32,761 existing local IDs plus three disjoint source IDs could import, abort at
32,767 total IDs and still publish one final ordinary operation without replaying
any source ID. Pure plan/codec checks passed 8 of 8. After a fresh strict whole-app
compile into the verifier-owned immutable
`/tmp/ipse-collection-v3-checkpoint-20261026-01` snapshot, the final focused run
passed all 40 checks in 221.3 seconds, seed 669885, `--max-cases 1`. It used the
actual bundled protected helper, without an override. The command was:

```sh
MIX_BUILD_PATH=/tmp/ipse-collection-v3-checkpoint-20261026-01 mix test --no-compile test/ipse/extension/collection_test.exs test/ipse/extension/collection_migration_test.exs test/ipse/extension/collection_encoding_test.exs test/ipse/extension/collection_planning_test.exs test/extensions/knowledge/notes_test.exs --max-cases 1
```

The [first full 40-check checkpoint run](storage-v3-checkpoint-initial.log)
passed 38 checks. One newly added test
incorrectly expected the mutation receipt to contain the snapshot's floor anchor;
the assertion was corrected to inspect the snapshot. The 4,096-record shared-value
import hit its 180-second whole-test deadline during overlapping control stress.
Its finite fixture deadline was increased to 300 seconds for the corrected run.
This timeout is preserved as a verification failure; it supplies no latency or
capacity pass. Native per-transaction deadlines and quota bounds were unchanged.

A complete planned-import fixture passed with 4,096 logical 6-KiB records and
20,950 already-known receipt IDs, including altered-page rejection and checkpoint
removal. Its value blob was intentionally shared. The 141.6-second test exercises
metadata and identity planning; it is neither a distinct-value physical-capacity
result nor an individual annual workload or latency qualification.

An attempted `--no-compile` run after an unrelated interrupted Mix compilation was
invalid because stale dependent beams, including `Ipse.Usage`, had been removed.
Those undefined-module failures did not exercise storage. A fresh strict app
compile and owned-module compilation replaced that incomplete build before the
valid checks. Build paths remain verifier-owned; later verifiers must use a fresh
unique path and leave an active compiled snapshot immutable.

## Physical planner probe: refusal is a failed gate

The independent [probe script](../../../dev/knowledge/storage_planning_probe.exs)
constructed 4,096 **distinct** exactly 6,144-byte values with deterministic
hash-derived varied evidence. It seeded 20,950 synthetic valid receipts rather
than performing 20,950 transactions. Every actual fixture file was staged,
synced and installed through the same protected native owner and unchanged quota.
It used no model, download, qualification corpus or gold labels.

The [raw receipt](storage-v3-physical-planning.json) records exact source/helper
hashes, retained synthetic-store location and selected filesystem provenance.
The helper SHA-256 is
`385f42879330838a8635af4689d5c9fd422c6f19beb9de72b710474ac08f216c`.
The selected NVMe workspace reports Btrfs, 4,096-byte block/fragment units and
`compress=zstd:3`, `ssd`, `discard=async`, `space_cache=v2`. Another component's
control stress overlapped, so no latency or comparative performance claim follows.
After building the matching helper and compiling the immutable snapshot, the
probe invocation was:

```sh
mkdir -p _build/storage-workloads
MIX_BUILD_PATH=/tmp/ipse-collection-component-build mix run --no-compile dev/knowledge/storage_planning_probe.exs --parent "$PWD/_build/storage-workloads" --output /tmp/ipse-physical-planning-probe-20950-v3.json
```

| Counter | Measured value |
| --- | ---: |
| Distinct logical value bytes | 25,165,824 |
| Fixture manifest bytes | 2,314,753 |
| Collection allocated bytes | 35,876,864 |
| Peak allocated bytes including 22-MiB control reserve | 58,945,536 |
| Planned same-store import | `collection_capacity` refusal |

Post-refusal inspection confirmed unchanged generation 20,950, floor zero,
20,950 IDs, allocation and absence of an import fence. No import was retried.
The source stayed within the store envelope, but complete generation/receipt
copies plus guaranteed abort headroom did not fit. This is an actual failed
physical migration-capacity gate. It cannot be attributed to floor-lineage
growth: this fixture's floor and applied lineage were zero/empty.

The next proposed format separates lossless immutable receipt blocks so a small
generation does not rewrite every lifetime receipt. That repair must preserve
exact lookup/export, all reachability during current/staged/checkpoint ownership,
bounded reclamation, ancestry and unknown-outcome rules. No annual individual
365-day plus 10,000-cycle qualification, reference-hardware p95 result, platform
qualification, Session integration or P31C1a completion is claimed here.
