# Independent whole-P27 final review: ca5838b

Subject: `ca5838be881049cb0f11eded8f6ab3c9fc2843a3` (`origin/main`).
Reviewed 2026-10-23 on Serenity.

## Environment and method

**Environment**

| Item | Value |
|---|---|
| Host | Arch Linux, kernel 7.2.10-arch1-1, x86_64, 20 CPUs, 46 GiB RAM |
| Toolchain | Elixir 1.20.4, OTP 29, rustc 1.99.0 |
| Checkout | Isolated detached clone at `/tmp/claude-1000/-home-lexlapax-projects-lexlapax-ipse/4a82a1bb-2fdd-4f73-8a8a-e8e62a385373/scratchpad/ipse-ca5838b`, with Git metadata kept |
| HEAD | Verified to equal the subject SHA |
| Tracked files | Clean throughout |
| Untracked files at the end | `dist/`, build outputs, and an `erl_crash.dump` produced by a parallel probe. All are disposable. |

**What was left alone**

- The primary checkout, other worktrees, services, captured benchmark runtimes, published evidence and host configuration were not modified.
- No inference, model download, re-judging or seal replay was performed.

**How the review was done**

- Five independent read-only review passes ran in the clone:
  - host contracts
  - Workspace, HTTP and architecture
  - Knowledge
  - evidence and drift
  - documentation, records and earlier dispositions
- I independently re-checked every finding a pass raised before adopting it. Two P2s were downgraded after reading the full text (see "Rejected or downgraded claims").
- Each finding is labelled as **reproduced** (observed behaviour) or **source-based**.

## Verdict

**P27 acceptance holds at ca5838b within its documented optional-package scope.**

- **No P1 or P2 finding is justified.**
- **The a7f4982 review's N1–N8:** the two P2s (N1, N2) and the four code items (N4, N5, N7, N8) are resolved. The two disclosure items (N3, N6) are disclosed, with narrow wording gaps noted below.
- **Local checks at ca5838b all pass:** the full native-inclusive suite, the package build and the exact installed-package proof.
- **Hosted CI for ca5838b is green.**
- **Evidence:** the immutable evidence and every published quality, resource and integrity number recompute exactly from raw records.
- **Remaining issues:** P3 correctness corners, all failing closed, plus documentation and record precision.

The reference choice holds under the pre-registered method, but adjudication decides it. This is now disclosed (see A3).

## Actionable findings (all P3), ranked

### C1. Legacy v1 MCP fingerprints are no longer recomputed byte-exactly for overlapping cross-server secrets

Reproduced.

- **Where:**
  - `lib/ipse/mcp/config.ex:87-91`: `fingerprint_version/2` builds the manifest through `redact/2`.
  - `config.ex:128`: `redact/2` uses the cross-server `:redactions` list attached at `config.ex:35`.
  - `lib/ipse/session.ex:2369-2371` calls this on every resume.
- **Old behaviour:** at a7f4982, resume compared stored metadata against `server.fingerprint`. That value was computed at parse time with redaction of the server's own secrets only (`a7f4982:lib/ipse/mcp/config.ex:354`, `redact(&1, %{env: env})`).
- **Trigger:**
  1. Server A has a secret `abc` and the argument `--k=xabc`.
  2. Server B has a secret `xabc`.
  3. Own-secret redaction gives `--k=x[redacted]`; all-secret redaction gives `--k=[redacted]`.
  4. The probe (`…/scratchpad/probes-b/fp.exs`) printed `v1 recompute matches a7f4982: false`.
- **Consequence:**
  - A legacy journal using such a config refuses to resume with `resume_configuration_mismatch`, though a7f4982 resumed it.
  - This contradicts "legacy journals keep their exact old encoding" in a contrived corner case.
  - It fails closed, so there is no unsafe effect.
  - New v2 sessions stay self-consistent, because both write and resume use the recomputation. The load-time `server.fingerprint` also differs from the recomputed one, which is a trap for any future caller.
