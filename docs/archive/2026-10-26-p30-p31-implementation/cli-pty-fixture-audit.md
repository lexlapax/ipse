Historical-only independent fixture diagnosis and private candidate evidence,
finalized **2026-10-27**. Literal report preserved below; original SHA256:
`01ee8628882490e310051c2b13508df9166961933223141a17eac11003801166`.
Root subsequently reviewed and applied the exact two-file patch with SHA256
`3ca24d102f673b77972cb311e256982fc0ba89d3332bb2635b6f2e7d1eaf691e`.
The [repeat receipt](reference-fixture-full-repeat.md) preserves the failed full
run and limits; the [plan](../../plan.md) owns acceptance status.

# Independent CLI PTY timeout triage

2026-10-27. Scoped synthetic-fixture diagnosis and private candidate verification. No public source/index, owner graph, shared build/helper or production store was changed by this auditor. Root reviewed the diagnosis, approved the private candidate and requested the final default-Mix regression wrapper; public application remains Root's decision.

## Finding

The PTY fixture can stall after a successful native question answer and completed turn because it assumes a new `you> ` display must follow `Finished.`. The CLI legitimately starts the next prompt reader while work is finishing, and retains that same reader across busy→idle. When its prompt is printed just before `Finished.`, the old fixture never sends `/exit` and reaches its 60-second watchdog.

This was reproduced with the unchanged driver and actual private runtime, independently of the failed full suite: four direct conversations passed, then conversation five failed after 60,017 ms. Its raw stdout ends:

```text
Running…
you> 
Finished.
```

The same synthetic journal contains the native operator answer, answered wait, completed model response and `turn_finished` status `ok`; there is no close because the fixture has not sent exit. The original driver's phase-five guard is false for these bytes. This is an actual fixture ordering defect, not a claim that a full-suite test is merely flaky, and not an observed product answer/authorization/locking failure.

The full suite's original timeout exposed no terminal stdout because its 60-second ExUnit bound encompasses compilation and the child's own 60-second watchdog. Thus the full suite killed the test inside System.cmd before the driver could print its buffered transcript. The original full-run phase cannot be retroactively proven from that sparse log alone. The independently reproduced same-fixture stall provides the concrete cause and repair evidence without treating a later passing rerun as diagnosis.

## Exact proposed repair and scope

`proposed-two-file.patch` changes only:

- `test/support/operator_cli_pty.rs`: extract `ready_for_exit(text)`, requiring both `Finished.` and the latest `you> ` to occur strictly after the latest `answer> `. Use it only in existing phase five. Add seven pure readiness controls for both valid orders and absent/completion/historical/refreshed-question negatives.
- `test/ipse/cli/operator_input_test.exs`: add one ExUnit case compiling that **same Rust source** with `--test -D warnings`, executing its seven pure tests, and asserting zero exit. This wires regression coverage into ordinary Mix tests instead of leaving cfg(test) controls unexecuted.

It does not accept any historical prompt, send exit before observed completion, loosen native answer/source/choice/literal/authority/cleanup checks, or alter the original four cases. No native, product, protocol, helper or deadline change is proposed. The native driver and ExUnit retain their original 60-second bounds. The helper's readiness predicate is confined to the synthetic driver's final exit phase; queued EOF and owner-kill branches retain their behavior.

Root read the full driver and operator_cli.exs, approved the predicate and private controls, then reviewed the clean one-file patch and required the extra ExUnit wrapper. The auditor authored the private candidate and wrapper; this is independent diagnosis of the original failure, not an independent review of the auditor's own repair. Root performs the clean-patch review/application.

## Source and runtime provenance

Owner graph `/tmp/ipse-reference-fixture-repair-20261027-02` was copied to `/tmp/ipse-independent-cli-pty-triage-20261027`. Its manifest `source-runtime-before.json` SHA256 is `a25520ddda629e3f9120e2d52e0fa866985047e2b7b8d6f1567c56ca6082255b`, binding 2,303 regular project/build inputs, excluding the owner's declared Mix test execution cache and Git metadata. Every declared byte matched in owner and private copy before any probes and after the final real Mix run. No input under project/build was edited for the candidate: additional candidate files and generated selectors live outside those sealed roots.

Original fixture bindings:

| Input | SHA256 |
| --- | --- |
| operator_input_test.exs | `5bb6e96bf61cfb29037889855d05d6c688dee5418857b59203d28f2a93c668ab` |
| operator_cli.exs | `bb7f2c4a288a2b92ef5cf0d12bde962876c10e6531ba8510c8d2f1b667b4549b` |
| operator_cli_pty.rs | `a2b1293abaed054a0d0611459d368465b320f5d7ecb62601a3557ffbb4b7cbef` |
| operator_pty.rs | `efd5a93217068ba39cb1640250b4ce9d2d53454f8169f81490d2c940906031f9` |
| operator_channel.exs | `e0497653cd1ca0beb208f3101e887e648f5a8cfeac0c43e9f94080be46d5f460` |
| operator_eof.exs | `f9e78b380d3418cb89851d9d3ab6c9b1a021e1fc241a8493ebacfbadd78408aa` |
| Actual copied ipse-runner helper | `d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b` |

