# Whole-source knowledge review and atomic admission

Historical review and correction record, 2026-10-20. Provenance is the working
increment after `0f7322694c192387023d96dba7200977758dbdc6`, following two
independent whole-P27 internal source reviews, reproduced probes, a follow-up
review and an independently judged design comparison. This is internal review,
not external acceptance or a completed P27 quality evaluation.

Current procedures are in [Corpus](../../operator/corpus.md),
[Graph](../../operator/graph.md) and the [package build guide](../../../extensions/knowledge/README.md).
Current implementation training is in [knowledge extensions](../../developer/knowledge-extensions.md)
and [State host calls](../../developer/extension-host-calls.md).
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns milestone status.

## Reproduced findings and corrections

| Finding | Reproduction and resulting behavior |
| --- | --- |
| Suppression imports bypass source capacity | Public imports accepted 33 roots, then returned tokens that public revalidation refused. Import now counts its actual destination record and shares ordinary capacity preflight. |
| Extraction silently discards time-qualified facts | Public Graph extraction reported success but omitted future-valid, past-valid and future-observed-source facts. Publication validates attribution; query-time eligibility retains its separate owner. The same unchanged probes now retrieve each fact inside its interval. |
| Rounded float32 ceiling rejects legal extrema | Evidence and host accepted the exact finite maximum while the adapter refused it. Adapter reconstruction now accepts the full finite range and still refuses infinity/NaN encodings. |
| Compatible positive requirements become conflicts | Two positive `Release requires ...` relationships were labeled conflicting solely because their objects differed. The user explicitly chose compatibility; conflict requires opposite polarities for the same relationship. |
| Concurrent creators bypass snapshot capacity | Distinct missing keys read the same 31-root snapshot and all won per-key CAS. New root creation now conditions its first write on that snapshot's namespace generation. |
| V2 root success accepts impossible generations | A public Store update accepted the requested root at revision 3 with an envelope generation of zero. V2 positive records now require revision no greater than store generation. |
| Synthetic v2 owner reuses a root tombstone | Direct fixture CAS replaced a positive-revision deleted root with either nullable or current generation. V2 refuses this target before mutation; Store also refuses it. V1 behavior is preserved. |
| Other v2 positive paths accept impossible generations | Correlated snapshot, get-many, immutable-write and collection replies accepted positive revisions at generation zero. The shared v2 boundary check covers every positive path; collection also proves requested snapshot generation plus one. |
| V2 get-many accepts a phantom revision-zero object | A nondeleted revision-zero object passed the adapter. V2 requires the canonical missing form, deleted true and null value. Downstream Store checks already prevented phantom evidence publication. |
| Addressed recovery promise omits the remote read ceiling | An 89-record remote partition refused inspection/export before root-count validation. Manuals now name the inherited 88-record ceiling and require reviewed server-side administrative recovery beyond it. Bounds are unchanged. |
| Selected remote queries are described as whole-store checks | Corpus's selected-reference route does not count all roots. Its manual now distinguishes selected queries from whole-store snapshots. |

Both integrated reviewers closed their confirmed findings after repair and
bounded follow-up. Their checks include independent synthetic assertions and
source tracing, not proof of a real server's ACL or internal transaction.

## Selected architecture and compatibility

Store owns the 32-root policy. Canonical State gains only an optional generic
`state.put.expected_generation` condition, compared under its existing native
namespace lock after target revision and before the write deadline. Successful
conditioned receipts prove `G+1`; deadline failures retain `G`; conflicts prove a
revision or generation mismatch. The last deadline check remains after temporary
output sync and before rename. Unconditioned requests and saved receipts retain
their previous semantics. Stored State, root and page formats remain unchanged.

Creation derives from the actual cached missing target, not the operation name or
a source ID absent from suppression exports. Store repeats pure capacity admission
at that final boundary. Existing-root writes and immutable pages stay unfenced.
The first claim occupies a source slot even if later work fails or its reply is
unknown. There is no rescan, retry, replay, reservation release or new record.

The two design packages also considered fixed physical root slots and a permanent
membership registry. Slots require new keys/layout and migration. A registry adds
durable reservations, orphan handling, another effect and a remote read-budget
edge. The selected namespace condition avoids those costs. An independent judge
favored retaining source/hash/draft witnesses in v2 conflict summaries. Root
accepted that reasoning over its initial preference for a smaller summary that
would have changed existing conflict semantics.

