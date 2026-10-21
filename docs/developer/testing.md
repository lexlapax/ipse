# Verify behavior in source and installed runtimes

Choose an observable behavior, exercise it with an isolated fixture and then run
the checks appropriate to the changed boundary. Evidence belongs to the source,
runtime and environment actually tested. A fixture result does not establish
live account behavior, retrieval quality or OS enforcement.

Build the checkout using [developer setup](index.md) and run commands here from
the repository root. Keep source and build outputs fixed during a run. Concurrent
compilation or helper rebuilding can invalidate executable pins. Use separate
checkouts/build roots when testing different OTP versions.

## Begin with an observable failure

For a write-approval change, start with `test/session_test.exs`. A fixture provider
proposes a real write and the test observes complete approval arguments. Denial
must leave the file absent, record denial and let the turn finish. Approval must
authorize only the exact pending proposal.

```sh
mix test test/session_test.exs
```

Use its temporary directory/configuration, without personal credentials or a paid
model. Make the incorrect behavior observable before repairing its owner. A
helper return-shape assertion misses an effect that happened before the helper
failed. Choose the nearest existing fixture:

| Boundary | Starting point |
| --- | --- |
| Prompt/approval/questions/cancellation | `test/session_test.exs`, `test/question_session_test.exs` |
| Filesystem effect classification | `test/tool_recovery_test.exs`, `test/file_effect_test.exs` |
| Journal durability/quota/restore | `test/journal_writer_test.exs`, `test/journal_limits_test.exs`, `test/ipse/journal_test.exs` |
| Task, process and lock ownership | `test/task_resources_test.exs`, `test/stdio_runner_test.exs` |
| Provider schema/stream/usage | `test/provider/limits_test.exs`, `test/usage_session_test.exs` |
| Extension contracts | Matching `test/extensions_*_test.exs` and [SDK exercises](extensions.md) |
| CLI parsing/display | `test/cli_test.exs`, `test/cli_sessions_test.exs`, `test/terminal_test.exs` |

Inspect adjacent source/tests rather than treating this table as a fixed matrix.
For expiry, establish the stored wall-clock deadline and recheck it after waiting.
A timer alone proves no wall-clock condition. Bound the wait monotonically and
retain unchanged-record, failure-receipt and inert-resume assertions. See
`test/extensions_memory_session_test.exs` for approval before/after expiry.

Presentation is also a distinct observation. `Session` sends presentation before
its final journal append and `done` notification. In the prompt/presentation-only
fixture, `Session.info/1` queues behind the same finishing callback:

```elixir
assert_receive {:ipse, ^pid, {:presentation, "<answer>visible</answer>"}}, 5_000
info = Session.info(pid)
assert info.phase == :idle
assert_receive {:ipse, ^pid, {:done, :ok}}
```

Keep native-history, journal and cleanup assertions afterward. If after-turn jobs
are configured, await their actual completion instead of assuming one callback
settles the turn. Observation timeouts are not product latency guarantees.

## Run a complete source baseline

After a runtime change:

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

The build fetches locked dependencies and builds Rust helpers. Tests use local
HTTP, generated auth keys, temporary workspaces and real OS processes. The demo
uses a scripted provider; no paid credentials are required.

Format after edits, then check. Require a completed ExUnit summary and inspect
the exit status together. A process stopped by SIGTERM can return zero without
finishing. Failure fixtures intentionally log process exits or certificate
rejections, so error-looking lines alone do not determine suite outcome. Retain
failed/incomplete runs while investigating; later green output does not explain
the original failure.

Mix's lock service and HTTP fixtures need loopback sockets. Use the environment's
permission flow or an appropriate terminal when restricted. Do not weaken TLS,
skip assertions or change transports to obtain green output. Test supported
toolchain versions when changing compiler or raw ERTS launch code, not just the
newest installed version. Raw verification launches explicitly select Unicode
standard output so locale defaults cannot corrupt JSON protocols.

## Prove an independent artifact without rebuilding the host

`scripts/verify.exs` exercises separately compiled artifacts through real host APIs.
Choose source with an existing SDK, or installed with a compatible runtime archive.
The verifier never repairs/rebuilds an input artifact to make it pass.

Start with the model-call proof:

```sh
IPSE_PROOF_ROOT=$(mktemp -d)
elixir scripts/build-artifact.exs model-calls --sdk _build/dev/lib/ipse/ebin --output "$IPSE_PROOF_ROOT/model"
elixir scripts/verify.exs source model --sdk _build/dev/lib/ipse/ebin --input "$IPSE_PROOF_ROOT/model" --selection json-none
```

