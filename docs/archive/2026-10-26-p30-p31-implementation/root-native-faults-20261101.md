# Original root-only approval waiting faults through native input

Dated **2026-11-01**, author-run synthetic Linux verification on branch
`codex/p30-p31`, based on `751fbb0`. This is a historical engineering receipt,
not an operator procedure or milestone acceptance. The [plan](../../plan.md)
owns remaining scope; [testing](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
teaches the current fixture flow. This extends the
[original three positives](root-native-approval-20261101.md) without substituting
signed-note content for version-3 root metadata.

## Preserved cases and actual boundary

The twelve original test names, SDK artifact, snapshot, policy, provider sequence,
tool arguments and root-change operations remain. Each write/shell/MCP case now
runs inside the existing native PTY child instead of expecting a raw subscriber
approval message and calling `Session.approve/3`. That API cannot replace the
protected display/input witness. A separate subscriber refusal remains required.
The original positive tests continue to require their actual permitted effects.

The observer requires the genuine `managed_approval`/`review_input` phase, exact
arguments, nonempty version-3 dependencies and an absent target after the PTY
observes the displayed proposal and `approval>` prompt. A fake approval reference
must fail. Only then does it change the original root, revoke its saved policy,
wait past the original signed expiry, or kill the actual consuming Session.
Expiry retains the original six-second policy; neither its clock nor its deadline
is replaced. The PTY supplies the fresh native answer for the first three faults.
For owner loss it supplies no answer and requires CLI failure after actual death.
The existing Rust driver and production helper are unchanged.

All faults require no effect admission, no target and exactly two completed
registered-provider requests. Root change, revocation and expiry require an
observed result with withdrawn release; owner loss requires neither an effect
tool start nor result observation. MCP also requires an absent `calls.log`.
Strict Saved restoration retains all version-3 dependencies. For owner loss,
the fixture proves the original OS lock can actually be acquired and released
before resuming; it never deletes or replaces the lock. Every consumer resumes
idle with exactly its saved messages and original journal prefix plus one valid
ownership marker, then closes with a signed release claim. Target and provider
counts remain unchanged. No approval, callback, effect or inference replays.

The shared positive checks still require the original inspection followed by
the approved tool, three completed requests, the exact physical effect,
per-effect-ID confirmed cleanup and current result release. MCP retains separately
admitted start/send and one call before and after recovery. An OTP Agent only
observes actual HTTP requests because Terminal consumes its mailbox.

## Terminal verification

The first write-only migration ran:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only native_root_fault --max-cases 1 --seed 791682
```

At that draft only the four write cases carried this tag: **4 passed**, 163
excluded, 125.8 seconds, exit 0. The log is
`/tmp/ipse-native-root-write-faults-first-20261101.log`. Its unused old write-helper
warning was removed before extending the migration to shell and MCP.

The final combined run used:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only native_root_approval --only root_subscriber_refusal --only registered_capture_lifecycle --only registered_capture_sequence --only registered_competing --only registered_capture --max-cases 1 --seed 791683
```

Result: **24 passed**, 143 excluded, 510.7 seconds, exit 0: three original
positives, twelve waiting faults, the raw-subscriber refusal and eight registered
capture regressions. The child seed remains 791678 and selects exactly one native
case; parent and child totals are not added together. The final log is
`/tmp/ipse-native-root-faults-combined-20261101.log`, including the retained private
synthetic roots. The [selected-input receipt](root-native-faults-20261101.json)
hashes the final test inputs and terminal logs after execution. It is not a
prelaunch freeze or complete loaded-runtime inventory.

## Scope and remaining work

Whole testing and operator recovery chapters, plus both MCP manuals, were reviewed
for this increment. The testing chapter integrates waiting-fault injection and
lock-release recovery into its existing worked example. Operator behavior is
unchanged. Whole-checkout formatting exited 0. Documentation checked 1,020
Markdown files and 8,458 local links with zero errors; its Git discovery emitted
permission warnings for existing private `.serenity-*` directories, which were
not opened or changed. Check logs are
`/tmp/ipse-native-root-faults-format-20261101.log` and
`/tmp/ipse-native-root-faults-docs-20261101.log`; the selected-input receipt hashes
them. No runtime, native helper, dependency, policy limit or protocol changed;
no runtime/package rebuild or complete suite was rerun for this test/documentation
change.

These automated Linux `7.2.11-arch1-1` tmpfs/PTY/loopback controls establish no
human, live-model quality, installed, non-Linux or confinement result. Faults
during shell execution, MCP start/send transitions, HTTP and complete C0/capacity
remain open. The [complete frozen baseline](full-suite-20261101.md) remains
3,653 passed and 54 failed at `f44b63c`; focused passes cannot be subtracted from
it. Full P30/P31 implementation, integrated qualification and final audit remain
open.