- **Smallest repair:**
  - For version 1, build the manifest from `Map.delete(server, :redactions)`, i.e. the server's own secrets.
  - For version 2, use one redaction source everywhere.
  - Add an overlapping-secret resume test.

### C2. Session metadata with an explicit `"mcp_fingerprint_version": 1` is accepted as legacy

Source-based.

- **Where:** `lib/ipse/session.ex:2369-2370` (`Map.get(meta, "mcp_fingerprint_version", 1) in [1, 2]`) and `lib/ipse/extension/external_calls.ex:338`.
- **Why it is inconsistent:**
  - No writer produces an explicit 1: legacy journals omit the key and new sessions write 2.
  - The binding-side shape check (`external_calls.ex:280-292`) rejects an explicit `fingerprint_version: 1`.
- **Consequence:** a non-canonical metadata shape is admitted. v1 fingerprints must still match exactly, so integrity is unaffected.
- **Repair:** map an absent key to 1 and an explicit 2 to 2; refuse anything else.

### C3. The `mcp_tool_error` diagnostic skips the private-value recheck that successful MCP text gets

Reproduced at the redaction level.

- **Where:** `lib/ipse/extension/external_calls.ex:149,177-187`. For comparison, the success path rechecks at `:190-191` (`Config.contains_private?`).
- **Evidence:** redaction is not idempotent. With secrets `q[redacted]` and `zz`, redacting `qzz` yields `q[redacted]`, which equals a configured secret (probe in `…/probes-a/`).
- **Impact:** negligible. The server must already know the secret except for its suffix, and ordinary tools behave the same way.
- **Repair:** apply `contains_private?` before building `mcp_tool_error`. On a hit, return a fixed message or `unknown`.

### D1. The documented "reference" build is not the measured artifact's preset

Confirmed in the evidence.

- **Measured:** the hybrid variant used artifact alias `dense` with an empty `rerank` registry (`comparison/experiment.json` → `plan.variants[id=hybrid].artifacts[0]`). That artifact is built with `--preset state-dense` (`docs/developer/knowledge-evaluation.md:89`).
- **Documented:** the manuals and archive say to build `state-semantic` with a `rerank.ordered` registry and a `ranker` model profile:
  - `docs/operator/corpus.md:195-263`
  - `docs/developer/knowledge-extensions.md:164-169`
  - `docs/archive/2026-10-23-p27-heldout-comparison/index.md:153`
- **Why it matters:** `state-semantic` adds `host.model` authority (`extensions/knowledge/src/profiles.ex:13-14`) and an inference route the measurement never had. The retrieval configuration (`blend` = measured `combined`) is identical, so behaviour does not change; only granted authority does.
- **Also missing:** the measured `top_k: 10` is not stated as part of the reference in either manual (operator examples use 5).
- **Repair:** name `state-dense` with an empty `rerank` registry and `top_k: 10` as the measured reference. Present `state-semantic` with rerank as the optional alternative.

### D2. The owner-resolution record carries `independent: true`, and the scorer requires that flag to count it

Confirmed in the evidence.

- **Evidence:**
  - In `reviews/final-reviews.json`, the `.semantic[]` entry for `p-12e97cb1…` (rerank c-q19) has `"reviewer_id": "user:project-owner"` and `"independent": true`.
  - `dev/evaluation/metrics.exs:258-289` counts a judgment, and review completeness, only when `independent` is true.
  - Without the record, `scores-model-adjudicated-r2.json` has `complete_review: false` and `quality_gates_passed: false`.
- **What is already disclosed:**
  - index.md:108-118 and acceptance-audit.md:42-46 say the resolution "extends the pre-registered method … is not another independent blinded review … closes review completeness".
- **What is not disclosed:**
  - The raw flag, and that the scorer counts the record only because of it.
  - The headline Result paragraph (index.md:16-19) and acceptance-audit row 25 ("All 350 outcomes and 635 pairs have measured judgments") still read as fully independent.
