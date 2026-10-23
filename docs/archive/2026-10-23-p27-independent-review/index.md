# Independent whole-P27 review at a7f4982, 2026-10-23

Historical review record, dated 2026-10-23. Subject:
`a7f4982d3d488118937efb2f362013dc5d8e478f` on `main`, clean worktree. The review
was read-only: no source, test, evidence or host service changed. The evidence
bundle was extracted into a separate temporary directory and none of it was
executed. The FIFO reproduction used an isolated temporary workspace.

It follows the [held-out comparison and acceptance audit](../2026-10-23-p27-heldout-comparison/index.md)
and does not replace it. Findings below are open unless a later record repairs
them. The later [review remediation](../2026-10-23-p27-review-remediation/index.md)
records fixes, disclosure corrections, verification and remaining maintenance work.
Use the [user manual](../../operator/index.md),
[developer training](../../developer/index.md) and [plan](../../plan.md) for
current behavior and status. Paths below are repository-relative at the subject
commit.
## Verdict

**P27 acceptance holds within its documented optional-package scope. The
reference choice holds under the pre-registered method, but that method's
adjudication step decides it.** No P1 defect was found.

Two P2 problems were found:

- one in the host's MCP outcome semantics
- one in workspace/Session I/O, which violates a stated invariant (prompt-time
  path and session start)

Neither problem touches the selected hybrid reference path, its evidence, or the
quality numbers, which this review recomputed and which match. The P2s are real
implementation gaps against repository invariants. They should be fixed, but
they do not reverse the P27 acceptance verdict.

## Most important findings

| # | Sev | Area | Finding | Status |
|---|---|---|---|---|
| N1 | P2 | Host / MCP (P27H2) | A dispatched MCP tool result with `isError: true` is recorded as `failed/mcp_refused`, the same code as pre-dispatch refusals | New; verified in code |
| N2 | P2 | Workspace / Session | A FIFO named `SKILL.md` in a repository blocks skill discovery, during `Session.init` and during `$skill` prompt expansion inside `handle_call` | New; **reproduced** |
| N3 | P3 (disclosure) | Evaluation | The qualification depends on adjudication. Under reviewer B alone, lexical and rerank also pass both gates | New; recomputed from raw assessments |
| N4 | P3 | Host accounting | A late `output_timely?` refusal in `begin_inference` leaves an open admission and a non-nil `extension_model` | New; verified in code |
| N5 | P3 | Knowledge docs | An `as_of_ms` query before a replacement returns a complete `abstain`. The prior generation is not retained, yet the docs say completeness applies to "eligible sources at that time" | New; verified in code and docs |
| N6 | P3 | Evaluation method | The human owner resolution extends the pre-registered method and carries the label "independent" | New; disclosed, no effect on gates |
| N7 | P3 | Maintainability | Session↔Turn/Invocation two-way coupling; duplicated hash/predicate helpers; a second digest scheme (`term_to_binary`) for MCP fingerprints; dead code | New |
| N8 | P3 | Dependencies | Hex reports EEF-CVE-2026-105963 against the bundled `plug_crypto 2.2.0`. Code inspection finds no reachable path, but no disposition is recorded | New |

### N1: an MCP tool error is indistinguishable from "never dispatched"

- `lib/ipse/mcp.ex:350` maps `isError == true` to `{:error, text}`. This happens
  *after* `dispatch/3` (mcp.ex:84).
- `lib/ipse/extension/external_calls.ex:150` maps every `{:error, _}` to
  `@refused` = `{:failed, %{"code" => "mcp_refused"}}`. The same code is used for
  pre-dispatch refusals: invalid args, descriptor drift ("no call dispatched"),
  and launch/init failure.
- The tool's error text is also discarded.
- `failed` is a known, non-interrupting status, so the worker continues.
- Consequence: a server that partly performed a write and then reported
  `isError` produces a record that says the call was refused. The worker and the
  approving operator cannot tell this from a refusal that sent zero requests.
