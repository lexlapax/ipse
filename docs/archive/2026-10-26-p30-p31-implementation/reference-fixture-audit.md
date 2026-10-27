Historical-only independent scoped review, finalized **2026-10-27**. Literal
report preserved below from owner-only evidence; original SHA256:
`46f61d6a678619c2b8aac96d5f314aa0eac551950d0ae3f7922055017352e451`.
The [repair receipt](reference-fixture-repair.md) records actual combined tests;
the [plan](../../plan.md) owns remaining implementation and acceptance.

# Independent post-repair fixture review

2026-10-27. Review base `2ab411bf4064b6b981e135db4d89418a5b84c758`. No repository, index, active full-suite graph, compile cache or shared helper was changed by this auditor.

## Verdict and independence

No actionable fixture defect or weakened authority, no-replay or history assertion was found in the nine Root-owned fixture corrections independently reviewed here. The whole developer testing chapter was read with its diff; one concrete pre-existing P3 documentation inconsistency was reported and corrected by Root. All 17 fresh actual Feed.Model controls passed. The original before-source control reproduces the extra tool proposal caused by a valid Reference after a completed tool group.

The twelve frozen changed fixture files include three files previously authored by this auditor: `mcp/catalog_session_test.exs`, `mcp/session_test.exs`, and `session/permissions_test.exs`. Those three are **excluded from the independent-review claim**. Their earlier 20 MCP and seven permissions controls already have durable reports under `independent-mcp-fixture-triage` and `independent-permissions-fixture-triage`; they were not rerun. Decision's separately committed questions changes and the Git-aware declaration fixture setup are outside the independent code-review scope here.

This is a scoped fixture audit, not a whole-milestone or production-runtime audit.

## Frozen evidence

Immutable owner graph: `/tmp/ipse-reference-fixture-repair-20261027-02`. Its 2,303-input source/runtime manifest SHA256 is `a25520ddda629e3f9120e2d52e0fa866985047e2b7b8d6f1567c56ca6082255b`. The auditor copied only the twelve changed fixture sources, relevant inspection sources, the complete testing chapter, and 30 minimal runtime files (Jason plus actual Ipse.JSON and Session.Reference BEAMs). Forty-two selected fixture/runtime inputs were checked against that owner's manifest before copying and checked exact in owner and independent copy afterward. No native helper was needed or executed.

Independent working root: `/tmp/ipse-independent-reference-fixture-audit-20261027`. `selected-inputs.json`, `verify-after-final.log` and the durable files manifest bind the exact source/runtime bytes. `reviewed.diff` retains all twelve fixture diffs plus the chapter diff, SHA256 `720451f49564b6843d0b360179e0a2d85539ff5a4a1a602b471ccaf2f5ace8a3`.

Original full baseline evidence was read from durable `full-baseline-first-failed`; its complete original log is copied to `before/tests-first.log`, SHA256 `1a95d031d2c25eaf0ed205ce57137eec41608921441a61858ca4ae16e40a05dc`. It reports 2,374/2,418 passing, i.e. 44 failures, with four skipped and 36 excluded. That original failure is retained and is not reclassified as a pass. Root02's focused `tests-focused-first.log` is **owner evidence**, reporting 157/157 including Decision's questions and two declaration cases; it was inspected but not unnecessarily rerun or relabeled independent. The active full-suite repeat was not read as a finished pass or modified.

## Independent static review of the nine files

