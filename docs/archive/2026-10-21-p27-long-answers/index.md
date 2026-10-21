# P27 bounded final-answer calls, 2026-10-21

Historical implementation and diagnostic record after
`fad2856916b658487a23375c3484b4382e3f79a9`. P27 remains open. Current operating
instructions belong to [configuration](../../operator/configuration.md#allow-a-longer-extension-answer);
contributors should use [model effects](../../developer/extension-effects.md#request-bounded-text-inference)
and [evaluation training](../../developer/knowledge-evaluation.md). Acceptance
belongs to the [plan](../../plan.md#p27-optional-research-graph-and-rag).

## Preserve the two failed operating policies

The user selected the existing pinned `qwen3.5:9b`, CPU-only execution and
reasoning for final answers only. The earlier default-thinking diagnostic
retains [eight deadline failures](../2026-10-20-p27-quality-remediation/index.md#retain-the-default-reasoning-deadline-result).

The [advisory-brevity trial](brief-trial.json) appended a fixed instruction to
aim for at most 128 reasoning tokens. That instruction was advisory, not an
enforced limit. It preserved the eight exposed inputs/schemas, 4096-token
allowance and 120000 ms request deadline. One first response decoded in
112258 ms; seven were cancelled at 120001 ms. The one decoded response described
the freshness gauge with two separately cited claims. This observation is not an
independent semantic grade or a quality improvement claim. The advisory was not
integrated into production instructions.

The [long-deadline trial](long-trial.json) retained the original instructions and
enabled default thinking, selected a version-three request, and explicitly set
root/profile/request to 480000 ms with 8192 output tokens and reservations. It
predeclared stopping on the first invocation or decode failure. Its first
lexical Q02 request timed out at 480001 ms; no answer decoded. The trial stopped
after that single admission. It used a fixed 439-file prototype inventory
`206c31b69e371e76ef1a984df1fd545bff4a607b6213bc770e929a14d004c39a`,
before the complete evaluator integration. It does not certify the final feature.

Both trials verified the pinned model's enabled default before inference,
preserved unique canonical attempts and confirmed Session, native and staging
cleanup. Their source inventories remained unchanged. There were no retries,
private workload reads, model/provider switches or matched resource claims.
The long trial's initial preparation refused a missing directory argument;
another preparation refused macOS archive metadata that doubled the file
inventory. Neither preparation reached inference. A fresh metadata-free source
snapshot produced the retained single actual attempt.

## Keep the longer allowance explicit

The repair adds no SDK generation or invocation timer. `model.complete` version
three shares version two's structured response and byte bounds, with a bounded
600000 ms request ceiling. An operator-only profile field explicitly grants
the longer model-call allowance; root policy and each request still narrow it.
Absent that field, old snapshot bytes and the 120000 ms ceiling are preserved.
Project configuration cannot grant the override, ordinary main/child settings
exclude it, and saved-source validation still requires exact captured execution.

The existing SDK-1 answer helper forwards the complete prepared request. The
evaluator has a separate closed policy for version-three answers while keeping
extraction and rerank at version two, 4096 tokens and explicit thinking suppression.
The real measured path verifies the answer model's enabled default in each owned
cell. SDK-2 aggregate/read/publication limits remain unchanged. Scoring binds the
chosen policy and retains the individual 90%/95% qualification gates.

The [host review](review-a.md) and [evaluation review](review-b.md) found no
defects in the scoped implementation. They are independent source reviews,
not execution proofs or whole-P27 acceptance. The [whole-manual review](manual-review.md)
found one stale selection reference; the README now names the two version-two
selections explicitly. Source/installed synthetic selections exercise the longer
policy without claiming actual model quality or long generation.

## Observe one completed CPU answer

The [combined diagnostic](concise-long-trial.json) used the advisory instruction,
8192 output tokens and a 600000 ms deadline. It predeclared exactly one exposed
lexical Q02 admission and stopped afterward. Its final answer decoded in
457545 ms. Canonical usage records 1400 input tokens and 1709 output tokens;
the separate reasoning-token count is unavailable. The cited freshness statement
supports the final claim, according to supervisor inspection. This is not an
independent semantic grade or a workload quality result.

The service verified enabled default thinking and the same pinned model. Session,
native and staging cleanup were confirmed. Source remained unchanged. The helper
was a separately hashed diagnostic clone with the advisory instruction;
production answer instructions stayed unchanged. No further batch ran.

Repeating that duration for 350 answers would take about 44.5 hours before
preparation, beyond the existing one-day measured-root limit. That multiplication
illustrates scale, not a runtime forecast. The user chose to wait for GPU repair
instead of preparing a multi-day CPU comparison. Read-only host diagnostics found
an older running kernel and loaded NVIDIA module than the installed packages,
with an NVML driver/library mismatch. No host repair was attempted by this agent.

Final operating-policy selection and the new private evaluation freeze remain
open. A repaired GPU will still need an explicit benchmark device policy;
the current owned-service selection deliberately forces CPU execution. No engine
has been selected, and the private workload remains sealed.

## Retain completed platform verification

The [verification receipt](verification.json) records completed checks for
`fda3841290cf4042698c42202ba2b539f063108f`. Its runtime inventory contains
439 files with SHA-256
`480a2d6adc8bfdb1268da6bf9540b95056086ef5245827bfa2335d77caf91787`.
Both platforms preserve that inventory after their package proofs.

| Check | Result and scope |
| --- | --- |
| macOS build, format, strict compile, full suite and demo | Passed; 1,446 tests passed, one skipped and 36 excluded |
| macOS native enforcement and stdio | Passed; 30 tests passed and six excluded |
| macOS fresh package and installed proofs | Passed; package, version-three structured answer and legacy `json-none` selections |
| Linux build, format, strict compile, native-enabled full suite, demo and docs | Passed; 1,488 tests passed and 19 excluded |
| Linux fresh package and installed package | Passed |
| Linux source and installed structured-answer proofs | Passed with `json-long` |
| Linux source and installed measured populations | Passed with `sealed-long-answers`; each saved 350 synthetic rows with complete execution and resource audits |
| Supported Elixir 1.18.5 and OTP 27 | Strict compile rebuilt 131 current files; 68 focused tests passed |

These measured populations use scripted responses. They verify the longer answer
contract, first-prediction preservation, native charged-memory collection and
audit admission. They establish no actual-model quality or matched-model
resource result. All 21 Linux batch steps exited successfully. The final
source inventory was unchanged, its controller exited, and no temporary
measurement units remained when the host was cleared for reboot.

The [hosted run for `fda3841`](https://github.com/lexlapax/ipse/actions/runs/39630222410)
failed the Elixir 1.18 formatter before tests. Commit
`01303641d36b35183de9e4703314f39f446310f9` replaces two consecutive `Map.put`
calls with an equivalent `Map.merge`. Both supported formatters and 14 affected
Answer tests pass after that correction. The current runtime inventory is
439 files with SHA-256
`c20a322fc43e2030d4ee70652c02593370c873ae8ab643e2e579e9de01290ff2`.
The [exact corrected-commit hosted run](https://github.com/lexlapax/ipse/actions/runs/39631577148)
was in progress when the platform receipt was recorded. The broader results above
remain attributed to `fda3841`; the formatter correction does not turn them into
exact-commit execution evidence for `0130364`.

## Preserve the later hosted CLI timeout

The same corrected-commit run subsequently finished its macOS test step with
one failure. It reported 1,483 tests, one failure, 36 excluded and one skipped
in 1,770 seconds. The captured-evaluator declaration CLI test exhausted its
default 60-second watchdog during its third plain CLI invocation. The stack
stopped in `System.cmd/3`; it does not identify a child operation or prove a
deadlock. Native enforcement, packaging and later installed proofs did not run
in that macOS job. Ubuntu remained in progress at this observation.

The test makes seven CLI invocations in total. Its individual runtime-identity,
relative-path, changed-code and unopened-input assertions remain intact. Only
this test receives a finite 120-second whole-sequence watchdog, consistent
with the existing multi-CLI observation budget. No runtime, model-call, Worker
or native deadline changes. The original test passed locally in 26.1 seconds
with the hosted seed, so that local check does not reproduce the hosted delay.
Both corrected CLI exercises passed locally in 42.4 seconds. A fresh local
Elixir 1.18.5/OTP 27 checkout passed both exercises too, with compilation and test
execution together taking 47.7 seconds. Its whole-tree format check passed.
The contributor testing chapter was read in full; its proof-selection table
also needed the existing `json-long` and `sealed-long-answers` selections.
Its documented two-test command passed, and the documentation checker found
zero errors. A fresh hosted result remains a separate gate.