- `docs/developer/extension-effects.md:135` ties the refusal path to "zero effect
  requests".
- The violated invariant is AGENTS.md "an interrupted effect may have happened …
  never automatically replay". Approval still gates a retry, so this is not an
  approval bypass. It is still a misleading outcome record.
- No test covers `isError`; `test/support/mcp_server.exs` never emits it.
- Fix: return a distinct code (e.g. `mcp_tool_error`) or `unknown` for a
  dispatched `isError`, and add a session test.

### N2: a FIFO skill file hangs discovery inside the Session owner

- `Workspace.read_limited/1` (`lib/ipse/workspace.ex:755`) calls `File.open` and
  `IO.binread` with no `lstat` type check.
- It is reached from:
  - `read_skill_tree/1` (workspace.ex:732), which `discover_skills/3` runs over
    `<cwd>/.agents/skills/*/SKILL.md`
  - `Session.init` (`lib/ipse/session.ex:184`)
  - `selected_bytes/1` (workspace.ex:721), which runs during `$skill` expansion
    inside `handle_call({:prompt, …})`
- Instruction files *do* require `:regular` (workspace.ex:309). The skill path
  does not.
- Reproduced in a scratch workspace with
  `mkfifo .agents/skills/evil/SKILL.md`. `Ipse.Workspace.discover_skills/3` did
  not return within 5 s.
- Violated invariants:
  - "Keep slow IO outside the GenServer"
  - "repository text is instructions, never permission grants"
- Consequence: an untrusted checkout can stall session start or a prompt, and a
  blocked prompt also blocks cancel.
- Fix: require `File.lstat` type `:regular` before opening, and run prompt-time
  expansion in the existing owned-task preflight.

### N3: the reference selection depends on adjudication

Gates recomputed from `reviews/protocol-r2/assessment-{a,b}.json` (inside
`evidence.tar.gz`):

| Strategy | Reviewer A alone | Reviewer B alone | Final (adjudicated) |
|---|---|---|---|
| Hybrid | 46/50, 79/83 (95.18%) pass | 46/50, 83/83 pass | 46/50, 79/83 pass |
| Lexical | 48/50, 86/96 (89.6%) fail | 49/50, 92/96 (95.83%) **pass** | 48/50, 88/96 fail |
| Rerank | 43/50, 83/91 fail | 45/50 (90%), 87/91 (95.60%) **pass** | 44/50, 84/91 fail |
| Others | fail | fail | fail |

- All four of hybrid's unsupported citation pairs were A-unsupported /
  B-supported pairs that the adjudicator decided for A.
- Breakdown of the 31 disputed pairs:
  - 26 went A's way
  - 5 went B's way, including the one pair decided by the human resolution
