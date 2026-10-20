# Verify a change to Ipse

This chapter teaches the verification workflow for a contributor. You will choose
an observable behavior, exercise it with an isolated fixture, then run the checks
appropriate to the changed boundary. Test output is evidence for the source and
environment you actually ran. A fixture result does not establish live account,
model quality or OS enforcement.

Build the checkout using the [developer setup](index.md). Run commands below from
the repository root. Keep source and build outputs fixed while a test run is
active. A concurrent compiler or helper rebuild can invalidate executable pins
and make the result unsuitable as a baseline.

## Start with a behavior

Suppose you change write approval. Begin with
[`session_test.exs`](../../test/session_test.exs), where a fixture provider proposes
a real write and the test observes the full approval request. Denial must leave
the file absent, record the denied outcome and allow the turn to finish. Approval
must authorize only the exact pending proposal.

```sh
mix test test/session_test.exs --trace
```

Use the existing fixture's configuration and temporary directory. Do not load
personal credentials or ask a paid provider to decide whether the test passes.
When fixing a bug, first make the incorrect behavior observable. Confirm the
regression fails for that reason, then repair the responsible owner and rerun it.
A test that only checks a helper's return shape will miss a write that happened
before that helper failed.

For expiry behavior, establish the stored record's actual wall-clock deadline
before approving the pending write. Recheck that condition after sleeping;
a timer's elapsed duration does not prove that wall time has reached the expiry.
Bound the wait with a monotonic deadline, then retain the unchanged-record,
failure-receipt and inert-resume assertions. The
[`memory session fixture`](../../test/extensions_memory_session_test.exs)
exercises both approval before expiry and rejection after expiry.

### Choose the closest fixture

| Changed behavior | Start with |
| --- | --- |
| Prompt, approval, questions or cancellation | `test/session_test.exs`, `test/question_session_test.exs` |
| Filesystem effect classification | `test/tool_recovery_test.exs`, `test/file_effect_test.exs` |
| Journal durability, quota or restore | `test/journal_writer_test.exs`, `test/journal_limits_test.exs`, `test/ipse/journal_test.exs` |
| Task/process lifetime and lock ownership | `test/task_resources_test.exs`, `test/file_effect_test.exs`, `test/stdio_runner_test.exs` |
| Provider schemas, stream bounds or usage | `test/provider/limits_test.exs`, `test/usage_session_test.exs` |
| Extension capability/action contracts | The matching `test/extensions_*_test.exs` and [SDK exercises](extensions.md) |
| CLI argument parsing and display | `test/cli_test.exs`, `test/cli_sessions_test.exs`, `test/terminal_test.exs` |

Confirm each named test exists before using a copied command. A subsystem can
span several files; inspect the source and adjacent fixtures rather than treating
this table as a fixed test matrix.

### Distinguish presentation from completion

Trace `Session`'s `:extension_presentation` result into `finish/2`. Presentation
is sent before the final `turn_finished` journal append and `done` notification.
Receiving display text does not establish durable completion or a latency bound.

For the prompt/presentation-only fixture in `extensions_session_test.exs`, the
public `Session.info/1` read queues behind that same callback:

```elixir
assert_receive {:ipse, ^pid, {:presentation, "<answer>visible</answer>"}}, 5_000
info = Session.info(pid)
assert info.phase == :idle
assert_receive {:ipse, ^pid, {:done, :ok}}
```

Keep the journal, original-content, native-continuation and cleanup assertions
afterward. The state assertion does not replace the completion notification.
If a fixture configures after-turn subscriptions, `finish/2` can start another
owned job. Await that job's actual completion instead of applying this
single-callback assumption. Do not add sleeps or turn an observation deadline
into an undocumented product latency guarantee.

## Run the source baseline

After a runtime change, run the following sequence:

```sh
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
elixir scripts/check-ci-policy.exs
elixir scripts/check-docs.exs
mix test
IPSE_CHECK_HOME=$(mktemp -d)
IPSE_HOME="$IPSE_CHECK_HOME" ./bin/ipse demo
```

The build fetches locked dependencies and builds the Rust helper. The suite uses
local HTTP fixtures, generated authentication keys, temporary workspaces and real
OS processes. No paid credentials are required. The demo exercises CLI/session,
skills, file tools and the helper with a scripted provider; it is not inference.

Use `mix format` after Elixir edits, then rerun the check. Inspect the ExUnit
result summary rather than counting error-looking lines: some failure fixtures
deliberately terminate a process or reject a certificate. Preserve genuine failed
runs while investigating. A later green run alone does not explain a failure.

