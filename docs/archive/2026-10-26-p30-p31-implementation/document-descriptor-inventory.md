# Read-only document descriptor inventory — 2026-10-29

This scoped implementation follows the [maintenance design review](document-collection-maintenance-design-independent-review.md).
The [corrected v2 proposal](document-collection-maintenance-v2-design.md) separately
resolves the proposed barrier/export design; it adds no destructive runtime API.
The [plan](../../plan.md) owns acceptance. No deletion, fence, migration, mutating
grant, native helper, runtime gate or domain extension changed in this slice.

## Exact API and permission

An already trusted document instance may request:

```json
{"op":"collection.store","scope":"project","request":{"op":"value.index","generation":1,"after":null,"limit":16}}
```

Generation is an exact safe unsigned integer; limit is an integer in 1..16;
`after` is null or an exclusive public key. All `host.*` cursors refuse. Results
contain the existing checked summary, `records`, `next`, public `count`, and
`coverage:"public_document_records"`. Each complete descriptor is exactly
`{key,revision,record_sha256,record_bytes}`: hash and size describe the **physical
packed record**, unlike `value.stat`'s logical body hash/size. Complete rows are
removed from the tail until the result fits 4 KiB; `next` is the last actual
returned key when more remain. Empty/final pages use null. Coverage identifies
public metadata; it asserts neither source eligibility nor GC reachability.

The parent explicitly approved this narrower interpretation of the review's
separate maintenance capability: existing `host.collection.store` plus its fixed
operator document binding already authorizes reading public values in the same
namespace, so descriptor enumeration uses that **existing read grant**. It does
not add mutation authority or a trust/configuration selector. Ordinary reads
require no mutation approval. The host still resolves an already admitted
ProjectIdentity, derives only its fixed `document_graph_v1` namespace and checks
current artifact/Session/job binding. The worker cannot supply another namespace,
profile, path or owner. Missing or foreign-instance binding refuses. The separate
destructive maintenance permission remains only a proposal.

## Ownership and zero-body-IO path

`DocumentStage` validates/classifies `value.index` as a read. Its fixed-profile
`Collection.document_index` entry uses the existing Collection native lock,
validated root/manifest metadata, quota check and unchanged final native
check/release handling. Directory reuses OTP ordered iteration. It excludes
**all** `host.*` keys before sorting, counting and pagination, including stages,
ready values, parts and future private names. It never calls `read_record` or
opens value objects. The final locked generation check protects the page even
if the earlier DocumentStage snapshot became stale. No cache or second index
is persisted. Legacy notes/index/read-view contracts are unchanged.

An index is a generation-pinned page, not a leased whole traversal. Any store
mutation invalidates that generation; callers inspect/restart explicitly. The
8,192-record bound may need more than one invocation's 512 reads once startup
and other reads count. This API adds no automatic continuation, retry or scan
completeness attestation. Native owner/release uncertainty retains the existing
unknown result semantics.

## Focused evidence and exact source

The [manifest](document-descriptor-inventory/manifest.json), SHA-256
`afa3cb876e4ee6ccf9af21f8fd17331af1900272f79b0e92841327c3f586f7e0`,
pins six final source/test snapshots, eight chronological passing logs, two
compile/run scripts and 705 files in the isolated runtime graph. The graph is a
copy of the reviewed document-decision runtime with exactly four inventory owner
modules recompiled. Strict compilation reported four modules and no warnings.
The unchanged helper is
`7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067`.
This is not the current whole-source Host/Session integration graph. Generated
runtime files remain under `_build`; retained source/logs are in this archive.

- Pure `47080-final`: 1/1. Forty 96-byte keys, maximum safe generation/floor/
  revision widths and complete physical descriptors traverse deterministically
  through bounded pages; CollectionStore validates each response. Private/
  malformed cursors, floating counters/limits and extra namespace/profile
  arguments refuse. This exercises actual 4-KiB shrinking rather than assuming
  sixteen maximum-width descriptors always fit.
- Native `47080-final`: 1/1. Forty public records plus five private keys are
  seeded through actual native Collection writes. **Every value object is then
  corrupted**; inventory still returns the exact original physical descriptors
  and all public keys, with zero value reads and no storage-file changes.
  Stale generation conflicts, private cursors refuse, an absent store returns an
  honest empty page, and a notes-profile root refuses document interpretation.
  Native fixture homes run on the already reviewed available-host `/tmp` profile;
  this is not a new production filesystem qualification.
- Actual public Session `47080-journal`: 2/2. An independent worker uses actual
  `collection.store` host calls to enumerate forty public 96-byte keys in three
  pages while foreign-project and host-private records remain excluded. There
  are zero mutation approvals and zero model calls. Stored root bytes stay
  unchanged. Every Action result and SDK resume payload validates, and Saved
  reconstructs the journal. The largest resume payload is 4,172 bytes; the exact
  Worker request-envelope construction with recorded sequence is 4,227 bytes,
  below 16 KiB, and the real Worker accepts the exchanges. Actual Registry
  preparation refuses missing and foreign-instance trust; a forged namespace
  binding and missing identity binding refuse. A valid stale generation-zero
  request against generation one produces a validated failed action receipt;
  a private cursor refuses before an inventory action, without mutation.

Earlier initial/final/frame logs are retained as chronology. The snapshot and
manifest describe the final cohort, not original source snapshots for each
earlier passing diagnostic. Later test refinements added a valid stale-generation
seed, explicit notes-profile refusal, complete Worker envelope sizing and exact
negative journal assertions; no runtime test failed. Pure/native tests were
repeated only after the ordered-iteration implementation and those focused
assertions changed. Public tests were repeated only for those added assertions.

Scoped commands were the retained strict compile/run scripts (pure, native,
Session), `mix format` on the six touched Elixir files and `git diff --check`.
No aggregate suite, model call, package/install run or docs checker ran. The
parent owns manuals/navigation, full integration checks and commit/push.

Full-scale metadata traversal, native loss schedules for this added read entry,
populated capacity, GC and migration remain outside this receipt. Existing
native release behavior was reused without changes; no broader lifecycle or
destructive acceptance follows from the four passing focused cases.
