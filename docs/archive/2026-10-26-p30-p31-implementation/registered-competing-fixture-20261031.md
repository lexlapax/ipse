# Restore the competing V3 positive control through a registered route

2026-10-31, source increment based on `da65196`. The completed
[c7cb484 baseline](full-suite-c7cb484-20261031.md) retains this as failure 16. Its
synthetic demo/provider callback could not continue once managed history existed;
the current host requires registered inference ownership. No runtime safety
condition was weakened to repair the control.

The V3 case now uses the existing native Ollama HTTP fixture and protected
service registration. Its six fixed responses cover an initial protected save,
two concurrent barrier captures and both final continuations. The original
source/action binding, saved reconstruction, settled-liability and collection
generation checks remain. The concurrent-success assertion is stronger:
exactly one request must publish at 63 pending records. The separate legacy
case and its first failing baseline remain unchanged.

`mix test test/ipse/extension/managed_collection_call_session_test.exs --only registered_competing`
passes **1 test, 137 excluded**, in 9.2 seconds. Log:
`/tmp/ipse-v3-competing-registered-first-20261031.log`. These are synthetic native
HTTP exchanges, not real model calls. The developer verification chapter now
teaches the registered fixture path and forbids fabricating completion witnesses
or removing dependencies. The operator manuals already describe the unchanged
registered-service runtime behavior; no user procedure changed in this repair.

Before this repair, integrating `dd0ceb9` through `da65196` into the original goal
branch passed 122 focused provider/CLI/native-reconciliation/domain controls in
18.4 seconds, standard build of 180 modules/three bundles, format, CI policy, docs and
credential-free demo. Those focused results do not replace the 58-failure default
baseline. Additional failures in managed approvals, legacy publication and
supersession require their own diagnoses; a new complete pass has not run.