Mix uses loopback TCP for filesystem locks; HTTP fixtures also need loopback.
If a sandbox denies those sockets, run through the environment's permission flow
or an appropriate local terminal. Do not weaken TLS, skip assertions or substitute
a different transport to make the suite appear green.

## Verify documentation changes

Treat a manual as something a reader can follow. Read the whole affected chapter,
then carry out its credential-free example or check the exact real-provider path
against the implementation when an account would be required.

```sh
elixir scripts/check-docs.exs
mix run examples/session/hello.exs
./bin/ipse --help
```

The documentation checker validates local files and heading anchors, example
presence in active manuals, the separation of milestone/CI history, and archived
snapshot hashes. It does not prove prose is useful or execute shell blocks from
Markdown. Review examples for complete prerequisites, explained placeholders,
expected output and a way to inspect the result. Check configuration objects
through the actual `ipse config` command with an isolated `IPSE_HOME`.

Documentation-only edits need these relevant checks, not an invented runtime
regression. If source, tests, packaging or CI behavior also changes, verify that
change at its own boundary.

## Test actual OS enforcement

The default suite excludes host-dependent enforcement tags. A skipped test is
not evidence that a sandbox works. For Linux boundary changes on a supported host:

```sh
mix test --include native_sandbox
```

The kernel must supply the required Landlock and namespace facilities. Included
checks fail when those capabilities are unavailable. See [the sandbox training
chapter](sandbox.md) for the host policy and failure modes.

On macOS, use the same subset as the checks workflow:

```sh
mix test test/macos_sandbox_test.exs test/stdio_runner_test.exs test/macos_filesystem_test.exs --include macos_sandbox --include macos_filesystem
rustc --edition=2021 --test native/ipse-macos-sandbox.rs -o /tmp/ipse-macos-policy-test
/tmp/ipse-macos-policy-test
```

The filesystem checks require an actual case- and normalization-insensitive volume
and verify inode identity. They do not simulate aliases on an unsuitable volume.
The native checks use isolated owner-only homes, rather than the operator's
signed cache. Report platform exclusions separately from executed checks.

### Probe the signed macOS worker

Use a disposable workspace outside the probe's temporary directory:

```sh
IPSE_MACOS_WORKSPACE=$(mktemp -d)
elixir scripts/verify-macos-sandbox.exs priv/ipse-runner "$IPSE_MACOS_WORKSPACE"
```

The default probe verifies file/network denial, allowed workspace/private-temp
operations, inherited policy and codesigning. Its optional `--process-boundary`
mode tests a stronger descendant-lifetime property using controlled `setsid` and
`setpgid` cases. Detached descendants can survive under the supported best-effort
macOS cleanup policy, so that stronger diagnostic can report gaps and exit
nonzero. Do not present those gaps as passing containment evidence.
macOS retains generated app containers under `~/Library/Containers`; the script
cleans its own temporary bundle/files. Read the [signing lifecycle](sandbox.md)
before changing cache cleanup.

## Diagnose worker and stdio cleanup

Give a completion observation enough time for the bounded operation it observes.
An extension continuation starts a fresh worker, initializes it, runs its callback
and closes its resources before Session reports `done`. A three-second assertion
cannot cover even one callback admitted under a five-second protocol deadline.
The pending-question recovery fixture deliberately takes four seconds in that
callback and uses a finite twenty-second completion wait. It still requires inert
resume, unchanged journal/callback bytes before the answer, exactly two callbacks
and the final completion notification. Runtime deadlines stay unchanged.

Exercise that continuation and the public evaluation CLI cases together:

```sh
IPSE_TEST_STDIO_PROBE=1 mix test test/extensions_invocation_test.exs test/knowledge_evaluation_runner_test.exs --seed 77259
```

Expect the controlled continuation to finish and the CLI rejection assertions to
pass. The mode/hash-before-label scenario has an explicit two-minute test budget
for its fixture VM and four fresh CLI processes. It preserves hash rejection
before unavailable label/review paths are opened. The opt-in
`synthetic_evaluation_cli_phase` records contain only a fixed phase name, start or
finish event and elapsed milliseconds. They distinguish fixture freezing and
individual CLI waits, including compilation, runtime identity checks and exit.
They do not identify the child operation responsible for a long wait. Inspect
the original incomplete phase before changing a runtime limit or retrying work.

Attach return tracing only to synthetic fixtures:

