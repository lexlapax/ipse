# Multi-page native recall diagnostic, 2026-11-02

This development investigation found an unfinished P31E recall path; it is not a qualification or milestone completion. Current status is in the [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance).

The existing automatic worker considers at most 32 indexed notes, so a pure worker test with 33 short notes reported partial coverage even when the complete projection fit the available envelope. An experimental change followed more 32-record index pages; its isolated worker tests included all 33 and passed an unavailable-source control. That change was not retained.

The [native Session fixture](../../../test/support/native_note_recall_many.exs) creates 33 actual, separately reviewed synthetic operator statements in one Session, closes it, and starts a fresh Session with a local synthetic provider. With the experimental worker, two runs saved all 33 but stopped before provider dispatch with an `unknown` worker-input result and unconfirmed task cleanup. The fixture's first launcher had a syntax error and did not execute the scenario. The experimental runs used seeds 791911 and 791912; the isolated worker controls used 791908 and 791909.

After restoring and rebuilding the original 32-note worker, the same fixture with `IPSE_RECALL_BASELINE_CONTROL=1` expected the existing partial 32-note result. It again ended before dispatch with an unknown worker-input result and unconfirmed cleanup (seed 791913; synthetic log `/tmp/ipse-recall-many-baseline-20261102.log`). This establishes a failure in this original-runtime scenario as well as in the attempted expansion. It does not establish the exact cause, a general failure for every 33-note store, or a safe timeout or permission change. None of the runs used a live model or supplied human attestation.

The opt-in diagnostic is excluded from the ordinary suite while the path remains open:

```sh
IPSE_TEST_RECALL_MANY=1 IPSE_RECALL_BASELINE_CONTROL=1 mix test test/ipse/session/native_note_recall_test.exs --only recall_many --max-cases 1
```

The baseline control currently fails as described. Removing `IPSE_RECALL_BASELINE_CONTROL` asks for complete 33-note recall and also remains an acceptance target. The next implementation needs to retain the real source and delivery boundaries while making this journey reliable, then verify its latency and the full fitting-set behavior. Increasing the worker's candidate count alone is insufficient.

After restoring the worker, the existing recall worker and native Session tests passed three tests with this diagnostic skipped (seed 791914). The normal bundle build, repository formatting check, strict compilation, isolated-home credential-free demo and documentation/link check also passed. These checks do not turn the failed diagnostic into a pass or establish whole-source qualification.
