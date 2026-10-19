# Whole-run capacity and source identity, 2026-10-19

Historical implementation and verification record after `dd02f56`. The
containing commit owns these corrections. Current procedures are in the
[evaluation manual](../../developer/knowledge-evaluation.md#follow-a-matched-public-session-comparison)
and [verification training](../../developer/testing.md#distinguish-presentation-from-completion).
This work does not complete P27, expose held-out inputs or measure model quality.

## Reproduce the whole-run call ceiling

The declared fifty-question Research workload can require one search and ten
fetches per question, or 550 calls. The controlled gateway's hard-coded whole-run
cap was 512. A framed loopback regression failed during a fetch at question 47;
three of four service tests passed, seed 595319. Changing project documents or
beginning a query correctly did not renew that cap.

The gateway now accepts an explicit finite allowance, retaining the 512-call
default. The runner derives its allowance from the validated query count and
per-question source bound. Supported inputs cap it at 11264 calls. Invalid
limits refuse before listening. Constant-time counters enforce exhaustion,
and unknown tool metadata is recorded as `other`.

All 550 declared calls now succeed. Call 551 refuses after document selection
and query changes, with no renewal. The bounded log retains 550 records, while
the separate summary retains total decoded requests and over-limit refusals.
The service suite passed five tests in 0.4 seconds, seed 905131. The complete
declaration, service and Session matrix passed nineteen tests in 138.6 seconds,
seed 290183. That pass preceded the later identity controls below.

## Reproduce the independent per-invocation fetch ceiling

The runner's approval policy still allowed only three fetches per investigation.
A retrieval-only public-Session control supplied four selected sources. Its
first setup left an answer binding selected after disabling answers, so plan
validation correctly refused it before dispatch. Removing that unused binding
and artifact corrected the fixture.

With the three-fetch cap retained, the corrected control recorded four gateway
calls, one approval refusal and one failed prediction, seed 369364. Those calls
were one search and three fetches. The new policy uses the declared source bound
while retaining one search, one fetch per selected URI, exact descriptor binding
and complete search/fetch argument checks. The control passed in 18.0 seconds,
seed 995899, with all five calls and zero model requests.

## Distinguish identical bytes and reused version labels

The control was strengthened with two generations per source, identical body
bytes and reused version labels. Some labels were integer `1`, others string
`"1"`. The former `dataset:project:document:version` URI omitted generation and
coerced those label types to the same text.

All five calls completed without an approval refusal, but the prediction failed
because its captured citation matched more than one dataset source identity.
That retained run used seed 399972. The URI now hashes a versioned ordered JSON
array containing project, document ID, source ID, generation, typed version and
body SHA256. The corrected control passed in 18.1 seconds, seed 696849. Raw
Research capture generation remains one; the saved prediction maps to the
current dataset generation two with its exact original version type.

A separate input control exposed another ambiguity: the adapter accepted two
rows for the same project/source/generation if their version labels differed.
That run passed four of five input tests, seed 91816. Duplicate generation
validation now ignores document IDs and version labels. Another project remains
a separate valid identity. This rejects an ambiguous complete input rather than
choosing a current version by row order.

The combined input/runner/service suite then passed twenty of twenty-one tests,
seed 833299. The CLI negative fixture still supplied two versions of the same
generation; the stricter adapter correctly rejected the entire input before
prediction rows existed. That fixture now uses two valid generations with an
explicit forget followed by a refused resurrection attempt. Its original two
partial rows, first-attempt markers, completed execution and failing exit-status
assertions remain unchanged. The selected CLI and all five input tests passed
together in 24.6 seconds, seed 690511.

## Retain the hosted presentation failure

The [dd02f56 hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39257560066)
failed its Linux source step. The ordered annotation/presentation fixture had
received presentation, then waited the default 100 ms for `done`. Its mailbox
held status and usage notifications. Linux reported 1163 tests, one failure and
32 exclusions in 642.3 seconds, seed 994755. Later checks were skipped.
The macOS job completed successfully, including 1163 source tests with 32
exclusions, its separate native subset and all package/installed checks.
Every one of the 24 steps in both terminal jobs was inspected. The matrix's
overall outcome remains failure; macOS success does not erase Linux's negative.

Source order sends presentation before `finish/2` appends `turn_finished` and
notifies completion. The test's existing public state read now precedes the
unchanged `done` assertion and additionally requires idle state. That read queues
behind the same callback. Original content, presentation, private-continuation
redaction, restored native continuation, journal validation and cleanup assertions
remain. No timeout, sleep, production code or cleanup contract changed.

The selected test passed 21 iterations with the hosted seed. Those passes do not
identify why the hosted callback exceeded 100 ms. The test now verifies actual
committed completion instead of assuming a sub-100-ms gap after presentation.
The older append timeout and MCP negative evidence remain separate and unresolved.

## Final verification

The final full local suite passed 1149 tests with 17 Linux-only exclusions in
600.5 seconds, seed 721522. Strict stdio tracing and both actual macOS enforcement
tags were enabled. Build, warnings-as-errors compilation, local formatting and
pinned CI policy passed. The contributor chapters were reviewed as complete
manuals. Documentation checks covered 232 files and 2576 local links without errors.
The credential-free demo also passed with an isolated operator home and the
existing Mix toolchain.

All seven changed Elixir files also matched Elixir 1.18.5 formatting. The official
OTP-27-built distribution was verified against its published SHA256
`56a065fa2bc609f49a4a3950d509a6a9aa9a827e8610b717e6cfca74a9090580`
and ran in a private temporary directory on local OTP 29. This is a formatter
compatibility check, not hosted OTP 27 runtime verification. No source file was
rewritten while tests were active. The ordinary local suite used Elixir 1.20.3.

No package, host SDK, native helper or production Session implementation changed
in this increment. The source/installed domain checks at `dd02f56` remain distinct
from the new development-only orchestration and input controls. No release was
rebuilt or published. Full P27 quality, independent review, runtime memory
co-selection and the remaining acceptance audit stay open.

No held-out member, manifest contents or evaluator was read. All provider work
used scripted fixtures; no model weights, inference or paid provider was used.
