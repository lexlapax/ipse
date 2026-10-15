# Verification and local handoff

See the [documentation map](../index.md) for ownership, [usage](../operator/usage.md)
for operation, and [troubleshooting](../operator/troubleshooting.md) for recovery.

## Documentation completion check

Before declaring any sub-goal or milestone done, review developer and operator
guidance against implementation and actual results. Update commands, examples,
limitations, and status claims; separate fixture coverage from live checks.
Check relative file links, heading anchors, and consistency between entry points.
When adding or moving a guide, update the map and all old references. Keep
operator procedures in `docs/operator/`, developer guidance in `docs/developer/`,
and superseded material in the [archive](../archive/index.md).

Documentation-only changes need relevant CLI/example and link checks, not
invented runtime tests. Report blocked external link checks accurately; an HTTP
success alone does not establish that a source supports the associated claim.
See the [completion rule](../../AGENTS.md#finish-a-change).

## Checks that require no account

```sh
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
IPSE_HOME=$(mktemp -d) ./bin/ipse demo
```

Use focused tests during changes, then run the suite for a runtime handoff.
The suite exercises real filesystem and process behavior, local HTTP streaming,
OAuth validation with generated test keys, refresh serialization, skills,
journal recovery, approvals, and cancellation. HTTP fixtures bind to loopback;
Mix can also need local sockets. Initial dependency fetching needs network.
No real API keys or subscription are required. Auth transport injection and
subscription loopback endpoint overrides are compiled only for the test
environment. OAuth recovery and session-level subscription error fixtures are
separate from live account checks.

Ordinary `mix test` excludes `:native_sandbox` and `:macos_sandbox` enforcement checks. On a supported
Linux host, run `mix test --include native_sandbox`; included checks fail when
unavailable. On macOS, run `mix test test/macos_sandbox_test.exs --include macos_sandbox`.
Report the exclusion count and actual OS enforcement separately.

The demo is deterministic and does not call a model. It checks that the CLI,
session loop, skill loading, file tools, and native command helper work together.
Use its printed ID with `./bin/ipse chat --resume SESSION_ID` under the
same `IPSE_HOME`; `/session` should show the session without replaying tools.

### macOS App Sandbox diagnostics

After building on macOS, use a disposable workspace outside the probe's own
temporary directory:

```sh
IPSE_MACOS_WORKSPACE=$(mktemp -d)
elixir scripts/verify-macos-sandbox.exs priv/ipse-runner "$IPSE_MACOS_WORKSPACE"
elixir scripts/verify-macos-sandbox.exs priv/ipse-runner "$IPSE_MACOS_WORKSPACE" --process-boundary
rm -rf "$IPSE_MACOS_WORKSPACE"
```

The default probe checks signed file/network enforcement and ordinary child
inheritance. The extra flag also runs twelve process cases through the same
signed helper. Four controls keep the descendant in the original group. Eight
cases use `setsid` or `setpgid`, each followed by normal exit, timeout, explicit
Port closure, or Port-owner death. Readiness follows the group change and an
actual inherited outside-read denial. The probe confirms helper-process exit,
then releases a scratch-file gate and checks for a descendant's write and exit.
Children stop after five seconds even if the probe crashes. No process flood,
provider account, or credential file is involved.

Currently the extra flag prints eight `GAP` lines and exits nonzero. This is a
failure of the stronger descendant-lifetime contract, not a passing containment
result. The developer subsequently accepted best-effort cleanup for macOS native
mode. CI includes production macOS enforcement, the default experimental probe,
and both source/package platforms. The stronger process diagnostic remains opt-in.
The script removes its scratch files and bundle, but macOS retains each generated
`org.ipse.sandbox.<random-id>` app container under `~/Library/Containers`.
See [production gates and container lifecycle](sandbox.md#signing-and-integration-gates).

## Release check

```sh
./scripts/package.sh
```

From the source checkout, verify the printed archive automatically:

```sh
elixir scripts/verify-package.exs dist/ipse-*.tar.gz
```

The glob must select exactly one archive; otherwise pass the exact printed path.
This creates an isolated fresh HOME/IPSE_HOME and utility-only PATH, checks
default/explicit working directories (including spaces), and runs bundled helper
lifecycle checks. It uses the existing account and needs a bounded outer job
timeout. CI runs it on Linux and macOS; no archive is published automatically.

Extract the printed archive into an empty directory. Run `./ipse --help`
and `IPSE_HOME=$(mktemp -d) ./ipse demo` there. Do not rely on a source
checkout's `priv/` directory or build artifacts. Record OS, architecture, libc,
Elixir/OTP, and Rust versions with results. A release includes ERTS and the
native helper, but needs compatible system libraries.

From that extracted directory, also run the bundled helper checks:

```sh
./bin/ipse eval 'Code.require_file("verify-release.exs")'
```

On macOS it also checks native workspace writes, outside-file denial, and ordinary
child timeout cleanup using built-in codesign without a development toolchain.
This Elixir script verifies that runtime and application paths belong to the
extraction, exercises timeout and owner-death cleanup, and checks lock exclusion,
release on owner death, and inode preservation. The cleanup commands emit readiness
only after spawning their descendants, so the checks establish that work started
before cancellation or timeout. `./bin/ipse eval` is the bundled OTP launcher;
the root `./ipse` wrapper accepts Ipse CLI commands instead.
To prove independence from development tools, repeat help, demo, and helper
checks with Elixir, Erlang, Mix, and Rust executables absent from `PATH` while
retaining ordinary host shell utilities, including `sleep` for the helper check.

The packaging script copies the documentation tree recursively. When distributing
a release, set `IPSE_NOTICES_DIR` to a directory containing the bundled toolchain's
license notices; the packager copies these into `licenses/`. Building on one Linux
distribution does not establish compatibility with another distribution.
Inspect that directory in the extracted archive and record the supplied notice
sources and versions. Repackaging replaces the generated docs and licenses trees
so deleted material from an earlier build cannot survive there.

## Live provider acceptance

These checks are manual and use the account owner's authorization. Use a scratch
workspace and a small prompt. Record success/failure without credentials,
authorization URLs, tokens, private prompts, or full transcripts.

1. ChatGPT: browser login, status, streamed answer, tool-call round trip, resume,
   token refresh after expiry, and logout. Confirm account/model eligibility and
   that no API billing fallback occurs. Expiry/refresh must be tested with the
   live service before claiming the complete subscription lifecycle works.
2. OpenAI API: set the key securely; test streamed text and a tool round trip
   with `--provider openai`. This uses separate API billing.
3. Ollama: start the service and a tool-capable model; test text and a tool round
   trip with `--provider ollama`. Record the model/version and relevant hardware.
4. Anthropic API: test text, tool use, continuation, and a surfaced provider error
   with `--provider anthropic` and a key supplied securely.

## Current evidence and next checks

### Documentation restructure, 2026-10-14

Operator and developer guides now have separate directories, with a central
documentation map, dependency inventory, and historical archive. Verified 139
local file links and heading anchors across 24 Markdown documents, including
the archived snapshot. Checked active CLI commands against `./bin/ipse --help`
and the implementation. The 21 distinct public external links in active
documentation were reachable through HTTP checks or direct source retrieval;
reachability does not guarantee future availability. `git diff --check` passed.
These documentation-only changes introduced no runtime dependency; no runtime
suite or packaging rerun was required. The runtime evidence below is retained
from its actual checks.

### Initial Debian handoff

Initial handoff checks passed on Debian 13 Linux x86_64 (glibc 2.41),
Elixir 1.18.3 / OTP 27, Rust 1.85.1:

- Source build and compilation with warnings as errors.
- Elixir formatting and **49 tests, 0 failures**.
- Source CLI demo and interactive session resume without tool replay.
- Bundled release build; extracted CLI help and demo from a separate directory,
  without the development toolchain's library-path setting.
- No occurrences of the old project spelling in repository source or filenames.

### Arch source check, 2026-10-14

On Arch Linux x86_64, glibc 2.44, Elixir 1.20.4 / OTP 29 (ERTS 17.0.6),
Rust 1.99.0:

- Fixed Elixir 1.20 bitstring-size pin warnings in the native frame parser,
  SSE parser, and SSE fixture helper.
- Source build, formatting check, warnings-as-errors compilation, and all
  **51 tests passed** after the live fixes below. Tests use fixtures, not live
  model services.
- Source demo passed with isolated state under `/tmp`; interactive resume
  restored the idle session without replaying tools.
- The first sandboxed build failed because Mix's TCP lock returned `:eperm`.
  Build and checks passed with the required socket access outside that sandbox.
- Reviewed the implementation against official OpenAI
  [registration](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
  [session lifecycle](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions),
  and [inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
  documentation. This is a source review, not live protocol verification.
- An initial browser callback connection refusal involved a stale callback
  port; a running login listened on a different port. A fresh matching attempt
  reached the listener. The precise cause of the initial stale URL is unknown.
- Fixed the real auth transport's strict `not uri.userinfo` check: normal URLs
  have `nil` userinfo, which raised before HTTP exchange. Public OpenID discovery
  then succeeded with TLS verification enabled. Added a real-transport URL
  credential rejection test; OAuth protocol fixtures still inject transport.
- Fixed the Responses adapter discarding streamed output items when the live
  `response.completed` event contained `output: []`. A regression fixture now
  covers text, tool calls, and opaque continuation retention in this case.

### Live ChatGPT subscription check, 2026-10-14

Verified with the account owner authorizing in Chrome on the same Arch machine:

- Fresh browser authorization, loopback callback, token exchange and signed
  identity validation completed. Status confirmed plan-usage permission; the
  credential file mode was `0600`.
- Explicit `chatgpt` provider with `gpt-6.1-sol` returned streamed text using the
  public Responses API with `store: false` and `stream: true`. No API provider
  or API key was selected.
- In a scratch workspace, individually approved `write`, `edit`, and `shell`
  calls created a small file, changed its contents, and read it through a shell
  command with exit code 0. Full proposed arguments appeared before approval.
- After closing and resuming the live session, the model recalled the file,
  final contents, and command result without tools. Journal tool-start counts
  remained three, confirming no replay.
- Logout returned success (remote revocation confirmed by the auth transport).
  Status then reported no session. Checked that access, refresh, and ID token
  fields were removed while client registration and host ID remained.

### Arch release and local provider checks, 2026-10-14

Built `ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` on the Arch toolchain recorded
above. Fresh extraction under `/tmp` passed CLI help, credential-free demo, and
the bundled `verify-release.exs` checks. These ran with a utility-only `PATH`
containing no Elixir, Erlang, Mix, or Rust executables. The runtime and helper
resolved inside the extraction. This validates this host, not another Linux ABI.

An initial archive had only the generic Apache and Jason license texts. Rebuilt
with `IPSE_NOTICES_DIR` containing official upstream Elixir v1.20.4 and OTP
29.0.6 license trees, OTP/app authors, ERTS vendor license texts, and source
header/provenance inventories. Sources were tag commits
`759443e724f55bf58e71c0603644e99058918d52` (Elixir) and
`e07fd07837e5aa845657f5fa340637121e451d47` (OTP). Verified those files inside the
extracted archive. The header inventory includes upstream tests/examples;
it records provenance rather than certifying exactly which source files were
linked. No new build dependency was added.

Rebuilding initially retained stale documentation and notice files. After fixing
the packager to replace those generated directories, both sentinel checks passed.
Formatting, warnings-as-errors compilation, and all 51 fixture tests passed.

The installed Ollama-compatible service/client reported 0.40.1. A live
`qwen3.5:9b` read-tool round trip read the scratch file and returned its contents.
No model was downloaded. `ollama ps` reported the `llamacpp` runner, 4096 context,
and mixed CPU/GPU execution (28%/72%) on this host (Intel Core i7-12700K; NVIDIA
PCI vendor/device `10de:2486`). This is evidence for that local configuration,
not all models or hardware.

An intentionally unavailable ChatGPT model returned HTTP 400 under explicit
`chatgpt` selection; the failure surfaced without API provider fallback.

Natural-expiry refresh subsequently passed (see below). The later
[P0 closure check](#p0-closure-on-serenity-2026-10-15) observed a live usage-limit
error with Ipse's permission disabled. Broader plan eligibility, exhausted
allowance, live revoked-session recovery, paid API calls, and live provider use
on macOS remain unverified. Successful fixtures do not establish live-service compatibility.

### HTTP lifecycle regression checks, 2026-10-14

Controlled CLI fixtures exposed a transport lifetime defect: standalone profiles
reused fixed names, and asynchronous shutdown could leave the old profile alive
or collide with the next request. Replaced the duplicate auth/provider lifecycle
code with guardian-owned leases from a fixed 64-name pool. Each guardian starts
its own linked profile, monitors the borrower, and waits for profile exit before
releasing the name. This adds no package dependency.

Four behavior tests verify completed-request cleanup, borrower-death cleanup,
overlapping requests with isolated options, and repeated active cancellation
closing both linked processes and actual loopback sockets before immediate reuse.
All **55 fixture tests passed**. The isolated five-test P1 CLI draft also passed
against this transport; that is preparation, not a claim that P1 UI work is done.

Priorities and completion criteria are in [plan.md](../plan.md). When reporting a
failure, include the command, toolchain, sanitized error, and whether it ran in
a sandbox. Avoid calling permission failures application regressions until
the same command has been checked with the required access.

### Live natural-expiry renewal, 2026-10-15

Waited for the original access-token expiry without changing its timestamp or
re-authorizing. After expiry, `Ipse.Auth.token/1` renewed the session: both access
and refresh tokens changed and expiry advanced. Registration, host, identity,
and plan permission were preserved; credential mode remained `600`.
A subsequent explicit ChatGPT `gpt-6.1-sol` request returned the expected text
in four streamed chunks. Logout succeeded and access/refresh/ID token fields
were cleared. The check used the normal protected account registration, kept
all secrets in memory/protected storage, and retained only sanitized booleans
and timestamps as evidence. This is live renewal evidence, separate from fixtures.
No API-billing fallback was enabled. The later
[P0 closure check](#p0-closure-on-serenity-2026-10-15) adds one live usage-limit
error response. Broader eligibility, exhausted allowance, live revoked-session
recovery, paid API calls, and other platforms remain unverified.

### P1 CLI behavior, 2026-10-15

Six controlled CLI integration tests exercise the real CLI, session, HTTP
transport, and isolated journal homes with a loopback Ollama-protocol fixture.
They cover idle EOF, visible provider failure, running/finished states and
queued input at EOF, approval denial after EOF, resume preserving completed
write history without replay, and cancellation races. The cancellation check
forces repeated cancel and input arrival while cancellation is pending, proves
queued/discarded input is not sent, then completes a fresh turn in the same CLI.
No live model or account is used by these tests.

Build, formatting, warnings-as-errors compilation, all **61 tests**, and the
credential-free source demo passed. These checks do not establish live provider
compatibility beyond the separately recorded P0 account checks.

The rebuilt Arch bundle also passed help, credential-free demo, native timeout,
owner-death and lock checks, and HTTP-profile acquisition/cleanup from a fresh
extraction using a utility-only `PATH` without the development toolchain. A
source `chat --provider demo --yes` smoke check accepted two piped tasks and
finished both before exiting on EOF in an isolated scratch workspace. This is
scripted CLI evidence, not additional live model connectivity evidence.

### P1 runtime identity, 2026-10-15

Build, formatting, warnings-as-errors compilation, all **66 fixture tests**, and
the credential-free source demo passed. Added checks cover application version,
provider/model overrides, bounded invalid identifiers, missing/differing reported
models, secret exclusion, repeated-turn context, historical versus current-run
metadata after resume, and `/info` without inference while a request is pending.
Existing HTTP fixtures now assert runtime context survives serialization for
ChatGPT/OpenAI, Ollama, and Anthropic, and optional response metadata preserves
existing tool/continuation formats.

A separate live request to the already installed local Ollama `qwen3.5:9b`
returned application version `0.1.0`, configured provider `ollama`, and requested
model `qwen3.5:9b` from the supplied host facts. Resuming that scratch session
showed the saved provider-reported model in `/info`, with the current-run field
unavailable before inference. A plain “What version are you?” follow-up returned
`0.1.0`. No model was downloaded and no paid credentials were used. The new
identity behavior was not rechecked live with ChatGPT, OpenAI API, or Anthropic;
the earlier subscription lifecycle evidence remains separate.

The rebuilt Arch archive passed help, `/info` followed by EOF without inference,
credential-free demo, native timeout/owner-death/lock checks, and HTTP-profile
cleanup from a fresh extraction with a utility-only `PATH` containing no
development toolchain. `/info` showed bundled application version `0.1.0` and
explicit demo/scripted configuration. All 144 local documentation links/anchors
across 24 Markdown documents passed validation; developer/operator guidance was
reviewed against the implementation.

### Subsequent live ChatGPT identity, 2026-10-15

Reauthorized the same Ipse registration through the documented browser consent
flow. An explicit ChatGPT `gpt-6.1-sol` scratch session returned application
version `0.1.0`, provider `chatgpt`, requested model `gpt-6.1-sol`, and appropriately
unknown backend revision. `/info` after resume showed saved reported model
`gpt-6.1-sol` separately from unavailable current-run metadata, without inference.
No API provider or billing fallback was enabled.

### P2 context compaction, 2026-10-15

Build, formatting, warnings-as-errors compilation, all **78 tests**, and source
demo passed. Six helper tests cover safe boundaries, repeated compaction,
verbatim intent/action provenance, native recent continuation, old reasoning
exclusion from summary input, bounded/schema/tool-call rejection, stable JSON
digests, and disabled compaction. Five session integration tests cover durable
commit plus continuation, original journal retention and resume without replay,
cancellation before commit, owner death after commit, malformed summary recovery,
and rejection of corrupted committed checkpoints. Existing approval tests now
verify host-written decision/outcome metadata rather than inferring it from text.
A cancellation regression distinguishes approval-pending calls that never started
from executing calls whose effects may already have occurred.

A separate live ChatGPT scratch transcript with synthetic project facts compacted
from **29,490 to 3,358 bytes**. The resulting streamed reply (16 text chunks)
retained the project name `acorn` and MIT constraint. Exactly one checkpoint was
saved, all original messages remained, and no tools started. Resume retained
those facts without another compaction or tool execution. This is live evidence
for that account/model, separate from deterministic fixtures. Summary fidelity
is not proven generally; native OpenAI compaction and other providers' live
compaction behavior remain unverified. See [the contract](context-compaction.md).

The final compaction archive passed help, `/info`, `--context-bytes 8192` and
`--no-compact` parsing, credential-free demo, bundled compaction-module loading,
and native timeout/owner-death/lock checks from a fresh extraction with no
development toolchain on `PATH`. Developer/operator docs were reviewed and all
153 local links/anchors across 25 Markdown documents passed validation.

### Minimum-version formatter compatibility, 2026-10-15

GitHub CI for the identity and first compaction commits stopped at formatting
before behavior tests. Elixir 1.18 formatted two multiline tuple assertions
differently from Arch's 1.20. Rewrote those assertions to avoid that layout
ambiguity without changing their coverage. Formatting passes with both Arch
Elixir 1.20.4 and the official checksum-verified Elixir 1.18.4 OTP-27 build.
The latter was used for formatting only on the local OTP 29 host, not as proof
of the minimum runtime combination. All 11 affected provider fixtures passed
locally. The follow-up [GitHub Checks run](https://github.com/lexlapax/ipse/actions/runs/38703884589)
passed on the configured OTP 27 / Elixir 1.18 combination, including formatting,
all 78 tests, build, and demo.

## P3 workspace context (2026-10-15)

On Arch, the source build, Elixir 1.20 and 1.18 formatter checks,
warnings-as-errors compilation, all **95 tests**, and credential-free demo
passed. Workspace fixtures cover global/ancestor/nested scope, referenced
resources, non-repositories, source bounds/UTF-8/symlinks, snapshot validation,
saved-content resume with drift, explicit async refresh, and canonical cwd
aliases. A two-call pending write batch is recorded as not started when new
nested instructions appear; neither write executes before a revised proposal
reaches approval. `/context` and refresh are local, and refresh is refused while
model work is active. Independent review reproduced and fixed nonregular-source
crashes and disagreement between resource discovery and snapshot validation for
sensitive absolute paths; regression fixtures passed.

Separate **live ChatGPT subscription** scratch checks used explicit
`chatgpt/gpt-6.1-sol`: a coding task created `nested/hello.exs` with the comment
required by nested guidance and ran it with Elixir (56 streamed text chunks,
three approved mutations). After resume and a changed ancestor instruction file,
a non-coding notes-file task retained the saved project marker and README purpose
(29 streamed text chunks, one approved write). Two context snapshots were journaled;
changed instructions produced drift diagnostics. Full proposed mutation arguments
were displayed before approval. These checks do not establish semantic instruction
compliance for every model or arbitrary shell target.

Source and fresh bundled launchers passed from an arbitrary Git subdirectory
and with explicit `--cwd`, using isolated `IPSE_HOME` directories. Fixture journal
metadata and manifests confirmed the chosen cwd and ancestor provenance.
The isolated P3 archive used the previously committed native helper (pending
sandbox changes were excluded). The extracted release ran without Elixir, Mix,
Rust, or Erlang on `PATH` and passed bundled timeout, owner-death, and lock checks.
This is same-host Arch release evidence, not a new OS account or cross-machine
portability check. The original journal is retained; resume never replays tools.

## P2 native Linux sandbox (2026-10-15)

On Arch x86_64, kernel `7.2.9-arch1-1`, the source build, both Elixir formatter
versions, warnings-as-errors compile, **97 ordinary tests (7 enforcement tests
explicitly excluded)**, and demo passed. Running `mix test --include native_sandbox`
against the rebuilt helper passed **all 104 tests**. These are actual OS checks,
not simulated permission errors: outside fake credentials and symlink targets
could not be read/written/chmodded; system metadata remained read-only; workspace
chmod, Rust threads, and Elixir compilation worked; inherited test secrets and
`/proc` were absent. A reachable loopback control endpoint became inaccessible
inside the sandbox. Host signals, IPC, pidfds, process-group escape, scheduling,
page/process-memory mutations, and cross-PID resource changes were denied.
A disposable host process's file-descriptor limit stayed unchanged, while
current-process limit queries worked. Synchronized timeout and owner-death tests
proved started descendants did not leave delayed effects.

Independent review found host-process resource-control calls still needed
restriction. The fixed profile now allows `prlimit64` only for current-process
PID zero and denies scheduling/priority/page mutation APIs; compiler and thread
checks passed afterward. Native mount-source replacement was also checked
against retained inode/device identities and failed closed.

Separate **live ChatGPT subscription** evidence: `chatgpt/gpt-6.1-sol` streamed
42 text chunks while creating a scratch Elixir file and executing precisely
`elixir hello.exs` under the native profile. Both effects were individually
approved with full arguments; the native shell returned exit zero and expected
output. Provider inference remained outside shell enforcement. No fallback to
API billing or trusted execution occurred.

A fresh bundled extraction passed native outside-file denial, workspace write,
protected-workspace refusal, demo, and existing timeout/owner-death/lock checks
with no development toolchain on `PATH`. Linux aarch64 and other kernel policies
remain unverified. macOS enforcement and Windows remain separate work; selecting
native on unsupported platforms fails closed. See [scope and limits](sandbox.md).

## P4 release verification and protocol proposal (2026-10-15)

The local Arch source baseline and all **104 tests with native enforcement
included** passed again after the cross-platform fixture setup change. Both
Elixir formatter versions passed. Rebuilding the archive with version-matched
runtime notices and running
`elixir scripts/verify-package.exs dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`
passed: fresh extraction, empty isolated HOME/IPSE_HOME, no development toolchain
on `PATH`, help, default launch cwd containing spaces, explicit `--cwd`, exact
demo output file, and bundled OTP/helper lifecycle checks. This is a fresh-home
check on the existing account, not a newly created OS account or another host.

The CI matrix now schedules these source/package checks on Linux and macOS.
The experimental macOS script uses the approved built-in `codesign`, an ad-hoc
helper app, and Rust standard-library TCP probe. It requires successful execution
and a reachable network control before claiming network denial; it checks outside
file/symlink/metadata denial and allowed workspace/private-temp writes. Syntax
and the Rust probe were checked locally; the hosted probe result is recorded
below. The supported CLI still fails closed
for native mode on macOS; this probe alone does not implement resource/process
containment for a production backend.

The [protocol proposal](protocol-proposal.md) defines schemas, explicit trust and
configuration, approvals, cancellation/ownership, durable intent/results, and
unknown-outcome recovery. It does not implement MCP, delegated agents, or remote
execution. Those require their own focused implementation and tests.

The [first cross-platform CI run](https://github.com/lexlapax/ipse/actions/runs/38709598986)
passed Linux checks and macOS source build, formatting, warnings-as-errors
compilation, ordinary tests, demo, packaging, and fresh-home bundled verification.
The experimental macOS step failed before enforcement because the hidden Rust
source filename produced an invalid inferred crate name. An explicit crate name
fixes this reproduced build issue. Review also tightened network checks to accept
only a connect permission denial, rejecting refusal, timeout, and successful
connections. The revised Rust probe passed those controls under Linux native
enforcement before the successful macOS run below.

The [second hosted run](https://github.com/lexlapax/ipse/actions/runs/38710166415)
again passed both platforms' core/package checks, then stopped at code signing:
the auxiliary entitlement input had been placed in `Contents`, a nested-code
location. It now stays outside the app bundle, following Apple's documented
[bundle structure](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle).
This is a signing-layout fix, not a passing enforcement result.

The [corrected hosted run](https://github.com/lexlapax/ipse/actions/runs/38710566686)
passed on both platforms, configured with Elixir 1.18/OTP 27. Each passed build,
format, warnings-as-errors compile, ordinary tests, demo, packaging, and fresh-home
bundle verification. Archives were `ipse-0.1.0-linux-x86_64-glibc-2.39.tar.gz` and
`ipse-0.1.0-darwin-arm64.tar.gz` (macOS 14 runner). This establishes those hosted
source/bundle paths, not that the Arch/glibc-2.44 archive runs on Ubuntu.

The actual macOS signed-helper probe also passed: strict code-signature and
entitlement checks; denied outside fake-credential/symlink reads, outside writes
and chmod; permitted workspace chmod/write and private-temp write; same Rust
binary successfully executed inside the sandbox; reachable loopback connection
became a connect permission denial; nested shell inherited the restrictions.
Resource ceilings, adversarial process escape/cleanup, runtime signing/cache
lifecycle, and a production CLI backend remain unimplemented/unverified on macOS.
No Windows execution or paid API checks were performed. Final live-test logout
completed successfully; local subscription tokens were cleared while retaining
the app registration for the next sign-in.

## macOS process boundary (2026-10-15)

Historical research milestone before the native-backend decision below. Statements
about unavailable native mode describe this earlier state. See the
[current backend and verification](#macos-native-backend-2026-10-15).

Continued from `d7d2118` on macOS **26.7.2**, build `25G325`, Darwin `25.6.0`,
arm64. The installed toolchain was Elixir **1.20.3**, Erlang/OTP **29.0.5** with
ERTS **17.0.5**, and Rust **1.97.1**. Source build, formatting,
warnings-as-errors compilation, **97 tests with 7 Linux enforcement tests
excluded**, and the credential-free demo passed. The initial build was blocked
by Mix's loopback TCP lock under the execution sandbox; the build and tests
passed with the required socket access. TLS and tests were unchanged.

The default signed App Sandbox probe passed. Two subsequent invocations with
`--process-boundary`, including one refined to confirm actual helper-process
exit, reproduced these results:

| Descendant | Normal exit | Timeout | Port closure | Port-owner death |
| --- | --- | --- | --- | --- |
| Original process group | Stopped | Stopped | Stopped | Stopped |
| New session using `setsid` | Survived | Survived | Survived | Survived |
| New group using `setpgid` | Survived | Survived | Survived | Survived |

Each surviving descendant retained outside-file denial and wrote its workspace
marker only after the signed helper had exited. The bounded fixtures then
terminated; liveness checks confirmed their exit. Both diagnostic runs exited
nonzero with eight named containment failures. The three initial probe runs
also left three generated macOS app containers; scratch bundles and workspace
fixtures were removed. This is actual host OS evidence, separate from provider
fixtures and the earlier macOS 14 CI evidence.

The local `ipse-0.1.0-darwin-arm64.tar.gz` archive built and passed
`verify-package.exs`: fresh isolated HOME/IPSE_HOME, help, default and explicit
workspaces containing spaces, exact demo output, bundled timeout/owner-death
and lock checks, and no development toolchain on PATH. This verifies the
existing trusted runner, not bundled native-mode enforcement. No additional
version-matched toolchain notice directory was supplied, and no release was
published. Final formatting, warnings-as-errors compilation, and the ordinary
97-test suite passed again. All 189 local inline documentation links and heading
anchors across 29 Markdown files passed validation.

Public-interface research is recorded in
[the macOS boundary](sandbox.md#public-interfaces-and-remaining-limits).
`--sandbox native` remains unavailable on macOS. Resource ceilings, signal
isolation, adversarial reparenting, signing/cache recovery and container cleanup,
and bundled native-mode enforcement remain open. Linux enforcement was not run
on this macOS host. No live provider or Windows check was performed.

The [CI run for `e4ce266`](https://github.com/lexlapax/ipse/actions/runs/38714558457)
passed both Ubuntu Linux and macOS 14 jobs: source build, formatting,
warnings-as-errors compilation, ordinary tests, demo, packaging, and fresh-home
bundled verification. The macOS file/network probe also passed. The new
process-boundary flag was not included in that passing CI run; its eight local
failures remain open production acceptance checks.

Following the developer's decision to keep native mode unavailable and continue
public-native investigation, reviewed Foundation termination through Context7,
Apple's XPC/spawn/ptrace contracts, XNU libproc and coalition sources, and
Endpoint Security documentation and installed SDK headers. The SDK was **27.0**.
No compatible process-tree boundary was verified. These are documentation/source
findings, not live tests of the candidate APIs. No private API, service,
entitlement, or package was adopted. See the
[candidate comparison](sandbox.md#additional-native-controls-reviewed).
The follow-up documentation check validated 192 local inline links and heading
anchors across 29 Markdown files. CLI help still documents opt-in native mode
and fail-closed unavailability. No additional runtime behavior was changed.

## macOS native backend (2026-10-15)

After the research above, the developer requested native execution on the Mac,
accepting best-effort detached-descendant cleanup. On the same macOS 26.7.2 arm64
host, the production Runner path passed actual workspace writes, outside-file
read/write/chmod and symlink denial, protected signed-worker mutation denial,
environment scrubbing, temporary-home writes, and installed Elixir compilation.
A reachable loopback TCP positive control connected; the sandboxed Rust probe
received `EPERM`. Host and supervisor signal probes were denied. Resource probes
verified inherited ceilings, descriptor exhaustion, regular-file write denial,
and inability to raise a hard limit.

Ordinary process-group children stopped on timeout and owner death. A synchronized
detached child retained an output pipe after its parent exited; Runner completed
within the bound, then the surviving child proved outside-file denial before its
bounded exit. This explicitly verifies the accepted lifetime limitation rather
than claiming complete descendant cleanup. Changed signed-worker contents and
workspaces containing the active application failed before command effects.

The full suite with macOS enforcement included passed **121 tests with 7 Linux
enforcement tests excluded**. Sixteen portable cache tests use a fake helper;
they cover reuse, corruption, unsafe links/modes, abandoned stages, generation
capacity, malformed or broadened entitlement schemas, and competing locks.
Those fixtures are distinct from the real codesign and OS enforcement checks.
A Rust policy-parser test also passed, including boolean/array type confusion,
exact roots, duplicates, and trailing-data rejection.

Source build, formatting, warnings-as-errors compilation, and the credential-free
demo passed. The actual CLI demo also completed with `--sandbox native` in an
isolated scratch workspace and state home. The Mac archive built and
`verify-package.exs` passed using a fresh isolated HOME/IPSE_HOME and utility-only
PATH. Its bundled native checks exercised allowed workspace writes, outside-file
read/write denial, and ordinary child timeout cleanup without Elixir/Mix/Rust on
PATH. Earlier trusted helper/lock checks also passed.

Linux enforcement and live provider inference were not run on this Mac.
OS-managed test app containers persist. No package was published.

The first CI run for `2ffcad2` stopped at formatting on both platforms before
tests. Elixir 1.18 wraps a long pinned-pattern expression differently from 1.20.
Extracting the entitlement path keeps the expression short and both formatter
versions agree. Formatting passed locally with Elixir 1.18.5/OTP 27.3.4 and
1.20.3/OTP 29.0.5; all 16 cache tests passed after this behavior-preserving change.
Operator guidance was reviewed and remains valid. The
[replacement CI run for `f07d3f2`](https://github.com/lexlapax/ipse/actions/runs/38757410934)
passed the complete Linux job and Mac source/ordinary tests. Seven Mac enforcement
tests passed; the compiler check returned 127 because CI installs Elixir outside
the native profile's fixed tool roots and minimal PATH.

The corrected suite separates workspace/environment checks from compiler access.
An unsandboxed compilation first proves the installed toolchain works. Native
execution must compile when that toolchain is under the fixed readable roots;
otherwise it must report permission denial and leave no compiled artifact.
All nine corrected Mac enforcement tests passed locally with Homebrew Elixir.
Formatting passed with both supported Elixir versions. A local attempt to use
the isolated older toolchain could not start tests because its fresh Mix home
lacked Hex; no dependency was installed and that attempt is not a test pass.
The [final CI run for `3c349f5`](https://github.com/lexlapax/ipse/actions/runs/38758452442)
passed both Linux x86_64 and macOS 14 arm64 jobs, including source checks, demo,
packaging, and fresh-home verification. The Mac passed all nine corrected native
enforcement tests, the Rust policy-parser test, and the experimental file/network
probe. Its installed compiler positive control succeeded and native execution
outside the readable tool roots was denied without a compiled artifact.
The final local full suite passed **122 tests with 7 Linux enforcement tests
excluded**. Developer/operator docs were reviewed for the transfer back to
Serenity. The subsequent [Linux return checks](#p0-closure-on-serenity-2026-10-15)
ran native enforcement on Serenity rather than inferring it from ordinary CI.

## P0 closure on Serenity, 2026-10-15

Pulled clean `main` from `origin` through `ec5fb85`, preserving the Mac native
backend and its accepted detached-descendant lifetime limit. This closes P0 for
the available Arch host and account; unavailable live branches stay explicitly
unverified below. It does not claim every subscription plan or platform works.

### Recovery and protocol fixtures

Reviewed current official OpenAI [errors and recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery),
[profiles and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions),
[preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations),
and [models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).
The subscription request uses developer messages and `additional_tools` input
items instead of top-level function tools; OpenAI API requests keep their
separate format. Subscription URLs are pinned to the public OpenAI endpoint,
with test-only loopback overrides.

Fixtures cover terminal refresh errors clearing only unusable tokens, retained
registration/account identity, invalid-client and transient failures preserving
credentials, and rotated tokens with reduced scopes being saved before denial.
A discovered post-rotation discovery outage could previously lose the new refresh
token. Renewal now saves protected pending rotation before fetching identity keys.
Tests verify retry and owner-death recovery without a second token exchange,
original expiry retention and consistency checks, malformed/mismatched/expired identity rejection,
fresh-login replacement, and logout revoking the newest pending refresh token.
Unverified identity is never activated. Loss before durable storage still
requires fresh login; expired unvalidated identity requires fresh login too.

Structured HTTP and SSE failure fixtures preserve bounded status, body shape,
code, parameter, and request ID without provider prose or credentials. Real
session/loopback fixtures simulate ineligible-account and usage-limit failures,
prove one request with no retry or API-key fallback, retain credentials, and
resume without replay. CLI fixtures verify queued input is discarded visibly
after errors and only fresh input starts another turn.

### Live account checks

The normal protected ChatGPT registration passed the updated request shape with
`gpt-6.1-sol`: **43 streamed chunks and two individually approved effects** in a
scratch workspace. It wrote `hello.exs`, then ran exactly `elixir hello.exs` under
the actual Linux native profile, with the expected output and exit code zero.
No API billing path was selected. Earlier browser sign-in, approved edit,
session resume, natural-expiry rotating refresh, and logout evidence above
remains valid; those lifecycle actions were not repeated for this patch.

With the owner's specific approval, temporarily disabled only “Allow Ipse to use
plan limits,” saved it, and made one tiny request. The live SSE stream returned
`subscription_sharing_usage_limit_exceeded`; Ipse stopped and surfaced recovery
guidance. Restored the saved permission to enabled at its original 100% app limit;
credit use remained disabled. This proves handling of the live code, **not actual
allowance exhaustion**. Automatic approval review rejected an extra post-restore
request as outside that permission-test scope; restoration was verified in the UI.

No already ineligible or exhausted account was available. Broader plan/workspace
eligibility, genuine allowance exhaustion/reset behavior, live revocation
recovery, and the pending-renewal outage path remain unverified against OpenAI.
Those negative branches have fixture coverage only. No allowance was deliberately
exhausted, no credits were enabled, and no API billing fallback was used.

### Local and release checks

Serenity: Arch Linux x86_64, kernel `7.2.9-arch1-1`, glibc 2.44,
Elixir 1.20.4 / OTP 29 (ERTS 17.0.6), Rust 1.99.0. Source build, both Elixir 1.20
and 1.18 formatter checks, warnings-as-errors compilation, and isolated
credential-free demo passed. Ordinary tests: **142 passed, 16 enforcement tests
excluded**. With actual Linux native enforcement included: **149 passed,
9 Mac enforcement tests excluded**. Historical Mac evidence remains separate.

Rebuilt `ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` with the same version-matched
official runtime notices described above. `scripts/verify-package.exs` passed:
fresh isolated HOME/IPSE_HOME, utility-only PATH without Elixir/Erlang/Mix/Rust,
help, demo, default/explicit workspaces with spaces, and bundled helper lifecycle
and lock checks. This is a local archive check, not publication or another Linux ABI.

Developer/operator commands and content were reviewed; the fulfilled Serenity
handoff is preserved in the documentation archive. All 221 local links and
heading anchors across 30 Markdown documents passed validation. No new
dependency was added.

## P5 local MCP, 2026-10-15

Implemented the explicitly configured local stdio client described in the
[MCP contract](mcp.md). Reused MCP Elixir SDK 1.1.0 and JSONSchex 0.10.0 after
comparing published package contracts and actual source. The SDK's advertised
optional Req/Plug modules were necessary for compilation on Elixir 1.20; their
locked dependency chain is documented. Req 0.7.5 replaced the older release
flagged during resolution, and `mix hex.audit` passed with no current advisories
or retired packages. The developer explicitly approved Telemetry and Rebar3.
Rebar3 was already installed here (3.27.0); no new system package was installed.

### Protocol, effect, and ownership evidence

Local fixtures use real subprocess stdin/stdout, not an in-memory MCP transport.
They verify explicit config/allowlists, collisions including normalized dotted
names, strict schema subsets and bounds, pagination, duplicate/changed discovery,
unsupported sampling, safe protocol errors, text redaction, and invalid/oversized
messages. Mixed request/response envelopes are rejected before SDK decoding, and
private values containing JSON escapes are checked before encoding. Persistent
configuration fingerprints exclude private values.

Real session fixtures verify exact approval arguments, intent before dispatch,
headless denial, serial calls, confirmed cancellation, owner-death cleanup,
configuration-bound resume, completed-call preservation, and unknown-outcome
batch stopping/resume without replay. The OS supervisor tests cover independent
stdout/stderr, environment clearing, lossless bounded binary relaying, output and
input backpressure, timeout/owner death, ordinary child cleanup, and cancellation
while writes are queued. Only an unsent cancellation control can retry; tool
input is never replayed. Cleanup confirmation requires actual exit status,
including after a linked Port error. Detached process-group escape remains an
explicit trusted-execution limitation on both platforms.

`mix run scripts/demo-mcp.exs` passed with the existing SDK as **both client and
example server**, a scripted model, one displayed exact approval, and a verified
scratch `mcp-note.txt` write. No model service was contacted. The documented
`--mcp-config` CLI option also passed a credential-free scratch smoke check;
`--help` and operator examples were reviewed against the implementation.

### Source and package baseline

On Serenity's Arch x86_64 toolchain recorded in P0, source build, warnings-as-errors
Ipse compilation, both Elixir 1.20/1.18 formatter checks, and the original
credential-free demo passed. Ordinary suite: **182 passed, 16 enforcement checks
excluded**. Including actual Linux native enforcement: **189 passed, 9 Mac
checks excluded**. All 244 local documentation links and heading anchors across
32 Markdown files passed validation. Mac enforcement was not run on this host.
Fresh upstream dependency compilation emits existing UUID/JSONSchex deprecation
and type-analysis warnings on Elixir 1.20; these were not suppressed, vendored,
or patched. Ipse's own warnings-as-errors compilation passes.

The Arch archive rebuilt with every resolved package's upstream license notices,
including NimblePool's README notice. Corrected the old Jason MIT label to match
its pinned Apache-2.0 notice. Fresh-package verification passed the existing
help/demo/workspace/helper/lock checks and a **real bundled MCP SDK round trip**:
both peers used the extracted runtime without Elixir/Erlang/Mix/Rust on PATH.
The matching Elixir/OTP notice set from P0 was supplied. No archive was published.

These are fixture and local SDK interoperability checks. Live ChatGPT/Ollama/API
use with MCP, arbitrary third-party servers, persistent server sessions,
network transports, resources/prompts, sampling/elicitation/tasks, delegation,
remote execution, and Windows remain unverified or unimplemented. The P0 live
subscription evidence is separate; no account setting or billing path changed
in this milestone.

The first P5 hosted run failed because the source fixtures launched Elixir with
the deliberately cleared environment but did not select the CI installation's
Erlang path. Arch's system Erlang masked that test setup error. Source fixtures
and the SDK demo now explicitly select the running OTP installation's `bin`
directory; the runtime environment isolation policy is unchanged.

The corrected implementation at `b7522dd` passed
[Linux x86_64 and macOS 14 arm64 CI](https://github.com/lexlapax/ipse/actions/runs/38773218000):
source checks, ordinary tests, credential-free demo, packaging, and fresh-home
bundled MCP verification. Mac native enforcement and the signed App Sandbox
probe also passed. These hosted checks are separate from the local Arch results.
