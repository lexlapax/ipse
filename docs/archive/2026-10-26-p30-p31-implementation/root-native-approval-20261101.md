# Preserve root-only positives through native terminal approval

Dated **2026-11-01**. Author fixture migration on top of `ef1b473`, following
the [actual-note MCP qualification](native-mcp-approval-20261101.md). This is
historical synthetic evidence, not full C0 acceptance or independent review.
Current verification belongs to [testing](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols);
the [plan](../../plan.md) owns remaining scope.

## Keep the original context and required positives

Three existing `managed_collection_call_session_test.exs` tests still require:

- `current managed native write starts after approval and releases one bound result`;
- `current managed shell admits the native spawn and releases one bound result`;
- `current managed MCP call admits server start and its exact request`.

Their SDK fixture, protected policy, snapshot observation, registered provider
responses, effect arguments and test names remain. Their metadata dependencies
stay version 3; they are not replaced by signed literal contents or the separate
actual-note journey. Their former subscriber wait and `Session.approve/3` call
could not establish the native display/input witness now required by the host.

The `native_root_approval` parent selection now runs that same test inside the
existing synthetic PTY driver. Its child loads the same SDK/dependency paths,
normal test bootstrap and source module, then selects exactly the original
write, shell or MCP case. The parent skips only its unused per-test storage/
listener setup; the child executes the full original setup. Protected consent
is the existing trusted fixture setup, not a new human permission review.
Actual native approval displays the complete original arguments and takes the
fresh code through the normal Terminal. A raw fake approval reference still
refuses during the real input wait.

Each positive requires the inspection tool under saved consent followed by the
ordinary effect under fresh approval; exact file bytes; the original one-effect
write/shell or two-stage `mcp.start`/`mcp.send` admission; confirmed cleanup for
each effect ID; one observed result and one current release; strict Saved/live
message equality; and nonempty version-3 dependencies. Three actual completed
provider requests remain mandatory. An OTP Agent observes real HTTP payloads
because Terminal consumes its mailbox; it supplies no response or witness.
The existing extra-request observation remains active until fixture shutdown.

The consumer also closes, resumes idle with the exact prior journal prefix plus
one validated ownership marker, closes with a signed release claim and retains
the same target and three-request count. MCP keeps exactly one `write_note`
entry before and after resume. No callback/effect/model request replays.

## Retained first failures

The first native run, parent seed 791678, failed all three cases: zero of three
passed, 164 excluded, 127.7 seconds, exit 2. Their effects and model turns
completed, but the fixture watcher dereferenced `Session.info/1` while that API
correctly returned `session_share_frozen`. Without its exit-ready marker the
provider's extra-request watchdog later timed out. The host gate was preserved;
the watcher now reads ordinary OTP system state as the existing native fixture
does. The compile-time parent/child setup also removes an unreachable-clause
warning in the first draft.

Parent seed 791679 then failed all three, zero of three passed, 164 excluded,
98.8 seconds, exit 2. A new harness assertion counted only the effect tool,
omitting the original `ext__capture__inspect` start. It now requires both exact
ordered starts and their distinct approval tags. Provider shutdown is in `after`
so a failed assertion cannot leave its extra-request listener waiting.

Parent seed 791680 passed all three positives: three passed, 164 excluded,
98.9 seconds, exit 0. Each child selects one case with its fixed seed 791678;
parent and child totals are distinct, not added together.

The final parent seed 791681 combined these positives with the existing raw
subscriber refusal and all registered lifecycle/sequence/competing/result/
revocation/mapping capture controls: **12 passed**, 155 excluded, 167.8 seconds,
exit 0. Its log is `/tmp/ipse-native-root-approval-combined-20261101.log`.
This qualifies the shared setup/observation changes for that selection, not the
unrun complete module. Its retained roots are listed in that log.

Logs are `/tmp/ipse-native-root-approval-first-20261101.log`,
`/tmp/ipse-native-root-approval-observer-fixed-20261101.log` and
`/tmp/ipse-native-root-approval-exact-tools-20261101.log`. The passing run retained
synthetic roots `/tmp/ipse-root-approval-2192d6a2e927e0692d6ccf624c1aa34c`,
`/tmp/ipse-root-approval-c8ccb831f0f1ebe603652961ede5d181` and
`/tmp/ipse-root-approval-a6d94505adc5dcb1cef47be917204249`.

## Remaining qualification

The existing no-native-channel MCP refusal remains a separate
`root_subscriber_refusal` control. Other subscriber-shaped root/expiry/revocation/
owner-loss cases still need their native-terminal migration; none is silently
converted into a refusal pass or covered by these three positives. HTTP and
actual-note fault shapes retain their own scope. No runtime, helper, dependency,
deadline, policy limit or wire protocol changed.

The [selected-input receipt](root-native-approval-20261101.json) hashes the final
test module, child launcher and four terminal parent logs after execution. It is
not a prelaunch freeze or full loaded-runtime inventory. The testing chapter
integrates the exact native command and distinguishes root metadata from signed
contents. Whole developer/operator MCP guidance and existing knowledge/recovery
procedures retain their current ownership and approval rules.
Whole-checkout formatting and documentation checks exited 0. Documentation
covered 1,019 Markdown files and 8,451 local links with zero errors. Logs are
`/tmp/ipse-native-root-approval-format-20261101.log` and
`/tmp/ipse-native-root-approval-docs-20261101.log`. No runtime/package build or
complete suite was rerun for this test-and-documentation increment.

These automated Linux `7.2.11-arch1-1` tmpfs/PTY/loopback checks establish no
human, real-model quality, installed runtime, non-Linux or confinement result.
The [complete frozen baseline](full-suite-20261101.md) remains 3,653 passed and
54 failed at `f44b63c`; focused passes cannot be subtracted from it. Full P30/P31,
capacity, lifecycle, installed quality and the final audit remain open.
