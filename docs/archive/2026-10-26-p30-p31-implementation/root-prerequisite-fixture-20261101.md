# Canonical root-prerequisite fixture repair

Dated **2026-11-01**, author implementation on `f44b63c`. Historical verification
record; [the plan](../../plan.md) owns milestone acceptance and the
[testing manual](../../developer/testing.md#require-positive-controls-and-inspect-uncertainty)
owns current fixture guidance. This is a test-only correction, not a new runtime
permission or full-source acceptance.

## Reproduced failure and cause

The clean-clone complete baseline at `f44b63c`, seed 791639, reported its first
failure in `ManagedToolUseTest`: distinct own absence reads were refused as
publication prerequisites. That baseline is still running; its log is
`/tmp/ipse-p30p31-full-source-20261101-fdrped/test.log`. No complete aggregate is
claimed here, and the frozen clone has not been changed.

The fixture supplied its two root observations in request order, whereas the
host stores `ManagedReference.union/1`'s canonical digest order. The production
invocation validator requires that complete canonical union. A read-only pure
reproduction, `/tmp/ipse-root-prerequisite-order-20261101.exs`, showed both
individual cache checks passing, the original publication check refusing and
the same two reads in canonical order passing. Its log is
`/tmp/ipse-root-prerequisite-order-20261101.log`.

An isolated run of the actual prerequisite tests reproduced **2/3 passed,
10 excluded**, seed 791640, exit 2, before the repair. The log is
`/tmp/ipse-root-prerequisite-baseline-20261101.log`.

## Preserve the intended positive and negative controls

The shared fixture constructor now uses the existing public union helper before
storing invocation reads, dictionary entries and read IDs. This retains all
dependencies and canonicalizes the altered negative variants too, so root,
policy, cache and scan controls exercise their intended refusal rather than an
earlier ordering failure. No runtime source, cache classification, authority,
deadline, native helper or publication predicate changed.

The complete pure `managed_tool_use_test.exs` module then passed **13 tests,
0.05 s**, seed 791643, exit 0, in a separate Elixir VM:

```sh
elixir -e 'Code.prepend_paths(Path.wildcard("_build/dev/lib/*/ebin") |> Enum.map(&Path.expand/1)); :ok = Application.load(:ipse); ExUnit.start(autorun: false, seed: 791643, max_cases: 1); Code.require_file("test/ipse/session/managed_tool_use_test.exs"); result = ExUnit.run(); if result.failures > 0, do: System.halt(2)'
```

Log: `/tmp/ipse-root-prerequisite-fixed-loaded-20261101.log`. The VM loaded the
already-built development dependency closure and Ipse application metadata;
it started no application, native helper or model and wrote no host BEAMs.
This kept the full native baseline exclusive. Two earlier whole-module launches
each passed **12/13** but lacked, respectively, the MCP dependency path and the
application-version metadata required by the discovery fixture. Those launch
failures remain in `fixed` and `fixed-closure` logs; no production change was
made to bypass them.

The fixture was formatted with Elixir's standard formatter using this project's
default options, without running Mix or rebuilding runtime modules. The testing
chapter was reviewed in its existing source/fixture/native structure and now
explains canonical input before its registered capture examples. Operator
procedures and behavior remain unchanged. Documentation checking passed
**1,012 Markdown files, 8,398 local links, 0 errors**, log
`/tmp/ipse-root-prerequisite-docs-20261101.log`; pre-existing inaccessible private
ledger warnings remain without inspection or repair.

These shaped observations and cache entries prove pure consistency only. Actual
source ownership, committed reads, permission and publication still require the
separate registered/native Session controls. The running complete baseline is
against the unmodified earlier revision and will retain its original failure;
this focused pass does not replace or reduce any full-suite failure count.
