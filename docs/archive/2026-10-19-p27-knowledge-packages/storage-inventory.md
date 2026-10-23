# Read-only storage inventory, 2026-10-19

Historical development record after `f5b91b0`. The source commit containing this
record owns the inventory implementation. Use the
[evaluation training chapter](../2026-10-22-before-structural-consolidation/docs/developer/knowledge-evaluation.md#verify-retained-storage-without-querying-through-the-audit)
for the current audit boundary and exercises. The
[plan](../../plan.md#p27-optional-research-graph-and-rag) retains the complete
acceptance requirements. No held-out member or actual model inference was opened.

## Validation and corrections

The pure domain inventory reuses Store's existing root/page schema and identity
checks. It verifies the complete selected reference closure, including reference
hashes, partition, source and generation. It checks a repeated reference before
skipping traversal. It counts selected pages, active draft pages, orphans, roots,
other live records and namespace-wide tombstones/slots separately. Root and page
identities remain opaque hashes; source text is not returned. Encoded record and
value byte lengths remain distinct from actual State file lengths.

The first lifecycle control failed because the new inventory treated a source
draft's `source_generation` as its target. That field is the old-source
precondition. Source pages belong to `target.generation`; projection drafts keep
the existing source generation. The corrected suite passed nineteen isolated
Store tests in 37.0 seconds, seed 516511. It includes first ingestion, replacement,
abort, suppression, collection, conflicting/forged/missing/deleted/foreign
references and complete selected reachability of twelve pages holding two
4096-coordinate vectors. Collection retains slots and deletion revisions.

The host audit validates bounded owner-only State files through the public
record validator and exact namespace/version/generation accounting. A separate
Elixir process loads the frozen reviewed artifact and its public SDK dependencies.
The parent verifies unchanged State bytes and artifact identity afterward.
Domain modules remain unloaded in the main host. A real State-file control
refuses inconsistent generation sums, floating-point generations and permissive
file modes, and proves that the audit returns no stored private payload.
An initial test incorrectly expected empty builder stdout; the builder's
documented success message corrected that fixture expectation.

The initial child setup omitted Jason, which the public SDK's bounded object
validator requires. The early metadata-only control did not enter root validation
and missed that dependency. A stronger public-Session test required real selected
pages and failed with an unavailable inventory. A separate controlled check
showed SDK validation failing without the existing Jason path and succeeding
with it. The audit now includes that existing dependency; no package was added.
It retains all validation rather than replacing it with an audit-specific schema.

After the correction, seven focused controls passed in 22.5 seconds, seed 429772.
Seventeen public query/answer invocations retain their real nonempty inventory
and reuse exactly one storage-inventory file. The cache binds the exact State
file path/hash, artifact digest and partition. Missing or corrupt snapshots
cannot pass coverage, and incomplete inventory now makes execution incomplete.
Research explicitly reports that it has no retained State store.

## Integrated verification and limits

The integrated Store, runner, resource, raw-State and service suite passed 38
tests in 163.0 seconds, seed 615362, including finalization and file-accounting
observations. Subsequent label/pricing-descriptor corrections and full source
verification retain their separate checks. The final full local suite passed
1140 tests with 17 Linux-only exclusions in 582.4 seconds, seed 387321. Strict
stdio tracing and both actual macOS enforcement tags were enabled. A subsequent
fixture-format correction has whole-file syntax-tree equivalence and its one
affected raw-State audit test passes. Build, formatting, warnings-as-errors
compilation, pinned CI policy, documentation links and the isolated credential-free
demo pass. No production deadline, success assertion or paging bound changed.

Fresh lexical Corpus and model-capable Graph artifacts built successfully. The
source driver passed five checks with seven durable invocation receipts and zero
model requests. The installed Graph recovery proof passed eight checks with
confirmed cleanup, zero model requests, development tools hidden and unchanged
host/archive bytes. The archive SHA256 remains
`d5d2517e87cf358cfe6b6d82060719e6be52ce0e5fcf7920fc4729df7d5c8a4f`.
It was not rebuilt or published. These protocol checks do not claim installed
execution of the development-only metadata wrapper or prove the cause of the
[accounting revision's hosted append timeout](resource-accounting.md#retained-hosted-failure).

File lengths do not establish allocated disk blocks,
compression, sharing or an exact transient peak. Harness BEAM samples do not
establish worker/model RSS or whole-system peak memory. The resource evaluation
flag remains false, and the held-out comparison, independent semantic review,
engine decision and remaining P27 acceptance audit remain open.
