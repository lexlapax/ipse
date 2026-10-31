# Fixed document read ownership after current-host compilation

Scoped implementation, 2026-10-29, following the
[independent source-dispatch requirements review](document-producer-source-egress-independent-review.md).
The [plan](../../plan.md) owns acceptance. This provides the missing retained
document reader; it does not admit inference or remove the public producer gate.

`Collection.with_document_read/3` selects only the existing fixed document
profile, acquires the actual native Collection owner, loads/validates its root,
and supplies a trusted same-process callback with root witness and selected-record
reader. It reuses the existing managed-read closure, token sealing and final
native check/release. The notes path retains its 32-unit limit; the new document
path permits at most 512 string-key record reads. Each value retains the existing
64-KiB document limit. SDK strings, public envelopes, disk quotas and operation-ID
caps do not change. A 512-record maximum implies at most 32 MiB of selected value
bytes read, excluding existing bounded manifest/process overhead; it is not a
promise that callback allocations or a complete producer fit a resource budget.

The reader rejects foreign/escaped closures, nested mutations/owners and
non-key document queries. Read exhaustion is sticky. A callback's typed unknown
is preserved; loss of the actual native owner prevents known success. The root
check now uses the existing `Profile.unfence/2` before comparing the pointer to
the loaded summary, preserving notes validation and accepting a correctly fenced
document root. Raw root bytes/hash retain the actual storage-profile field.

The trusted dispatch caller still must authenticate its operator/project scope,
claim, source bundles, raw input slices, policy times and one-use batch/wire.
It makes its final admission under short retained ownership and releases before
model/long IO. This primitive supplies no source policy or effect permission and
cannot reconstruct an admitted batch from saved pending JSON.

## Evidence

The [manifest](document-held-reader/manifest.json), SHA-256
`848a8394f1fa2c4e72c7532a4d9ee4cb7c324a1587a96219d2e5c019a4f5fd44`,
pins the complete 208-input host/native/toolchain snapshot, three affected
source/test snapshots, seven retained scripts/logs and both runtime inventories.
The frozen host source predates the separate public-forget wiring. Independent
knowledge packages are not compiled by this host checkpoint. Runtime inventories
include compiled dependency/host files and private assets, recording symlinks
without traversal; compiled binaries remain in the named `_build` trees.

- `47159` copied the current source and verified every source hash before/after
  the copy and against its snapshot. It copied installed dependencies; no fetch
  or external service was needed.
- In that isolated tree, the exact current native helper was compiled with
  `rustc --edition=2021 -D warnings -C opt-level=z -C strip=symbols -C panic=abort`.
  Its SHA-256 is `40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
  The command exited zero with no output; no separate raw native build log was
  captured. The pinned source/helper and command, not an invented log, are retained.
- `47160` ran `mix compile --force --warnings-as-errors` once in that snapshot:
  all 173 host/bundled source files compiled cleanly. The existing private bundle
  assets were copied; this is not a fresh bundle/package build or a full suite.
- `47161` forked that complete source/build tree and strictly compiled only the
  new Collection implementation, with empty compile/runtime diagnostics.
- `47162` passed eleven focused native controls in 5.6 seconds: four new document
  cases plus the seven affected existing notes held-read/token-seal controls.
  The new cases cover a real large document record and profile-bound root,
  contender exclusion followed by successful post-release mutation, cross-process/
  escape/nested refusal, 512 actual large reads and sticky exhaustion, real native
  owner kill with successful successor but unknown old result, and typed unknown/
  malformed callback behavior. Root bytes remain unchanged by read-only cases.

These tests use actual `/tmp` storage on the available admitted Linux profile
with the freshly built matching helper. They do not qualify another filesystem,
OS, source-use policy, inference egress, whole-workload capacity, installed package
or milestone. No model request, aggregate runtime suite or prior capacity trace
was run. Independent reader review and source-dispatch integration remain.
