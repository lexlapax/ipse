# Second external P26 review, 2026-10-19

Historical review report supplied by the user from `serenity:/tmp/ipse-p26-review-r2.md`.
The original report body follows unchanged. It reviewed
`b1dc82094afdae8708cdb45dea16beb6c948f88b`; later repairs and acceptance
belong in the [remediation record](index.md). Current user procedures are in the
[memory manual](../../operator/memory.md), contributor guidance in the
[memory training chapter](../2026-10-22-before-structural-consolidation/docs/developer/memory.md), and status in the
[plan](../../plan.md#p26-optional-working-and-long-term-memory).

---

# P26 external re-review at `b1dc820`

Review date: 2026-10-19. Reviewed SHA:
`b1dc82094afdae8708cdb45dea16beb6c948f88b` (verified with `git rev-parse HEAD` in a
detached, isolated worktree). The main checkout was at `6a76950` and stayed
clean. The later receipt-only commit `6a76950` was not reviewed as the target.

## Verdict

**P26 meets its documented scope in code, but its hosted platform gate is still
red at this exact SHA, so the plan's verification requirement is not yet met.**

- **No blocking or medium-severity defects found.** All four first-review findings
  are repaired, and the three issues raised by internal reviewers (legacy
  visibility, legacy restore, working-memory binding) are too. The new generic
  write deadline enforces the user's chosen rejection after expiry without
  interpreting note fields or granting new authority.
- **One low-severity finding:** a gap in failed-receipt validation (finding 1).
- **Hosted run 39295194794 failed `mix test` on both Ubuntu and macOS-14.** Every
  later hosted step was skipped: macOS native, demo, package, installed and
  independent proofs. The failures are 60-second timeouts in P27 knowledge tests.
  The evidence below points to an inherited, pre-repair runtime problem rather
  than a P26 regression. Still, it leaves no hosted verification of P26 at this
  SHA. The gate needs either a green rerun or an explicit, recorded waiver tied to
  that evidence.

If the hosted gate is resolved or waived, I'd accept P26 as complete within its
documented scope. Finding 1 can be fixed or recorded as a known limit.

## Findings

### 1. Low: a failed deadline receipt can name the current operation as the previous writer

- **Location:** `lib/ipse/extensions/state.ex`, `outcome?/4` clause for
  `state.put` with `write_before_ms` and status `"failed"` (around lines 420-432).
  Its fourth argument, the operation ID, is ignored.
- **Causal path:** journal validation on resume calls `State.valid_outcome?`. The
  clause checks code, `checked_at_ms >= deadline`, the summary's shape, key and
  expected revision. It never checks that `record.operation_id` differs from the
  failing operation's own ID.
  `docs/developer/extension-host-calls.md` ("Bound a prepared write by time") says
  "Its operation ID belongs to the previous successful write".
- **Probe (scratch ExUnit, R1):**
  1. Write `note` once.
  2. Run a put with `write_before_ms: 0` and get `{:failed, f}`.
  3. Set `f.record.operation_id` to the failing operation's own ID.
  4. `State.valid_outcome?(req, "failed", forged, op)` returns `true`.
- **Expected:** refused, since a failed write cannot be the last writer. **Actual:**
  accepted.
- **Impact:** limited to journal integrity. A corrupted or edited receipt can make
  the failed operation look like the author of the unchanged record. No write,
  replay or authority change follows, because the status stays `failed`.
- **Fix:** in that clause, also require `value["record"]["operation_id"] !=
  operation_id`, and add this tamper case to the receipt test in
  `test/extensions_state_test.exs`. A summary with `deleted: true` is correctly
  accepted: a deadline put over a tombstone legitimately fails with a deleted
  summary.

### Observations (not defects)

- **Downgrade by import.** An approved import of a *version-one* active record
  with a greater generation over a live *version-two* note is `stored`. The note
  becomes legacy and hidden until migrated (probe R2). The block on import over an
  unmigrated target only covers the opposite direction. This gives no new power:
  dependencies could already be removed through an approved remember with a newer
  generation. The manual describes only upgrade-direction restores, so a sentence
  on this would help.
- **Expired import over a live note.** An approved import of an already-expired
  record with a newer generation over a live note is `stored` and hides the note
  (probe R3). This follows from the user's choice to restore expired backups
  unchanged, and the developer chapter's "cannot be renewed" wording still holds.
  It just isn't called out.
- **CLI batch input.** Piping every `/ext` line into `ipse chat` at once returns
  "Extension command unavailable, invalid, or busy" for commands that arrive while
  the first one is still running. Commands aren't queued. This is outside P26, and
  the manual's interactive flow works (see the matrix).

## Acceptance matrix

Columns show the strongest kind of evidence obtained for each item:

- **Code:** source inspection.
- **Fixture:** handler-level or State fixture tests, including my probes.
- **Session:** public Session tests, including provider-received messages.
- **Native:** actual Linux native sandbox enforcement.
- **Installed:** extracted runtime package.
- **Hosted:** hosted CI steps at this SHA.

| Requirement | Code | Fixture | Session | Native | Installed | Hosted |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Model inspection/recall hides expired, suppressed, orphan, transitively blocked and unmigrated text; legacy-parent descendants; readable control; recovery after migration | ✔ `exclude_derivatives` seeded with `Records.visible?`; `inspect` scan pinned to the `state.get` generation | ✔ suite + R5 (legacy child metadata-only → full after migrate) | ✔ inspect: provider tool messages carry no hidden text/title/provenance (suite); recall: my R6 probe, no hidden text in the provider tool message and the control note present | n/a | memory corpus only | ✘ skipped |
| Inspection refuses changed generation without modifying State | ✔ scan with explicit generation → generic conflict result | ✔ suite ("refuses a changed generation") | — | — | — | ✘ |
| 2. Complete export / fresh restore keeps exact values, blocked children, suppression priority, generations, expiry, retention; legacy import needs migrate | ✔ export conversion removed; `import_note` order checked | ✔ suite + first-review P2 repro now passes | ✔ "public export and import preserve a blocked child's later visibility" | — | — | ✘ |
| 3. Missing collection: `not_found` at revision 0 (with and without cause), `conflict` when stale, no reservation, Session usable | ✔ the `not_found` check precedes the cause lookup | ✔ R4: `not_found` / `conflict` / revision 0 afterwards | ✔ suite (collect then remember in the same Session) | — | — | ✘ |
| Forget of an absent ID creates permanent suppression; typo consequence documented | ✔ | ✔ (first review, P3) | — | — | — | — |
| 4. Selected scope vs binding at admission and revalidation; working memory optionally bound; projects can't grant; third-party `scope` option has no host meaning | ✔ `selected_state_scope?` limited to `@builtins` entries declaring `state_scope_option`; `Config.admitted?` unchanged | ✔ binding tests | ✔ Registry prepare/revalidate cases for both artifacts, including positive controls | — | — | ✘ |
| 5. Delayed approval for remember and active import: exact `write_before_ms` = target expiry; `source_expired`; State unchanged (value/expiry/revision/generation/operation ID); known failed receipt; Session usable; inert idle resume; live-renewal and fresh-expired-backup controls | ✔ deadline attached only when old and new are both active, for remember/import | ✔ deterministic delayed-read regression | ✔ four real-Session tests: full `state.get` equality before/after, failed receipt in journal, recall afterwards, journal bytes unchanged on resume | — | — | ✘ |
| 6. Generic deadline: put-only optional scalar; null/unknown refused; CAS before deadline; check under lock and after sync/chmod before rename; temp cleanup; elapsed result preserved; exact failed summary; recorded-time validation; unbounded requests unchanged; interrupted writes unknown | ✔ `FileEffect.run` + `Runner.lock`; second check precedes `File.rename`; `after File.rm`; validator compares recorded times only | ✔ State tests; ✘ finding 1 | via 5 | — | — | ✘ |
| Forced delay inside temporary staging | Source placement only | not exercised | not exercised | — | — | — |
| 7. Default-off, scope isolation, separate full-argument write approval, denial/cancellation, concurrent forget, stale continuations, bounded work/outputs, legacy namespaces, stable identity | ✔ | ✔ | ✔ suite | full suite with native cases | ✔ | ✘ |
| No silent provider/service change; no dependency added | ✔ diff touches only memory, records, registry and state | — | — | — | — | — |
| Measured quality/resources separate from correctness | ✔ | `measure-memory.exs` passed (corpus `3f11a10a…`, recall@5 1.0, exact-span precision 1.0, zero model/encoder calls) | — | — | ✔ installed corpus passed | ✘ |
| Operator manual's literal example | — | — | ✔ real CLI, demo provider, isolated HOME/IPSE_HOME, `--yes`, one command per line: remember ×2, recall, inventory, forget → recall `[]`, collect, export | — | — | — |
| macOS native / App Sandbox | — | — | — | not run (Linux host) | — | ✘ skipped |

## Environment, commands and results

- **Host:** Arch Linux, kernel 7.2.9-arch1-1, x86_64, 20 schedulers. Elixir
  1.20.4 / OTP 29; Rust/cargo 1.99.0.
- **Workspace:** detached worktree at `b1dc820` in my session scratchpad; deps
  copied from the main checkout; synthetic temporary HOME/IPSE_HOME for the demo
  and CLI runs. The worktree, temporary homes and probe files were removed after
  use. Other worktrees (for example `/tmp/ipse-p26-b1dc820-Xiuxg2/source`) were
  left untouched. I did not read credentials, private journals,
  `.ipse/continuations/` or P27 predictions/labels.

| Command | Result |
| --- | --- |
| `./scripts/build.sh` | Passed |
| `mix format --check-formatted` | Passed (1.20.4 formatter only; the 1.18 floor was not run locally) |
| `mix compile --warnings-as-errors` | Passed (warnings shown are from dependencies) |
| Five focused files (memory, memory session, state, state binding, state scan) | 41 passed, 16.4 s |
| `mix test --include native_sandbox` | **1,177 passed, 15 excluded** (macOS-only tags), 622.8 s. Matches the recorded Linux baseline |
| Scratch probes R1–R6 | 6 ran: R1 found finding 1; R2/R3 are the observations; R4/R5/R6 confirmed the repairs. Deleted afterwards |
| `./bin/ipse demo` (isolated HOME/IPSE_HOME) | Passed. A first attempt failed only because isolated HOME hid Hex; rerun with `MIX_HOME`/`HEX_HOME` pointing at the real install |
| `mix run scripts/measure-memory.exs` | Passed |
| `./scripts/package.sh` | Passed: `ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`, SHA-256 `539bf70a61881cf7b16e5baf19843874b64c635e9e789cc65e67df6b7597913c` |
| `timeout 900 elixir scripts/verify-package.exs dist/ipse-*.tar.gz` | PASS: help, demo, workspaces with spaces, bundled MCP/delegation/extensions, OTP/helper, installed memory corpus, utility-only PATH |
| `elixir scripts/check-docs.exs` | 240 Markdown files, 2,626 local links, **0 errors** |
| `ipse config` + `ipse chat --provider demo … --yes` with the manual's literal JSON and commands | Passed when paced one line every 4 s (see observations) |
| `mix test test/knowledge_evaluation_runner_test.exs:92 :1159 --slowest 2` | 3 passed; "suppressed source selection" took **47.6 s**, "current source selection" 31.4 s, CLI-freeze test 26.1 s (60 s limit) |
| `gh run view 39295194794` (exact SHA) | **failure** on both jobs at `Run mix test`; every later step skipped |

### Hosted failures: inherited or new?

| Run | SHA | Failing tests (all `ExUnit.TimeoutError` after 60,000 ms) |
| --- | --- | --- |
| 39295194794 | `b1dc820` (target) | Ubuntu: `KnowledgeEvaluationRunnerTest` "all seven variants preserve suppressed source selection…" (1,192 tests, 1 failure, 32 excluded). macOS: same test + "CLI freezes copied selections…" (2 failures) |
| 39282076952 | `d300b68` (parent, before repairs) | macOS: `KnowledgeIndependenceTest` timeout |
| 39275849251 | `8183920` | Ubuntu: same "all seven variants…" timeout |
| 39272939320 | `a3007ee` | Ubuntu and macOS: same "all seven variants…" timeout |

The same P27 test timed out on Ubuntu before any P26 repair. Locally it passes
but takes 47.6 s on a 20-scheduler host, close to the 60 s limit on smaller hosted
runners. The test drives P27 knowledge packages, which issue `state.put` without
`write_before_ms`, so they take the unchanged path. That's strong evidence these
are inherited P27 timing failures and not P26 regressions. It's still an
unexplained gate failure, not a verified pass. The P26-relevant hosted steps
(macOS native, package, installed and independent proofs) did not run at this
SHA. Run 39297243712 for `6a76950` was still in progress when checked and isn't
evidence for the target.

### Unverified limits

- **macOS:** native enforcement, App Sandbox, the 1,160-test baseline and the
  macOS package. The root's receipts cover these; I didn't reproduce them.
- **Hosted steps** at this SHA: none past `mix test`.
- **Elixir 1.18.5 / OTP 27:** no local run; the hosted run stopped at the test
  failure.
- **Forced delay inside temporary staging:** not exercised by anyone. Only the
  placement of the second check was verified, by source.
- **Interrupted-write recovery** beyond what the full suite already covers was
  not re-exercised.
- **Real providers / paid inference:** none used. Only the demo and fixture
  providers.

## Documentation assessment

**Operator manual (`docs/operator/memory.md`)** reads as a task path: choose a
scope, configure, remember/inspect, forget/collect, export/migrate/upgrade, keep
forgotten content out of later inference.

- The JSON example and the eight `/ext` commands ran as written through the real
  CLI, and the results matched the stated expectations, including recall `[]`
  after forget and collection of the derivative at revision 1.
- The new paragraphs are accurate against the code: inspect visibility, the
  `write_before_ms` approval behaviour, `not_found` vs `conflict` for collection,
  the absent-ID forget warning, and exact backups including expired text.
- The scope-mismatch error `extension_admission_refused` is the real atom
  (`registry.ex:4`), and the troubleshooting entry cross-links correctly.
- **Gap:** the downgrade and expired-over-live import behaviours (observations)
  aren't described.

**Developer chapter (`docs/developer/memory.md`)** teaches the flow through the
source:

- Admission metadata, the remember continuation and the deadline, the inspect
  generation pin, export fidelity, missing-target ordering, and legacy migration.
- It points to the regressions to read before changing each flow, and its claims
  match the implementation I traced.
- **Minor:** its test command block lists four files but omits
  `test/extensions_state_test.exs`, which now holds the generic deadline contract.

**Host-call chapter (`docs/developer/extension-host-calls.md`, "Bound a prepared
write by time")** describes the request, CAS-first ordering, the two clock checks,
cleanup, the failed shape, and the linearization/rollback limits accurately. The
one exception is the operation-ID sentence that finding 1 shows isn't enforced.

**Plan and records** (`docs/plan.md`, the remediation index, internal review and
expiry design):

- They keep historical evidence separate from the candidate's.
- They correctly mark Linux/hosted gates and external acceptance as pending.
- I found no stale "complete" claim for P26 in the manuals or the plan.
- Doc check: 0 broken links or anchors.
