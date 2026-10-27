# Interrupted full test attempt and environment controls

Historical evidence, 2026-10-27. This is an **incomplete full test attempt**,
not a baseline pass. A private graph was copied from the working tree to
`/tmp/ipse-full-baseline.gl0sv4zx` and compiled in test mode with
`--warnings-as-errors`. The copied genuine native helper had SHA-256
`d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`;
its native source tree matched the separately retained source graph. The
[post-run manifest](SHA256SUMS) records selected source/test files and the
helper. Post-run comparisons found `lib`, `test`, `extensions`, `native` and
`dev` identical to the working tree. This manifest does not freeze dependencies,
all graph files or the environment.

The serial `mix test --no-compile --seed 20261112 --max-cases 1` run used
`/tmp`, a `tmpfs` filesystem, and excluded the standard platform tags. It
reported protected-storage refusals and some fixture tests explicitly said
their positive paths were not run. The copied graph mistakenly omitted
`.github`, causing release workflow-file tests to fail. Later a test reported
`disk quota exceeded` writing a temporary fixture. The coordinator sent
SIGTERM to the verified test process to prevent cascading failures. Its shell
reported exit 0 after Erlang handled SIGTERM; there was no final ExUnit summary,
so that exit code is **not a pass**. The retained partial log at
`/tmp/ipse-full-baseline.gl0sv4zx/full-test.log` has SHA-256
`ac803df3930bf1a437a0245ca8e0208f03ad511a83fbb0fb6ba1a11457109ba6`; it is
not committed. At inspection `/tmp` still reported 4.6 GiB available; the
specific quota cause was not established. No retained Serenity fault fixture
was removed by this test attempt.

The two affected workflow-file tests were rerun against the complete working
tree with the private compiled build and passed (seed 20261114; two tests, 12
excluded). Separately, one protected Collection test was run with a new
owner-only Btrfs `TMPDIR` on Serenity and the same genuine helper. It still
returned `collection_filesystem_unsupported` (seed 20261113; zero passed, one
failed, ten excluded). The source profile does not admit the running 7.2.11
kernel; the generic refusal does not independently isolate its sole cause.
Neither control qualifies that kernel or establishes a complete full-suite run.

Use a complete private graph including `.github` and an appropriate Btrfs
temporary location for a fresh full attempt. Preserve the first failed run,
any unknown effects and the existing fault-test artifacts. P30/P31 integration,
positive protected-storage paths, full platform tests and final acceptance
remain open.
