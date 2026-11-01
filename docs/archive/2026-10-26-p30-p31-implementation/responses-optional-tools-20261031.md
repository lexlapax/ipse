# Preserve optional tool arguments in OpenAI Responses

2026-10-31, increment based on `af5b70a`. This is a focused provider repair and
exposed development investigation, not P31I completion or independent quality
acceptance. The [plan](../../plan.md) owns status. Current provider ownership is
taught in [architecture](../../developer/architecture.md#trace-prompt-admission-and-the-provider-response);
the [operator procedure](../../operator/usage.md#refine-a-request-before-submitting-it)
retains the draft workflow and its limits.

## Failure and implementation

A prepared native-terminal `/enhance` journey used Ipse's actual configured
ChatGPT subscription route and requested `gpt-6.1-sol`, with synthetic data and a
hard four-request shared budget. Its first two attempted reads filled every
optional field, combining line options with binary encoding and a placeholder
expected hash. Both refused. A proposed shell alternative was denied by the
draft ceiling. The three-step draft limit was reached without obtaining context
or asking its material question. Native cancellation and an unrelated exact-word
request succeeded; no workspace mutation occurred.

The adapter had omitted `strict` for these function definitions. The
[official function-calling documentation](https://developers.openai.com/api/docs/guides/function-calling#strict-mode)
states that Responses attempts strict normalization when the flag is absent;
preserving optional fields requires an explicit non-strict choice or an appropriate
nullable strict schema. The [migration guide](https://developers.openai.com/api/docs/guides/migrate-to-responses#5-update-function-definitions-and-outputs)
also documents the explicit opt-out. The [item reference](https://developers.openai.com/api/reference/resources/conversations/subresources/items/methods/create)
permits the flag on functions in `additional_tools`. This explains a concrete
compatibility risk consistent with the observed filled arguments; the investigation
did not inspect a private server's normalized schema or claim deterministic model
behavior from one exposed case.

`Provider.OpenAI` now supplies `strict: false` when an OpenAI or ChatGPT function
does not already select a strict contract. Parameters remain unchanged and
`{"path":"project-brief.md"}` remains a valid complete text read. Explicit strict
contracts survive. Both API top-level tools and subscription `additional_tools`
use the mapping; Grok's separate mapping is unchanged. The host still validates
arguments, source access, execution ceilings and approvals. No model, billing,
endpoint, tool authority, dependency or public SDK contract changed.

## Actual post-repair result

A separate fresh native Session used the same exposed synthetic task and another
hard four-request budget. The first call read the brief with only `path`. The
second asked solely about rollback tolerance, without re-asking the supplied
target, maintenance window or owner. The exact native choice reached the main
model. The third streamed a proposal using those requirements but exceeded the
existing64KiB response bound. Its outcome is **failed/partial**, and no completed
draft was committed. The limit was not increased. One unknown budget liability
remains; no manual settlement or replay was attempted.

After native cancellation, the fourth request returned exactly the unrelated
requested word. Both original journals preserve the cancelled marker; Saved
projection withholds it. Saved reconstruction succeeds, only reads started,
and the original synthetic workspace file is unchanged. The CLI exited normally.
These are visible outcome, native-input and saved-projection observations, not
independent human use or an independent outgoing-wire capture. Read-before-question
has this narrow positive; complete live draft, notes/document integration,
carryover/compaction quality and installed acceptance remain open.

The [sanitized evidence](responses-optional-tools-20261031.json) records both
Sessions, source/test and runtime hashes, four admissions each, actual completed
and partial outcomes, budgets and original journal hashes. Raw synthetic journals
and plan files remain private under `/tmp/ipse-enhance-live{,-fixed}-20261031`.
The [call ledger](live-call-accounting.md#native-enhancement-investigation-2026-10-31)
charges all eight requests:234of300conservatively charged,66remaining. Local
inference remains2of1000. Authentication stayed in Ipse's original credential
store; no auth file or private production transcript was copied.

## Verification

The initial focused provider/native-tool cohort passed34tests. Broader provider,
transport, conformance, native-tool, draft/acceptance and question controls passed
200of201; the remaining loopback wire assertion expected the former omitted flag.
After updating that exact intended wire expectation, the same cohort passed
**201 tests in16seconds**, log `/tmp/ipse-responses-optional-tools-verified-20261031.log`.
The original failed log remains. Explicit strict preservation and optional read
schemas are covered on both OpenAI routes; existing Grok controls also pass.

Standard build passed180modules and three bundles. Compile with warnings as
errors, format and credential-free demo passed. Architecture and operator Usage
were reviewed wholly; the Usage chapter's stale blanket capture-refusal statement
was reconciled with the canonical Knowledge manual's narrower supported scope.
No full-suite pass is claimed: the separate clean `e86b1b8` run excludes this repair.
The final documentation checker passed981Markdown files and8166local links with
0errors. The provider source, actual development BEAM and native helper matched
the post-repair live preflight after verification.
