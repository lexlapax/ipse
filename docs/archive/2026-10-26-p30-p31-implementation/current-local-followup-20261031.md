# Current local follow-up checks

2026-10-31. Historical component and integration evidence after the
[failed full-source baseline](full-suite-20261031.md). This is not an independent
audit, full-suite pass, installed qualification or P30/P31 completion. Current
acceptance belongs to the [plan](../../plan.md).

## Source and ordinary checks

The isolated legacy SDK, journal-resource and fixture repairs were copied back
to the original worktree as 23 explicitly listed, byte-verified files. The
pre-run original source manifest still matched before copying. No retained
`.serenity-*` evidence was changed. The follow-up
[runtime/test manifest](current-source-20261031.sha256) has 1,069 entries and
SHA-256 `d831d96cf880adacd4f93911d98ba4be362446df9436c23ae7ca4eeb8a3a82cd`.
It matched again after the initial P30 protected-input controls. The native
helper remains
`c6768890455697de64284463092806fa2e30305a7ea7b8e6ee60c625f3f0ccff`.

On this original worktree:

- `./dev/build.sh` passed, including native compilation, warning-free host
  compilation and a fresh Knowledge bundle.
- `mix format --check-formatted` and `mix compile --warnings-as-errors` passed.
- The credential-free scripted demo passed.
- Seven focused files passed **99 tests in 38.5 seconds**, covering managed
  receipts/current use, signed reads, worker projections, legacy SDK publication
  and unchanged strict gates.
- Twelve P30 files passed **79 tests in 14.7 seconds**, covering neutral typed
  contracts, provider transport, configuration, capabilities, Session
  admission/replay, usage and pure policy/metric calculations.

The first sandboxed build and demo stopped because Mix could not acquire its
loopback filesystem-lock socket (`:eperm`). Their socket-enabled reruns passed;
TLS and test boundaries were unchanged. Logs are the ephemeral
`/tmp/ipse-followup-root-{build-escalated,format,compile,demo-escalated,regressions}.log`
and `/tmp/ipse-followup-p30-current.log`.

The separate [accepted recall](accepted-recall-20261031.md),
[legacy admission](legacy-sdk-admission-20261031.md) and
[result expiry](output-expiry-fixture-20261031.md) records retain the precise
native follow-up scopes. The larger isolated managed Collection file still
failed **44 of 123 tests**, with 79 passed and 15 skipped. It ran before the
obsolete unmanaged blanket-refusal assertion was repaired; both selected current
publication cases subsequently passed. Those selected passes do not replace
either failed aggregate.

## Current-runtime protected decision input

The existing native fixture runner was invoked with the current graph
`_build/test/lib`, rather than its formerly documented retained pre-gate graph:

```sh
elixir test/support/managed_literal_pair_runner.exs \
  /tmp/ipse-current-p30-split-20261031a _build/test/lib split
IPSE_LITERAL_AB_ROOT=/tmp/ipse-current-p30-split-20261031a \
  IPSE_TEST_MANAGED_PACK=1 mix test \
  test/ipse/extension/managed_collection_call_session_test.exs \
  --only managed_pack_actual_overflow
```

It created eight genuinely reviewed synthetic literals across two separately
closed original Sessions, generation 8, with both journal hashes retained. The
helper's old `HISTORICAL_SEED` marker is not the runtime selection; the explicit
argument above identifies this run. Native PTY automation establishes the tested
input boundary, not participation by an independent human.

The protected over-budget control passed **1 test in 23.2 seconds** (137
excluded). It read all eight records, obtained the actual context allocation,
sent the synthetic shadow decision and remeasured the result without publishing
Collection or State changes. A fresh `20261031b` seed then passed
`managed_pack_actual_overflow_stale` in **14.5 seconds**: withdrawing the first
original journal before preflight prevented decision dispatch, while retaining
all eight dependencies, valid Saved reconstruction and restored journal hashes.
The logs are `/tmp/ipse-current-p30-protected-overflow.log` and
`/tmp/ipse-current-p30-protected-preflight-loss.log`, with matching
`/tmp/ipse-current-p30-split-seed{,-b}.log` seed receipts.

A third fresh `20261031c` seed passed `managed_split_response_lost` with
`IPSE_TEST_SOURCE_INDEX=1` in **17.0 seconds**. The second original journal was
withdrawn after the synthetic request arrived and before the held response was
released. No successful decision result or worker reprojection was delivered;
all eight dependencies, Saved reconstruction and restored source hashes were
checked. This is response withholding after an already dispatched request,
not a zero-egress claim. Its logs are
`/tmp/ipse-current-p30-protected-response-loss.log` and
`/tmp/ipse-current-p30-split-seed-c.log`.

These are current-source protocol/ownership controls using a test-only worker,
synthetic query and explicit fixture approval. They are not separately granted
finite-experiment consent, a production selectable consumer, an independent
quality workload, live engine eligibility, latency/cost benefit or a qualified
default strategy. The unchanged full-source failures and remaining protected
display, correction, lifecycle, quality and package gates remain open.
