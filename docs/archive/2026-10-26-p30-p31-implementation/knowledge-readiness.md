# Saved selection and capture availability — 2026-10-29

This scoped implementation corrects knowledge setup/status reporting while the
strict publication gate remains active. The [plan](../../plan.md) owns acceptance.
It does not enable capture or qualify the unavailable positive journeys.

Knowledge status previously reported a saved selection as ready for the next
Session after its artifact, route and timeout matched, without showing the
current runtime's refusal of every protected publication. Status now preserves
that activation observation and separately reports `publication_supported_now`,
`capture_ready_now` and `publication_unavailable_reason`. Capture readiness
requires both activation matching and implemented publication support. Plain
status says a saved selection matches, then states that protected note saving
is unavailable. Native enable displays the same limitation before confirmation
and after saving permission. The full proposed policy remains displayed and its
existing native confirmation, refresh and compare-and-swap path are unchanged.

The Core's new `publication_support/0` returns fixed advisory metadata, using
the same reason constant as the existing refusing admission function. It prepares
no authority, callback or effect. No configuration or worker value can enable
publication. Permissions inspection retains its null activation-readiness value,
exact policy and epoch, while showing the known unavailable runtime capability.
The [operator procedure](../../operator/knowledge-permissions.md#inspect-readiness-or-the-saved-review)
and [contributor ownership explanation](../../developer/collection-sdk.md) describe
this distinction.

The first [strict compile](knowledge-readiness/ipse-knowledge-readiness-compile-47002.log)
reported type warnings because the CLI compared an always-error admission tuple
with `:ok`. The final report is explicit advisory metadata rather than a
pretended success branch; the [two-module compile](knowledge-readiness/ipse-knowledge-readiness-compile-47003.log)
then passed with no compile or runtime warnings. This changed no publication
gate semantics.

The [actual native readiness test](knowledge-readiness/ipse-knowledge-readiness-native-47004.log)
passed **one test, seven excluded**, in1.2seconds. It runs the real native
identity/permission review with synthetic demo configuration, then stops before
the older fixture's Session/capture journey. The genuine saved grant reports
activation matching true but publication/capture false. Plain text reports the
limitation, raw permissions preserve the exact policy/epoch and config bytes,
and precreated pending files remain unchanged. The fixture creates no Session,
makes no model request and does not claim a protected save. The seven other
cases were not run by this selection.

The [independent review](knowledge-readiness-independent-review.md) inspected the
source and these exact receipts without rerunning them and found no concrete
defect in this scope. Scoped formatting and diff checks passed. The
[manifest](knowledge-readiness/manifest.json) pins four source snapshots, all
three logs, relevant loaded modules and the copied native helper. Its local
runtime `_build/knowledge-readiness-47002/lib` is copied from the recorded
literal-source consumer graph and is not a whole-source build or qualification
of the newer release-receipt integration.

Final focused commands:

```sh
ERL_FLAGS='+S 4' mix format lib/ipse/extension/collection.ex lib/ipse/cli/knowledge.ex test/ipse/cli/knowledge_test.exs test/support/knowledge_setup.exs
ERL_FLAGS='+S 4' ERL_LIBS=_build/knowledge-readiness-47002/lib elixir -r test/test_helper.exs -e 'Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [knowledge_readiness: true], seed: 47004, max_cases: 1); Code.require_file("test/ipse/cli/knowledge_test.exs")'
```

Native PTY access required the execution environment's permission flow. No
aggregate suite, new native helper build, installed-package or model-quality
verification ran. Honest unavailable status is containment and user guidance;
the requested usable capture, recall/lifecycle and final integrated qualification
remain required.
