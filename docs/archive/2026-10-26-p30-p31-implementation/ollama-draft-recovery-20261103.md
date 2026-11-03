# Ollama draft recovery: focused synthetic validation

Dated **2026-11-03**. This historical development-source receipt records a
focused increment on committed base `768ad096e55160a6619b016ab295526f09464036`
plus nine uncommitted source, fixture and manual overlays. It does not close
P31I. Current operator instructions are in [request refinement](../../operator/usage.md#refine-a-request-before-submitting-it);
the [developer chapter](../../developer/workspace-context.md#withdraw-draft-intent-before-ordinary-work)
describes the implementation, and the [plan](../../plan.md) owns remaining work.

The change permits a completed plain-text Ollama draft interval to be withheld
when cancelling or accepting it, while leaving earlier and later native history
unchanged. Native thinking, tool calls, unexpected fields or inconsistent text
inside the removed interval still refuse unsafe projection. This is a bounded
provider-specific increment, not a general opaque-continuation rule.

## Verified scope

An isolated `git archive` checkout under
`/dev/shm/ipse-ollama-validation-768a-20261103-01/source` used copied dependency
sources, an isolated Mix/Hex home and a private fixture home. The nine
[pre-format fingerprints](ollama-draft-recovery-20261103/pre-format.sha256)
matched the live overlay before snapshotting. The
[post-format manifest](ollama-draft-recovery-20261103/post-format.sha256)
matched the isolated files before and after the focused suite. Exact tested
[Elixir overlays](ollama-draft-recovery-20261103/overlay/) are retained; the
two manual copies there have a `.md.txt` suffix and match their corresponding
manifest hashes. The [archived-overlay manifest](ollama-draft-recovery-20261103/archived-overlays.sha256)
can verify all nine copies directly from the evidence directory. These historical
copies do not promote the implementation into the current runtime.

The recorded commands included the following, with `MIX_ENV=test`, isolated
`IPSE_HOME`, `MIX_HOME` and `HEX_HOME`, `TMPDIR=/dev/shm`, and two BEAM
schedulers:

```sh
sh dev/build-native.sh
mix compile --warnings-as-errors
mix run --no-start dev/build-bundles.exs
mix format --check-formatted
mix test test/ipse/session/draft_projection_test.exs test/ipse/session/draft_vertical_test.exs test/ipse/session/draft_acceptance_test.exs --max-cases 1 --seed 0
./bin/ipse demo
elixir dev/check-docs.exs
```

The [complete focused suite](ollama-draft-recovery-20261103/focused-suite-first.log)
passed **36 tests**. Separate selected runs passed the
[projection file](ollama-draft-recovery-20261103/projection.log), the
[actual Session and local Ollama transport](ollama-draft-recovery-20261103/ollama-session-first.log),
and the [native terminal acceptance fixture](ollama-draft-recovery-20261103/ollama-pty-first.log).
The loopback Session fixture checks cancellation and accepted replacement,
later requests and resume, retained earlier/later thinking, and an ordinary tool
call and result. It reconstructs a retained journal prefix before the tool
result and checks the synthetic unknown result; this is not a live owner-death
test. The PTY test exercises actual terminal acceptance with a local fixture;
its later resume is programmatic.

The native helper and bundle builds succeeded, as did project compilation with
warnings as errors, the repository-wide format check and credential-free demo.
The compile log includes upstream dependency warnings. The isolated indexed
[documentation check](ollama-draft-recovery-20261103/docs-check-indexed.log)
reported **1,113 Markdown files, 9,140 local links and zero errors**.

The logs capture output, not the command-line flags or exit codes themselves.
The commands, environment, exit results and ordering above come from the recorded
orchestration. The targeted location tests used the formatted test-file lines
902 and 108 respectively, with `--max-cases 1 --seed 0`.

## Retained failures and limits

The [first compile attempt](ollama-draft-recovery-20261103/compile.log) stopped
before compilation because the fresh fixture Mix home lacked Hex. The existing
isolated Hex toolchain was copied and the subsequent
[compile](ollama-draft-recovery-20261103/compile-with-isolated-hex.log) passed;
no dependency fetch was needed. The [first documentation check](ollama-draft-recovery-20261103/docs-check.log)
stopped because the archive checkout had no Git index. A tracked-Markdown-only
index was created in that isolated checkout, after which the check passed.

The [log manifest](ollama-draft-recovery-20261103/logs.sha256) binds the exact
synthetic logs, including both initial setup failures. The
[build manifest](ollama-draft-recovery-20261103/build-artifacts.sha256) binds
three compiled Session modules, the native helper and knowledge bundle
descriptors; those binaries remain only in the temporary isolated checkout.
The archived logs were inspected and contain synthetic fixture/demo output,
public dependency warnings and isolated paths, with no credentials,
authorization codes or private transcripts found.

The full repository test suite remains required on a later integrated candidate.
These checks do not establish live Ollama behavior, paid inference, an installed
package, independent-human use or P31I completion.
