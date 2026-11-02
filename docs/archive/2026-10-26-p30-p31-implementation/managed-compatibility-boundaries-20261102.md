# Managed compatibility and historical-source boundaries

Dated **2026-11-02 UTC** (**2026-11-01 US/Pacific**), author-run Linux synthetic
verification based on `ce43601`. Historical engineering record, not independent
review or whole-P30/P31 acceptance. Current instructions belong to the
[Collection SDK](../../developer/collection-sdk.md) and
[knowledge recovery](../../operator/recovery.md#inspect-unconfirmed-protected-knowledge).
The [plan](../../plan.md) owns remaining qualification. This follows the failed
[complete module](managed-collection-module-current-20261102.md), preserving its
170-passed/five-failed/15-skipped aggregate unchanged.

## Preserve the actual publication contract

Session's named admission requires a valid single-new-record V3 managed capture.
V2 managed objects remain valid historical protocol data but do not acquire that
execution path. The [recorded admission](notes-publication-admission.md) explicitly
keeps legacy shapes gated. The distinct supported legacy `collection.call`
[publisher](legacy-sdk-admission-20261031.md) is not a V2 `collection.managed`
permission. No admission, source, native owner or publication gate changed here.

Three remaining Session tests still expected successful V2 publication before
their queue, concurrency or deferred-Identity-loss boundary. A current-source
reproduction confirmed that all three stopped at the intended shape refusal,
before those later assertions. Their replacements explicitly observe the actual
valid V2 request and exact gate reply before checking no managed publication
intent/result, no reservation or ledger change, unchanged collection, strict
Saved and nonreplaying idle resume.

The cases cover an empty store, a trusted 64-row pending fixture and two concurrent
candidates at 63 rows. Raw test rows establish geometry only. These are V2 refusal
controls, **not V2 capacity, publication or late-loss qualification**. Both
concurrent Sessions are admitted before either starts work; active Identity
ownership during Session startup is a different boundary.

The supported V3 lifecycle/full-queue and competing-last-slot controls remain.
The V3 late-Identity-loss case now uses a registered synthetic loopback main route.
It reaches actual native publication and the checked deferred packet, then loses
the original native owner before outer Identity completion. Its assertions retain
the published root, unknown action, full publishing/unknown liability with null
actual/receipt despite smaller private measurements, prepared domain, unconfirmed
close and unchanged liability across inert resume. Exactly one main request occurs;
there is no final request after the loss. The old V2 late-loss assertion is not
reported as having reached that boundary.

The refusal diagnostic previously claimed the native clock could not fence
scheduling before rename. That physical-completion wording contradicts the
recovered final-locked-decision contract. It now identifies the unavailable request
shape, preserves the no-publication-started statement and points to knowledge
recovery. It grants no effect, changes no stored error code and does not change
readiness flags. Existing generic error tests now include its real recovery anchor.

## Fresh genuine historical input

The retained `_build/retention-cli-final-switch-20261028/lib` matches all **209**
host/helper identities recorded in the original
[historical-source inventory](literal-v4-source-union/runtime.json). Before new
execution, a separate receipt also hashes **615** dependency/host BEAM and app
files. All those path sets and bytes match after the seed and consumer finish.
Original transitive dependency identities, system Elixir/ERTS, environment,
permissions/inodes and in-memory code are outside that attestation.

The exact archived PTY and seed sources run against that retained historical
runtime in a fresh private root:
`/tmp/ipse-historical-literal-20261102-c17077cf869560a6`.
Actual native identity/consent and `/remember ordinary` statement/category reviews
publish one genuine signed literal at generation 1. Its original source journal
is kept at its original path; it is not copied, synthesized or substituted with
a current-runtime capture. No inference is dispatched. This is fresh old-format
input, not an aged retention/endurance fixture.

The current consumer imports its actual synthetic test artifact and explicitly
selects its existing fixture policy while preserving the historical namespace,
recipes and source categories. It obtains the genuine version-4 A and delivers
a fresh quote from independent current Session B before holding the candidate.
Only then does the controller rename A's original journal. Earlier withdrawal
would exercise the already-qualified Worker-input fence instead of publication.

Tracing the real publication guard proves the candidate cites only B while the
complete causal union still contains A. Structural admission returns true and
one exact action intent is journaled; owned current-use validation refuses before
reservation or successful storage. Complete root witness, snapshot and Consent
ledger remain unchanged. The subscriber, Session metadata and restored messages
contain no A text. Strict Saved and idle resume work while A remains unavailable,
without replay or accounting change. The original is restored and checked byte
for byte after the case.

The historical test now shares the existing optional-fixture convention: absence
of `IPSE_LITERAL_AB_ROOT` produces an explicit skip, with no fresh-current-source
fallback. The separately executed real fixture above supplies this checkpoint's
historical evidence. A skip itself proves no upgrade behavior.

The final combined check uses a second independently created native seed at
`/tmp/ipse-historical-literal-20261102-391b473af4f54ab0`. The first fixture and its
reused-marker failure remain preserved. Both seeds start from the same unchanged
recorded historical runtime; neither is a replay of a saved capture.

## Executed checks and retained failures

| Seed | Selection | Result | Seconds | Exit |
| --- | --- | --- | --- | --- |
| 791751 | Original three V2 cases plus V3 late-loss at current committed source | 1/4 passed, 186 excluded | 58.9 | 2 |
| 791752 | Three V2 refusals plus V3 lifecycle, queue, concurrency and registered late-loss | 6/7 passed, 183 excluded | 29.6 | 2 |
| 791753 | Same seven controls after admitting both concurrent Sessions before work | 7 passed, 183 excluded | 30.3 | 0 |
| 791754 | Current consumer using the fresh genuine historical-runtime literal | 1 passed, 189 excluded | 12.7 | 0 |
| 791755 | Complete CLI-error, managed-shape and strict-deadline contract modules | 27 passed | 0.8 | 0 |
| 791756 | Combined post-build eight-case selection; reused historical release marker raced the observation hook | 7/8 passed, 182 excluded | 48.7 | 2 |
| 791757 | Combined post-build controls with marker cleanup and a fresh historical seed | 8 passed, 182 excluded | 33.4 | 0 |

The 791756 historical case reused the first native seed after its successful
selected run. The prior case's cleanup had left `.candidate-release`, so its
worker could proceed before the controller installed publication tracing.
The missing trace is not evidence of an admitted source bypass. Read-only
inspection preserves that fixture and confirms generation 1, two failed consumer
publication results and one unknown input in each consumer; the only successful
publication remains the original historical seed. Its store was not rolled back,
reset or replayed. Literal-fixture setup now removes the stale release marker
before new work. A separate fresh historical seed is used for final verification.

The 791752 failure was the second Session's startup refusing busy Identity after
the fixture had already prompted the first. Both are now admitted first; no
product lock, timeout or authority check was weakened. Native/Mix/PTY cohorts
run serially. These focused results neither subtract failures from an older
aggregate nor establish a new complete module/full-suite result.

Reproduce the current boundary controls in a built checkout:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only legacy_managed_refusal --only publication_identity_loss --only registered_capture_lifecycle --only registered_competing --max-cases 1 --seed 791753
IPSE_LITERAL_AB_ROOT=/tmp/ipse-historical-literal-20261102-391b473af4f54ab0 mix test test/ipse/extension/managed_collection_call_session_test.exs --only legacy_managed_refusal --only publication_identity_loss --only registered_capture_lifecycle --only registered_competing --only historical_literal_capture --max-cases 1 --seed 791757
```

The second command requires the actual retained original fixture and a matching
current build; its path is local evidence, not a fresh-checkout seed recipe.
Do not copy its journal to another location or run the old publication against
current source by overriding a gate. The [selected-file and local-log receipt](managed-compatibility-boundaries-20261102.json)
records the final source/test identities separately from historical runtime
inventories. No external model calls were made.

Whole-document review covered the operator recovery workflow and developer
Collection chapter, with the permission and source chapters' unchanged authority
contracts retained. Recovery now distinguishes a new unsupported-shape refusal
from a previously successful capture whose delivery was withheld. Current manual
examples, historical source ownership and audience entry points were reconciled;
dated verification stays here and package status stays in the plan.

`./dev/build.sh`, global formatting validation, warning-free compilation and the
credential-free demo each exited 0. The final documentation check covered 1,034
Markdown files and 8,568 local links with zero errors. Git enumeration emitted
permission warnings for existing private staging directories; their contents
were not read or copied into this change. The selected receipt records these
logs and the exact final source/test/helper hashes.

Full-source, installed, independent quality, complete lifecycle/capacity and final
adversarial/reviewer acceptance remain open.
