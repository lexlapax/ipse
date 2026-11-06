# Document Source and lexical Index epoch conditions — 2026-11-06

Historical engineering checkpoint. This P31C1b increment extends the [internal maintenance fence](document-maintenance-epoch-20261105.md)
to Source and lexical Index continuations. Current contracts are taught in the
[Collection SDK](../../developer/collection-sdk.md#stage-ordinary-documents-under-their-own-grant)
and [storage walkthrough](../../developer/knowledge-storage.md#fence-document-stages-before-metadata-maintenance).
It does not complete general maintenance, destructive GC, adoption or capacity
qualification. The [plan](../../plan.md) retains those requirements.

## Implemented scope

At epoch zero the snapshot and Source continuation preserve their legacy
shapes. After a fence, the closed document descriptor reports a positive epoch
and idle/active status. Mutating SDK requests carry a frozen consistency
condition; missing means exactly zero. The live host requires the actual idle
epoch before dispatch, while its trusted root/namespace/owner/status/epoch
admission and final native CAS remain authoritative. Exact old-stage abort and
expired reclaim remain reducing operations. Historical request/result validation
grants no current write.

Source captures its epoch once. Its nonzero-epoch version-four continuation
adds a separate epoch-binding digest; its existing plan hash remains the complete
source-body hash consumed by acquisition and workspace guards. Changing only an
old token's version/counter cannot adopt its prefix.
The lexical Index similarly binds continuation, durable job and current epoch.
Read-only inspection/query remain available. Explicit abort can retire the exact
old job under a current idle epoch without adopting its earlier stages or write
checkpoint. A partial retirement has its own frozen version-four `aborting`
continuation, usable only for abort. Confirmed retirement permits an explicitly
new job. Retained stages can still exhaust capacity; no reclamation or guaranteed
progress is claimed. Generic Job and Projection mutation paths remain legacy-zero
and refuse after a fence.

No new dependency, capability, model route, public maintenance command or grant
was added. Conditions do not replace ordinary full-argument approval.

## Actual focused verification

An earlier four-file integration selection passed **16 tests in 55.6 seconds**,
with 78 excluded. It used the intermediate Source hash contract described below;
that result is not retroactively attributed to the final Source schema. The two
Index proxy cases each ran their exact native child test; these are not additional
independent successes. The command used ordinary startup, one outer test at a
time and fresh disposable homes/native roots:

```sh
mix test test/ipse/extension/collection_document_maintenance_test.exs \
  test/ipse/extension/collection_store_session_test.exs \
  test/extensions/knowledge/collection_adapter_session_test.exs \
  test/extensions/knowledge/collection_split_append_native_test.exs \
  --only document_maintenance --only document_maintenance_session \
  --only source_maintenance_epoch --only lexical_maintenance_stale \
  --only lexical_maintenance_fresh --max-cases 1 --trace --seed 826047
```

Those selected checks cover closed descriptor/request grammar, historical shapes,
active/stale refusal, reducing old-stage cleanup, native owner/floor/checkpoint
invariants, exact Source retrieval after fresh publication, full Saved and
same-ID idle/no replay, and native Index retirement/fresh rebuilding with cited
retrieval. They use no Terminal/Input review, provider or model. Independent
source review accepted the Source/host boundary; whole developer chapters and
the operator Corpus chapter were reviewed. Its index recovery procedure now
distinguishes an uncreated job, a known unfinished build and a stale abort.

The first actual public workspace case then failed: the unreleased intermediate design had
overloaded `plan_sha256` with an epoch-bound digest, but the existing host
acquisition contract correctly interprets that field as the actual source-body
hash. The final design preserves that meaning and adds the separate closed
`epoch_binding_sha256` field. No WorkspaceDocumentGuard check was relaxed.
Corpus's workspace guard uses the actual source hash, and its Index abort
continuations preserve the original abort action instead of returning `next`.

With that final Source, the exact Source and public workspace cases passed
**2 tests in 39.4 seconds**, with 97 excluded. The Source case rejects missing,
malformed, changed-counter and forged-digest continuations without a native
change, then completes the known current plan. The workspace case uses the
normal shipped Corpus bundle, actual file acquisition and native storage. It
independently reconstructs the complete stored source bytes and proves
`guard SHA == plan SHA == body SHA`, with a distinct epoch-binding digest. Exact
original-file citations, full Saved, confirmed close and same-ID idle/no replay
pass. Both use ordinary manual approvals and a provider that raises if called.

A separate public Corpus Index retirement case passed **1 selected test**, with
10 excluded, in a 9.7-second outer run. It drives the actual handler and native
Collection with 63 metadata-only catalog page references and 12 group references
in a 13,757-byte job. After
a real native write-parts result it deliberately exhausts the in-memory effect
budget to force a partial abort. This models a nearly exhausted allowance;
it does not claim that sixteen preceding effects actually ran. It checks the returned v4 abort command,
changed-epoch refusal and exact command resumption with a new invocation ID and
the same synthetic Session owner. It starts no actual Session, model or Input;
the metadata is not an actual 1,000-source population. Nested child counts are
not added to any aggregate.

The first three public retirement attempts failed on a fixture encoder alias and
fixture geometry that did not reach the intended pause. An earlier passing
version remains separate from the final Source/artifact run above.

The final working-tree normal build passed strict compilation of all **198 host
modules and all four normal bundles**. This is not a clean release or installed
qualification. Root's standard format/docs/demo and the separate broader
regression have their own receipts.

Earlier outcomes remain failed: an 11/12 run expected a later refusal code; a
15/16 run exposed a Source content/plan hash mix-up; the next 15/16 run exposed
omitted read-only Index operations in the new helper allowlist. The separate
initial Index run also exposed an existing nil/boolean bug on its unbuilt-job path. Each was
corrected before the earlier 16-case selection, and the original logs remain preserved.
The independent frozen whole-suite run was unchanged. No original retained
notebook was accessed.

## Commitments

Hashes identify reviewed source and the private focused log; no journal,
transcript, runtime or log body is published here.

| Owner or receipt | SHA-256 |
| --- | --- |
| Host Collection | `073d31c2a1b5215c72cd0ddaaac661899bcf0e19cb70fa4e67b15a0fe6e46a2d` |
| DocumentStage | `b3f4bf7af52622483e8dd1286e2e886b5453e7673bee0d14d44daddd3a04efb0` |
| CollectionStore | `509ee0336d8bb2438ef26e050190b27df76ac5a4eaa10877e5703cc990441b67` |
| Final Source adapter | `ff1aee5c619af925874140ec468a5b6c44775eeb228f2f396f6bd52701a546a9` |
| Lexical Index | `eb402539734a144f13bdfe61de7d109ff501280b12c818d7245574630c0e3e5b` |
| Final Corpus consumer | `c713348ad0f66510efe7640689ae4a978e79d082e9b054df4ddea5e4f3da6c83` |
| Earlier 16-case focused log | `464a5752ab62e9331bc1b827d7e523ce9e6c7145f8a0d68e2547d4e5b4fa2c22` |
| Failed workspace log | `c71a4bbd4c22db8ffbd37ae5010a92db8a7c2e68fb1034d8ef25bfc5d13efac2` |
| Final Source/workspace log | `1693f7bfe0ca81391097cb19e72d9858f9917622868fbad71e61da30817f5b1b` |
| Final public Index retirement log | `45bf351e2b4690272372e473ec7ffe46a76c1ebec972d1c9f8d29abf5b825f9c` |
| Final normal build log | `8d5ae64e3a295e526a64403600590c9eeaaa5f51a9a9a6d692b72c87251b12fd` |
