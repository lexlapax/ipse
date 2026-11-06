# Separate selection references from later semantic reviews

Dated **2026-11-06**. This is a development-contract checkpoint, not a new live
study, model-quality result or milestone acceptance. The
[plan](../../plan.md#p30-advisory-decision-engines) owns current scope; the
[developer chapter](../../developer/decisions.md#exercise-a-consumer-without-contacting-an-engine)
teaches the current workflow. Historical declarations and results remain valid
under their original formats.

## Problem and repaired contract

Version-1 selection declarations commit one combined label/review file before
candidate collection. Its reviews must already name the candidate's prediction
and citation IDs. `ProtectedAnswer` derives those IDs from the later real
invocation/result and exact claim/span pairs. That format cannot generally
precommit independent reference labels while admitting those later reviews.
The earlier [packaged paired protocol](../2026-11-05-packaged-paired-cli/index.md)
does not claim to have completed this scoring lifecycle.

New version-2 declarations keep the existing finite limits, case/blob joins and
benefit bars, with a separate lifecycle:

1. `commit_references/1` validates reference-only bytes containing case IDs and
   critical note members. The caller freezes their hash before either answer.
   Prediction IDs, semantic verdicts and independence assertions do not belong
   in this file.
2. After the complete ordinary answer is projected, its actual baseline blob is
   committed in the OFF declaration before candidate work. `verify_references/3`
   checks the earlier reference commitment and exact case population.
3. `freeze_rows/3` binds first candidate rows. `prepare_reviews/5` verifies the
   full baseline blobs and actual first-row digest before producing a flat
   opaque-ID semantic template, with no arm/route/engine labels. Verdicts remain
   `unmeasured`, with `independent:false` and an unassigned reviewer.
4. `score/7` verifies the original frozen population and reference bytes before
   invoking its separate review loader. It rejects changed bindings, missing or
   extra prediction reviews, foreign citation IDs and mixed historical formats.
   The caller supplies the blinded saved answers/evidence and genuine reviewer
   custody. A digest cannot prove chronology, blinding or independence.

Historical version-1 declarations retain `score/6`; neither API silently
converts the other format. Unknown/missing predictions remain absent, unknown
time and cost remain null, and unmeasured reviews produce no quality comparison.
Even a measured calculation does not establish a qualified strategy.

## Actual verification and preserved failure

One bounded direct-Elixir run against an immutable sixteen-application runtime
stopped at compilation of a new test fixture's nested capture expression.
**No tests ran.** Its primary status was 1; input/runtime posts passed and its
owned process group was empty. That first outcome remains separate.

The correction replaced only that nested capture with an explicit function.
A fresh run used the same 60-second limit plus ten-second termination grace,
one scheduler, strict compile diagnostics and exact counters:

| Actual corrected scope | Result |
| --- | --- |
| Selection controls | 15 cases: nine preserved historical controls and six version-2 controls |
| Protected-answer isolation wrapper | One outer case enforces twenty child cases: nineteen preserved controls and one new scoring join |
| Outer result | **16 passed**, zero failures, skipped or excluded; 3.7 seconds |
| Integrity and cleanup | All seventeen source/input hashes and the full runtime inventory unchanged; strict diagnostics empty; Ipse App not started, host domain module unloaded, ports unchanged; owned process/group absent, independently rechecked |

The outer and child counts are **not additive**. The new integration control
commits references before constructing actual `Invocation` intent/result objects,
uses `ProtectedAnswer.response/4` for exact citation-pair IDs, freezes rows, then
invokes the separate review loader. Its reviews remain non-independent and
unmeasured. It does not run a protected service or replace the existing authentic
paired Session evidence. The controls also reject ID/citation/population
substitution, altered commitments, wrong loader ordering and version mixing.

The current source tests can be exercised from a normally built checkout with:

```sh
mix test test/dev/selection_experiment_test.exs test/dev/evaluation/protected_answer_test.exs --max-cases 1
```

The recorded run used a separate immutable runtime and direct ExUnit entry,
without Mix compilation, App startup, native helper dispatch, Input, model calls
or original retained-notebook access. It verifies this source contract; a fresh
paired version-2 evaluation recipe, independent labels, accepted matched quality,
whole-task time/cost and a current whole-default baseline remain open.

## Provenance and editorial review

| Input/evidence | SHA256 |
| --- | --- |
| `selection_experiment.exs` | `57722cc2fd84de3eadcdb18ec3ae5f649d8b5816b73e547ad771840b6d38ab6f` |
| Selection tests | `18448f808e64252de2d07c88c62025594bd1ead000ea9672c89b9ba00ff4728b` |
| Protected-answer child cases | `5e22b28d72493834d4f9c237a2ed2fe2a514c57e3d89332051e3c1171dbf1cb8` |
| Protected-answer isolation wrapper | `5ec487872a4b7e221f4cef685a7c2588382fe69f95a10bfba1d015a35a0b4365` |
| Corrected run log | `a0f5a9b1e25d301cf831d1573eec5ec2b4f6fc4cd4f3633415eb7ec5a0b814b4` |
| Corrected run status | `75ba9abe117a40650fc6636bc9b83298599fddc57a64b72f0534d258eafdd072` |
| Runtime inventory | `211b2bdb9ac11702d679c089516699d2e7b9a9cefe58f28b48a654afecfc34e2` |
| Failed first compile log | `6e65ce4c4eae609b6a8f65998f47a68ffaf1cda1b7da702673fd31853eee667d` |

The whole developer Decisions chapter and overlapping operator Knowledge
Permissions chapter were reviewed. The developer flow now separates reference
custody, baseline freeze, blinded review preparation and scoring, with worked API
examples and historical-format limits. The operator's finite shadow grant,
approval and experimental-use procedures are unchanged; no operator edit was
needed. Source formatting used canonical Elixir 1.18.5/OTP 27 and the focused diff
check passed. This checkpoint grants no authority or qualified default.