- **Plan requirement affected:** "obtain independent semantic judgments for every applicable answer, claim and citation". This is met for 349/350 cases and 634/635 pairs. One rerank case relies on an owner judgment, which is disclosed and changes no qualification.
- **Repair (no change to the bundle):** one sentence in the Result paragraph and the audit row naming the flag and the dependence of completeness on it.

### D3. Historical-record precision

1. **Archive edits without an in-place note.** Commit 4171fb4 rewrote prior sentences in the archived `2026-10-23-p27-heldout-comparison/index.md` and `acceptance-audit.md`: "The project owner independently judged…" and "Hybrid is the only strategy meeting both targets."
   - The new text is more accurate.
   - The archive policy requires not "silently updating historical claims", and no dated correction note points back to a7f4982.
   - The header's "editorial review found no actionable issues" is also now superseded.
   - The evidence bundle, manifest, receipt, `final-platforms.json` and `editorial-review.md` are byte-identical since a7f4982.
2. **A dropped disclaimer.** The ca5838b edit to `docs/archive/2026-10-23-p27-maintenance/index.md` (~line 117) removed "toolchain-floor check" from "No fresh macOS sandbox-specific check, toolchain-floor check or live-model measurement is claimed".
   - The ca5838b follow-up adds only an Elixir 1.18 formatter run, so no toolchain-floor runtime check exists.
   - Restore the clause.
3. **Unrecorded verification for post-acceptance commits.** `docs/plan.md:531-541` describes 4171fb4, dd0a130 and ca5838b without stating how they were verified:
   - 4171fb4's Linux full run failed in setup.
   - dd0a130's first full runs each failed one test, and hosted run 40012980389 failed formatting.
   - ca5838b has bounded follow-up checks in its record.
   - The plan does not claim a clean pass, and this review's runs now provide one (see the Commands section). One sentence should record the verification status.
4. **CPU/GPU placement not named.** The held-out index does not name the mixed CPU/GPU placement policy (`nvidia_visible_mixed_v1`, partial residency on an 8 GiB GPU), which affects latency comparisons. The single fixed order with no repeated trials is disclosed.

### D4. Minor manual and UX gaps

None of these makes a documented claim false.

- **Skill-file limitation not in the operator manual.** `docs/operator/usage.md:135-137` lists the skipped non-regular skill files but does not carry the concurrent-replacement limitation stated in `docs/developer/workspace-context.md`.
- **as-of caveat missing from Graph.** `docs/operator/graph.md` lacks the caveat added to `corpus.md` (as-of filters retained generations and does not reconstruct history), although Graph shares the same eligibility.
- **Stale HTTP purpose.** `docs/developer/dependencies.md:57` still lists HTTP as an OTP purpose after `:httpc` and `:inets` were removed.
- **Typo.** `docs/developer/knowledge-storage.md:180` has "in4096-byte".
- **Misleading skill-preflight error.** `lib/ipse/session/turn.ex:41-43` reports any skill-preflight worker failure as `:skill_catalog_changed`, so the operator is told to `/context refresh` after an internal failure. A test locks this in.
- **Silent config acceptance.** `ipse config --mcp-config` ignores the MCP file, so an invalid remote config exits 0 there while `run` refuses it.
- **Resume-mismatch wording.** The message (`lib/ipse/cli.ex:542-544`) does not mention MCP configuration or runtime. That is the expected v1 failure after an OTP-major upgrade.

### T1. Coverage gaps

These are test gaps, not defects.

- **Ordinary MCP `isError` over HTTP** has no session test. The stdio path is tested, both transports share `dispatch`→`result_text`, and extension `mcp.call` is tested over both.
- **`independence_test.exs`** still covers only the `state-lexical`, `state-explicit` and `offline` presets. The dense, semantic and MCP presets have no zero-call independence proof, although `lifecycle_proof` partly covers `state-dense`.