The copied Runner's helper pin and app_dir select this private byte-exact helper from the private project cwd. No native helper was rebuilt; only the existing Rust **test PTY drivers** and new pure driver unit binary were compiled. Shared helpers were not used. Original private driver executable is retained, SHA256 `fbc24e6647c2be7f994ab2e96065dd97fa01ed61e72aa90d9cc9ebf246d1c1d7`.

Root full-repeat failure is retained byte-for-byte as `owner-full-repeat-failed.log`, SHA256 `54877213da7b254e9e55422db1d8dc6f605c35995336cffcac49b439ef8b138d`. It records 2,418/2,419 passed, four skipped, 36 excluded, total 1,680.1 seconds, sole failure operator_input_test.exs:46 at System.cmd line 76, ExUnit 60-second timeout. It remains a failed run. The earlier 44-failure full baseline passed this same case; that historical fact and a focused pass were not treated as proof against a race.

## Diagnosis from actual source

After a valid last native answer, Terminal.native_input clears the question, sets busy true and calls client_loop. refresh_reader selects the prompt request and can display `you> ` while the next model response is completing. reader_request's prompt identity depends on cancelling, not busy. When done is received, Terminal prints Finished and sets busy false, but refresh_reader sees the same prompt key and keeps the same live reader. It therefore need not print a second prompt.

The original Rust phase-five condition checks only the suffix after the last Finished. This conflates completion with prompt display ordering. The repaired condition recognizes the currently active prompt after the last question display, regardless of whether completion was rendered before or after that prompt. Native `/exit` is still sent only after completion is observed.

The original raw stall had already passed startup, native channel allocation, fresh question renders, rejection of invalid 99 and stale code, valid choice two, exact Unicode/literal answer handling, and model completion. This rules out startup/pipe/native-global-lock waiting as its observed blocking phase. The native per-user operator lock is nonblocking; contention is not silently retried. Native operator/PTY windows were coordinated with Root for every actual PTY run and explicitly released after final hash verification.

## Runs and retained outcomes

1. **Initial sandbox attempt: 0/4**, 7.7 seconds, retained in `original-four-first.log`. Sandbox `/tmp` metadata was uid 65534, mode 01777. The native helper requires a root-owned protected temporary root and therefore refuses before opening the operator channel. This is an execution-environment boundary, not the historical 60-second reproduction. `sandbox-tmp-metadata.log` retains only those narrow directory facts. Approved execution outside that filesystem sandbox supplied the real native boundary; no guard was weakened.
2. **Unchanged original four CLI cases: 4/4**, seed 20261113/max_cases 1, 2.8 seconds, `original-four-native.log`. Default ExUnit and native watchdogs stayed at 60 seconds. This pass alone did not diagnose the historical failure.
3. **Original raw driver, bounded up to 20, stop at first failure:** cases one–four passed in 602–666 ms; case five failed once at 60,017 ms. No retry or hidden restart occurred. `raw-original/case-5/stdout.log` SHA256 is `1882203e69bb72ee6c5261daacf2d4771949181ac26d24e9b765e03f498ee987`; its journal and `result.term` are retained. A live read of that synthetic journal's event types/statuses was saved to `raw-case5-live-journal.log` before watchdog cleanup. The bound and first failure were preserved unchanged.
4. **Private Rust pure controls: 8/8**, `candidate/unit-tests.log`. Seven portable controls plus an eighth private replay of the actual captured original stall prove the old guard false/new predicate true for the actual bytes. The private eighth case references private evidence and is intentionally excluded from the clean public patch.
5. **First private candidate original four CLI cases: 4/4**, seed 20261113/max_cases 1, 2.9 seconds, `candidate-four.log`. All original case assertions remain unchanged; the generated private test selector only redirects the Rust source path to the candidate.
6. **Candidate actual CLI repeated conversations: 20/20**, `raw-candidate-summary.log`, 590–614 ms each. Every run invokes the original operator_cli.exs assertions for exact input, fresh answers, two observed answer pieces, literal Unicode bytes, SourceIndex reads, Saved restore, no effects beyond ask_operator, and confirmed Session cleanup. Raw stdout and fixed phase traces are retained per case. Seventeen runs printed Finished then prompt; **three runs (4, 6, 17) printed prompt then Finished** and all completed successfully. This directly exercises the repaired ordering in real CLI runs. Those durations are fixture observations, not product performance or latency qualification.
7. **Clean portable Rust controls: 7/7**, `candidate/proposed-unit-tests.log`, rustc edition 2021 with `-D warnings --test`. Main/non-cfg(test) driver source is exactly identical between this clean source and the eight-control private candidate used for the four-case run; `final-checks.log` checks that byte equality. The raw phase-traced binary adds only private phase/elapsed/count diagnostics, recorded in its distinct source and executable bindings.
8. **Final real Mix suite: 5/5**, seed 20261113/max_cases 1, 3.0 seconds, `final-five-real-mix.log`: four original native cases plus the new ExUnit wrapper compiling/executing the same clean Rust file's seven unit controls. No twenty-case repeat was needed after adding this wrapper because driver main bytes did not change.
9. **After hash checks: 2,303/2,303 exact** in both owner and private roots, including helper d84d…; `final-after-inputs.log`. Only private Mix's declared execution cache is outside the original seal. No owner input was modified.

