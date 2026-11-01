# Native shell approval from an actual stored statement

Dated **2026-11-01**. Author qualification on top of `cca9bc7`, using the
existing native statement and managed-approval journey. This is historical
synthetic verification, not an independent audit, full C0 acceptance or a
replacement for unrun shell fault boundaries. Current procedures belong to
[knowledge permissions](../../operator/knowledge-permissions.md) and
[testing](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols);
the [plan](../../plan.md) owns package status.

## Follow the actual source, approval and effect

The existing `operator_assertion_integration_test.exs` fixture creates reviewed
ordinary/preference statements through actual native input, protected capture,
signed Collection publication and original Session journals. Its consuming
Session recalls the actual stored note through the registered synthetic Ollama
wire route. These new cases reuse that complete journey and its actual terminal
approval, instead of a subscriber receiving raw arguments and calling
`Session.approve/3` without the native display/input witness.

The closed fixture proposal now selects either its original ordinary write or
an explicit shell command. Both write the exact stored ordinary statement into
the same private workspace target. Shell additionally emits `NATIVE_SHELL_RESULT`.
Only its declared cases normalize to the corresponding existing source-control
scenario; no production selection or authority changes. The native PTY driver,
helper, runtime, saved policy, budgets and deadlines are unchanged.

The allowed shell case requires the physical target bytes, one admitted shell
effect, confirmed cleanup for that effect ID and one current result release.
The marker must appear in the **tool-result message** in the next actual provider
request. Searching the whole request would be insufficient because the earlier
assistant command also contains the marker. Two completed requests, settled
inference slots, strict Saved reconstruction and preserved original journals
remain mandatory. The existing disclosed Worker-input descriptor inspection
also runs for this new allowed case; it observes the actual transaction before
the unchanged native pipe write and fabricates no completion witness.

The paired case changes the real original journal during the approval input
wait, after the complete protected display has released its owners. The fresh
native approval cannot authorize an effect against that changed source: require
no target file, no managed effect admission, one completed provider request and
strict saved history. It restores the exact original bytes under the retained
lock after the consumer closes. An approved `tool_started` fact alone does not
prove native spawn or a successful effect.

## Evidence and remaining boundaries

The first two native shell cases passed on the unchanged runtime, seed 791673:
two passed, 23 excluded, 30.8 seconds, exit 0. This initial run checked actual
file success/source-change refusal before adding the explicit stdout/admission/
cleanup assertions. Its log is
`/tmp/ipse-native-managed-shell-first-20261101.log`.

After adding exact effect/cleanup/result assertions, the complete native
`managed_approval:true` cohort passed, seed 791674: **13 passed**, 12 excluded,
207.2 seconds, exit 0. This retains the existing write, active/resumed source,
deny, stale-code, cancellation/exit, delayed input, source-change, revocation
and owner-loss scenarios alongside the two actual shell cases. Its log is
`/tmp/ipse-native-managed-shell-regressions-20261101.log`.

The final shell-only recovery addition then passed, seed 791675: two passed,
23 excluded, 32.9 seconds, exit 0. After closing each actual consumer and restoring
the controlled original source, it resumes that consumer idle, compares exact
saved messages and the unchanged journal prefix, permits only one validated
ownership marker, confirms close and requires the signed release claim. The
successful target remains exact and the refused target remains absent. No shell
or model request is replayed. This last addition is conditional on shell, leaving
the other eleven approval scenarios unchanged. Its log is
`/tmp/ipse-native-managed-shell-recovery-20261101.log`.

The [selected-input receipt](native-shell-approval-20261101.json) hashes the two
final fixture inputs and three completed logs after execution, not a prelaunch
freeze or a full loaded-runtime inventory. The 13-case run precedes the final
shell-only resume assertions; the two-case run verifies those final assertions.

Whole-checkout formatting and the final documentation checker exited 0; the
latter checked 1,017 Markdown files and 8,433 local links with zero errors.
Logs are `/tmp/ipse-native-managed-shell-format-20261101.log` and
`/tmp/ipse-native-managed-shell-docs-20261101.log`. The complete testing chapter
and existing operator knowledge/recovery chapters were reviewed as whole
documents. No runtime/package build or complete suite was rerun for this
test-and-documentation increment; the earlier source build remains unchanged.

The old subscriber-based shell tests in
`managed_collection_call_session_test.exs` remain unconverted requirements.
These genuine cases cover successful shell approval/result delivery and source
withdrawal before execution; root changes, timed expiry, revocation, source
loss during a running shell and process-group owner loss retain their separate
required qualification. No old positive was changed into a refusal pass.

These checks use automated PTYs, synthetic model responses and actual Linux
`7.2.11-arch1-1` tmpfs storage/OS effects. They establish no human attribution,
real-model quality, installed runtime, non-Linux behavior or confinement claim.
No real inference, model download, dependency or external review was added.
The [complete full-suite baseline](full-suite-20261101.md) remains 3,653 passed
and 54 failed at frozen `f44b63c`; focused current passes cannot reduce it.