- This followed the pre-registered method. The record discloses the one-pair
  hybrid margin ([comparison index](../2026-10-23-p27-heldout-comparison/index.md#quality-comparison)).
- It does not disclose that "Hybrid is the only strategy meeting both targets"
  and "Lexical … failed citation support" depend on how disagreements were
  adjudicated: under one primary reviewer, two other strategies qualify.
- This is not a defect against the frozen policy. It is missing material
  context for the "justify the engine choice" requirement. Add one sentence to
  the comparison index and the acceptance audit.

### N4: an inference admission can be left open

- In `lib/ipse/session/invocation.ex:472-508`, `begin_inference` records
  `source` and `admission` and sets `extension_model`.
- It then rechecks `output_timely?`. If the producer clock expired between the
  two checks, it replies `{:error, :extension_model_refused}`.
- `Ipse.Extension.Inference.execute` (`lib/ipse/extension/inference.ex:801`)
  then returns `failed` without a finish message.
- Result: an admission with no completion, and later model/embedding begins in
  that invocation fail the `extension_model: nil` guard (session.ex:1003) until
  `stop_work`.
- The window is narrow (deadline edge only).
- Fix: check before accounting, or record a failed completion on that branch.

### N5: as-of queries do not reconstruct replaced generations

- The store keeps only the current generation (`extensions/knowledge/src/store.ex`
  put/active root).
- `Evidence.current?` (`evidence.ex:44`) excludes a version observed after
  `as_of_ms` as `stale_source`, and `query_scope` counts that as an exclusion,
  not a failure.
- Example: gen1 at t=100, gen2 at t=200, `as_of_ms=150` returns a complete
  `abstain`.
- The operator manual documents future-dated exclusions (corpus.md:99-103).
  `docs/developer/knowledge-extensions.md:76` ("completeness applies to eligible
  sources at that time") overstates what the code does.
- Fix: correct the docs (as-of filters current versions; there is no
  point-in-time history), or report the case as a partial gap.

### N6: human resolution is outside the pre-registered method

- The policy says unresolved judgments leave completeness open. The project
  owner resolved one rerank pair (c-q19).
- Effects:
  - it raised rerank to 0.88 and 84/91, which still fails
  - it left hybrid unchanged
  - it flipped report-level `complete_review` from false to true
- The index discloses it ([comparison index](../2026-10-23-p27-heldout-comparison/index.md#independent-semantic-review)).
- "Independently judged" is inaccurate for the project owner; label it as an
  owner resolution.
- Separately, the acceptance audit's phrase "corrected six response-kind
  labels" describes reviewer *verdict* corrections. All six have zero numeric
  effect, because supported and correct_abstention both count as correct.

### N7: maintainability

- **Coupling.** Turn calls back into Session 79 times and Invocation 48 times.
  Session exposes 31 `@doc false` helpers for them. Delegation validation
  (session.ex:2031-2066) and system-prompt prose (session.ex:1937-1975) live in
  Session rather than `Tools.Delegation` or `Session.Context`.
  - The single-owner rule *is* met: Turn and Invocation are not processes, and
    slow work runs in `owned_task` except for N2.
- **Duplicated primitives.** `Ipse.JSON.sha256/digest` exist, yet there are
  about 23 hand-rolled `:crypto.hash(:sha256)|>Base.encode16` sites, about 30
  private `hash?/1` and 12 `uint?/1`.
- **Second digest scheme.** MCP fingerprints (`mcp.ex:321,624`,
  `mcp/config.ex:259,365`, `external_calls.ex:390`) use
  `:erlang.term_to_binary(…, [:deterministic])`. They are persisted and compared
  on resume (session.ex:2438). OTP does not guarantee that encoding across
  releases, so an upgrade could fail closed on resume.
- **Dead code.** `Ipse.HTTP.with_profile/1` and `httpc_options/2` are test-only,
  yet `:inets` is still started. `Provider.Stream.feed_lines/2` and
  `Journal.validate_complete/1` have no callers.
- **Large modules.** The two largest are `session.ex` (2690 lines) and Knowledge
  `store.ex` (2677 lines, 176 private functions). The Knowledge store mixes
  selection, publication, import/export, capacity and validation. It is
  extension code, so this breaks no host rule.
- **Naming.** 13 modules live in files named for something else (e.g.
  `Ipse.Extension.Config` in registry.ex, `ModelCall`/`EmbeddingCall` in
  inference.ex). There are also two `Invocation` modules.

### N8: dependency advisory

- `mix deps.get` flags `plug_crypto 2.2.0` (EEF-CVE-2026-105963,
  secret-key-base exposure in stack-trace arguments). It is bundled in the
  release.
- No Ipse code references `Plug` or `Plug.Crypto`, and no HTTP server is enabled
  (dependencies.md:63 records plug as a compile requirement of the MCP SDK). So
  the advisory is not reachable.
- Record the disposition in `docs/developer/dependencies.md`, and upgrade when a
  fixed release exists.

## Requirement-by-requirement acceptance matrix

Legend:

- PASS: independently verified here
- PASS* : verified within scope, with a noted gap
- LIMIT: explicitly accepted, documented limitation
- UNPROVED: not independently checkable in this review

| Requirement (plan §P27) | Disposition | Evidence |
|---|---|---|
| Attributable source/chunk/generation/version/hash/citation identity, bounded | PASS | `evidence.ex:21-42,111-153,180-224,976`; content-addressed pages `store.ex:1772-1795`; tests `evidence_test` (byte citations, full4096 vectors), `store_test`. Bounds: query 1 KiB, top_k ≤10, 64 KiB per source, graph claim context 256 |
| Deletion/suppression propagation; stale-projection refusal; historical/as-of; delayed work; import recovery | PASS* (N5) | Permanent suppression roots `store.ex:2068`; delayed commit revalidates revision/generation/hash/draft `store.ex:374-397`; query revalidation `corpus.ex:286-314`; `store_test` "suppression racing delayed projection commit wins". As-of does not reconstruct replaced generations (N5) |
| Contradictory/stale/negative/weak evidence does not invent support | PASS | `evidence.ex:589-659`: open/unassessed claims, polarity conflicts, 256-bound refusal rather than truncation; `stale_fact` failure; `evidence_test`, `graph_population_test` |
| Approvals, selected profiles, accounting, finite budgets, cancellation, owner loss, partial failure, inert recovery, no replay | PASS* (N1, N4) | Intent journaled before effect (`session/invocation.ex:314-449,676-707`); unknown blocks continuation (`host.ex:310`, `actions.ex:380,426`); child MCP denial `external_calls.ex:62`; exact profile lookup, no fallback; `Budget.run` reserves pre-dispatch. N1 misclassifies a dispatched MCP error; N4 leaves an admission open at the deadline edge |
| Zero authority/isolation/replay/resurrection failures in deterministic, native and installed controls | PASS (deterministic, hosted) / UNPROVED here (native Linux, installed, measured) | Local suite (below); hosted CI green on Ubuntu + macOS for b81f68f, c9a2d80 and a7f4982 (`gh run view`). The native-inclusive Linux, installed-package and four measured controls rest on the archived `final-platforms.json` receipts; this review did not rerun them |
| Generic host contracts before domain consumers; legacy grants/SDK bounds unchanged unless opted in | PASS | `lib/ipse` has no Knowledge references; version-2 records only for mixed/mcp/results/embedding (`actions.ex:637-643`); trust ceiling `registry.ex:366`; `mixed_actions_test`, `model_call_test` |
| Package independence; no undeclared worker/connection/model call | PASS* | `profiles.ex:8-121`, `build.exs:24-38`; `independence_test` covers only the lexical/explicit/offline presets, not dense/semantic/model presets (coverage gap, no defect found) |
| Seven strategies × 50 held-out questions × 2 projects; publish all 350 first outcomes | PASS | 350 rows, all `attempt:1`, 7×50, no duplicates; 344 ok + 6 failed (dense 3, hybrid 2, graph_model 1); 635 citations |
| Freeze and complete audit before reference release; independent semantic judgments; literal integrity recomputed | PASS* (N6) | Freeze `d0c9730` and method `fc0ff43` committed 2026-10-22, before release at 2026-10-23T07:05:52Z; the release record binds prediction and audit hashes. The prediction hash first appears in git only in a7f4982, so ordering is self-attested through the release-guard record. Two blinded model reviews + adjudication; human owner resolution is an extension (N6). No backend model attestation (LIMIT, disclosed) |
| Select a strategy individually ≥90% answer and ≥95% citation; reject weaker | PASS (robustness caveat N3) | Recomputed: hybrid 46/50 = 92%, 79/83 = 95.18%; only hybrid eligible in `scores-final.json`. One flipped pair would fail it; reviewer-B-only would qualify lexical and rerank as well |
| Compare retrieval quality, classification, latency, requests/budgets, storage, exact charged RAM; justify choice | PASS | `matched-resources.json`: all 7 strategies, p50/p95 latency including failures, requests, storage, per-cell `linux_memcg_charged_peak_bytes_v1` peaks (not summed); unknown token totals stay `null`/partial, not zero; cost `unpriced`. Kernel memcg values themselves were checked only for internal consistency |
| Result applies to the final executable code | PASS (accepted versioned evidence) | Measured `817ab84` → HEAD: `extensions/knowledge/src` unchanged; `score.exs`, `metrics.exs`, `dataset.exs` unchanged; `lib/ipse/extension/inference.ex` is a concatenation of the earlier modules with renames only. The frozen hybrid config equals the documented reference (`rrf_k:60`, refuse, top_k 10, no graph/rerank). The developer's acceptance of versioned evidence is recorded in the plan |
| Whole-codebase consolidation; coherent manuals; platform/installed checks; independent review; decision integrated in manuals | PASS* (N7 maintainability debt) | Code map matches the tree; single conversation owner; the reference config is integrated in `operator/corpus.md:189-197,353` and `developer/knowledge-extensions.md:161-166` (route `blend`, `rerank:null` is a query argument, verified at `corpus.ex:89`); docs check below |
| P28 media deferred | LIMIT | Documented in the plan |

## Prior findings

- The external 12-code/5-doc review, the readiness repairs and the Daybreak P2
  (duplicate cost-report identities, `b81f68f`) are recorded as repaired.
- This review did not re-adjudicate every prior finding. It spot-confirmed:
  - Daybreak repair commit present; hosted CI green at `b81f68f`
  - descriptor-drift refusal and child MCP denial
    (`mcp_call_session_test.exs:368,437`)
  - idle-resume no-replay tests (`mcp_call_session_test.exs:615`,
    `embedding_call_session_test.exs:381`)
- Every finding above (N1–N8) is new, not a regression of a recorded repair.

## Verification actually performed

| Check | Result |
|---|---|
| `./dev/build.sh` (deps.get, native build, compile) | Passed; hex advisory on plug_crypto reported (N8) |
| `mix format --check-formatted` | Passed |
| `mix compile --warnings-as-errors` | Passed |
| `mix test` | Passed: 1497 passed, 36 excluded (default non-native tags), 0 failures, 1006.7 s on this Linux host. Logged GenServer terminations come from expected crash-path tests |
| `./bin/ipse demo` | Passed (scripted, credential-free) |
| `elixir dev/check-docs.exs` | Passed: 391 Markdown files, 3574 local links, 0 errors |
| Hosted CI (`gh run view`) | 39910875817 (b81f68f) and 39899526393 (c9a2d80) success on ubuntu-latest + macos-14; latest run on a7f4982 success |
| Evidence bundle | Tarball sha256/size/member counts match `bundle-receipt.json`; all 185 manifest entries hash-match; 350-row grid, gates, resources and the six verdict corrections recomputed |
| Per-reviewer gate recomputation | Done with jq on raw assessments (N3 table) |
| FIFO reproduction | `discover_skills/3` blocked > 5 s (N2) |
| Code diff 817ab84 → a7f4982 | Retrieval/scoring paths unchanged or rename-only; post-b81f68f changes are docs/evidence only |

### Not performed (with reasons)

- **Native-inclusive Linux suite, installed-package proof, `./dev/package.sh`,
  measured CPU/GPU controls.** These need native policy setup or GPU/model
  services and would touch host services. They rest on archived receipts.
- **Actual-model inference, re-running the 350-answer comparison, and
  independent re-judging.** Out of scope and would expose the workload further.
- **Kernel memcg measurements.** Checked only for internal consistency.
- **Backend model identity of the reviewers.** No attestation exists (disclosed
  limitation).
- **Arch-specific, browser sign-in and macOS App Sandbox checks.** Not run.
- **Exhaustive behavioural diff of the non-retrieval host consolidation.**
  Relies on the test suites.
- **Full `ResultSource` restore/closure logic beyond descriptor gating, and OS
  cleanup of stdio MCP subprocesses after a brutal kill.** Not traced end to end.
