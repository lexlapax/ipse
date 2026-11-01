# Concurrent native input affects the running e86b1b8 suite

2026-10-31. This records a verification error while the clean-clone default suite
at `e86b1b8` is still running. It is not its final aggregate or a passing baseline.
The source inventory's after-launch timing remains separately recorded. The
[plan](../../plan.md) owns acceptance; the [testing manual](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
requires serial native-terminal commands.

The author launched two real, bounded native CLI enhancement Sessions and focused
provider/draft tests while the default suite was active. The provider/draft cohort
includes native PTY controls. A later six-test native document setup investigation
also overlapped the suite. Running these commands concurrently was incorrect:
`native/ipse-operator.rs` takes a nonblocking, retained per-user `input.lock` before
native display/input, independent of checkout or private Session home. A live
terminal waiting for input can therefore make a different test's correct native
review refuse before displaying any facts. Independent temporary directories do
not isolate that lock.

The default suite reported two document setup failures before review: its
positive journey refused native confirmation, and the competing-configuration
fixture did not reach its review-ready barrier. On the current committed root,
after the live CLI closed, the entire document setup file passed6tests in15.6seconds.
That separate pass is not proof of the original failure's cause: source/artifact
versions differ, and no lock-owner trace was captured at its exact failure.
The known overlap and native lock mechanism make contention a concrete candidate.
Other native failures must still be inspected individually; this record does not
classify all failures as fixture defects or excuse missing positive behavior.

Both live CLI Sessions exited normally, their original outcomes and eight model
requests are retained in the [Responses investigation](responses-optional-tools-20261031.md).
The root document investigation log is
`/tmp/ipse-documents-setup-current-investigation-20261031.log`; it changes no source.
The full suite remains exec16652 in `/tmp/ipse-goal-current-full.Nu68hy`, log
`/tmp/ipse-goal-e86b1b8-full-suite-20261031.log`. It has not been stopped or restarted.
Do not derive final totals from nested child summaries or treat a polling timeout
as process completion.

No further native-terminal work should overlap that process. On completion,
retain its complete result and unchanged-source/helper verification with this
concurrency limitation. Then rerun affected native cases alone against the same
source before diagnosing their failures, and use an exclusive complete run for
final acceptance. The latest earlier completed baseline is unchanged; this run
cannot silently replace it with a clean-environment qualification.
