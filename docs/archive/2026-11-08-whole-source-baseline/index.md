# Whole-source baseline on the P30/P31 integration branch

Historical reference only. This record preserves the first passing complete
source baseline on `codex/p30-p31`. Use the [current plan](../../plan.md) for
status and the [testing chapter](../../developer/testing.md#run-the-complete-source-baseline)
for the procedure.

| Provenance | Value |
| --- | --- |
| Source commit | `b6df1b11` (`codex/p30-p31`) |
| Toolchain | Elixir 1.18.5, Erlang/OTP 27.3.4 (CI parity), Rust helpers from `./dev/build.sh` |
| Host | Arch Linux, kernel 7.2.11, 20 CPUs, 46 GB memory; no other suite or load generator running |
| Date | 2026-11-08 (US/Pacific); suite 16:41–19:13 |
| Replacement | [Current plan](../../plan.md#execution-order-for-p30-and-p31) |

## Result

| Command | Result |
| --- | --- |
| `./dev/build.sh` | Pass; native helpers, warnings-as-errors compile and inert bundle catalog |
| `mix format --check-formatted` | Pass |
| `mix compile --warnings-as-errors` | Pass |
| `elixir dev/check-ci-policy.exs` | Pass; action references pinned |
| `elixir dev/check-docs.exs` | Pass; 0 errors |
| `mix test` | **4,665 tests, 0 failures**, 132 excluded, 136 skipped; 9,132.7 s (264.3 s async, 8,868.4 s sync); exit 0 |
| `IPSE_HOME=$(mktemp -d) ./bin/ipse demo` | Pass |

This is a local single-VM run. Hosted CI partitions, other platforms, packages and
installed checks were not run for this record. Opt-in workloads such as the
2,000-note integrated cohort are excluded by default and remain separate gates.

## Earlier runs on the way to this result

Each earlier run is retained as a failure, not merged into the passing count.

| Run | Source | Outcome | Disposition |
| --- | --- | --- | --- |
| 1 | Before `6e41801b` | Summary of 3,425 tests, 99 failures; several later collection controls never ran | Operator-input PTY tests contended for one per-user channel lock, and the OTP 27 `-noshell` stdin reader consumed typed lines meant for native helpers. Fixed in `6e41801b` (per-terminal lock with bounded wait; `Ipse.Runner.TerminalInput` pauses the VM reader). All 23 affected files then passed serially, 151 tests. |
| 2 | `308ef051` | 4,665 tests, 4 failures | Three collection adapter controls required a clean close after deliberately closing the native lock port; the helper exit is then unconfirmed, as the [draft-abort record](../2026-10-26-p30-p31-implementation/document-draft-abort-20261106.md) already established. One replay-cache test used the 100 ms receive default; under load its scope cleanup killed the linked borrower task and surfaced as a killed test process. Test expectations corrected in `b6df1b11`; runtime unchanged. |
| 3 | `b6df1b11` | 4,665 tests, 13 failures | All 13 failed in the async phase while leftover CPU load generators from a separate stress check were still running (async phase 597 s versus 264 s). The nine affected files then passed alone, 94 tests. Not a baseline. |
| 4 | `b6df1b11` | Pass | This record. |

The abort control can now stop before its result append, because a poisoned
retirement share stops the Session; its unmatched intent is the durable unknown
record and resume stays inert. The opt-in 2,000-note cohort run on the same day
left one native commit outcome unknown in segment 55; that root is retained,
was not resumed, and is tracked under the plan's notes lane.
