# Evaluation identity seal and input projection, 2026-10-19

Historical tooling increment after `2cbbd00`. The commit containing this record
adds maintained input and freeze helpers. Use the current
[evaluation training chapter](../../developer/knowledge-evaluation.md#seal-identities-before-opening-inputs)
for their exercise. Full P27 acceptance remains open in the
[plan](../../plan.md#p27-optional-research-graph-and-rag).

The query adapter projects exactly query ID, project and query text. Synthetic
controls change expected answers, classes and relevance, including invalid labels,
while requiring unchanged projected query inputs. Corpus validation retains all
generations and verifies UTF8, hashes, byte lengths and timestamps. Scoring labels
use a separate API and preserve full source identity and byte-coordinate spans.
The existing host JSON decoder supplies duplicate-key rejection and the explicit
1 MiB member ceiling. No new parser dependency or production host change is added.

The freeze helper records a clean Git commit/tree and every tracked source file,
runtime code-path BEAM files, Ipse native helpers, toolchain identity and exact
plan bytes. It uses the inert host artifact store to preserve reviewed independent
copies. Verification requires a separately retained manifest hash and rechecks
the source, runtime, plan and copied artifact identities. It refuses an existing
output directory and preserves incomplete output on failure. It opens no dataset
or provider and activates no worker. Plan policy and effect approval still belong
to the execution caller.

The first synthetic run passed eleven of twelve cases. The remaining control
showed that an array could be sealed as a plan. The corrected boundary requires
a version-one plan object before creating output. All twelve cases then passed
in 3.0 seconds on macOS arm64, Elixir 1.20.3 and OTP 29. Controls include copied
artifact tampering, changed plan/manifest bytes, dirty/untracked sources, a new
clean commit, a new runtime file and output preservation. The negative run is
retained. Fake artifact bytes remain inert throughout these identity tests;
these cases do not prove worker execution or model quality.

Only permitted tuning inputs were opened. An independent source/span audit
verified all four tuning relevance quotations at their declared byte offsets.
Its first reporting command tried to encode native match tuples directly as JSON;
normalizing those tuples to arrays corrected reporting without changing data.
Held-out corpus, qrels, manifest and evaluator remain sealed. No actual model
inference ran for this increment.

The maintained full comparison runner, domain inference/lifecycle controls,
capacity audit, complete execution freeze, matched held-out predictions, resource
measurements and independent semantic review remain required. The identity helper
and query projector alone do not satisfy those gates.

## Exact-source platform receipts and retained failure

All applicable steps of both jobs at `94dc78d` passed in
[run 39214067505](https://github.com/lexlapax/ipse/actions/runs/39214067505), including
source/native/package, both installed model thinking selections and Graph recovery.
Only the Linux job's macOS-only steps were skipped.

The later test/documentation-only `2cbbd00`
[run 39214785345](https://github.com/lexlapax/ipse/actions/runs/39214785345) passed
Linux. Its macOS source suite reported 1115 tests, two failures and 32 exclusions.
Both failures were in existing MCP Client cases, during discovery or rediscovery
before tool dispatch, with `MCP transport failed before tool dispatch.` The four
new evaluator-driver negative cases did not fail. Subsequent macOS steps were
skipped. The original failed logs are retained; a bounded unchanged local
reproduction is separate evidence and cannot itself explain or repair the
hosted failure. Its cause remains under investigation.

The unchanged local command with the hosted seed and `--repeat-until-failure 10`
completed eleven iterations of eleven MCP Client tests, all passing. The local
Elixir/OTP versions differ from hosted 1.18/27. This is a reproduction attempt,
not a repair. Opt-in fixture timing receipts now cover startup, initialization,
catalog and tool stages on unexpected success-path failures. They retain only
fixed stage names, bounded numeric times and host elapsed time. A privacy control
rejects unrelated files and private/malformed content. All fifteen focused MCP
Client and stdio-probe cases pass after instrumentation.

The first diagnostic setup used environment value `1`; the existing MCP secret
redaction guard correctly rejected its overlap with public command metadata.
Using a public fixture argument corrected that test setup before server launch.
No MCP production code, deadline, retry or success assertion changed. Both that
negative setup run and the original hosted failures remain retained. Additional
diagnostics do not establish the hosted failure's cause.

The final integrated input/freeze/Session/answer/scorer/metrics/MCP/probe suite
passed 51 tests in 24.2 seconds. Formatter, CI-policy and whitespace checks pass.
The documentation checker reports 224 Markdown files and 2536 local links without
errors. Existing Git and Unix-tool inventory entries now state their seal/test
scope; no dependency was added or installed. Exact-source hosted verification of
this increment remains separate from the earlier successful runtime gate.
