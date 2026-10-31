# Historical reviewer prompt snapshot

Preserved on 2026-10-29 from the uncommitted working file `review-prompt-working.md`
before its current-scope rewrite. Original body SHA-256: `23c72125fe4261309ff73309ab9aba432a5a4a27f565d36544e2a3c9bf6676e1`.
This snapshot is historical only; its kernel, integration and agent instructions
are superseded by the [current working reviewer prompt](review-prompt-working.md)
and [plan](../../plan.md). The original body follows unchanged.

---

# Working review prompt for P30/P31

Created 2026-10-27; updated 2026-10-28. This prompt is a working handoff artifact, not evidence that the
requested post-implementation audit has happened. P30/P31 are incomplete.
Update this prompt and the linked evidence after subsequent implementation; the
final reviewer must audit the final source and completed journeys.

> Review the current Ipse P30/P31 work adversarially against `AGENTS.md`,
> `docs/plan.md`, `docs/knowledge-design.md` and the frozen baseline. First
> inspect the branch, index and worktree; do not assume an archived hash matches
> the current bytes. Read the [continuation handoff](handoff-20261027-terra.md)
> and [corrected full-regression record](corrected-full-regression-followup.md).
> The 46621 diagnostic passed on a graph missing two tracked files; 46653 was
> interrupted after the same omission was found despite its zero exit code.
> Inspect the later complete-source run and require both its test summary and
> exit status; distinguish the private test helper from production admission.
> The newer full working-tree run and the isolated available-host diagnostic
> are recorded in the continuation handoff. Check their exact source snapshots,
> helper differences, exclusions, failed and `NOT RUN` paths before drawing
> conclusions; neither qualifies an unadmitted production storage profile.
> Preserve all unrelated dirty edits and the `.serenity-*` evidence. Do not
> clean or replay prior stores, device faults or unknown effects. Do not use
> credentials, live model services or external actions unless separately
> authorized. Publication is not authorized.
>
> Trace the actual host-owned Session path, not only pure helpers. For each
> read, continuation, projection, inference and effect, identify the owner,
> authenticated input, durable intent/result ordering, authority, locks,
> linearization point and failure/cleanup behavior. Try concurrent revocation,
> stale root, changed source, owner loss, timeout, replay, duplicate or missing
> records, and unmediated worker outputs. Verify that unknown effects are never
> automatically replayed and that knowledge consent cannot widen workspace,
> shell, MCP or delegation authority.
>
> Review the pushed [owned staging inventory change](sol-recovery.md) against
> actual native writer leases, retained stages and quota admission. Its injected
> sync error and synthetic zero allowance prove refusal paths, not real Btrfs
> writeback failure or a physical quota. The 2,883-test diagnostic used a private
> kernel override; the separate production-profile build and transaction controls
> did not admit kernel 7.2.11. Keep those claims separate.
>
> Audit the uncommitted [journal-origin integration](sol-source-origin.md) through
> actual Journal creation, locked resume before repair, Writer startup, window
> installation, source queries and managed publication. Try copied/moved files,
> same-path replacement, canonical aliases, missing or malformed origin fields,
> legacy downgrade and mismatched reconstructed windows. Check that source
> versions bind the actual recorded origin without exposing private locations in
> worker proofs, and that legacy inspection cannot manufacture publication
> authority. Distinguish cooperative-storage identity checks from protection
> against coherent same-user rewriting. The 96-test selection is scoped synthetic
> evidence; it does not establish cross-Session current-source lookup, source
> leases through egress, attribution, withdrawal or current recall. The full
> diagnostic predates this integration. Require final source-current checks and
> actual use/egress tests before accepting that broader path.
>
> Review the [native statement/category path](native-assertion.md) through real
> terminal input and the existing protected capture command. Test statement,
> category, scope and nonce substitution, cancellation, planning and revocation
> during review. The receipt records endorsement, not external truth or effect
> permission. Whole plain messages must stay pending, while an ordinary review
> cannot become a current/preference literal. Keep targeted section evidence
> separate from aggregate regression and installed/platform qualification.
>
> Trace the [managed read admission](current-source-read.md) from actual
> `CollectionCall` policy selection through provisional observation, original
> source ownership and final signed-record admission. Try mismatched recipes,
> old plain-input literals, expired host clocks, category/source exclusions,
> root changes, original-journal replacement, partial tails, missing/replaced
> lock files, active other owners, multiple source ordering and consumer failure.
> Confirm current-Session queries require the actual action/job/worker lease.
> Distinguish the 42 targeted tests and later cleanup check from aggregate or
> platform qualification. Read-time validation currently discards its normalized
> dependency after checking it: no durable producer lineage or final send/delivery
> freshness is implemented by this section. Do not accept those broader claims
> without tracing their subsequent actual integration.
>
> Audit [declared planning MCP reads](planning-mcp-live-read-followup.md)
> through actual approval, descriptor rediscovery, intent and lifecycle evidence,
> interruption, restoration and terminal draft acceptance. Try declaration,
> mode and checkpoint substitution, exhausted evidence capacity, stale source,
> schema changes, and changed policy after approval. Distinguish a Session's
> static configuration from immediate on-disk policy revocation, and distinguish
> structural journal checks from authentication against wholesale rewriting.
> Reproduce unavailable journal sources at the start and outcome boundaries;
> confirm no draft read dispatches without a bound lifecycle start and that
> an uncertain effect is never represented as safely retryable.
> Exercise checkpoints with and without declarations, a crash between a
> checkpoint and its new epoch, completed but unconsumed drafts, and existing
> or newly requested session grants under restricted modes. Audit the working-tree
> `/plan` and `/plan exit` transitions for native input origin, CLI startup
> markers, local versus inherited ceiling provenance, legacy checkpoints,
> delegated configuration, in-flight and queued work, crash prefixes and resume.
> Try to invalidate a startup marker across a pending draft and MCP epoch, and
> verify exit cannot publish deferred decisions or widen unrelated authority.
> Inspect terminal journal-limit receipts before the first MCP epoch, between a
> transition and its epoch, and after a pre-start intent. Verify the receipt's
> sequence and final position, that no missing start is inferred, and that a
> sealed Session cannot resume or dispatch through an earlier epoch.
> Review the declared-read controlled Session-death tests before and after the
> synced exit record, including their writer-proxy and synthetic-input
> assumptions, before extending their results to native terminal, power-loss or
> in-flight MCP cleanup claims.
>
> Inspect the uncommitted P30 coverage policy and its actual built artifact:
> can unavailable eligibility, incomplete or falsely fitting coverage, forged
> plans, missing rows, byte framing or advice produce a misleading action or
> bypass a real allocation? The [coverage record](p30c-coverage-followup.md)
> describes synthetic evidence; it does not authenticate its inputs or qualify
> a consumer.
> Include nonempty eligible sets with missing candidates or permitted packs,
> true zero allocation, fitting complete sets and separately built artifacts.
> Compare the synthetic planner-to-Session shadow fixture with the eventual
> protected consumer: fixture facts and its result grant no source authority,
> publication, experiment budget or evidence of a qualified strategy.
>
> Inspect the managed-reference and dispatch changes, including the
> [marker reproduction](managed-reference-marker-followup.md) and
> [dispatch consistency checks](dispatch-admission-followup.md). Determine how
> a reference-aware withdrawal can preserve reference classification, validated
> occurrence identity, journal replay, draft projection and compaction without
> retaining stale managed content. The current refusal is not the full feature.
> Check version-1 null-record refresh and replay: its missing selector must not
> let a changed whole-root result remain eligible. Assess the compatibility
> impact on any private or future journals using the old projection rule.
> Review the later same-root requirement for all legacy dependency shapes: an
> unchanged record does not prove that a worker ignored root metadata. Verify
> changed-root replay refusal and assess whether any proposed selective refresh
> binds the complete observed result and every derived output.
> Examine the internal [record-only observation experiment](record-observation-followup.md):
> verify that the root witness never reaches a supposedly record-only consumer,
> result and request hashes are authenticated by owned reads and durable Session
> chronology, and other reads, suppression history, descendants and current
> authority cannot escape the lineage. The current pure version-4 shape alone
> proves none of those facts. Test the signed historical publication-policy
> digest separately from current consent, including re-consent, forged or stale
> source proofs, expired deadlines and metadata read under a different root.
> Reproduce both retention-override read counterexamples, including a recipe
> with a nondefault override prefix. Require the selected recipe digest and
> absence of its override at the same authenticated root. The conservative
> refusal of all present overrides is not an implemented retention workflow.
> For [pending observations](pending-observation-followup.md), attack signed
> record/recipe/policy bindings, forged source-shaped JSON, clock mismatches,
> pending versus current eligibility, override races and root changes between
> reads, including nondefault recipe evidence, lineage and category paths.
> Check both historical literal observation and subsequent dependency validation
> against actual signed publications. Also examine signed
> observation after real Knowledge worker publication and saved Session
> reconstruction; distinguish a synthetic same-Session proof check from
> authenticated current cross-session source selection and lock-held delivery.
> Require separate current consent, source authentication, expiry and
> actual review/acceptance; the historical observation supplies none of them.
> In particular, a stored source proof names a Session but does not bind its
> selectable state directory. Try copied, moved, deleted and independently
> advanced histories with the same Session ID; do not infer the originating
> journal or current redaction state from the default directory.
> Check live admission versus replay, service identity, queued retries and
> duplicate intents. Do not interpret an intent as proof of an actual send.
>
> Inspect the unwired Mint and wire-facts experiments and the
> [transport record](mint-text-contract-followup.md). Reproduce or refute the
> documented TLS connection-wait race and distinguish it from the proposed
> one-use send continuation. Attempt phase, parser settings, target/body,
> reservation, source-root and policy substitution; inspect lock ordering,
> stalled sends, owner death and TLS cleanup. Equality of caller-supplied facts
> is not authenticated authority. The experimental path must not be wired until
> a complete current-authority and cleanup protocol is proven.
>
> Review the capacity-controller changes and
> [controller record](managed-v3-controller-followup.md): require a pinned
> helper, durable intent before any effect, clean exit and checked release,
> immutable workload/source binding and no retry after uncertainty. The host's
> 7.2.11 kernel is outside the admitted profile. Do not run a capacity workload
> until its native, crash-durability and workload gates are independently met.
> Initial-addition geometry is not 30/90/365-day lifecycle or turnover evidence.
> Attack the shared V2/V3 `pending.` capacity check with full and malformed
> summaries, byte boundaries, simultaneous publishers, stale roots, nondefault
> prefixes, legacy replay and direct or imported writes. Its fixed-prefix
> summary is not a global multi-instance quota, and the private-helper controls
> do not establish production storage qualification.
>
> Audit automatic capture, source attribution, saved consent and headless
> admission, managed eligibility and withdrawal, notes correction/forgetting,
> document acquisition and fidelity, optional local embeddings/RAG, P30
> consumers and frozen experiments, installed workflows, migration, human and
> platform evidence. Treat absent or indirect evidence as unverified; explicitly
> separate synthetic, experimental and live results. Review operator and
> developer manuals as whole documents against actual behavior, then check
> commands and links. Inspect full test output and exclusions; a test that says
> a positive journey was not run is not a pass for that journey.
> For the uncommitted Notes retention changes, attack same-lineage deadline
> renewal, future or expired choices, clock rollback, prior-choice substitution
> and historical-gap reporting. In particular, `:absent` is an unauthenticated
> caller assertion; require the actual host path to check both relevant lineage
> states under the transaction lock. Test the legitimate reason that collides
> with the internal marker, and do not infer current eligibility from the pure
> policy, a matching note, or a synthetic input receipt.
> Reproduce the [fragment admission counterexample](capture-fragment-followup.md)
> with both the normal and deliberately weakened synthetic worker. Check that
> whole-event quoted or pasted content is not silently promoted and that older
> stored records receive an explicit safe treatment; the current guard alone
> does not establish either property. The same follow-up records an actual
> synthetic PTY and saved-consent publication of text labeled as a third-party
> report as a current literal note; reproduce it before assessing the repair.
> For the native-question guard, try `yes`, selected options, full-sentence
> answers and forged literal requests through both worker and host, including
> historical signed records and raw read paths. Reproduce the signed historical
> record that the old reader returned and the repaired reader refuses, while
> checking that embedded proof JSON is not treated as current authority. Verify
> pending publication still requires its own saved grant and a question answer
> cannot accept a card.
> Audit the current DOCX recipe against ambiguous namespace attributes, hidden
> content, source acquisition and stale indexes; synthetic parser tests and a
> built artifact do not qualify real Word interoperability. The frozen
> independent document set remains unrun by the implementer. Attack annotation
> identity and point-reference binding: malformed or duplicate numeric IDs,
> hidden/deleted or multiply referenced markers, unreferenced annotations,
> marker-only paragraphs, UTF-8 byte offsets, table cells, comment ranges and
> other document stories. Confirm a point is never described as a complete
> annotation range; attack v11's same-paragraph byte spans with hidden or
> deleted markers, duplicate IDs, cross-paragraph ranges and intervening text.
> Confirm stale v7/v8/v9/v10 extraction results are not silently
> treated as the current recipe.
> Inspect [embedding input binding](embedding-input-binding-followup.md) at
> page admission, Store projection commits and retrieval of existing rows. Try swapped inputs,
> later-page changes, stale chunks, and strict versus explicitly partial lexical
> fallback; verify reindexing and historical data handling. A matching digest
> does not authenticate the provider or identify model weights. Assess how a
> future formatted-input recipe will version its identity and compatibility.
>
> Return findings ordered by severity with exact file/line, concrete trigger,
> consequence, reproducible evidence and the smallest safe repair. List missing
> acceptance evidence and any compatibility or deployment risk. Do not declare
> P30/P31 complete or an independent audit passed unless the final source and
> every applicable gate have actually been reviewed and verified.

The developer selected work in a single agent for this session. This prompt is
for the eventual handoff requested by the developer and does not authorize
spawning agents or contacting anyone now.
