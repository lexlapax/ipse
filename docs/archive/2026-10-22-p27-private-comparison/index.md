# First private GPU comparison: retained failure

Historical execution record, dated 2026-10-22. Predictor/runtime source is
`7bffee05e4ec9fa4730d608e0fa0cc7297b5a815`; `e402be6` adds documentation only.
Current procedures belong to the [evaluation manual](../../developer/knowledge-evaluation.md)
and acceptance belongs to the [plan](../../plan.md#p27-optional-research-graph-and-rag).
This record establishes neither P27 acceptance nor a selected engine.
The [previous P27 plan section](previous-plan.md) preserves the earlier milestone
history from `e402be6`, with relative links rebased and its original section hash.

## Preserve the original execution

The fresh execution on the verification host finished after about 9 hours and
35 minutes. Its local root is
`/var/tmp/ipse-p27-heldout-20261021-7bffee0-c2` on Serenity. This location is
provenance, not a required product configuration. The execution seal SHA-256 is
`aa17f45e1a272c8b82cab45b14d075383546ece5e09fd91e4e4662e3e2f1b582`.

All sixteen native stage receipts report natural exit zero and confirmed cleanup:
preparation, fourteen strategy/project cells and finalization. The root receipt
reports the same outcome. The finalizer saved 350 first outcomes and no execution
or accounting errors. Those facts do not establish successful answers or a
complete joined audit.

Both public `measure` and subsequent read-only `audit` exited one with
`file_limit`. The observer's completed flag means observation finished; it does
not override those failures. No replay, claim reset, receipt rewrite, log
truncation or replacement of the captured runtime was performed.

| Retained report | Bytes | SHA-256 |
| --- | ---: | --- |
| `reports/predictions.jsonl` | 4,150,340 | `6dc5fcde1753276cc5b5297a135478f1543f155029f960dca7a73198781b0291` |
| `reports/execution.jsonl` | 68,167,328 | `d8e962cfd0abab82d93db1d064d2b3922da0db640c1555f42f66530f51fd8311` |
| `reports/finalized.json` | 2,819 | `4c48997fc0435c2a3cec855fdb103ce08ce04a28db28674e2d2722b198dc671c` |
| `reports/resource-summary.json` | 4,441,901 | `8423bef3cabbcb8952adec07147d902dc7e4ce77c3c49624a9c8b9ce393b4872` |

The native root's raw peak field is 42,796,732,416 bytes under
`linux_memcg_charged_peak_bytes_v1`. It is retained as native receipt evidence.
The complete joined resource audit did not pass, so this number is not an
accepted matched resource comparison. It does not measure RSS or device memory.

## Separate answer failures from the audit failure

The saved first-outcome statuses are:

| Strategy | `ok` | `failed` | `partial` |
| --- | ---: | ---: | ---: |
| Lexical | 15 | 35 | 0 |
| Explicit Graph | 18 | 32 | 0 |
| Model-extracted Graph | 3 | 22 | 25 |
| Dense | 18 | 32 | 0 |
| Hybrid | 16 | 34 | 0 |
| Rerank | 18 | 32 | 0 |
| Research | 14 | 36 | 0 |
| Total | 102 | 223 | 25 |

These are execution statuses, not independent support or citation judgments.
No strategy can reach the individual answer-support target on these outcomes.
The 25 partial rows did not execute the final answer call. The remaining 325
answer calls comprise 102 completed requests and 223 failed requests. Every failed
answer envelope reports `model_request_failed` with confirmed materialization and
completion observation. No semantic content was printed during diagnosis.

Canonical accounting contains input and output counts for every answer request.
All 223 failed requests consumed exactly 4096 input-plus-output tokens. Their
output counts range from 2665 to 2991; none reached the selected 8192-token output
allowance. The 102 completed requests have total counts from 1451 to 4096.

All fourteen captured model-service environments omit `OLLAMA_CONTEXT_LENGTH`.
Bounded probes of the daemon logs find automatic configuration zero and an
effective 4096-token text context. Six cells also show a 2048-token context for
the separately loaded embedding model. Only numeric context metadata was
extracted; raw logs, argument lists and environment dumps were not published.

Ollama's [startup selection](https://github.com/ollama/ollama/blob/main/server/routes.go)
uses a 4096-token automatic context on its low-VRAM tier. Its
[context configuration](https://github.com/ollama/ollama/blob/main/docs/faq.mdx)
supports an explicit `OLLAMA_CONTEXT_LENGTH` override. The captured execution
evidence, rather than current upstream defaults alone, establishes what this run
used. A generation allowance does not enlarge the context containing the prompt
and generated tokens.

## Repair the contracts before another acceptance attempt

Two independent source reviews confirmed the merged-stream defect. Finalization
can concatenate fourteen individually admitted cell files, each bounded at
64 MiB, but the auditor applies a 64 MiB limit to the aggregate. This execution's
log exceeds that aggregate limit by 1,058,464 bytes. Execution-log bytes contribute
an audit digest and do not need to be retained as one binary.

The corrective implementation uses bounded exact streaming comparison in schedule
order, verifies each cell's retained digest, and computes the aggregate digest
from those same compared chunks. It returns bounded parsed evidence separately.
A new 64 MiB-plus-one regression fails with `file_limit` on the original code and
passes after the repair. The focused twelve-test file and strict compilation
pass. Both corrective source reviews report no actionable defects. The broader
verification state appears below; these focused checks alone do not close it.

The separate context repair now has a version-three service selection and portable
experiment. It binds explicit context, checks actual final completion-model
context, and permits a different positive embedding-model window. New extended
answer declarations require context larger than every text output allowance.
That static guard cannot establish actual prompt fit. The combined focused suite
passes 41 tests. Two independent source reviews found no further context-admission
defect; one identified two missed fixture callers, subsequently migrated to
keyword options. Affected caller tests, full platform/native/installed checks
and exposed real-model viability have separate evidence below. The chosen 9B model,
final-answer-only reasoning and original failed outcomes remain unchanged.

The current frozen-runtime contract does not admit a replacement auditor for
this old seal. Both independent reviewers confirmed that a separately versioned
re-audit would require its own reviewed authority and review/scoring admission.
The product reader repair does not retrospectively turn the original public
commands into passing commands.

## Verify the corrective increment

The [corrective verification receipt](verification.json) binds the checks below.
The source inventory contains 439 runtime, test and tooling files,
SHA-256 `e7ea0a162ddfb4478edafd4d5a0cb6327edd7a37cd616d409f17e29b2a7db33f`.
The [review record](repair-reviews.md) retains independent design, implementation
and whole-document reviews, the accepted findings and their dispositions.

| Check | Verified result |
| --- | --- |
| macOS baseline | Build, formatting, strict compilation and demo passed; 1,456 tests passed, 1 skipped, 36 excluded in 1110.5 seconds |
| Linux baseline | Build, formatting, strict compilation and demo passed; native-enabled suite: 1,509 passed, 19 excluded in 1301.7 seconds; package built |
| Supported toolchain | Elixir 1.18.5/OTP 27.3.4 build, formatting, strict compilation and 75 affected tests passed; all 439 source hashes unchanged |
| Caller correction | Six affected macOS tests passed, 26 excluded; Linux-only cleanup behavior also covered by the native-enabled suite |
| Manual examples | 60 fenced examples parsed; four complete operator configurations inspected through the real CLI without inference |
| Extended-answer preflight example | Exact manual driver passed against the synthetic model fixture with context 16384, saved first result, accounting, decoding and confirmed cleanup; no real inference |
| Linux installed package | Package proof passed |
| Model-service fixture | All 31 cases passed in source and installed modes |
| Complete measured proofs | Source and installed CPU/GPU selections each passed 350 rows, full execution/resource audits, scoring/tamper/replay controls and unchanged inventories; final source/Git checks passed |

The floor snapshot's reused dependency cache is an untracked `deps` symlink;
its source inventory matches, but a Git-clean snapshot is not claimed for that
component check. The first Linux snapshot admission failed before build because
macOS archive metadata introduced extra AppleDouble files. All expected source
hashes matched. A fresh metadata-free archive passed source admission. Neither
setup failure consumed a private evaluation attempt.

The synthetic manual setup first failed because its fixture BEAM was loaded only
in memory. A second setup let its temporary compiled fixture disappear between
VMs, causing a service exit before the callback. Both failures are retained.
Using the existing fixture loader and keeping its lifetime around the complete
driver produced the passing synthetic check. The documented driver itself was
unchanged by those setup corrections.

The [exposed real-model diagnostic](exposed-context-diagnostic.json) completed
eight first requests across lexical and dense contexts in two projects. All eight
requests completed with final canonical accounting and decoded successfully.
The saved policy audit passed; Session close and native/staging cleanup are
confirmed. The selected 9B model retained its verified enabled reasoning default,
600-second deadline and 8192-token output allowance.

Final inventory reports completion context 16384, `size` 6,582,278,550 and
`size_vram` 4,930,341,436. This is partial residency, not a device-memory peak.
Input-plus-output totals are 2163, 6307, 5693, 6332, 5891, 1723, 4741 and 5423.
Six completed requests exceed the old 4096 limit. Request durations range from
19.452 to 259.626 seconds; the whole service lifetime is 1446.842 seconds.
These are exposed protocol/configuration observations. Independent semantic
support, held-out quality and matched resource acceptance remain unmeasured.

Reference answers remain sealed. No new semantic packet was created and no
independent semantic judgments or final quality scores exist for this population.
The original first outcomes and failures must remain part of the published
evaluation history. Final held-out acceptance, exact resource comparison,
individual qualification, engine selection and manual integration remain open.