Expect nine passed assertions, `verification.precompiled_harness:true` and
`verification.inventories_unchanged:true`. The loopback service supplies scripted
text/usage without paid requests. Read the proof's assertions for behavioral
scope; unchanged inventories alone prove no operation succeeded.

Repeat against an already built archive:

```sh
IPSE_ARCHIVE=/absolute/path/to/the-compatible-archive.tar.gz
elixir scripts/verify.exs installed model --archive "$IPSE_ARCHIVE" --input "$IPSE_PROOF_ROOT/model" --selection json-none
```

Replace the placeholder with the actual archive printed by the packager. SDK,
artifact and runtime must agree on platform, OTP and supported SDK. Source
success does not establish installed compatibility. Preserve old compiled
artifacts when checking host upgrades; rebuilding them checks a different claim.

### Follow compilation and execution ownership

Read `dev/verification/cli.exs`, `scenarios.exs` and `runtime.exs` in that order:
CLI admits a closed grammar; Scenarios selects finite source/module identities,
arguments and assertions; Runtime inventories inputs/origin and compiles trusted
proof modules in a separate VM before starting the host. Domain assertions remain
in proof modules. `package.exs` owns broader installed CLI checks.

Runtime rechecks host, dependencies, ERTS, boot, harness and utility bytes before
child launch, compares input/origin inventories around the proof and checks
runtime inventories afterward. Children get private HOME/TMP and a PATH of
declared utilities plus selected Erlang, without system Elixir, Mix or Rust
development commands. This controlled launch is trusted code, not OS confinement.
Canonical paths account for filesystem aliases.

Ordinary runtimes are disposable, including failures. Model-service evidence
remains at its requested output while its runtime is disposable. Measured cases
retain runtime and evidence so audit/scoring reopen identical executable files.
Retained files do not authorize retrying an interrupted effect.

| Scenario | Input | Selection or additional requirement |
| --- | --- | --- |
| `model` | Model-call artifact | `default`, `none`, `json`, `json-none`, `json-long` |
| `embedding`, `mcp`, `saved-results` | Matching SDK artifact | Default |
| `lab` | Built lab artifact directory | Default |
| `memory` | `examples/memory/corpus.json` | Fixed lexical fixture |
| `package` | Same corpus | Installed only |
| `knowledge`, `knowledge-independence`, `knowledge-complete` | Parent containing Corpus, Graph and Research artifacts | Default |
| `knowledge-evaluation` | Lexical Corpus artifact | Default |
| `knowledge-recovery`, `knowledge-graph-lifecycle` | Graph `state-model` artifact | Default |
| `knowledge-corpus-lifecycle`, `knowledge-selection` | Corpus `state-dense` artifact | Default |
| `knowledge-mcp` | Corpus `mcp-lexical` artifact | Default |
| `knowledge-research` | Research `mcp` artifact | Default |
| `model-service` | Compiled `dev/fixtures/model_service_probe.rs` | Fresh output |
| `measured-knowledge` | JSON map of seven prebuilt artifact directories | Clean repository, fresh output; six selections |
| `measured-authority` | Same artifact map | Clean repository, fresh output; Linux backend |

