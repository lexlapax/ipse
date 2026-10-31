# Pending review: historical display and current publication

2026-10-31. Historical implementation decision and local verification record
from the dirty `codex/p30-p31` worktree, following the developer's request to
step back from the source-path display investigation. This is a course
correction, not independent review or P31E acceptance. Current guidance belongs
to the [developer manual](../../developer/knowledge-extensions.md#follow-protected-capture-from-a-session-source),
[operator manual](../../operator/knowledge-permissions.md#save-your-own-reviewed-statement)
and [plan](../../plan.md).

The later [public CLI integration](pending-review-cli-20261031.md) supersedes this
record's closed-public-route status. Its historical-display decision and test
cohort remain as recorded here.

## Decision and original requirements

Display the exact signed pending proposal as historical data under its target
Identity, active Consent, Collection and management journal owners. Release the
target owners before waiting for input. After native `accept CODE`, independently
acquire the original source and freshly revalidate the current consent and
unchanged target before consuming the one-use permit and publishing.

The [baseline](baseline.md#confirming-a-proposed-decision) requires exact native
selection with preserved original provenance, then source-version/exclusion and
current-consent checks before publication. The [independent direction](pending-acceptance-independent-direction.md#minimal-supported-owners)
expressly leaves original-source ownership during historical display as a
purpose clarification; it does not require a fifth native lease. The current
[extension trust boundary](../../developer/extension-effects.md) treats workers
as trusted executables with ordinary OS permissions. Host effect mediation does
not sandbox arbitrary same-user file replacement. None of these contracts
promises instant revocation of historical text against that actor.

The preceding [checkpoint](checkpoint-pending-acceptance-20261029.md) demonstrated
that a source lock pathname could be replaced before historical card output,
while later publication refused. That observation remains valid. Its assertion
that no historical text may appear was stronger than the approved baseline and
sent implementation toward an unnecessary native fencing protocol. This record
supersedes that blocker without erasing the failure or file-lease experiment.
Current-source disclosure and egress still require their own current-use guards;
this decision only covers clearly labelled historical pending review.

## Implementation

`Management.begin_acceptance_review/7` reads the actual signed pending target
through the existing Identity/Consent/ObservedRead adapters. The private terminal
entrypoint explicitly selects historical review and reuses the existing four-owner
native protocol. No native protocol, dependency or permission scope was added.
The earlier test-only pre-write PID instrumentation was removed.

`publish_consumed_acceptance/7` keeps its separate original-source acquisition,
exact proof comparison, fresh policy and target verification, bounded plan,
one-use Review permit, journal-before-effect and unknown/no-replay handling.
A displayed card or native input alone cannot recreate publication authority.
The public CLI acceptance route remains closed.

The regression now holds an independent replacement source lock before review,
without helper instrumentation. It requires historical card text to appear,
publication to refuse before an acceptance event or intent, no acceptance link,
and the exact pending Collection result (including revision/generation) to remain
unchanged. The original lock pathname is restored after the isolated test.

## Local evidence and limits

`./dev/build.sh`, `mix compile --warnings-as-errors`, test-environment
compilation, `mix format --check-formatted` and `./bin/ipse demo` passed.
The documentation checker inspected 956 Markdown files and 7,973 local links
with zero errors. These aggregate build/manual checks do not establish full
milestone acceptance. Focused checks:

- `mix test test/ipse/cli/management_acceptance_selection_test.exs test/ipse/runner/review_test.exs`: 25 passed.
- `mix test test/ipse/cli/management_acceptance_selection_test.exs test/extensions/knowledge/knowledge_session_test.exs --only capture_parent_case`: two passed, two opt-in cases skipped, three excluded. The selection module is excluded by this tag; its coverage comes from the preceding command.
- Fresh-artifact `genuine_pending_acceptance`: one passed, five excluded. Covers synthetic main-model Session capture, native cancellation, acceptance with original proof and atomic selected-state checks, duplicate refusal, and consent revocation during human input.
- Separately isolated fresh-artifact `genuine_pending_path_swap`: one passed, five excluded. Covers historical display with unavailable source, unchanged pending state and refused publication.

The two fresh-artifact controls each copy the compiled test runtime into a
separate temporary directory, replace its `priv` symlink with a copy, and remove
only that copied bundle catalog. The existing test stages its freshly built
Knowledge artifact there and asserts installed/fresh manifest equality. Run one
tag per copy because staging requires an absent target catalog:

```sh
MIX_ENV=test mix compile --warnings-as-errors
trial=genuine_pending_acceptance # or genuine_pending_path_swap
trial_runtime=$(mktemp -d /tmp/ipse-historical-review.XXXXXX)
cp -a _build/test/lib "$trial_runtime/lib"
rm "$trial_runtime/lib/ipse/priv"
cp -a priv "$trial_runtime/lib/ipse/priv"
rm -rf "$trial_runtime/lib/ipse/priv/extension-bundles"
set --
for beam_dir in "$trial_runtime"/lib/*/ebin; do
  set -- "$@" -pa "$beam_dir"
done
IPSE_TEST_GENUINE_PENDING_ACCEPTANCE=1 IPSE_TEST_PENDING_PATH_SWAP=1 \
  IPSE_TEST_FRESH_BUNDLE_ROOT="$trial_runtime/lib/ipse/priv/extension-bundles" \
  elixir --erl '+S 2:2' "$@" -e \
  "ExUnit.start(exclude: [:test], include: [:$trial]); {:ok, _} = Application.ensure_all_started(:ipse); Code.require_file(\"test/extensions/knowledge/knowledge_session_test.exs\")"
```

These use a synthetic loopback model, programmatically installed test consent
and the private management entrypoint. They do not qualify public callers,
live-provider behavior, accepted-note recall, installed packages, all owner-loss
and expiry boundaries, or the full dirty host worktree. The exact logs are
`/tmp/ipse-historical-review-contracts.log`,
`/tmp/ipse-historical-review-focused.log`,
`/tmp/ipse-historical-review-genuine_pending_acceptance.log` and
`/tmp/ipse-historical-review-genuine_pending_path_swap.log`; those local paths
are temporary receipts, not portable artifacts.

## Next bounded work

Qualify the explicit public caller and its expiry/owner-loss behavior, then the
accepted-note recall and correction journeys. Use the existing contracts and
process owners. Add a mechanism only for a reproduced violation of a supported
contract; arbitrary same-user replacement of historical sources is not a new
acceptance requirement. Full P30/P31 tests, adversarial audit, whole-manual
acceptance and reviewer handoff remain open in the plan.
