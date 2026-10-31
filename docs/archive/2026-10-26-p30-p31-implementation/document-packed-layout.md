# Read-only packed document layout — 2026-10-29

This scoped implementation supplies the missing original-part metadata needed
to plan faithful document export. It does not implement an export artifact,
import acceptance, maintenance fence, GC or full-profile qualification. The
[plan](../../plan.md) remains authoritative. The
[inventory receipt](document-descriptor-inventory.md) and
[maintenance proposal](document-collection-maintenance-v2-design.md) explain the
separate metadata enumeration and future destructive boundaries.

The [manifest](document-packed-layout/manifest.json) has SHA-256
`a95dd90c4430b68766dda279598bc327cc61b4534b3e324e9ebd13e8d90c3607`.
It pins four source/test snapshots, six chronological logs and 705 runtime
files. No generated BEAM or helper binary is copied into the archive. The
runtime is a copy of the independently reviewed inventory cohort; all 703
unmodified files were checked against that ancestor, and exactly DocumentStage
and CollectionStore were compiled as overlays. The unchanged helper has SHA-256
`7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067`.
Actual native fixture data used `/tmp` tmpfs, with no ambient override. This is
not a build or qualification of all current Host/Session source.

## API and meaning

An existing operator-bound document reader may send:

```json
{"op":"collection.store","scope":"project","request":{"op":"value.layout","key":"data.example","generation":12}}
```

The request accepts exactly `op`, a public `key` and the expected native
`generation`. Namespace, project, profile, owner, filesystem path and quota
remain host-derived. Existing configuration/presets and grants are unchanged.
`value.layout` is classified as a read and spends the existing read budget,
without a mutation approval.

The response contains the existing summary, requested key and `layout`. An
absent record returns `layout: null`. An unsupported packed shape, invalid
logical document, corrupt object, stale generation or private key refuses;
these cases are not converted into absence.

The closed layout has version `1`, recipe `document_packed_layout_v1`, native
record revision, `record_sha256`, `record_bytes`, logical `sha256`, logical
`byte_count`, and one through ten ordered part descriptors. Each part contains
its exact cumulative byte offset, byte count and SHA-256. Offsets start at zero
and the last part ends at the complete logical byte count. Repeated equal part
hashes are allowed; their positions remain explicit.

`record_sha256` and `record_bytes` identify the actual encoded immutable object,
including its packed wrapper and escaping. Logical `sha256` and `byte_count`
identify the concatenation of its original parts. The response contains neither
the logical body nor raw physical bytes. It is not by itself a complete export,
replay permission, current-use attestation or proof of a GC mark set. A future
faithful writer must still reproduce or copy the exact physical bytes and
compare the physical digest; decoding and re-encoding logical JSON alone is
insufficient.

Existing `value.read` keeps its bounded logical slicing behavior. Its slices
need not coincide with original stored parts. Two records with identical
logical bytes and different legal original boundaries therefore have the same
logical hash, different physical hashes, and different layouts.

DocumentStage reuses the existing native `get`: Core verifies the raw object
size/hash and decoded value through the retained native owner. The returned
generation must equal the captured snapshot generation before projection. The
adapter then validates the complete packed body and logical document and
computes part metadata. The result remains below 4 KiB. CollectionStore checks
the closed result, exact request generation/key, offsets/counts and normal
project binding. No new caller-supplied lease or authority receipt is accepted.
As with existing reads, an absent namespace can create persistent directories
and lock files; logical read-only behavior does not claim zero filesystem
changes for every absent path.

## Focused verification

| Control | Result and scope |
| --- | --- |
| Strict compile `47101` | Two overlays, zero compile/runtime warnings |
| Native `47102` | 1 passed, 13 excluded, 1.6 s: same logical bytes in one/two original parts; ten-part Unicode record; exact physical/hash/offset checks; logical re-slicing; absence; foreign namespace isolation; stale generation; private/unsupported/invalid/corrupt refusal; notes-root fence; selected pointer/generation unchanged |
| Actual independent Session `47103` | 1 passed, 6 excluded, 2.3 s: operator-bound SDK read with approval policy denying mutations; zero approvals; own project data, foreign-only key absent; stale/private refusal; forged/missing binding and missing project identity refused; typed journal receipts and Saved reconstruction; largest worker request 1,021 B; no body text or model call |
| Maximum protocol `47104` | 1 passed, 13 excluded, 0.6 s: ten parts and maximum numeric/key widths; result 1,702 B, complete worker request 2,093 B; malformed offsets/count/order, float version, extra authority fields and private key rejected |

The native and Session tests use explicitly trusted synthetic seed data through
the existing Core API. They establish the read boundary, not a new mutation
grant, actual Word quality, populated capacity, imported-floor compatibility,
owner-loss schedule or installed-host acceptance.

The first compile (`47099`) deliberately retained its diagnostics: the older
Root2 host graph lacked the newer inventory APIs referenced by current
DocumentStage. The first control run (`47100`) passed the grammar check but
correctly refused a fixture containing one 40 KiB logical string, contrary to
that test's expectation. The fixture was corrected to several valid strings
while retaining ten original parts. Neither SDK/string limits nor production
gates were widened. The frozen inventory graph then supplied the coherent
runtime for the final three controls. No aggregate suite was run.

## Remaining dependency

The current per-value migration proposal still needs separately reviewed
batched acceptance or an operator-selected opaque artifact/native import-page
API, complete incoming-ID union and terminal reservations, epoch-aware
continuations and actual quiescence/recovery. The ongoing whole-recipe ledger
keeps logical bytes, physical allocation, live record-map keys, permanent
operation IDs and Session journals separate. This read slice does not authorize
those mutations or establish that the complete 256 MiB profile fits.
