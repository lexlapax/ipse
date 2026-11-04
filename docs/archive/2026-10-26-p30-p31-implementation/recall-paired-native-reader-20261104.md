# Root-checked paired literal reads — 2026-11-04

Historical paired-reader evidence. The later
[coalesced notes Worker-input reader](coalesced-worker-readview-20261104.md)
supersedes the notes fast path while retaining pairs for genuine initial capacity
fallback and the existing document route. This record preserves its original
qualification and failed retained reads.

This checkpoint records a bounded worker-observation optimization, its focused
controls and a private storage comparison. It does **not** qualify retained
2,000-note recall, a complete populated day, annual throughput or P31 completion.
The [plan](../../plan.md) owns acceptance; the
[Collection SDK](../../developer/collection-sdk.md) explains ownership and
[native knowledge procedures](../../operator/knowledge-permissions.md#use-bounded-current-note-recall)
remain the operator manual. Earlier failed consumers stay unknown and are never
automatically replayed.

## Keep the two retained read failures distinct

Both reads used the frozen c8245f87 runtime. The first, untraced consumer
delivered 21 Worker inputs and left its 22nd unknown with unconfirmed cleanup.
Its exact public error matched `owned_task_cleanup_failed`. No provider admission
was recorded, and its particular cleanup cause remains unresolved. The inner
preservation verifier passed unchanged original bytes/identities, control and
external evidence; the original outer metadata postcheck failed. That outer
failure is retained rather than relabelled as an all-green integrity receipt.

A separate fresh traced consumer delivered all 29 staged inputs, with 27
eligible notes, then reached the existing 120-second Host read deadline around
122.86 seconds. Native cleanup was confirmed; the pending five-second Worker
timer had not expired. A pure replay showed that its next request still fit the
existing SDK/frame limits. Its declared original, control, runtime, pathset and
outer preservation checks passed under its explicit retained-lock timestamp
contract. The bounded 17-function trace observed 1,788 events with no observed
overflow; it stopped deliberately and was not a complete execution trace.

The later deadline diagnosis does not explain the earlier cleanup failure.
Neither original was resumed or retried. The
[safe failure projection](recall-paired-native-reader-20261104/failed-reads-safe.json)
retains separate source receipt hashes, error hashes, counts and preservation
outcomes without text, arguments or private transcripts. Source-cache inheritance
was already present across admitted task, inference-slot and controlled-child
scopes; no missing bridge, cache exhaustion or permission-cache remedy was
established.

## Reuse identity within a pass, retain current owners at use

Worker delivery retains two independent protected observations and a final
actual native Collection owner. Successful authenticated version-4 literal
observations now supply their exact current root identity for version-3 root
comparisons in the **same** pass. Conflicting roots refuse. Each independent
pass starts fresh, and the final native root still must match all current
dependencies. No source, permission, lifetime or native lease is cached by this
identity reuse.

The worker's literal batch now groups two notes per existing held notes-reader
callback. Each pair uses 26 of the existing 32 observation units under one
actual Collection owner and one current quota inventory. The unchanged
record/format/live-page/anchor-page algorithm returns the same bounded witnesses
and records, and the native owner checks/releases before historical data escape
or source IO proceeds. Root versions 4/5 and exact equality across pairs are
required. Ordinary notes callbacks, public worker schemas, native protocols,
source/permission checks and deadlines are unchanged.

The old `managed_records` ReadView path and its corruption/barrier controls are
preserved. The new host-internal worker path creates no ReadView cache, so the
cache's separate four-MiB encoded envelope does not apply there. Its existing
eight-MiB decoded block bound, 8,192-record index ceiling, selected value/reply
bounds and 26-of-32-unit pair remain. This deliberate availability/resource
difference is not an identical-refusal claim outside the old cache envelope.

The [four-file source/test snapshot](recall-paired-native-reader-20261104/source.patch)
has SHA256 `57d411afed6313cfc8241a360bd41905bda01fe341b4d581479b026afc01cd5c`.
It is based on the reviewed 3226aab5 source. Paired isolated executions use the
complete c824 SDK with only the two reviewed App-module overrides; the earlier
root-reuse-only execution changes one module. Main's subsequent complete build
and focused verification are recorded separately below.
The [independent review](recall-paired-native-reader-20261104/independent-review.md)
records the callback-shape issue caught and corrected before execution, exact
owner/budget/witness checks, and explicitly unexecuted internal-pass root-change
interpositions. No production test hook was added.

## Focused controls and main integration

| Control | Actual outcome | Scope |
| --- | --- | --- |
| Root-reuse split8 Worker case | 1 passed, 201 excluded; 22.0 s | Authentic mixed v3/v4 equivalence, two independent passes without extra root reads, v3-only fallback and unchanged stale/source/expiry/revocation refusals; all postchecks zero. This is one case, not eight passed tests. |
| Paired storage and existing native fences | 5 passed, 50 excluded; 3.4 s | Three genuine signed literals equal old batch and singular observations; quota calls 16→2, invalid/33-request refusals; old ReadView native owner/root-change controls remain intact. All six postchecks zero. |
| 33 distinct storage observations | 1 passed, 54 excluded; 3.7 s | Exact old/paired 32+1 outputs and order, quota counts 16+1, and direct 33-request refusal before inventory. All six postchecks zero. |
| Fresh paired split8 Worker case | 1 passed, 201 excluded; 19.9 s | Genuine eight-original-source caller with both reviewed App overrides; exact facts, independent pass counters, stale/source/expiry/revocation refusals and all seed/private/driver/pathset/runtime checks passed. Operator lock and matching processes were clear afterward. |
| Integrated main native checks | 14 passed, 49 excluded; 17.1 s | Formatted main source, paired observations/33 boundary and the complete held-reader module; source/runtime/helper postchecks passed. |

The [qualification ledger](recall-paired-native-reader-20261104/qualification.json)
and [evidence manifest](recall-paired-native-reader-20261104/evidence.sha256) retain
separate exact results. Earlier root-reuse setup closure failures remain retained;
no failed or unknown effect was replayed to produce these results. Old controls
for worker input, post-egress result withdrawal and native source-owner loss
have [explicit individual scopes](recall-paired-native-reader-20261104/existing-controls.md).
They are not relabelled as deterministic root changes between these internal
passes or after the second observation before the final native owner.

The four formatted main files have the same normalized Elixir syntax trees as
the qualified patch. Main's strict test-runtime compile and complete
`IPSE_BUILD_PDF=0 ./dev/build.sh` each compiled all 197 host source files without
warnings. The actual 241 declared modules and Bootstrap resolved inside the
built application; all 2,564 distinct host imports resolved. All four normal
bundle payloads were independently imported and their digests matched the
catalog. This check started no Ipse application or domain worker. See the
[complete closure](recall-paired-native-reader-20261104/main-closure.json),
[focused output](recall-paired-native-reader-20261104/main-focused.log) and
[main check summary](recall-paired-native-reader-20261104/main-checks.json).

Full formatting and the credential-free demo passed, and all 291 pinned main
source/test inputs remained unchanged by verification. The first isolated-home
demo attempt failed before application startup because that home had no Hex
archive. A fresh isolated home with the already pinned local Mix archive passed;
nothing was installed and no model service was used. The complete combined
regression remains open. These checks identify 3226aab5 plus the reviewed overlay,
not a retroactive pass for an earlier full-suite failure.

The focused run's runtime postcheck passed before the complete build. That build
then intentionally regenerated nine bundle files and changed no host test-runtime
file. Reapplying the earlier runtime inventory afterward reported those nine
changes; the [build delta](recall-paired-native-reader-20261104/main-runtime-build-delta.json)
and fresh post-build inventory/closure checks record the separate phases.

The unmodified [documentation check](recall-paired-native-reader-20261104/main-docs.txt)
passes on the Git-rooted public candidate: 1,180 Markdown files, 9,677 local
links and zero errors. An earlier invocation in a non-Git scratch mirror found
zero documents and was discarded as an invalid input scope.

## Populated storage comparison

A fresh private copy of only the retained Collection preserved its 2,197-entry,
7,523,976-byte physical history geometry. The instrumented storage-only script
used unchanged public APIs for note/format/override get, live-page neighbors/get
and anchor-page neighbors/get. No Identity/Consent data, original native lock,
Session, provider, native Input or signed current-use authority was involved.
The Ipse application was not started.

| Literal observations | Single ReadView | Held pairs | Quota calls, view / pairs | Full index loads, view / pairs |
| --- | --- | --- | --- | --- |
| 8 | 1.134198 s | 0.631510 s | 41 / 4 | 1 / 4 |
| 32 | 4.137636 s | 2.498113 s | 161 / 16 | 1 / 16 |

Complete observations matched exactly. At 32 literals the paired route was
about 40% faster, while quota-call elapsed time fell 1.192354→0.093757 seconds.
Repeated full index loads and immutable reads offset much of the structural
saving; native read calls rose 170→800. These are single S1/A1 measurements in
view-then-pairs order, with return-trace message/copy overhead. Full load time
was counted, not independently timed. They are neither untraced latency nor
p95/annual/reference-hardware qualification. The
[storage report](recall-paired-native-reader-20261104/storage-review.md) and
[exact aggregate result](recall-paired-native-reader-20261104/storage-result.json)
retain the unchanged original byte/identity and complete SDK/path/link checks.
An earlier attempt failed its local preflight because it omitted dependency
leaves from the full pathset; it dispatched no native call and remains preserved.

## What remains open

After focused integration, a **new distinct ordinary retained-cohort read**
needs its own reviewed final runtime and result record. This checkpoint records
no such successful read. The current normal bundle differs from the cohort's
reviewed artifact, so the next check also needs ordinary current-artifact review,
compatible retained records and preserved routes, budgets and liabilities.
A complete populated day must then establish actual
Session/model/effect cost before projecting 14,600 turns or running annual
qualification. Full notes acceptance, quality, broader current-use/owner/cross-
batch adversarial coverage, installed and platform evidence remain separate.
No deadline, cache capacity, read budget or permission guard was relaxed here.
