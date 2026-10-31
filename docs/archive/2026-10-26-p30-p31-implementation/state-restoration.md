# Timed State restoration — 2026-10-29

This record covers the generic State decision contract and focused Memory
journeys, not completion of P30/P31. The [reviewed native owner](state-native-owner.md)
performs the final clock decision after staging while retaining the namespace
lock. A decision before expiry can physically finish after expiry; this is the
original P26 contract, not a promise of physical completion by the deadline.

The indiscriminate timed-put refusals were removed from `State.execute`, its
private write path and `Session.Invocation`. The approved request's original
`write_before_ms` reaches the native decision. CAS conflict takes precedence
over initial expiry, which takes precedence over quota; the final native
decision returns its actual checked time when staging crosses expiry. The
historical `state_deadline_fence_unavailable` receipt remains valid for saved
reconstruction. Managed State/service refusal and the independent Collection,
document, Review, source-use and output gates remain in place.

## Focused controls

[Source, runtime inventories and logs](state-restoration/manifest.sha256) record
the tested cohort. The State and Invocation files are the exact copies compiled
into `_build/state-restoration-sol-20261029`; the Invocation copy predates a
separate concurrent managed `collection.store` refusal. It must not be mistaken
for a test of that later change. The private managed-session fixture copy is
also preserved. The matching native/backend source is in the separately frozen
[native-owner evidence](state-native-owner/manifest.sha256). A second graph
uses the matching hook helper solely for the controlled final-decision test.

- Two State receipt cases pass for live success, elapsed failure, conflict
  precedence, closed receipt validation and unchanged state. A separate
  revision-exhaustion control proves conflict, then expiry, then quota.
- A real State operation held after synced staging until expiry returns the
  native checked-at value and leaves its prior record unchanged. Earlier raw
  native controls separately demonstrate that physical completion may follow a
  valid pre-expiry decision, and that lost acknowledgment remains unknown.
- Actual Memory Session tests pass for live remember and active import, and for
  delayed approval of each after the existing target expires. Delayed cases
  assert unchanged stored state, a `write_deadline_elapsed` action receipt,
  no expired recall and no automatic action replay on resume. A separate actual
  Session case stores a fresh expired backup without making it visible.
- Actual extension Session controls pass for an ordinary timed put and an
  ordinary untimed put, and for refusal of a managed timed put before its
  action intent even with `--yes`. They use synthetic inputs and a fixture
  provider, not a live model or external account.

The first Memory run used relative `ERL_LIBS`; the extension worker changed
directory and could not load its bootstrap, before any State action. The trace
and failure are retained. An absolute graph path fixed that fixture setup. The
first absolute run passed the live and expired-backup cases but the two delayed
cases failed a test assertion that compared action counts to a snapshot taken
before a later recall. Both passed after comparing to the actual pre-resume
journal; neither failure is hidden. The first copied managed-test launch also
failed its relative support path before test execution; a private matching test
layout passed both affected cases. These are scoped controls, not an aggregate
runtime, package or platform qualification. The first absolute run used the
earlier Memory fixture; `initial-memory-fixture-reconstructed.exs` reverses the
one assertion repair and matches the retained diagnostic copy apart from its
explicit instruction to retain the synthetic workspace.

The tests were run with an absolute graph path, for example:

```sh
ERL_FLAGS='+S 4' ERL_LIBS=/home/lexlapax/projects/lexlapax/ipse/_build/state-restoration-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [line: 360, line: 364, line: 368, line: 372, line: 429]); Code.require_file("test/extensions/bundled/memory_session_test.exs")'
IPSE_STATE_NATIVE_HOOK_TEST=1 ERL_FLAGS='+S 4' ERL_LIBS=/home/lexlapax/projects/lexlapax/ipse/_build/state-restoration-hook-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [line: 92]); Code.require_file("test/ipse/extension/state_owner_loss_test.exs")'
```

The first command describes the retained initial absolute run, whose delayed
assertion failures were repaired and rerun separately; its line selections
refer to the reconstructed earlier fixture. Remaining completion work includes current
manual reconciliation, broader required checks at the appropriate milestone,
the other still-gated lifetimes, and the explicit mixed-old-writer and
non-Linux limitations in the native-owner record.
