# Prior-Session decision-shadow control — 2026-11-02

Historical implementation and synthetic-test evidence, not a milestone completion
claim. Use the [current plan](../../plan.md), [operator knowledge manual](../../operator/knowledge-permissions.md)
and [developer knowledge guide](../../developer/knowledge-extensions.md) for
current scope and procedures.

## Source and boundaries

The tested source was an isolated archive of commit
`7af1b9c9ea2eadde7131a744efc204c1675cd399`, plus the 32 overlays listed in the
[SHA-256 manifest](decision-shadow-prior-session-20261102.sha256). Those hashes
matched after the tests and matched the shared worktree when verified. The
archive supplies all other tracked source at the base commit; dependencies were
copied from the existing locally fetched dependency cache. This is not a claim
that every dependency or generated file was independently fingerprinted.

All inference services in these tests were synthetic servers bound to numeric
loopback addresses and all homes, source files, and journals were synthetic
temporary fixtures. No live model, paid account, external service, installed
package, independent human or macOS journey was tested.

The opt-in shadow bundle exposes a separate `assess` tool for a previously saved
note. Its reviewed outer descriptor grants a protected collection read and a
single decision effect, not general workspace, shell, MCP, collection-write, or
other inference authority. The host accepts this outer class only for a valid
finite experiment declaration and the exact pair of reviewed mappings. The
decision dispatch independently requires the inventoried shadow-bundle digest,
the current project/policy/source binding, the configured local route and native
approval. The shared project ledger reserves the finite call before dispatch.

Each decision is admitted under the reviewed time window and accounting period.
Already admitted work may finish sending after expiry; a result that crosses the
release boundary is withheld and uncertain liability remains reserved. The tests
do not establish a monetary cap, nor do they qualify any hosted engine. Capturing
a note does not automatically start an assessment.

## Commands and observed results

The following commands ran in the isolated combined source with loopback access
and `ERL_FLAGS='+S 2:2 +A 2'`. Their ExUnit seeds are recorded so the ordering can
be reproduced; the local test runner selected the listed paths and line filters.

1. `IPSE_BUILD_COMMIT=7af1b9c9ea2eadde7131a744efc204c1675cd399 MIX_ENV=test ./dev/build.sh`
   succeeded. It compiled the host and built the native and decision-shadow
   Knowledge bundles alongside the other inert bundles.
2. `mix test test/ipse/extension/decision_outer_test.exs test/ipse/extension/collection_call_session_test.exs:473 test/ipse/extension/managed_collection_call_session_test.exs:3587 test/ipse/extension/managed_collection_call_session_test.exs:4992 test/ipse/extension/managed_collection_call_session_test.exs:8675 test/ipse/cli/knowledge_test.exs:94 test/extensions/knowledge/knowledge_capture_test.exs test/ipse/extension/semantic_consent_test.exs:138 test/ipse/provider/egress_gate_test.exs:83 test/ipse/extension/decision_session_test.exs:318`
   passed **14**, with **263 excluded**, seed `813606`. These include live denials
   for shell, native write, MCP, model and embedding actions, and replay tampering
   checks where a denied action was journaled. The MCP attempt was refused before
   an action intent. The batch also covered the collection-write guard,
   substituted artifact rejection, an ordinary decision compatibility control,
   and selected consent, preflight, capture and CLI controls.
3. `IPSE_KEEP_SHADOW_FIXTURES=1 mix test test/extensions/knowledge/shadow_experiment_session_test.exs --only 'shadow_case:revoked grant'`
   passed **1**, with **4 excluded**, seed `852101`. A first Session saved a
   real synthetic-source note, the grant was revoked, and a fresh Session had no
   active grant, decision intent, decision-provider call, or model-call reservation.
4. `IPSE_KEEP_SHADOW_FIXTURES=1 mix test test/extensions/knowledge/shadow_experiment_session_test.exs --exclude 'shadow_case:revoked grant'`
   passed **4**, with **1 excluded**, seed `470446`. The successful journey used
   separate capture and assessment Sessions, the actual bundle, current protected
   read, native approval, synthetic provider response and settled call. Separate
   controls covered denial, expiry while preflight was blocked with no reservation,
   and expiry while result admission was blocked with unknown liability retained.

The same frozen combined snapshot also passed the 27-case recall worker suite
(one outer test, seed 792120) and all three native recall journeys (three passed,
two excluded, seed 792121, 396.3 seconds). Those journeys used a 15-second
synthetic provider timeout. The 32-file manifest matched before and after those
checks. These focused runs are not a complete `mix test` or the full handoff
baseline.