## N1–N8 disposition (a7f4982 review)

| # | Disposition at ca5838b | Evidence |
|---|---|---|
| N1 MCP `isError` | **Resolved** | See below. |
| N2 FIFO skill | **Resolved**, apart from the documented TOCTOU limitation | See below. |
| N3 adjudication sensitivity | **Disclosed** | Recomputed: hybrid qualifies under reviewer A and B alone; lexical (49/50, 92/96) and rerank (45/50, 87/91) also qualify under B alone. index.md:170-178 states it, and the audit carries it. |
| N4 late deadline admission | **Resolved** | See below. |
| N5 as-of | **Resolved** in the Corpus and developer docs; Graph manual gap D4 | The probe confirmed that a replaced generation is not reconstructed and returns a complete `abstain` with `stale_source`, matching the corrected text. |
| N6 owner resolution | **Disclosed** with residual D2 | |
| N7 maintainability | **Resolved**, with residual C1 | See below. |
| N8 plug_crypto | **Resolved** | `mix.lock:14` pins 2.2.1, and the built deps and release match. No Plug or `Plug.Crypto` is referenced in lib, extensions, dev or test, and no HTTP server is enabled; Plug arrives only through the MCP SDK's compile-time references. The disposition is recorded in `dependencies.md`. |

**N1: MCP `isError`**

- `mcp.ex:341-355` turns a server-declared `isError` into `{:tool_error, text}`, with the text redacted, UTF-8 and at most 64 KiB.
- Pre-dispatch failures map to `mcp_refused` and transport loss to `unknown`; these stay distinct.
- **Extension path:** `external_calls.ex:148-151,177-187` records `failed/mcp_tool_error` with at most 2048 bytes, a code-point-safe cut and a truncation flag.
- **Ordinary tools:** `turn.ex:1247-1254` adds "Effects may have happened".
- **Saved validation** (`valid_outcome?` via `Actions.valid_result?`):
  - The probe confirmed acceptance of the valid shape and of exactly 2048 bytes.
  - It rejects 2049 bytes, invalid UTF-8, extra keys and wrong types.
- **Fixture effects:** the fixture's partial effect is real (`dev/fixtures/mcp.exs:174-185`). Both transports' extension tests show one call with the effect present and no replay on idle resume.

**N2: FIFO skill**

- `workspace.ex:753` uses lstat to require a regular file and checks size before reading.
- **Probe results:**
  - Discovery skipped the FIFO, directory and leaf-symlink `SKILL.md` promptly.
  - After a file was replaced with a FIFO or directory, `load_skill`, `expand_skills` and `load_skill_resource` refused within the timeout.
  - `ipse skills` with a FIFO returned promptly.
- **Prompt expansion** runs in `Session.owned_task` (`turn.ex:33`).
- **Cancel, close and worker death** settle the prompt through `stop_work` (`session.ex:1323-1326,1384`) with no partial message.

**N4: late deadline admission**

- `invocation.ex:482-524` calls `measure_request(:expired)` on a late refusal. This records `request_finished` as failed and clears `extension_model`.
- `inference.ex:800-805` never reaches `Budget.run` or a provider.
- The model test passes.
- **Embedding probe:**
  - The reply was `embedding_request_failed`, and `extension_model` was nil afterwards.
  - The journal order was intent → request → admitted → finished → result.
  - `Usage.restore` and `Actions.restore` succeeded.
  - There were zero HTTP calls.

**N7: maintainability**

- **Shared helpers:** `Ipse.JSON.sha256?` and `safe_uint?` match every replaced host helper exactly. Different bounds and nullable wrappers were retained.
- **Knowledge package:** it uses its own `Evidence.sha256?`, `safe_uint?` and `safe_positive?`, with no `Ipse.JSON`. An equivalence table was checked case by case.
- **Removals:** `httpc`, `:inets`, `feed_lines` and `validate_complete` are removed.
- **Fingerprints:** MCP v2 uses domain-tagged canonical JSON.
- **Coupling:** Session coupling was reduced modestly (Turn 23→17 distinct `Session.*` references, Invocation 19→17). Authority was not moved out of Session.

