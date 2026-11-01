# Repeated V3 capture through registered inference

Dated **2026-11-01**, based on `b790379` plus the focused test/manual changes
recorded here. This is synthetic source integration evidence, not P31 completion,
retention endurance, installed acceptance or model-quality evidence. Current
status belongs to the [plan](../../plan.md); procedures belong to
[testing](../../developer/testing.md#require-positive-controls-and-inspect-uncertainty)
and [notes permission](../../operator/knowledge-permissions.md).

## Preserve successful capture expectations

The old 27-publication split-fence fixture used a `provider_module` callback on
the demo route. Its first real V3 publication succeeded, but the next model
request correctly refused managed history without registered send/completion
ownership. An isolated original-source run failed **0/1, 166 excluded, 25.3s**
in `/tmp/ipse-repeated-v3-baseline-20261101.log`. The positive expectation remains
27 complete turns, rather than accepting a post-publication error as success.

The fixture now uses the existing loopback Ollama adapter, explicit registered
service and 54 finite synthetic responses. Each of 27 Sessions must finish two
completed/final requests, publish one candidate, validate Saved history, settle
accounting and close. Each then resumes idle with its exact prior bytes and
one valid ownership suffix; confirmed close changes no Worker trace. The final
visible scan must contain 27 pending records with exact text and distinct
original Session proofs. At least one publication must authenticate a nonzero
live-page split fence. Production policy limits, request deadlines and source
requirements are unchanged.

A second repaired fixture creates one genuine managed record through the same
registered route before newly reviewing a legacy reader. That reader must still
refuse the record without returning text or recording a managed read. Setup
publication and the security refusal are both required.

## Retain diagnostic failures

The first repair passed the reader case but inspected a Session after confirmed
close, causing a test-only `noproc` failure: **1/2, 165 excluded, 13.7s** in
`/tmp/ipse-repeated-v3-first-20261101.log`. Moving that inspection before close
passed **2 tests, 165 excluded, 65.7s** in
`/tmp/ipse-repeated-v3-second-20261101.log`.

The broader six-case run retained two failures: **4/6, 161 excluded, 80.2s**, log
`/tmp/ipse-repeated-v3-final-20261101.log`. Its added final inventory used raw
Collection scanning and counted four internal metadata rows alongside 27
candidates. It now uses the existing public visible scan. The concurrent-capture
fixture also exhausted its synthetic listener's five-second idle accept budget.
A speculative 30-second listener budget exposed the underlying turn failure in
the next run: **5/6, 161 excluded, 93.4s**, log
`/tmp/ipse-repeated-v3-final-second-20261101.log`. Population setup took only
267ms, ruling out the proposed setup-delay explanation. That timeout change was
reverted, without any production change.

An isolated original-timeout run retained the actual three Session journals
under `/tmp/ipse-collection-sdk-e971430d4af8f52f9138f2d209848b7d`, log
`/tmp/ipse-repeated-v3-competing-diagnostic-20261101.log`. One writer succeeded
and completed its model continuation. The other recorded a known
`collection_consent_denied` action, then its next actual Worker input was unknown:
the winner had changed the root both Workers read. A second model request from
the loser would discard that stale inherited dependency. The expected sixth
HTTP response was therefore never requested; the listener timeout had obscured
the earlier correct refusal.

The concurrency fixture still requires exactly one successful publication and
settled accounting. It now binds successful/failed turn outcomes to the actual
action result: the winner finishes two requests, while the loser retains its
known refused action and unknown input with one request. Both must close and
resume idle without callback replay. Five finite responses cover exactly those
requests, under the original listener and product deadlines. The isolated check
passed **1 test, 166 excluded, 14.4s** in
`/tmp/ipse-repeated-v3-competing-current-20261101.log`. Its retained root is
`/tmp/ipse-collection-sdk-96f14aed4492111ef2f003517af30b72`.

Before this focused repair, the whole managed Collection file was launched at
`b790379`, seed 791606. It repeatedly reproduced obsolete callback approvals and
unregistered-provider continuations, plus legacy ownership/loss assertions.
The run was deliberately interrupted; its process exit was observed. Its partial
log `/tmp/ipse-managed-collection-current-baseline-20261101.log` has no completed
aggregate and establishes no suite pass. The previous complete
[60-failure full-source result](full-suite-e86b1b8-20261031.md) remains unchanged.
Required native approval positives must be preserved when replacing those
obsolete fixtures; refusal-only assertions cannot qualify those paths.

## Final verification and limits

Final fixed-source verification passed **6 tests, 161 excluded, 75.9s**, with
terminal exit 0, seed 925051, in
`/tmp/ipse-repeated-v3-qualified-20261101.log`. The selected command was:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only registered_capture_sequence --only registered_competing --only registered_capture --max-cases 1
```

Format checking, strict compilation, CI policy and the credential-free demo
also passed, in `/tmp/ipse-repeated-v3-{format,compile,ci,demo}-qualified-20261101.log`.
The operator permission and developer testing chapters were reviewed as whole
documents and their existing capture/concurrency explanations reconciled.
Documentation checks passed **1006 Markdown files, 8364 local links, zero errors**,
in `/tmp/ipse-repeated-v3-docs-qualified-20261101.log`; inaccessible pre-existing
private ledger directories retained their directory warnings and were not opened.
The runtime, native sources, extension sources and dependency files have no diff
against `b790379`; no package or live inference was run for this test repair.

The exact test file SHA-256 is
`24b068a012eabffc0e5fdd620e76eb9806bd395cb782eb160053e4b426f8924a`;
the unchanged ProviderFixture hash is
`0092d34f9e3adeed2bf184e3ab48feabd79eeacd2b5f0e5c1b5c654ceba2dcc1`.
The matched native helper is
`5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.
`/tmp/ipse-repeated-v3-inventory-20261101.json` records the exact source/helper,
run-log, retained journal and trace hashes; its own SHA-256 is
`0384cf7a75126054525b5287fa7471ebb833f80a2351ea801986c2fae46ce1e5`.

| Retained final synthetic root suffix | Requests | Managed outcomes | Guarded inputs |
| --- | --- | --- | --- |
| `d6d6fb4e3df1cdccd6221ea6ceeb91ce` | 54 | 27 ok | 54 delivered |
| `abddde86f4fc48e17aff88fe6f911de0` | 5 | 2 ok including setup; 1 refused | 5 delivered; 1 unknown |
| `4846d3f2fa3a8e80e6fc0a0488b4a9c5` | 2 | 1 ok | 2 delivered |

Each suffix uses the prefix `/tmp/ipse-collection-sdk-`. The measured concurrent
population setup took 262ms. The six-case cohort also includes existing paged
capture, revocation and ambiguous-mapping controls; their temporary roots retain
their original cleanup behavior. These counts are not a full-suite aggregate.

The two sequence roots print as `REGISTERED_CAPTURE_ROOT`; the concurrent root
prints as `COMPETING_CAPTURE_ROOT`. They retain synthetic journals and traces.
The test changes add no dependency or runtime implementation.
No live account, model download or local inference is used. These are initial
additions with original-source and no-replay checks, not compaction, expiry,
30/90-day use, annual turnover, real model behavior or installed qualification.
The original pending-population seed remains explicit fixture data, not source
authority or a full sustainable-capacity proof. Full P30/P31, the final whole-suite
run, adversarial audit and reviewer handoff remain open.