| Fixture | Original failure and retained property |
| --- | --- |
| `extension/feeds_test.exs` | Raw List.last role mistook appended user-role Reference for another task, causing repeated proposals and missing done events. Only the fake's action-selection view now rejects messages passing the actual public Reference validator. Its callback still sends the entire original input for assertions; no approval, outcome, cancellation or journal assertion was removed. |
| `extension/session_test.exs` | Exact three-message patterns missed the fourth Reference. Both cases now require that exact additional message to validate. Restore requires the exact original user, exact saved selection and original assistant/provider continuation. Transform ordering and projection/history assertions remain. |
| `extension/subscriptions_test.exs` | Exact three-message pattern missed the fourth Reference. The new pattern requires the selection and validates it; original/effective prompt trace equality and ordering assertions remain. |
| `extension/text_test.exs` | Mailbox already contained completed turn and unchanged original text, but exact three-message pattern failed. New exact four-message pattern retains literal original input and additionally validates the selection. Worker-frame/privacy/order assertions remain. |
| `mcp/http_test.exs` | Journal was captured before explicit Session.close, which appends a lifecycle close receipt. The repair requires the old event list to be an exact prefix, exactly one additional receipt with the same session ID, close reason and confirmed cleanup, then exact closed journal on idle resume. Unknown/not_started outcomes, one actual external request, and no replay remain exact. |
| `session/saved_test.exs` | Raw final message was a Reference, while fresh task still existed immediately before it. The new exact final pair requires the exact fresh user task and validated selection. Approval denial, original handoff evidence, no source-session creation and absent never-replay file remain asserted. |
| `tools/delegation_parallel_test.exs` | Both failing journal comparisons were pre-close versus post-close. Both now require exact old prefix, exactly one confirmed same-session close receipt and exact journal on idle resume. Child overlap/routing, tool restrictions, separate approvals, result order/source checks, stopped workers, no child restart and configuration mismatch assertions remain unchanged. |
| `workspace_integration_test.exs` | New selection follows the actual skill/task message. New four-message pattern and final pair explicitly validate it while retaining original catalog placement, scope, changed-body and refresh requirements. |
| `workspace_resources_test.exs` | Both generated source cases compared pre-close versus post-close journals. The new exact prefix/single close receipt/exact resumed history preserves all records. Original recorded resource bytes, modified-file refusal to replace history, one tool start and exact retained result remain asserted. |

The unchanged production Session.handle_call(:close) calls close_epoch with cleanup result; RuntimeLifecycle.close emits the specific lifecycle_epoch_closed record. This matches the stricter prefix-plus-single-receipt fixture repair. It does not justify allowing arbitrary extra history, extra effects, replay or lost receipts, and the actual patches permit none of those.

The retained failure mailbox examples explicitly contain the extra selection and already-completed turn (e.g. text and workspace cases); saved handoff failure shows the selection as raw last input. Feed's original-source negative control independently identifies the fake-action bug, without invoking real tools or changing production dispatch. The original declaration failures explicitly report absence of Git metadata, supporting the new setup note; this audit did not rerun that workflow. Question corruption/checkpoint details in the added manual paragraph are not independently re-audited here.

## Fresh actual Feed.Model controls

`fresh-feed-controls.exs` parses the frozen actual fixture and compiles its exact unmodified nested Model body, qualifying only its enclosing module name to the actual `Ipse.Extension.FeedsTest.Model`. It does not reimplement the selection logic. The body AST SHA256 is `86ffbecc22f1d5df3ae415f08d6e887f0c1d643e1d8affa5bd35d60ac3f2e8b0`. Actual frozen Session.Reference and JSON BEAMs validate the messages. No application/native/model service is started; returned fixture tool proposals remain inert.

**17/17 controls passed**, with full original input equality checked on every fixture callback:

- Completed tool tail produces zero further proposals, with zero, one or two genuine current Reference messages.
- A genuine real user task preceding a Reference remains a task; a new real user after a Reference remains a task.
- Child delegation origin still suppresses proposals even with a real user and valid Reference.
- Eleven malformed/non-reference user messages remain visible to the fake's task selection: mismatched digest, changed body, uppercase session ID, missing/extra marker key, floating version, zero epoch, nonzero policy generation, non-map marker, reference label without marker, and ordinary user text mentioning reference markers. Each produces the expected exact write proposal instead of being dropped.

The positive completed tool tail also passes actual safe_tail validation. These controls test fixture selection; they do not authenticate operator intent or grant production authority.

`fresh-feed-controls-before.exs` differs only in selecting frozen HEAD before-source. Its same completed-tool positive control passes; its next unchanged valid-Reference control fails as expected with one proposal versus zero. Its body AST SHA256 is `abee83ca306db7bcd5e410e2faac6bff13e5a6285e55680bebf1b2937534f0db`. Full raw failure is retained. This before/after evidence diagnoses the fake, not an automatic replay by the real host.