## Acceptance matrix (plan §P27)

Legend: PASS = independently verified here. PASS-L = passes with an explicitly accepted, documented limitation. UNPROVED = not independently established here. FAIL = none.

| Requirement | Disposition | Evidence |
|---|---|---|
| Attributable source, chunk, generation, typed-version, hash and citation identity, bounded | PASS | See note 1 below. |
| Deletion and suppression propagate; stale projections refuse; historical/as-of eligibility; delayed work and import recovery | PASS-L | See note 2 below. |
| Contradictory, stale, negative and weak evidence does not invent support | PASS | `evidence.ex:589-659` (open/unassessed claims, polarity conflicts, 256-bound refusal), `stale_fact` partial results, graph seed from eligible facts (`evidence.ex:559-582`); tests pass. |
| Approvals, selected profiles, accounting, finite budgets, cancellation, owner loss, partial failure, inert recovery, no replay | PASS | See note 3 below. |
| Zero authority, isolation, replay or resurrection failures in deterministic, native and installed controls | PASS (Linux deterministic, native and installed; hosted Ubuntu and macOS); UNPROVED here for macOS native and the measured CPU/GPU controls | The local native-inclusive suite and installed proof (Commands section); hosted run 40014715937. macOS sandbox and the four measured controls rest on archived receipts. |
| Generic host contracts before domain consumers; legacy grants and SDK bounds unchanged unless opted in | PASS | No Knowledge references in `lib/ipse`. Version-2 records only for mixed, mcp, results and embedding; trust ceiling `registry.ex:366`. Knowledge BEAMs import only `Ipse.Extension` and `ResultPublication` (`:beam_lib` check). |
| Package independence; no undeclared worker, connection or model call | PASS-L | `build.exs` and `profiles.ex` closed capabilities; `config.exs` writes a disabled instance. Coverage gap T1. |
| Seven strategies × 50 held-out questions × 2 projects; all 350 first outcomes published | PASS | Recomputed: 350 attempt-1 rows (344 ok, 6 failed), 50 queries, 22 documents (11/11), no duplicate or retried requests (630/630 attempt 1). |
| Freeze and complete audit before reference release; independent semantic judgments; literal integrity recomputed | PASS-L (D2) | See note 4 below. |
| Select a strategy individually at ≥90% answer and ≥95% citation; reject weaker ones | PASS-L (adjudication-dependent, disclosed) | Recomputed: hybrid 46/50 and 79/83 (95.18%), the only eligible strategy. One flipped pair gives 78/83 = 93.98%, which fails. Aggregate 314/350 and 580/635 are diagnostic only. Reviewer sensitivity as in N3. |
| Compare retrieval quality, classification, latency, requests and budgets, storage and exact charged RAM; justify the choice | PASS-L (single run, fixed order, mixed CPU/GPU placement; D3.4) | See note 5 below. |
| Result applies to final code (accepted versioned evidence) | PASS-L (owner-accepted) | See note 6 below. |
| Consolidation, coherent manuals, platform and installed checks, independent review, decision in the manuals | PASS-L (D1, D3, D4) | Layout matches the code map; Session is the sole conversation process; Context, Questions and Delegation are pure policy with authority kept in Session; no slow IO added to callbacks. Docs checker passes. Reference integrated in the manuals, with the preset mismatch D1. |
| P28 media | Accepted limitation (deferred) | Plan. |

**Matrix notes**