```sh
IPSE_TEST_STDIO_PROBE=1 mix test test/stdio_probe_test.exs test/extensions_feeds_test.exs test/mcp/session_test.exs
IPSE_TEST_STDIO_PROBE=1 mix test test/extensions_invocation_test.exs:1558 --repeat-until-failure 100
```

The second command selects the diagnostic-question recovery test; verify its
location if the file has changed. The probe in
[`test/support/stdio_probe.exs`](../../test/support/stdio_probe.exs) uses an isolated
OTP trace session and arities rather than arguments. It reports classified
results and monotonic times, stopping after owner loss, twenty seconds or 64
returned/pending calls. Its report is explicitly incomplete. The recovery fixture
can also report metadata for four fixed trace paths on failure, without reading
contents or listing unrelated filenames. Privacy and owner-cleanup fixtures
exercise those boundaries.

For an unexpected MCP discovery or rediscovery failure, enable the same flag:

```sh
IPSE_TEST_STDIO_PROBE=1 mix test test/mcp/client_test.exs
```

The controlled server receives a public fixture-only argument and records fixed
boot, initialize, catalog and tool stages with integer wall times. Unexpected
success-path failures report at most sixteen stage records, the host's operation
start time and elapsed milliseconds. The collector accepts only fixed stage names
and bounded numeric times, and retains no arguments, environment or response
payload. Its privacy control checks unrelated files and malformed/private marker
content. Missing stages describe incomplete fixture observation; they do not
establish why a process stopped. Keep the original timeout and assertions while
collecting evidence.

For frame/drain load instead of host-call timing:

```sh
mix run scripts/diagnose-stdio-cleanup.exs --iterations 1000 --concurrency 16 > /tmp/ipse-stdio-cleanup.jsonl
mix run scripts/diagnose-stdio-cleanup.exs --iterations 100 --concurrency 4 --sandbox native > /tmp/ipse-stdio-native.jsonl
```

This generates synthetic output, delayed collection and native lifecycle cases.
It bounds trial count, concurrency, captured bytes and collection time. Native
setup is serialized, and a setup failure does not retry in trusted mode. Inspect
which component failed: callback delivery, Worker lifetime and native cleanup
are separate facts. Keep deadlines and strict success assertions intact while
finding the cause.

## Verify the extracted package

Run this when changing packaging, worker launch, runtime paths or OS helpers:

```sh
./scripts/package.sh
elixir scripts/verify-package.exs dist/ipse-*.tar.gz
```

The glob must select exactly one archive. Otherwise pass the exact path printed by
the packager. The verifier extracts a fresh runtime, isolates HOME/IPSE_HOME and
restricts PATH to declared host utilities. It checks help/demo, default and
explicit workspace paths, helper lifecycle/locks, bundled extension behavior and
the explicit-memory corpus. It cannot borrow source checkout `priv/` files or a
system development toolchain. Run it under a bounded outer job timeout.

To inspect a release manually, extract it into an empty directory and run:

```sh
./ipse --help
IPSE_HOME=$(mktemp -d) ./ipse demo
./bin/ipse eval 'Code.require_file("verify-release.exs")'
```

Use the root wrapper for CLI commands and the bundled OTP launcher for `eval`.
The [independent artifact chapter](extension-proof.md) teaches the additional
source/installed SDK proof. Do not rebuild the artifact during installed runtime
verification. Match archive OS, architecture and libc. A local verification
archive is not a published release. When distributing one, supply matching
runtime notices through `IPSE_NOTICES_DIR`; see [dependencies](dependencies.md).

## Measure and report honestly

Use `scripts/measure-memory.exs` for the fixed lexical-memory corpus and
`scripts/measure-session-startup.exs` for startup measurements. Read each script's
inputs and reported dimensions before drawing conclusions. Exact-token retrieval
fixtures do not establish semantic retrieval quality; sampled VM memory is not a
peak bound. Keep the corpus/source identity, runtime, OS, concurrency and cost
basis with any published measurement.

Live provider acceptance is a separate manual check requiring the account owner's
authorization. Record the selected provider/model, operation and sanitized result.
Do not copy credentials, private prompts or full transcripts into Git. Browser
sign-in, token rotation, paid inference and device behavior must each be exercised
before claiming them. Fixture-only changes need no new paid calls.

Finish a change with a short statement of behavior, commands actually run,
failures/exclusions and remaining limitations. Keep dated receipts and investigations
in the [archive](../archive/index.md); keep milestone status in the
[plan](../plan.md). The [checks workflow](../../.github/workflows/ci.yml) defines
current CI commands. It is a reproducible procedure, not a substitute for reading
the actual result at the candidate revision.