A separate synthetic native-terminal control exercised the operator walkthrough
on this same combined snapshot: `config`, the reviewed two-call/300-second
experiment, `/remember ordinary The release checklist requires a migration audit.`,
`/exit`, a fresh chat, `/ext`, model-selected assessment and native decision
approval. It observed the native assertion, two saved Session journals, one
settled decision call and no assessment-Session write. The [driver](decision-shadow-manual-20261102/manual_actual.exs),
[synthetic provider helper](decision-shadow-manual-20261102/provider_fixture.ex)
and [temporary PTY helper](decision-shadow-manual-20261102/operator_pty.rs)
retain the exercised fixture. Their SHA-256 values are respectively `43f9ecff6762a5e91e835b2f246daf75cc1caad84d96326b80113613a72964a2`,
`0092d34f9e3adeed2bf184e3ab48feabd79eeacd2b5f0e5c1b5c654ceba2dcc1`,
and `475040af0a9540ddbe661921641f8243c5aa0462bb191e4852f031af6b79ff2a`.
The raw synthetic terminal log was retained temporarily outside the repository;
its SHA-256 is `9b85a7d983ab55ff7c1fe4edbc98a636f9614bf1b4d104957b56d0f8110fe9ef`.
The temporary driver emitted unused-variable warnings; the actual CLI journey
completed. The retained log is synthetic and does not establish human use.

The first whole-source format check found three unformatted files. After formatting
those files, the [post-format fingerprints](decision-shadow-prior-session-postformat-20261102.sha256)
matched the working tree. Whole-source formatting and test-environment compilation
with warnings as errors then passed; the semantic-consent and collection-guard
controls passed 22 tests, with 15 excluded, seed 246130. The native-terminal
walkthrough was rerun successfully on those post-format sources; its separate
temporary synthetic log has SHA-256
`10b8f6fdfe97e0bdde246a5e1481461d6994926ed6719fb1ea795a0206d469be`.
The earlier approval, denial, expiry and combined-recall batches remain evidence
for the pre-format fingerprints; the three subsequent changes were formatting only.
The credential-free demo also passed in an isolated home. The first sandboxed Mix
compile attempt was denied a local TCP lock; it passed with loopback access.

## Retained failure history and open scope

The first automatic post-capture implementation wrote the note and reread it in
the same invocation. Its decision failed before reservation and the subsequent
main-model managed preflight refused: earlier generation-0 root observations and
the new generation-1 record appeared in the complete dependency union. The
decision provider received no request and no model-call reservation was created.
An experimental one-line canonicalization got as far as a preflight intent but
did not resolve those stale conversation-history observations. That experiment
was reverted. The automatic post-capture hook was removed so the successful save
does not start this known-failing continuation. A safe replayable same-Session
post-write assessment remains open; the prior-Session path does not fix it.

The first prior-Session attempt was also refused safely: the existing
`collection.read` outer binding prohibited every mutating inner action, including
`decision.create`. The current mixed-owner binding was introduced as a narrowly
reviewed host extension-API gap; ordinary read-only bindings keep their original
fence. An initial guard test then failed because its synthetic prompt did not
match the exact quote embedded in the fixture. Correcting the prompt made that
control pass. None of these failed runs justifies retrying an uncertain effect.

This receipt does not complete P30. The frozen held-out evaluation, independent
review and remaining broader qualification in the plan still apply. In
particular, the local synthetic decision service establishes a control flow, not
model quality, external billing limits or production readiness.

## Wording for integration into the current manuals

Operator guidance should tell a reader to configure an explicit `advice`
`system_one_compatible` decision profile and its registered local service using
a numeric loopback origin. From a native terminal,
`ipse knowledge experiment advice 2 300 --cwd /path/to/project` reviews a maximum
of two calls over at most 300 seconds, subject to the current accounting-period
boundary. Read the complete replacement-policy review and enter its fresh code;
start a new Session. Select an already saved eligible note with the shadow
`assess` tool and review each separate native decision approval. The experiment
replaces the prior project knowledge permission; after expiry, review
`ipse knowledge enable --cwd /path/to/project` to restore the ordinary selection.
The advice is shadow data and cannot change the saved note or authorize other
effects. Configuration examples must use an actual operator-configured local
service and must not imply that Ipse supplies one.

Developer guidance should trace the exported assessment descriptor through its
finite experiment policy, the decision outer binding, the current managed read,
native approval, shared Consent reservation, final source/policy admission and
result release. It should explain that the decision outer allows only a protected
collection read and `decision.create`, that the exact inventoried artifact is
required, and that an admitted send may complete after expiry while an unknown
effect remains charged. Explain the previously described same-Session post-write
boundary as an open limitation, not as a supported automatic path.