No paid/local model service, network service, qualification data, real credential, private transcript, broad process listing or environment dump was used. All conversations and stdout are synthetic. Narrow live inspection read only this auditor's own synthetic case-five journal. No process was killed outside the driver's own child cleanup and original owner-death fixture.

## Candidate bindings and replay

- Clean Rust source `candidate/proposed-operator_cli_pty.rs`: `b9f5490c18721b64304c2844d6c3c6d6af7c3851a6fc0fe3c39699c0b24eeaf5`.
- Private eight-control source `candidate/operator_cli_pty.rs`: `3e7a1dbd859a0487d8eb068cdacd5b450ad0aa878e46a9ea1312126c93d743b4`.
- Traced source `candidate/operator_cli_pty_traced.rs`: `228bb782011320f0bd1df6b1d5d11788ebe193c2072c017d4b2ba1226cb05eda`; executable `4410969463513a2e98f89a15d5b6dea1c43f44f82525b9398ad4bf87b5767aca`.
- Untraced candidate executable: `0fc57b998c50b9f9ad45d639d5065af5008ddca1746060bdd69a9ab3f112ec7f`.

`final-artifact-hashes.log` and the durable files manifest bind the final two-file patch, clean ExUnit source, final private selector and all new logs. `proposed-fixture.patch` is the superseded one-file proposal; `proposed-two-file.patch` is the final reviewable proposal. The clean test source contains repository-relative paths; its disposable private selector changes only the three existing CLI driver source references plus the new unit reference to the exact clean candidate path.

Commands actually used include:

```sh
elixir -pa '/absolute/private/build/lib/*/ebin' run-original.exs
rustc --edition=2021 -D warnings project/test/support/operator_cli_pty.rs -o original-pty
elixir -pa '/absolute/private/build/lib/*/ebin' run-raw.exs
rustc --edition=2021 -D warnings --test candidate/operator_cli_pty.rs -o candidate/unit-tests
candidate/unit-tests
elixir -pa '/absolute/private/build/lib/*/ebin' run-candidate.exs
elixir -pa '/absolute/private/build/lib/*/ebin' run-raw-candidate.exs
rustc --edition=2021 -D warnings --test candidate/proposed-operator_cli_pty.rs -o candidate/proposed-unit-tests
candidate/proposed-unit-tests
TMPDIR=/absolute/private/tmp-final-mix MIX_ENV=test MIX_BUILD_PATH=/absolute/private/build \
  mix test --no-compile /absolute/private/candidate/final-private-operator_input_test.exs \
  --seed 20261113 --max-cases 1
elixir verify-inputs.exs
```

Run only new disposable working copies, never durable evidence in place. Restore build/lib/ipse/priv as an alias to the working project/priv and chmod the working helper 0700; archive executables are data. Scripts use their private __DIR__, but generated historical selectors contain original absolute paths: regenerate with the retained make-*.exs scripts or adapt only disposable copies. The input verifier additionally compares the historical owner graph at its original path; independently checking retained manifest rows is sufficient if that historical source is no longer present. Keep actual operator/PTY tests serial; their conservative per-user lock is part of the existing native boundary. An ordinary sandbox whose /tmp is not root-owned cannot verify this facility.

## Limits and preservation

This diagnosis establishes a reproducible harness exit-readiness defect and a narrow, verified candidate. The original full-repeat remains failed; no complete source-suite pass, public application/commit, package, other OS, real human journey, paid inference or milestone acceptance is claimed. The final extra Mix case is pure readiness coverage; it grants no native authority and does not independently establish native security. Root owns public review/application and any new complete baseline.

The durable evidence includes all sealed graph inputs, exact helper/BEAM bytes, original failed full-repeat, original failed conversation and journal, all raw positive/negative transcripts, private candidate variants, final clean two-file patch, unit wrappers, commands, hashes and initial sandbox failures. All preserved directories are owner-only 0700, files 0600/single-link, with helper/test binaries stored as data. Every copied byte and declared manifest input is checked before/after preservation and synced. Dependency/source aliases are recorded without following unrelated external paths; executed private priv bytes are materialized. Preservation receipt and files manifest identify the exact final evidence set.