1. **Identity.** Citations as exact byte spans with a quote hash (`evidence.ex:111-153`), chunk-identity fusion (`evidence.ex:366-411`), content-addressed pages. Recomputed 635/635 cited spans, 423 context spans and 3,484 evidence spans valid against hash-verified document bytes. Knowledge tests pass.
2. **Deletion and as-of.** Suppression races, generation ceilings and recovery are covered (`store.ex:374-415,1881-1905`, `store_test`). The as-of limitation is accurately documented after N5 (D4 Graph gap).
3. **Approvals and effects.**
   - Durable intent before effects (`invocation.ex:314-449,676-707`).
   - Unknown outcomes block continuation (`host.ex:310`, `actions.ex:380,426`).
   - Child MCP denied (`external_calls.ex:62`).
   - Exact profile lookup with no fallback.
   - `Budget.run` reserves before dispatch.
   - Corner cases C1–C3 fail closed.
   - Focused cohorts passed: 183 + 86 + 176 tests.
4. **Freeze and judgments.**
   - Ordering: the answers hash (3ceeb6d, 2026-10-20), freeze (d0c9730) and review method (fc0ff43) were committed before the self-attested release at 07:05:52Z.
   - The prediction hash first appears in git only at a7f4982, so ordering is self-attested through the release-guard record.
   - Six verdict-label corrections changed no numbers.
   - Owner resolution: one rerank case, not blinded.
   - No backend model attestation (disclosed).
5. **Resources.**
   - p50/p95 recomputed from all 50 query timings per strategy, failures included, and match exactly.
   - Request groups match (630 rows).
   - Unknown tokens remain null; cost is unpriced.
   - The 14 memory cells match `full-audit.log` per cell and are not summed.
   - `audit_sha256` is a self-attested computed digest.
6. **Drift since measurement.**
   - Unchanged: `native/ipse-measure.rs` and `dev/evaluation/metrics.exs`.
   - Exactly equivalent: the Knowledge and evaluator helper substitutions.
   - `resources.exs`: renames with identical bodies.
   - Retrieval configuration is identical to the documented `blend`.
   - **Not proven equivalent:** `Provider.Stream`/`Transport` (replacing earlier modules) and `inference.ex` (merged). They are not on the retrieval or scoring path, and the suites pass.
   - A replay at ca5838b cannot reproduce 817ab84's precompiled evaluator identities (module renames, `cli.exs` removal). The archived evidence is not affected.

## Earlier external review r1 (12 code + 5 documentation findings)

All hold through current callers:

- F1–F11 hold. F4, F5 and F10b were confirmed from source and tests only.
- F12 remains accepted as a no-fix: the `extension_output: nil` heads stay unreachable.
- D1–D5 hold.
- None regressed.

The a7f4982 review record (a912db1) changed once, in 4171fb4, to add a forward link; its findings are byte-identical. The remediation and maintenance records keep their failed runs as failures and do not relabel them, apart from the dropped disclaimer in D3.2.

## Architecture and documentation assessment

**Architecture**

- Ownership and trust boundaries are coherent:
  - one conversation owner
  - synchronous Turn and Invocation
  - owned tasks for slow work (including skill expansion, but not init-time discovery, which now reads only regular files)
  - per-borrower private Finch pools with confirmed teardown before name reuse
  - TLS through Mint defaults (`verify_peer`, OS CAs, hostname match), with unknown-CA and wrong-host tests
  - CONNECT-only proxy that refuses malformed URLs
  - independent Knowledge BEAMs
- No new layers are warranted. The remaining large modules (`session.ex`, Knowledge `store.ex`) carry no concrete ownership defect found here.

**Documentation**

- The manuals match the code for:
  - MCP errors
  - fingerprint versioning
  - skills
  - Finch-only HTTP
  - plug_crypto
  - as-of in Corpus
- Remaining gaps: the reference-preset mismatch (D1), owner-flag precision (D2), record precision (D3) and minor items (D4).

## Commands and results (run in the isolated clone)