Commands actually run from the independent root:

```sh
elixir fresh-feed-controls-before.exs   # expected assertion failure: one extra proposal
elixir fresh-feed-controls.exs          # 17 controls passed
elixir verify-after.exs                 # all 42 selected bytes unchanged; exact doc correction
```

Driver SHA256 `49b3b33b25281a58bca0f042c46aa37b73c84debdaa74cd40ebc9759eb272943`; final log `51513bcc4b29d66d53be19aa19536efd39c9dd29b72599ffc3595a316f96ce2f`. Before driver `8676c6bd30fcfa397f99a584054845c0052d4af910f6cf967b5fb4ea36e3634b`; before log `8cded2d43c7f5fe59923ed124e31b9a449da13f4dfd8072a4101790298a2c850`.

## Accepted P3 documentation correction

The new testing guidance correctly restricts fake filtering to the public validator, retains complete provider input and malformed/ordinary users, distinguishes close receipts from effect replay, and requires actual Git metadata for the declaration fixture.

The whole-chapter read found a **pre-existing** contradiction outside those inserted paragraphs: line 365 said the hosted matrix allows 60 minutes, while the final paragraph at line 575 still said 45. Actual `.github/workflows/ci.yml:12` sets timeout-minutes: 60. Root accepted the finding and changed only that final 45 to 60. This auditor made no public edit.

The original reviewed chapter is retained as `docs/testing.md`, SHA256 `e43829e9e69aeade3ccaaa2f3128780edfab7ad342e0677e5c678543a0af1ddf`. Corrected chapter `docs/testing-after.md`, SHA256 `12451aee840b255e6fd58e534dae0debca9f6b535f4f7f11cc1b5dfa02b4b199`. The after-verifier proves that the entire difference is exactly that replacement. Workflow evidence is `docs/ci.yml`, SHA256 `7418270721bbbf0e15bb8271f17e7a126a5d328c00185b4e154ac857244d1375`.

## Retained audit-harness corrections

The first Feed driver assumed the source file's AST was a bare defmodule, but the actual file has a leading Code.require_file. It failed before executing any control. The raw script/log are preserved as `fresh-feed-controls-first.exs`/`fresh-feed-controls-first.log`. The correction locates the actual outer defmodule in its top-level block; Model body and all control assertions remain unchanged.

The initial snapshot flattened fixture basenames, so extension/session_test.exs was overwritten in the auditor's copy by mcp/session_test.exs. The original selected manifest and failed after-check exposed this; owner hashes were exact. `selected-inputs-first.json`, `verify-after-first.exs`/`.log`, `verify-after-diagnostic.log` and `repair-copy-names.exs`/`.log` preserve the error and correction. Both session files were copied under distinct names using their original hashes, and their original before-sources were retained separately. The initial flat session_test file remains historical data. No owner input, runtime file, reviewed diff or Feed input was changed; Feed probes were unaffected. Final all-42 checks pass. No initial failure is presented as a passing run.

## Limits and preservation

This review claims independent static scrutiny of nine fixture diffs and the whole testing chapter, plus fresh direct actual Feed.Model behavior controls. It does not rerun the 157-case owner suite, questions, the previous MCP/permissions triages, current full suite, production managed read/write integration, native guarantees, packaging, live providers, quality or whole milestone acceptance. Documentation examples unrelated to this fixture change were read, not executed. No new broad quality or platform claim follows from these fixes.

The durable evidence copy contains the minimal executable runtime, exact selected source/before-source files, original failed baseline log, owner focused log, reviewed diff, both documentation versions, original failing auditor drivers/manifests and corrected drivers/raw results. Owner-only directories/files, every copied byte, selected hashes and fsync are checked by the preservation script and receipt. Run only new working copies of evidence; selected inputs originally use historical absolute paths, so adapt only those verification paths in a disposable copy. The Feed driver itself uses its own __DIR__ and replays directly with the retained minimal runtime.
