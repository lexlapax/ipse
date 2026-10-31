# Independent review of read-only packed document layout

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
the [layout receipt](document-packed-layout.md) and its manifest SHA-256
`a95dd90c4430b68766dda279598bc327cc61b4534b3e324e9ebd13e8d90c3607`.
No runtime/native edits, model/network calls or passing test reruns were made.

## Disposition and provenance

Accepted as bounded read-only metadata for an existing operator-bound document
reader. No concrete blocker was found. This supplies original logical part
boundaries and authenticated physical-object identity; it does not implement a
faithful export/import artifact, a destructive maintenance fence or profile
capacity qualification.

The [verification script](document-packed-layout-review/review-manifest.exs)
and [result](document-packed-layout-review/review-manifest.log) check the exact
manifest, all four frozen source/test files, six logs and all 705 resolved
runtime inventory paths. The inventory contains 696 physical regular files
and nine inherited telemetry source paths reached through its existing `src`
symlink. Every physical regular file is inventoried. Relative inventory paths
match the pinned inventory ancestor, with exactly DocumentStage and
CollectionStore BEAM overlays and 703 unchanged paths. The helper remains
`7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067`.
The archive pins the runtime paths and hashes rather than copying generated
BEAMs or helper bytes into the archive. It is not a current whole-source build
of Host/Session or the later independent runtime slices.

The owner-source diff against that ancestor adds only the layout grammar/read
classification, layout projection and closed outcome validator. Core,
Directory, presets, quota limits and native helper are unchanged.

## Layout and read boundary

The request has exactly `op`, public `key` and safe-integer `generation` inside
the existing project storage envelope. It cannot select namespace, project,
profile, owner, path or new authority fields. `host.` keys refuse. Existing
operator selection, collection grant, live extension identity, project binding,
Session/current-action checks and read budget remain required. The new operation
is classified as nonmutating; it does not reuse that classification to grant
other operations or saved-consent authority.

DocumentStage captures a native snapshot and matches the requested generation.
Its subsequent Core get must return that same generation, so an intervening
generation change refuses rather than combining roots. Core reads the stored
object through the retained owner, checks its exact raw length/hash and unique
JSON decoding, and returns that physical descriptor alongside the decoded value.
Layout preserves the descriptor's hash and length rather than substituting a
re-encoded logical document.

Projection requires the closed packed wrapper, one through ten nonempty parts,
the existing per-part and total bounds, exact concatenated byte count/hash, and
a valid bounded logical document object. It computes each original part's byte
hash, length and cumulative byte offset. Equal part hashes remain legal because
position is explicit. CollectionStore independently checks closed version and
recipe, revision range, both hash/size domains, ordered contiguous offsets,
exact final length, matching request key/generation and the 4 KiB result bound.
Its validation is structural receipt validation; metadata alone cannot prove
reconstructed physical bytes or confer future-use authority.

Only an absent selected record produces `layout: null`. Unsupported wrappers,
invalid logical JSON, corrupt stored bytes, stale generations and private keys
refuse. An ordinary read remains a snapshot observation; later maintenance
must reacquire and validate its own current selection. Existing bounded logical
`value.read` slicing is unchanged and can cross original part boundaries.
Read-only here concerns logical publication: existing absent-path acquisition
can still create persistent directories and lock files.

## Retained controls and limits

I inspected strict compile 47101 and the three focused final controls:

- Native 47102 passes one selected case covering equal logical bytes with one
  versus two original parts, a ten-part Unicode record, physical and logical
  identities, original offsets, logical re-slicing, absence, foreign namespace,
  stale/private/unsupported/invalid/corrupt refusal and the notes-root fence.
  Selected pointer bytes and generation remain unchanged.
- Actual independent Session 47103 passes one selected case with mutation
  approval denied and zero approvals. It reads only its project, reports a
  foreign-only key absent, refuses stale/private requests and missing or forged
  bindings, records typed receipts and restores Saved state. The largest
  observed worker request is 1,021 bytes; the logical body is absent from the
  result. This uses trusted synthetic Core seeds, not a new mutation grant.
- Protocol 47104 passes the maximum numeric/key-width, ten-part structural
  receipt case: result 1,702 bytes and complete worker request 2,093 bytes.
  Malformed offsets/count/order, float version, extra authority fields and a
  private key refuse. This bounds the metadata frame, not populated capacity.

The initial old-graph undefined-API warnings and invalid 40 KiB single-string
fixture failure are retained. The corrected fixture uses several valid strings
without widening production limits; the coherent ancestor supplies the final
runtime. No aggregate suite was run. Full acquisition/quality, faithful raw
export/import, imported-floor compatibility, owner-loss schedules, complete
incoming-ID/reservation handling, GC/migration and the whole-recipe physical
capacity ledger remain open.
