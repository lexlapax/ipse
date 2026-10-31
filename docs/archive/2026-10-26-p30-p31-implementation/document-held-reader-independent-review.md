# Fixed document held reader — independent review

Scoped read-only review, 2026-10-29, of the
[fixed document reader](document-held-reader.md), following the
[source-egress requirements review](document-producer-source-egress-independent-review.md).
The [plan](../../plan.md) owns completion.

Disposition: accepted as a bounded retained document-reading primitive. No
concrete blocking defect was found. It supplies no document source eligibility,
permission, inference admission or public producer activation. Those remain the
trusted caller's separate obligation.

## Frozen source and runtime checks

Independently verified manifest SHA-256
`848a8394f1fa2c4e72c7532a4d9ee4cb7c324a1587a96219d2e5c019a4f5fd44`,
all three affected source/test snapshots and seven retained scripts/logs, both
runtime inventories and both matching native helpers. The 208 regular host,
bundled-source, native and toolchain tar members exactly match the source hash
list and original copied source tree. The candidate copy differs at precisely
Collection source; the other 207 inputs match. This check does not recompile or
execute those sources.

Each runtime inventory exactly covers 699 physical nodes: 697 regular files and
two recorded symlinks, checked without following them. Relative runtime path sets
agree; only `Ipse.Extension.Collection.beam` differs. The helper in both is
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
The [verification script](document-held-reader-review/verify.exs) and
[result](document-held-reader-review/verify.log) retain those checks.

The snapshot-copy launcher checks all selected inputs before/after copying.
Retained 47160 logs compilation of 173 host/bundled files and app generation;
the receipt records its strict full-source command. Retained 47161 explicitly
strict-compiles only the Collection overlay and requires empty compile/runtime
diagnostics. The exact native source/helper and recorded strict Rust command
remain; no separate raw native build log was captured. These distinctions are
preserved rather than inventing a unified build transcript.

## Reader bounds and root identity

`with_document_read/3` chooses the fixed existing `document_graph_v1` profile
inside the tracked file-effect owner. It reuses Collection directory safety,
actual native lock, loaded root/manifest validation, profile quota check and
native final check/release. Nested Collection ownership/mutation refuses. The
trusted callback receives a root witness and same-process read closure; it
receives neither a native capability nor a publication operation ID.

The new path permits only binary selected keys, validated by existing Directory
cost/key rules. Each selected-record attempt costs one unit, including absent
records; the fixed ceiling is 512. The 513th debit poisons the token, later reads
refuse and a nominal callback success cannot escape. Invalid document neighbor
or summary queries refuse. Notes retain the default 32-unit allowance and their
existing bounded special queries; managed normalization also retains that
default. No public SDK frame/string limit, disk quota, operation count or profile
value limit changes.

Document records use the existing authenticated record reader, encoded-size/hash
checks and 64-KiB logical value ceiling. Thus 512 maximum selected values imply
at most 32 MiB of selected value bytes read, not a bound on all native protocol
operations, decoded allocations, manifests or callback-retained memory. A
complete source-use validator still needs its own bounded assembly/accounting.

The added `Profile.unfence/2` in `managed_root` mirrors normal root loading:
notes accept their unfenced pointer, while documents require the exact document
profile fence and remove it only from the comparison view. The comparison still
binds loaded manifest and summary/generation/floor. Witness `root_bytes` and
`root_sha256` retain the actual stored fenced bytes. This does not reinterpret a
notes root as a document root or erase the stored profile identity.

## Lifetime, native loss and outcomes

Each closure captures the exact native capability, process and fresh token.
Foreign-process or escaped use cannot satisfy those checks. Reads check the
native owner before and after loading. Successful callback completion seals its
token; the same sealed token is idempotently valid for the private final check,
while further reads refuse without reopening or poisoning it. Normalization
still seals immediately after its read callback and before publication, retaining
the accepted repair against post-publication read-budget reclassification.

Only typed `{:ok, _}`, `{:error, _}` or `{:unknown, _}` callback results are
accepted; malformed shapes refuse. Typed unknown bypasses success-only token
checks and stays unknown. The outer owner still attempts native check and
release; loss can replace its reason with `collection_lock_lost`, never with
known success. The native owner's death may let a successor mutate the store;
the old callback's stale loaded snapshot cannot thereby become a successful
current read. The closure itself grants no later-use authority after release.

## Retained focused controls and limits

Retained 47162 passes eleven real-native controls: four document cases and seven
affected notes/read-token controls. They exercise a roughly 40-KiB document value
and exact fenced root, live writer exclusion and successful post-release writer,
foreign/escaped/nested refusal, 512 repeated large reads, sticky exhaustion,
actual native-owner kill followed by a successor write and unknown old result,
and typed unknown/malformed callback behavior. The notes controls retain 32-unit
exhaustion and the zero/32-read normalizer cases where later staged telemetry
reads refuse while known publication still agrees with the selected root.
Read-only cases assert unchanged root bytes. No passing test was repeated here.

These are isolated trusted fixtures on the available Linux `/tmp` native profile.
They do not qualify other storage/OS behavior, source authenticity or policy,
embedding dispatch, full-workload memory/capacity or installed packaging. The
208-input host checkpoint predates the separate public Management wiring and
does not build independent knowledge packages or regenerate copied private
bundle assets. The complete host compile is useful source qualification for that
checkpoint, not an all-current packaged release or an independent security audit
of every host/native module. No model call, runtime/source edit, gate change,
aggregate suite or prior capacity trace was performed by this review.
