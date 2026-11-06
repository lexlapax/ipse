# Witnessed-draft child counters, 2026-11-06

Historical verification record. The [testing guide](../../developer/testing.md#isolate-subprocess-inputs-and-shared-resources)
owns current contributor procedures; the [plan](../../plan.md) owns acceptance.
This extends the earlier [child-counter repair](ci-child-result-counters-20261106.md)
without changing draft behavior, approvals, test selections or deadlines.

## Failure and change

Completed Linux source partition 1 in hosted run `42207472372` failed two
otherwise successful draft controls because their common parent required the
rendered text `1 passed`. Its Elixir 1.18.6 children instead reported `10 tests,
0 failures, 9 excluded` and `17 tests, 0 failures, 16 excluded`.

The two existing entrypoints now disable autorun before loading the helper,
execute exactly one `ExUnit.run/0`, and require exact counters:

| Entry | Total | Failures | Excluded | Skipped |
| --- | --- | --- | --- | --- |
| MCP draft lineage | 10 | 0 | 9 | 0 |
| Extension draft lineage | 17 | 0 | 16 | 0 |

Only that result emits the fixed marker. The parent requires child exit zero
and exactly one complete marker line, handling the PTY's CRLF line endings.
Other failures in that hosted partition remain failed; this repair establishes
no native filesystem or platform support.

## Final focused result

The two existing outer controls passed in 4.1 seconds, with 25 unrelated cases
excluded. Each selected child traversed the actual synthetic PTY acceptance
and subsequent MCP or extension call, then passed its counter gate. The outer
and nested results describe the same two behaviors, not additional tests.

The run used Elixir 1.20.4/OTP29, the immutable current Job-binding Core runtime
and all 16 application siblings, normal application startup, a fresh private
home/tmpfs directory, one scheduler and a 180-second process-group timeout plus
ten seconds kill grace. No real model, paid provider, retained notebook or
operator account was used. This is a local source-fixture result, not a rerun
of hosted Elixir 1.18 or an installed-package qualification.

Source and runtime inventories remained unchanged. The wrapper reported an
empty owned group, no matching owned processes and no listener on port 39657.
A separate actual-host check also found both test groups, scoped processes and
the operator-input listener absent. An earlier callback-based candidate passed
the same two controls separately in 4.0 seconds; its source and receipts remain
preserved. The final entries use the existing explicit-run convention.

## Evidence and documentation review

Private fixtures/logs remain under `ci-24b9-followup-20261106`; no transcript,
journal or request payload is exported here.

| Evidence | SHA-256 |
| --- | --- |
| Original hosted Linux partition log | `cbfbe0a31223fb94a8829048a384075229cb7bb470cadfdeecb4521742994bcd` |
| Final focused source/harness manifest | `288ebe6ffaea129b8d5977bcb2c5e8c11bdb3adf5990946c22d63c24d21b4343` |
| Final focused output | `6ac80a4adfee8b5b10fa4598a710315e86155151429db10de0b156e67b241e76` |
| Final status | `fd03ecbe279f8c99bfa09bb3708f540c74f7b3ad97785b2573eb361b3aec9f2e` |

Whole-document review covered Testing (1,639 lines), operator Usage (500) and
Recovery (643). Their current exact-counter, native acceptance, current-revision
and no-replay guidance already matches the repaired tests; no manual rewrite
was needed. Canonical Elixir 1.18 formatting and the tracked documentation-link
check pass. Full current-source, hosted, installed and platform gates remain open.
