# Native approval before original running-shell faults

Dated **2026-11-01**, author-run synthetic Linux verification on
`codex/p30-p31`, based on `e47e671`. This is a historical engineering record,
not milestone acceptance. The [plan](../../plan.md) owns remaining scope;
[testing](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
teaches the current fixture. This extends the
[waiting-fault migration](root-native-faults-20261101.md).

## Preserved requirements

The two original running-shell tests retain their names, managed SDK root read,
original policy, registered provider responses and exact delayed shell command:
create `shell-started`, sleep 0.6 seconds, print the synthetic stdout and write
`finished` to the final target, with the original 2000-ms command timeout.
They now run under the existing native PTY caller instead of waiting for raw
subscriber approval. They require exact displayed arguments, nonempty version-3
dependencies and rejection of a fake `Session.approve/3` reference before the
driver supplies the real fresh answer. Only the physical `shell-started` marker
allows fault injection.

Revocation must preserve the command's completed file and private observed stdout,
with one admitted shell effect and same-effect-ID confirmed cleanup. The result
release is withdrawn, saved conversation text is withheld, the captured Terminal
must not show the successful shell result and the model receives no third request.
This preserves an already admitted effect while refusing later use of its result.

Owner loss follows the turn's registered cleanup scope to the actual `:shell`
resource and effect process, then its native Port. Read-only procfs observations
identify the helper, its group anchor and shell, and the shell's sleeping child.
The test kills the actual consuming Session and requires these observed processes
to disappear or enter an exited state. It retains the original additional 800-ms
absence check, beyond the command's sleep; the final write must not occur.
An admitted shell intent remains, with no observed result or result release.

Both tests require two completed registered-provider requests, strict Saved
restoration with nonempty version-3 dependencies, actual original-lock release
before recovery after owner loss, and idle resume of the same Session with exact
saved messages. Its original journal prefix gains only a validated ownership
marker before confirmed close and signed release claim. No command or provider
request repeats; the final file stays exactly completed or absent respectively.
The original allowed shell control still requires its exact successful effect,
current delivery, confirmed cleanup and three completed requests.

## Retained failures and final verification

The initial sandboxed command was refused before ExUnit startup because Mix could
not acquire its TCP filesystem lock (`eperm`), exit 1. Its log is
`/tmp/ipse-native-root-running-first-20261101.log`. The permitted loopback run
used the unchanged transport and assertions; no TLS or policy setting was weakened.

Parent seed 791684 selected the two faults: **1 passed, 1 failed**, 165 excluded,
80.2 seconds, exit 2. The new observer incorrectly searched the ordinary turn task
for the shell Port. It found none because managed shell work uses the tracked
file-effect process. The observer failed before killing the consumer; the command
therefore completed normally and the extra-request watchdog later expired.
The log is `/tmp/ipse-native-root-running-loopback-20261101.log`.

Parent seed 791685 added the allowed shell control: **2 passed, 1 failed**,
164 excluded, 106.4 seconds, exit 2. The corrected resource lookup initially
resolved the module's existing `Ipse.Extension.Registry` alias rather than OTP
Registry. Its compiler warning and failure remain in
`/tmp/ipse-native-root-running-resource-owner-20261101.log`. The final source
names `Elixir.Registry` explicitly. It also observes both direct helper children,
including the independently owned process-group anchor. No production code changed.

The final run used:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only native_root_running --only native_root_approval:shell --max-cases 1 --seed 791686
```

Result: **3 passed**, 164 excluded, 96.5 seconds, exit 0, with no compiler warning.
The child seed remains 791678; parent/child totals are not added together. The log
is `/tmp/ipse-native-root-running-native-owner-20261101.log`, including retained
synthetic roots. The [selected-input receipt](root-native-running-shell-20261101.json)
hashes the final test inputs and terminal logs after execution. It is not a
prelaunch freeze or complete loaded-runtime inventory.

## Limits and documentation

The whole testing and recovery chapters and both MCP manuals were reviewed with
the preceding waiting-fault increment. The current testing edit integrates these
distinct execution boundaries into the same worked example; operator behavior is
unchanged. Check results and log hashes are in the selected-input receipt.
No runtime/helper/dependency/limit changed, so no runtime/package rebuild or
complete suite was repeated for this test-and-documentation increment.

These are automated Linux `7.2.11-arch1-1` tmpfs/PTY/procfs/loopback controls, not
human, live-model quality, installed, non-Linux, confinement or detached-descendant
qualification. Broader actual-note faults, MCP start/send transitions, HTTP,
capacity, lifecycle and full P30/P31 remain open. The
[complete frozen baseline](full-suite-20261101.md) remains 3,653 passed and
54 failed at `f44b63c`; these focused passes do not establish a new aggregate.
