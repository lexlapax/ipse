# Atomic managed-collection storage boundary

Dated **2026-10-26**. Internal storage increment after `9ee296c` on the P30/P31
implementation branch. The [persistence chapter](../../developer/persistence.md)
owns its developer procedure; the [plan](../../plan.md) owns milestone acceptance.
No worker SDK operation, domain normalization, recall or standalone activation is
claimed complete by this record.
The later [Normalizer increment](managed-normalizer-component.md) requires explicit
floor advancement and replaces the optional-floor contract measured here.
The [source/runtime inventory](managed-collection-sources.json) binds the private
measured graph and focused test files.

## Explicit original and normalized publication

`Collection.execute_managed/6` is a trusted-host boundary. It checks original
commit CAS, duplicate IDs and writer fencing before invoking a host normalizer
under the same native Collection lock. The normalizer receives the root/manifest
witness and an owner/token/capability-bound read closure with 32 reads. It returns
a valid normalized commit containing every original change exactly, plus 1..16
nondeleted writes under `host.validity.`. Generation and floor choices remain
the original ones. It returns no worker/native capability and cannot extend the
closure's lifetime beyond the callback.

The durable receipt's existing request hash binds the normalized commit. A new
managed-binding hash binds original request, recipe and normalization-receipt
digests. The result retains the bounded normalization object and binding fields.
Wire root version 5 explicitly carries managed receipts; ordinary roots still
emit version 4. Older readers refuse version 5. Canonical block reconstruction
rejects a root relabelled as version 4; flat legacy versions 2/3 cannot carry the
new field. Typed complete migration and duplicate inspection preserve the exact
managed binding. Existing 24-MiB logical, 64-MiB managed, 8,192-record,
32,768-operation and bounded-block ceilings remain unchanged.

This seam authenticates no source and grants no consent. The adapter must reserve
worst-case metadata costs and verify policy, semantic recipes, current sources
and exclusions. It must block reserved metadata through every worker read/write
path. Trusted direct storage APIs retain their administrative access. A migrated
receipt is historical integrity data, not fresh Session authority.

## Source and checks

Private checkpoint `/tmp/ipse-managed-collection-20261026-01` copied the complete
117-module operator-sidecar checkpoint, then changed only the four storage files
and focused tests. Its private helper digest remains
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
The concurrently developed normalizer, managed recipe, activation and inference
dispatch are outside this measured graph. No helper was rebuilt.

- Strict compile passed, zero diagnostics:
  `/tmp/ipse-managed-collection-01-strict.log` and repaired incremental compile
  `/tmp/ipse-managed-collection-01-repaired-strict.log`.
- Final Collection, managed Collection, blocks, encoding, planning and complete
  migration suites: **53 passed**, **344.0 seconds**, seed **205725**;
  `/tmp/ipse-managed-collection-01-migration-repaired-tests.log`.
- Controls include actual native-owner loss, cross-process/expired/over-budget
  read closure, preservation of worker values, forbidden metadata deletion,
  original CAS/duplicate refusal, full typed import and canonical synthetic annual
  receipt/block bounds. Synthetic annual rows are not actual endurance writes or
  distinct-payload physical-capacity qualification.
- Actual Elixir 1.18.5 formatting of all seven component code/test files passed;
  `/tmp/ipse-managed-collection-01-focused-format118.log`. A concurrent inference
  draft was the only difference in the separate whole-tree formatting attempt;
  it is excluded from this component claim. Current Elixir formatting also passed.

The first run preserved two managed-write failures caused by a missed local
receipt validator and a 300-second existing large-import timeout, ending 30/33.
The local validator now reuses the shared closed receipt check. The next combined
run ended 50/51 because its existing telemetry handler observed a different
fixture's staged event. The handler now filters its exact transaction directory.
Both failed receipts remain in `/tmp/ipse-managed-collection-01-tests.log` and
`/tmp/ipse-managed-collection-01-repaired-tests.log`; tests and TLS were not weakened.

An independent agent reviewed the four storage changes and three test files
read-only and found no concrete correctness issue in that diff. It checked the
CAS/closure/binding/version/migration boundaries above, but did not run these
tests. This is a scoped static review, not the requested final adversarial audit.
Full branch, native, installed, domain-capacity and final audit gates remain open.
