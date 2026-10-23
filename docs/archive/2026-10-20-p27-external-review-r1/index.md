# External whole-P27 review and repair

Historical investigation record, 2026-10-20. The independently supplied
[report](report.md) reviews `b9370fb61cff9131463baca201584e5d9470bc47`.
Its original bytes and [provenance](provenance.json) are retained. The reviewer
left the repository untouched. This record describes the verified repair
increment over `beb9009`; it does not close P27 or establish corrected-source
model quality.

Current procedures belong to [Corpus](../../operator/corpus.md),
[Graph](../../operator/graph.md), [Research](../2026-10-22-before-structural-consolidation/docs/operator/research-extensions.md)
and the [knowledge contributor manual](../../developer/knowledge-extensions.md).
[Evaluation training](../../developer/knowledge-evaluation.md) owns scoring and
measurement procedures. The [plan](../../plan.md#p27-optional-research-graph-and-rag)
owns acceptance status. Earlier corrections and their passing checks remain in
the [preceding admission record](../2026-10-20-p27-historical-admission/index.md).

## Disposition

| Finding | Accepted direction |
| --- | --- |
| F1: duplicate hybrid candidates | Fuse by partition-qualified source/chunk identity, reinforce scores once per component and retain an exact representative span and complete graph bases. |
| F2: remote writes exceed readable capacity | Require an explicit V3 owner to enforce 88 retained records atomically across all accepted writer versions. Preserve legacy reads and recovery; refuse legacy record additions locally. No draft slot reservation is promised. |
| F3: reviewer controls literal integrity | Recompute every citation against hash-validated captured corpus bytes after binding verification. Ignore reviewer integrity flags for scoring; invalid reference bytes refuse scoring. |
| F4: advertised 32-fact extraction cannot fit | Pack known facts by actual encoded size and reserve bounded model-output pages/effects. Retain the 32-fact capability and existing SDK bounds; retain a recoverable draft if publication cannot fit. |
| F5: escaping breaks export and limit is ignored | Bound the complete encoded envelope, honor one through four source windows, and reconstruct complete no-duplicate-text imports before hash validation. |
| F6: graph seed ignores eligibility and entity boundaries | Choose from canonically eligible facts using whole entities, longest match first; expose the seed in component coverage. |
| F7: known unrecordable effects still dispatch | Preflight canonical per-record embedding/MCP capacity before approval or egress. Preserve ordinary aggregate byte/event sealing semantics. |
| F8: IPv6 wildcard escapes listener admission | Inspect both caller-side TCP tables under their shared bound and refuse any same-port IPv6 listener. |
| F9: unused MCP permissions accepted | Require Graph's retrieval registry to be empty and Research retrieval entries to be BM25. |
| F10a: negative-only assertions disappear | Keep eligible negative assertions as attributed context without traversing their objects. Distinguish negative context from counterassertions. |
| F10b: Unicode token/window mismatch | Use one normalized token stream retaining original UTF8 byte offsets for both matching and excerpts. |
| F10c: unrelated failures become missing embeddings | Preserve stage errors and allow missing-embedding fallback only for that actual condition. |
| F10d: tautological raw input hash | Remove the self-comparison; retain the host's original typed input/binding checks. |
| F10e: remaining time sampled twice | Sample once for each adapter decision and pass that exact remaining value. |
| F11: definite quota refusal becomes unknown | State returns a closed known-failure receipt for record, encoded-file and revision quotas before publication. Other uncertain IO retains unknown semantics. |
| F12: live handlers lack producer-open guard | No demonstrated defect: both independent reviewers traced Worker enforcement and saved-state rejection and found no reachable public sequence. Retain as defense in depth rather than widening this repair. |
| D1–D5: stale status and incomplete manuals | Reconcile plan/history and teach remote query/CAS contracts, limits, examples and recovery in the authoritative manuals; inventory the environment helper. |

The initial client-only capacity proposal was insufficient: two coordinated
writers each reading 86 records both admitted two additions and reached 90.
The selected remote-owner quota therefore applies under its transaction lock
to every writer version. V3 changes the inner envelope version, retaining the
V2 action fields and stored format. Cutover requires draining legacy writers,
qualifying the server and reconciling existing over-capacity partitions.

The listener defect reproduced against the original native code with a real
IPv4-loopback/IPv6-only-wildcard pair. The repaired native source passed nine
isolated Linux tests, including actual procfs admission and refusal controls.
The rebuilt baseline SDK plus repaired helper then passed all eight maintained
public listener cases, two metadata requests, zero inference requests and
confirmed cleanup. Two preliminary public-proof attempts timed out because
their reused SDK lacked the listener option; those are retained failed setups.
These focused checks are not an integrated corrected-source baseline.

## Independent review of the complete milestone

Two fresh read-only reviewers used the same whole-P27 intent and rubric, with
separate model selections and no shared findings. Their retained reports are
[review A](internal-a.md) and [review B](internal-b.md); model identities and
report hashes are in the provenance file. They inspected surrounding ownership,
implementation and manuals as well as the external repair diff. Neither
established a critical defect or claimed final acceptance.

Review A reproduced a further capacity mismatch through public Graph callbacks:
nine sources with 29 facts each occupied only 144 retained records, but their
flattened 261 facts exceeded the query validator's global 256-fact ceiling.
A query for the first source's 29-fact entity then refused. Suppressing only the
unrelated ninth source restored it at the same record count. The repair derives
a query-input ceiling from 256 retained records and at most 32 facts per distinct
manifest. Store's source/profile/head ownership and cycle checks prevent one
manifest from being counted through multiple heads. The resulting 8192-row
ceiling leaves physical storage and command limits unchanged. Every fact is
validated before eligibility; the relevant claim context stays at 256. A larger
complete context returns `graph_context_limit` through Graph, Corpus graph and
hybrid, with no truncated supported claims.

Review B reproduced loss of a completed Research response with less than one
second left of its investigation allowance. The next-fetch guard ran before
checking whether any fetch remained. The repair handles an empty queue first;
actual queued fetches and model reranks retain their separate time guards.
Maintained regressions exercise the unmodified module for empty search results,
hash-valid final captures and queued-fetch refusal. The generated-clock controls
remain separately named. Focused domain/package checks pass; integrated checks
must cover the resulting source.

Both independent follow-up reviews report no new actionable finding:
[follow-up A](followup-a.md) and [follow-up B](followup-b.md). They checked the
manifest-uniqueness bound, complete-population validation, contradiction bases,
256/257-context behavior and completed Research captures. A rerun of the original
261-fact probe succeeds. Their focused fixture runs supplement source review;
they did not run the final platform, package or semantic-quality gates.

The corpus-grounded scoring and review suites pass 22 focused tests. Their
regressions include fabricated quotes marked valid by the reviewer, genuine
bytes marked invalid, wrong reference offsets, corpus corruption and loader
ordering. State's 12 focused tests cover record quotas, the encoded-file quota
and maximum valid generation. Eight manual build/configuration/import/selection
combinations pass through the CLI. The independent post-repair reviews above
are complete.

## Final repair verification

Both platforms pass against the same [460-file runtime/test inventory](runtime-source.json),
SHA256 `73dd60daefd6098be2329e26a4e8b3525e321ad9128b775545a901e2832ab29a`.
The [verification receipt](verification.json) retains step results, log hashes
and package hashes. Each platform's final inventory matches the frozen input.

| Platform | Full suite | Additional checks |
| --- | --- | --- |
| macOS, Elixir 1.20.3 / OTP 29 | 1,344 passed, one skipped, 36 excluded | Build, format, strict compile, demo, 30 focused native tests, portable Rust controls, 15 independently built presets, source and installed knowledge/recovery/lifecycle/MCP/embedding proofs and extracted-package verification |
| Linux, Elixir 1.20.4 / OTP 29 | 1,383 passed, 19 excluded, native sandbox enabled | Fresh isolated build, format, strict compile, demo, Linux Rust controls, the same 15 presets, source and installed domain/host proofs and extracted-package verification |

The final controllers initially stopped while saving the last host MCP proof:
its log filename duplicated the earlier knowledge MCP proof's filename. Earlier
successful logs were preserved. A corrected finalizer captured a fresh isolated
host MCP proof under a distinct name and completed source-inventory verification.
This was a controller bookkeeping failure; no product source changed or full
suite was replayed. The receipts retain the recovery explicitly.

The manuals' complete examples, task flow, limits and recovery guidance were
reviewed against source and the runnable examples above. The documentation
checker reports 279 Markdown files, 2,928 local links and zero errors. These are
credential-free fixture and installed-runtime checks. They establish no live
external service compatibility, real cgroup measurement or model quality. The
packages precede the final documentation receipts, so the shared inventory binds
runtime/test source rather than claiming identical archive documentation bytes.

The earlier 350-row comparison remains a negative historical result from its
older predictor. Its exposed inputs are diagnostic material. No repaired-source
held-out quality, matched resource comparison or engine selection is claimed.
The next final validation uses a newly and independently authored private
50-question workload. Its answers remain sealed until predictions are frozen;
the exposed earlier questions are available only for tuning.
Whole-codebase structural consolidation and corresponding review of all user
and developer documentation are also required before P27 completion. That work
follows feature and review remediation and covers all code roots and tooling.