Measured-knowledge selections are `default`, `sealed`, `structured` and
`sealed-structured`, plus `sealed-long-answers` for the explicit longer-answer
policy and `sealed-gpu-answers` for its scripted NVIDIA-policy equivalent.
Cases other than `model` and `measured-knowledge` accept
only default. Follow the
[complete measured exercise](knowledge-evaluation.md#run-a-complete-synthetic-measured-population)
for artifact maps, retained paths and Linux prerequisites. Measured cases refuse
on another OS before reading inputs or creating output. Unused, duplicate and
unknown options refuse; ordinary proofs accept no repository/output options.

Start shared-runtime changes in `test/verification_test.exs`: it checks grammar,
compiler closure, input changes, source/installed launch, retained failures and
cleanup precedence. Keep each domain proof's positive and negative assertions.
Compilation alone cannot replace actual source/installed execution.

## Learn a complete workflow through the compatibility lab

```sh
IPSE_LAB_ARTIFACTS=$(mktemp -d)/artifacts
elixir scripts/build-artifact.exs extension-lab --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LAB_ARTIFACTS"
elixir scripts/verify.exs source lab --sdk _build/dev/lib/ipse/ebin --input "$IPSE_LAB_ARTIFACTS"
elixir scripts/verify.exs installed lab --archive "$IPSE_ARCHIVE" --input "$IPSE_LAB_ARTIFACTS"
```

Keep the variable for both runs. Construction compiles reviewed workers against
the public `Ipse.Extension` behavior, copies the license, inventories files and
pins runtime targets. It creates separate immutable memory versions, lookup and
observers; it imports, trusts or enables none. Read the lab in this order:

1. `spec.exs` for descriptors, schemas, capabilities, routes and disabled selections.
2. `src/memory.ex` and `src/lookup.ex` for public callbacks and finite host calls.
3. `proof.exs` for CLI import/selection, Session ownership, approvals and assertions.
4. Scenarios/Runtime for host-independent compilation and unchanged-byte checks.

The memory fixture recognizes `entity: Ada` and `link: Ada -> OTP`. Before-request
recall reads scoped state and a bound lookup, then publishes literal receipt
excerpts for the frozen request snapshot. After-turn capture proposes a separate
approved CAS write and cannot alter the completed answer. Facts retain occurrence,
view, extractor and package versions. Identical later text has a new source;
catch-up of the same source deduplicates. Fixed-range original-prompt catch-up
allows eight pages of up to eight records and reports gaps/continuation.

Domain limits are eight sources, sixteen entities and a 7000-byte stored value,
below host limits. Forgetting an entity removes whole contributing sources and
blocks their identities, potentially removing other facts from those sources.
Forget-all retains a tombstone and clears future context. A delayed pre-forget
revision conflicts. Journals, snapshots and prior transfers remain. This is a
teaching fixture, not a production knowledge engine or retention policy.

Lookup schema mismatch or required failure must prevent inference. Metadata
observes counts without private text; observer hangs exercise feed gaps; tool/text
observers exercise their exact selected views. Workers keep ordinary OS
permissions. Host-side privileged synthetic instrumentation is not an SDK grant.

Inspect each `checks` boolean with its assertion. The final deliberate required
service crash ends `safe_to_continue:false` and
`expected_terminal_cleanup:unconfirmed`; no later case runs. Exit zero means its
positive and negative assertions matched, not that every cleanup was confirmed.
To extend the proof, add an export and an independently observed effect assertion
while keeping artifact construction outside activation and host bytes unchanged.

```sh
mix test test/extension_lab_test.exs
```

The source integration does not replace installed checks. One platform's BEAMs
or `FROZEN_CORE` historical baseline does not prove another runtime. Use the
actual candidate and report SDK/platform compatibility honestly.

## Verify documentation and packaging at their own boundaries

Read the whole affected chapter and carry out its credential-free example. For
an account-dependent path, check exact implementation and identify unexecuted
steps. Use isolated `IPSE_HOME` with the real config CLI for configuration objects.

```sh
elixir scripts/check-docs.exs
mix run examples/session/hello.exs
./bin/ipse --help
```

The checker verifies local files/anchors, manual examples, audience/history rules
and archived hashes. It neither executes Markdown nor proves prose useful.
Review prerequisites, placeholders, expected results and recovery. Docs-only
changes need relevant example/link checks, not invented runtime regression tests.

For packaging, runtime paths, worker launch or native helper changes:

```sh
./scripts/package.sh
elixir scripts/verify.exs installed package --archive dist/ipse-*.tar.gz --input examples/memory/corpus.json
```

The glob must select one archive; otherwise use its exact printed path. The
verifier extracts a fresh runtime with private HOME/IPSE_HOME, checks help/demo,
default/explicit workspaces, helper lifetime/locks, bundled behavior and memory.
Standalone CLI checks have declared utilities without Erlang/development commands;
the precompiled memory harness adds only bundled Erlang. It cannot borrow checkout
`priv/`. Keep a finite outer job budget. For manual inspection, use root `./ipse`
for CLI and bundled `./bin/ipse eval` for trusted evaluation. A local archive is
not a published release; distribution needs matching `IPSE_NOTICES_DIR` runtime
notices from [the dependency inventory](dependencies.md).

## Exercise actual OS policies

Default tests exclude host-dependent enforcement tags. On a supported Linux host:

```sh
mix test --include native_sandbox
```

Required Landlock/namespace facilities must exist; included tests fail if absent.
For macOS, match the workflow's native and filesystem subset:

```sh
mix test test/macos_sandbox_test.exs test/stdio_runner_test.exs test/macos_filesystem_test.exs --include macos_sandbox --include macos_filesystem
IPSE_MAC_TESTS=$(mktemp -d)
rustc --edition=2021 --test native/ipse-macos-sandbox.rs -o "$IPSE_MAC_TESTS/policy"
"$IPSE_MAC_TESTS/policy"
```

Filesystem cases need a real case/normalization-insensitive volume and verify
inode identity. Native checks use private homes, not the operator cache. Report
platform exclusions separately. The [sandbox chapter](sandbox.md) teaches policy,
signing and best-effort descendant cleanup limits.

For native copy/authority changes, run their real protocol fixtures:

```sh
IPSE_NATIVE_TESTS=$(mktemp -d)
rustc --edition=2021 --test -D warnings native/ipse-file-copy.rs -o "$IPSE_NATIVE_TESTS/copy"
"$IPSE_NATIVE_TESTS/copy"
rustc --edition=2021 --test -D warnings native/ipse-bound.rs -o "$IPSE_NATIVE_TESTS/bound"
"$IPSE_NATIVE_TESTS/bound"
```

Copy controls retain size/inode/symlink/permission/nonblocking checks. Its ignored
FIFO probe is driven by a bounded enclosing case. Linux Bound adds authority,
FIFO and descriptor transfer; macOS runs only three platform-independent protocol
cases. Parallel fixtures use an atomic ordinal as well as PID/time to avoid
same-tick directory collisions; keep fixed-clock controls.

Probe the signed macOS helper with a separate disposable workspace:

```sh
IPSE_MACOS_WORKSPACE=$(mktemp -d)
elixir scripts/verify-macos-sandbox.exs priv/ipse-runner "$IPSE_MACOS_WORKSPACE"
```

The default checks file/network denial, allowed workspace/temp, inheritance and
signing. Optional `--process-boundary` probes stronger descendant properties;
detached descendants can survive supported best-effort cleanup, so gaps/nonzero
are not passing containment. The script cleans its own temporary bundle/files;
macOS retains app containers under `~/Library/Containers`.

## Diagnose incomplete stdio without weakening deadlines

Distinguish callback delivery, worker lifetime and native cleanup. Give a test
observation enough time for admitted initialization/callback/close work. Keep
runtime deadlines and strict cleanup assertions while investigating.

The captured-evaluator CLI exercise makes seven CLI invocations to declare, seal,
reopen and reject changed code. Its two-minute test watchdog covers that whole
sequence. A watchdog expiry during one `System.cmd/3` call does not identify
which child operation stalled. Run both CLI exercises together:

```sh
mix test test/knowledge_evaluation_declaration_cli_test.exs --seed 596778
```

Expect two passing tests. Preserve the exact retained-runtime inventory,
relative-path launch, missing/extra-code refusals and unopened-input assertions
when changing this exercise. Its test watchdog grants no extra model-call,
Worker or native execution time.

```sh
IPSE_TEST_STDIO_PROBE=1 mix test test/extensions_invocation_test.exs test/knowledge_evaluation_runner_test.exs --seed 77259
IPSE_TEST_STDIO_PROBE=1 mix test test/stdio_probe_test.exs test/extensions_feeds_test.exs test/mcp/session_test.exs
IPSE_TEST_STDIO_PROBE=1 mix test test/mcp/client_test.exs
```

The opt-in synthetic probe reports fixed phases, classified return values,
arities and monotonic timings without arguments, environments or payloads. Its
isolated trace session stops on owner loss, twenty seconds or 64 calls and labels
its report incomplete. CLI phase timing distinguishes freeze/launch/exit but
cannot identify every operation inside a wait. MCP fixture stages allow at most
sixteen fixed records with bounded numeric times; absent stages do not explain
why a process stopped. Privacy fixtures reject unrelated/private marker content.

For bounded frame/drain load:

```sh
mix run scripts/diagnose-stdio-cleanup.exs --iterations 1000 --concurrency 16 > /tmp/ipse-stdio-cleanup.jsonl
mix run scripts/diagnose-stdio-cleanup.exs --iterations 100 --concurrency 4 --sandbox native > /tmp/ipse-stdio-native.jsonl
```

These cases bound trials, concurrency, bytes and collection time. Native setup
is serialized and never falls back to trusted mode on failure. Use synthetic
data only; raw state inspection is privileged.

## Report the claim each check establishes

`scripts/measure-memory.exs` measures the fixed lexical fixture and
`scripts/measure-session-startup.exs` measures startup. Read dimensions before
comparing results. Token-overlap retrieval proves no semantic quality; sampled
VM memory is not an exact peak. Published measurements need corpus/source,
runtime, OS, concurrency and cost basis. Actual-model exact charged-RAM comparison
uses the separate [frozen evaluation procedure](knowledge-evaluation.md).

Live provider checks need the account owner's authorization and sanitized
provider/model/operation evidence. Never commit credentials, private prompts or
transcripts. Sign-in, rotation, paid inference and device behavior each need
actual checks before being claimed. Fixture edits need no new paid calls.

Finish with behavior, commands actually completed, failures/exclusions and limits.
Put dated evidence in [the archive](../archive/index.md) and status in
[the plan](../plan.md). Read the exact revision's
[workflow results](../../.github/workflows/ci.yml), not merely its commands.
Each hosted platform has 45 minutes for setup, suite, native, package and installed
checks. A passing source step does not prove later steps ran. An outer job budget
is separate from worker/model/native/test deadlines; change it only from retained
timing evidence and verify the complete candidate run.
