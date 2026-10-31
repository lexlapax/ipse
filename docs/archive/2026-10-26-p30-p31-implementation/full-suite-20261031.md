# Full-source regression result

2026-10-31. Historical local verification of the unchanged `codex/p30-p31`
runtime/test cohort, before the isolated legacy SDK and management-journal
resource repairs. This is a failed baseline, not milestone acceptance or an
independent audit. Current scope belongs to the [plan](../../plan.md).

`mix test` exited 2 after **5,938.2 seconds**: **3,488/3,559 passed,
71 failed, 108 skipped, 112 excluded**. The complete top-level failure list and
aggregate footer are retained in the [result extract](full-suite-failures-20261031.txt).
Nested subprocess results were not substituted for that aggregate.

The original source stayed unchanged throughout this run. All 1,069 entries in
the pre-run runtime/test source manifest passed `sha256sum --check --quiet` after
completion. Its SHA-256 is
`9d020714b7ca235ede3b220017c25cd709eff7a65e74b3c69e51c7c4057fb865`;
the native helper SHA-256 is
`c6768890455697de64284463092806fa2e30305a7ea7b8e6ee60c625f3f0ccff`.
The ephemeral full log is `/tmp/ipse-current-full-suite.log`, SHA-256
`523938a08abe321c214e42b8130a96802132da2bcaac4943a3d7caf89824ea16`.

The failures cover the short-literal result-expiry fixture; correction,
supersession and history consumers; a pending-review display-hash assertion;
legacy Collection SDK publication; and the larger managed Collection Session
fixture. That last fixture mixes current controls, earlier metadata versions
and positive expectations for presently gated protected display/effect paths.
Each failure needs a current-contract disposition; this classification does
not turn an unqualified path into a pass.

Follow-up development is isolated in `/tmp/ipse-goal-next-20261031`. Its
[legacy SDK controls](legacy-sdk-admission-20261031.md) and
[accepted-decision recall control](accepted-recall-20261031.md) qualify only their
recorded scopes. No second whole-source pass, package/platform acceptance,
human journey or live provider/model-quality result is implied. Terminal tests
are serialized because the native input lock is shared by the OS user.