| Command | Result |
|---|---|
| `./dev/build.sh` | Pass; deps resolved with `plug_crypto 2.2.1`; no advisory reported |
| `mix format --check-formatted` | Pass |
| `mix compile --warnings-as-errors` | Pass |
| `./bin/ipse demo` | Pass |
| `elixir dev/check-docs.exs` | Pass: 394 files, 3615 links, 0 errors |
| `mix test --include native_sandbox` | **Pass: 1532 passed, 19 excluded, 0 failures** (1013.9 s). Excluded tags: `macos_sandbox`, `macos_filesystem`, `memory_scope` |
| `./dev/package.sh` | Pass. Archive `dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`, sha256 `223e644a2522a80be82afc753911c69bd3293d53e2cb47e6cb3bcca987e34d3c` |
| `elixir dev/verify.exs installed package --archive <that archive> --input examples/memory-corpus.json` | Pass (see below) |
| Focused cohorts (MCP, invocation, effect/embedding results, JSON, HTTP, workspace skills, delegation, session, `test/extensions`) | Pass |
| MCP CLI controls (`dev/demo-mcp.exs`; invalid remote, `http://localhost`, 17-tool configs) | Pass. The demo exercises write, resource and prompt; invalid configs are refused |
| Corpus lexical operator flow and `ipse config` on the reference options | Pass |
| Probes (FIFO, fingerprint, embedding expiry, outcome validator, redaction, as-of) | As reported in the findings and N-table |
| Evidence bundle | See below |
| Hosted CI | See below |

**Installed-package proof**

- Private HOME, utility-only PATH, no system toolchain.
- Bundled memory: 100 records and 100 queries, recall@5 1.0.
- Inventories unchanged.

**Evidence bundle**

- SHA256 `bb1d87e7…f7f0` and 19,824,579 bytes; 186 members.
- All 185 manifest rows match by hash and size.
- Grid, citation bytes, scores, reviewer splits and resource joins were recomputed from raw records.

**Hosted CI**

| Run | Commit | Result |
|---|---|---|
| 40014715937 | **ca5838b** | **success** on ubuntu-latest and macos-14 |
| 40012980389 | dd0a130 | **failure**: format step on both platforms |
| 40006711554 | 4171fb4 | success |
| 39971395174 | a7f4982 | success |
| 39910875817 | b81f68f | success |

Earlier green runs do not verify ca5838b.

## Checks not run, and residual risks

- **macOS checks.** I did not run the native, App Sandbox or filesystem checks myself. Only hosted macOS CI covers them; the experimental sandbox limits remain.
- **`memory_scope` and the measured CPU/GPU controls.** Excluded and not rerun. They would touch systemd user scopes and GPU services, and their evidence is the archived `final-platforms.json`.
- **Toolchain-floor runtime check.** Not run at ca5838b; see D3.2.
- **Live and paid model inference, the 350-answer comparison, re-judging, seal replay.** Not run, by instruction. No fresh real-model quality or charged-memory claim is made for ca5838b.
- **Physical GPU placement, reviewer backend identity, and kernel memcg values.** Checked only for internal consistency.
- **Concurrency and transport.** Concurrent filesystem replacement (documented TOCTOU), live proxies and real remote TLS were not exercised.
- **Behavioural equivalence of `Provider.Stream`/`Transport` and the merged `inference.ex`.** Rests on the test suites.

## Rejected or downgraded claims

- **"The owner resolution is disclosed as changing no qualification, so docs mislead" (claimed P2).** Downgraded to D2. The record does state that it closes review completeness; only the raw flag and the headline wording are undisclosed.
- **"The plan overstates verification of current code" (claimed P2).** Downgraded to D3.3. The plan makes no clean-pass claim for the later commits, and this review's runs supply passing evidence.
- **"Overlapping secrets behaved the same at a7f4982" (one pass).** Rejected. a7f4982 compared against the parse-time own-secret fingerprint, so C1 is a real legacy-compatibility change.