Remote creation explicitly selects `ipse-cas-v2`, inner envelope version 2.
The surrounding MCP/result-window transport remains version 1. V1 reads and
existing-root updates retain their wire format; missing-root creation refuses
locally before dispatch. There is no automatic profile upgrade or fallback.
The v2 owner requires a non-null creation condition and verifies it atomically.
Exact client receipts establish the server's assertion, not its implementation.

The guarantee requires draining older Sessions and their admitted effects before
adopting corrected writers against a shared binding. Arbitrary trusted legacy
State writes remain possible. Overfull legacy whole-store snapshots refuse before
emitting more than 32 tokens. Addressed recovery works only within existing read
limits; MCP partitions above 88 retained records need the selected server's
reviewed administrative export/migration procedure. Suppression markers remain.

## Verification and limits

The initial integrated focused run passed 76 tests before later v2 hardening.
Maintained regressions reproduce the later invalid receipts before repair and
pass after repair. Controls cover all five creators taking the last slot in
turn, canonical State writes from stale snapshots, separate OS-process lock
contention, v1 compatibility, v2 closed replies, unknown effects, overfull recovery,
tombstones, shared record/byte quotas, temporal facts, float32 and graph labels.
The 88/89-record control checks both remote contracts. Actual CLI walkthroughs
build fresh Corpus and Graph artifacts, configure/import them into isolated homes
and execute the documented source/extraction/query journeys without a model.

The separate evaluator correction binds every merged prediction, resource,
request, domain-measurement, invocation and inventory stream to its ordered cell
inputs. Version-two review records bind the original prediction, captured answer
context and selected time. Shape/binding checks precede reference access. The
eleven evaluator files match clean checker `9177aba2e7e8b7844552835df58fc5cd52f3ffe1`,
whose [hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39410643549)
passes Ubuntu and macOS. That earlier matrix covers those evaluator files only,
not the subsequent product changes in this record or their Linux verification.

The first macOS baseline passes build, formatting, strict compile, CI-policy and
documentation checks, then reports 1,322/1,323 source tests passed, one skipped and
36 excluded. Its only failing assertion incorrectly forbids the shared test-only
CAS fixture from already being loaded in the host test VM. The isolation check
now applies to production domain modules. A separate run preloads that fixture
and passes the corrected test. This failed baseline is retained; it is not a
passing final gate.

The fresh macOS run passes all 1,324 source tests, with one skipped and 36
excluded, in 855.3 seconds. Build, formatting, strict compile, CI-policy,
documentation, demo, packaging and installed-package verification pass. A final
check confirms unchanged bytes for all 456 selected code/test inputs throughout
that run, digest
`19621956f4befff8b2c27eaf3fc3ef5173f99cc7632bde1368c447d0a5951e7a`.
The final affected run separately passes 59 tests after all receipt repairs.

Fresh independent artifacts pass 16 source knowledge checks, five complete-result
checks and nine actual MCP transport checks. The same checks pass in the newly
built macOS archive, SHA256
`820ef108e2947b2b67623fc594335834b4a45b2898d726c8fd45a14a2fcd6f90`.
Installed runs hide the system toolchain and confirm unchanged archive/host files,
zero model requests, no production domain modules in the host and inert recovery.
The exact remote options from the operator chapter also pass build, generation,
import and real CLI configuration validation.

No new dependency or native collector behavior is introduced. The separate frozen
comparison uses an earlier source and remains separate from corrected-product
quality evidence. Its 350-row execution has completed with confirmed native
cleanup. The [subsequent admission and platform record](../2026-10-20-p27-historical-admission/index.md)
records passing strict historical admission and the successful exact `b9370fb`
Ubuntu/macOS matrix. Its [saved-output review](../2026-10-20-p27-historical-admission/quality.md)
measures 28% support accuracy and retains four unmeasured citation pairs.
Corrected-source quality, independent external review, untouched held-out
requirements and P27 acceptance remain open.

To rerun the focused contract and integration exercises:

```sh
mix test test/extensions_state_test.exs test/knowledge_store_test.exs test/knowledge_store_contract_test.exs
mix test test/knowledge_packages_test.exs test/knowledge_evidence_test.exs test/knowledge_index_abort_test.exs
elixir scripts/check-docs.exs
```
