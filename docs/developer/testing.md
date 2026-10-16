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
Stdio fixtures create an isolated owner-only `IPSE_HOME`; they do not use or
change the operator's signed cache or its permissions.

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

### Stdio cleanup load diagnostic

After building, capture synthetic decoded frames with the Elixir diagnostic:

```sh
mix run scripts/diagnose-stdio-cleanup.exs --iterations 1000 --concurrency 16 > /tmp/ipse-stdio-cleanup.jsonl
mix run scripts/diagnose-stdio-cleanup.exs --iterations 100 --concurrency 4 --sandbox native > /tmp/ipse-stdio-native.jsonl
```

The script alternates the original initial-exit fixture, 64 KiB on each output
stream, and the same burst with collection delayed by 100 ms. It records every
decoded frame, helper exit status, elapsed time, and incomplete frame bytes.
The summary separates output-read errors, drain deadlines, other helper errors,
transport failures, and missing completion. Any unexpected status, output,
error frame, missing completion, or delayed child write makes the run fail.
Bounds are 1,000 trials, sixteen concurrent owners, 256 KiB captured per trial,
a five-second helper lifetime, and a seven-second collection deadline.

Native setup is serialized because signed-cache preparation uses a nonblocking
cross-process lock; launched servers and cleanup still overlap. Setup failures
remain failures and are never retried in trusted mode. State and workspaces are
temporary, and the previous `IPSE_HOME` is restored. Native Mac runs can leave
OS-managed app containers, as described above. Logs contain only synthetic
fixture output and can be large. No MCP or provider service is contacted.
The collector's delayed receive does not guarantee backpressure on the OS pipe.
See [local investigation evidence](#macos-stdio-cleanup-load-2026-10-15).

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

### Provider verification status

Milestone completion is scoped to its recorded evidence; fixture coverage is
not live-service acceptance. Current recorded status:

| Provider | Live evidence | Outstanding |
| --- | --- | --- |
| ChatGPT subscription | Browser sign-in, streamed coding/tools, resume, natural-expiry rotating refresh, logout, compaction, local MCP, and serial delegation on Arch | Broader eligibility/allowance cases and other hosts remain bounded by the individual records below |
| Ollama | Installed `qwen3.5:9b`: basic acceptance, compaction, native local/HTTP MCP, serial/parallel delegation and idle resume on Arch | Other models/hosts and feature-specific negative paths |
| Anthropic API | Explicit API billing with `claude-haiku-4-5`: basic acceptance, compaction, native local/HTTP MCP, serial/parallel delegation and idle resume on Arch | Other models/hosts and feature-specific negative paths |
| OpenAI API | Explicit API billing with `gpt-4.1-mini`: basic acceptance, compaction, native local/HTTP MCP, serial/parallel delegation and idle resume on Arch | Other models/hosts and feature-specific negative paths |

The developer authorized live API calls using the ignored repository `.env` on
2026-10-15. Keys were loaded privately for the check; they were not printed,
committed, journaled, or supplied to the MCP server. No model was downloaded,
no credential fallback occurred, and each provider was explicitly selected.
These results do not establish arbitrary model/host coverage. See
[the live acceptance record](#live-provider-acceptance-follow-up-2026-10-15).
Earlier Ollama evidence
is in [Arch local provider checks](#arch-release-and-local-provider-checks-2026-10-14)
and [runtime identity](#p1-runtime-identity-2026-10-15).

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

The checks above are fixture and local SDK interoperability checks. The live
ChatGPT follow-up below is separate. Live Ollama/API use with MCP, arbitrary
third-party servers, persistent server sessions,
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

### Live ChatGPT MCP follow-up

On 2026-10-15, the source CLI at `6b324b1` passed a live MCP session on Serenity's
Arch toolchain recorded above. Reused Ipse's existing protected sign-in and
explicitly selected `chatgpt/gpt-6.1-sol`; there was no API-provider fallback,
account-permission change, or new dependency. Reviewed the current official
[subscription inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
and [preview limits](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).
Local MCP functions went through the existing `additional_tools` subscription
route, rather than hosted MCP/connectors.

Configured only `priv/mcp-notes.exs`, using the existing SDK server, a fresh `/tmp`
workspace, separate scratch journals, an explicitly selected OTP path, and
`--max-steps 4`. The live model requested `mcp__live_notes__write_note` exactly
once. Reviewed the full arguments and individually approved the proposed content
`Live ChatGPT MCP verified.` followed by one newline. The server returned success;
exact file bytes matched, the streamed assistant reply completed with
`MCP_WRITE_OK`, and the journal retained one approved intent and one tool result.

Exited and resumed with the same explicit MCP configuration. Before any new
prompt, all ten journal events and the file's modification/change timestamps
were unchanged: startup did not replay the tool. A second live prompt requested
recall without tools; its streamed reply recalled the saved text and completed
with `RESUME_OK`. Final assertions found two finished turns, still one MCP
intent/result, unchanged file timestamps, and the same exact bytes. Scratch
transcripts and account details are not committed.

This is live-model evidence for one local SDK example server on Arch, separate
from scripted demos and protocol fixtures. Arbitrary third-party servers and
other live providers remain unverified. This follow-up did not independently
test refresh, logout, cancellation, or unknown-outcome recovery. Refresh/logout
retain their earlier P0 live evidence; MCP cancellation and unknown-outcome
recovery retain their P5 fixture evidence.

Reviewed developer/operator guidance against the live result. All 245 local
documentation links and heading anchors across 32 Markdown files passed.

## Linux Rust subprocess compatibility, 2026-10-15

During independent MCP investigation, an approved offline Cargo build inside
the native Linux sandbox failed to start Rust compiler subprocesses. Rust 1.99
uses a private connected Unix sequence-packet pair for its fork/exec error
channel; the profile previously permitted only stream pairs. Permitted
`AF_UNIX/SOCK_SEQPACKET` pairs while retaining datagram-pair and all external
socket/connection denials. Namespace, Landlock, filesystem, and resource policy
are unchanged.

Source build, formatting, warnings-as-errors compilation, and the full ordinary
suite passed in the development worktree. All nine focused Linux enforcement
tests passed, including actual Rust compilation/linker spawning and forced
`Command::pre_exec` child spawning. The probe also checked that private stream
and sequence-packet pairs work, while datagram/non-Unix pairs and standalone
Unix/IPv4/IPv6 sockets return permission denial. The previously failing locked
Cargo build then passed with networking disabled and writes confined to its
temporary native workspace. This is local Arch enforcement evidence, not a
new protocol-compatibility or macOS claim.

## P6 local delegation, 2026-10-15

Implemented opt-in serial local children using the existing OTP session, task,
approval, and journal boundaries; no new package was added. The child gets the
same provider/model/workspace, saved instructions, and selected task/context,
with a separate journal and no parent transcript, MCP, or recursive delegation.
See the [contract](delegation.md) and [operator guide](../operator/subagents.md).

Fifteen focused policy/session fixtures passed. They cover explicit enablement,
headless denial, exact parent/child approval references, individual child denial,
intent ordering and separate journals, context minimization and saved-instruction
drift, normal close, completed/unknown resume without replay, standalone child
resume refusal, abrupt parent death, real child-shell cancellation, timeout,
recursion rejection, two-child budgets, and oversized results. Human approval
waiting pauses the active child budget. Completed child closure records no
spurious cancellation. The real shell fixture stopped the child session before
parent cancellation returned, and its delayed file effect did not occur.

### Source and bundled checks

On Serenity's Arch toolchain recorded above, source build, both Elixir 1.20/1.18
formatters, warnings-as-errors compilation, and the original credential-free
demo passed. Ordinary suite: **197 passed, 17 enforcement checks excluded**.
With actual Linux enforcement included: **205 passed, 9 Mac checks excluded**.
`mix run scripts/demo-subagents.exs` passed two exact scripted approvals and
verified the file and both journals, without contacting a model service.

The extracted Arch package also passed the bundled delegation demo under a
utility-only PATH without a development toolchain, alongside its original
help/demo/workspace/helper/lock and MCP round-trip checks. The final runtime
notice-complete rebuild and fresh-package verification passed. Hosted Linux/macOS
[CI passed Linux x86_64 and macOS 14 arm64](https://github.com/lexlapax/ipse/actions/runs/38795554992), including source,
bundled MCP/delegation checks, and actual Mac native enforcement. Local Arch
checks alone do not establish Mac behavior.

### Live subscription check

A separate interactive source CLI check explicitly selected
`chatgpt/gpt-6.1-sol`, `--subagents`, `--sandbox native`, and `--max-steps 4`,
with a fresh scratch workspace and separate journals. Reviewed and approved one
exact delegation task. The child then requested two distinct parent approvals:
write `hello.exs` with `IO.puts("LIVE_CHILD_OK")` plus one newline, then run
`elixir --erl '+S 2:2' hello.exs` with a ten-second timeout. Approved each exact
proposal through the parent UI.

Verified exact file bytes, one approved parent delegation intent, two approved
child effects, and the child journal's native shell result: exit 0 and
`LIVE_CHILD_OK`. The parent consumed the bounded child result and completed its
stream with `DELEGATION_OK`. Idle CLI resume restored the saved delegation flag
and native policy without explicit flags. Parent/child journal event counts and
file modification/change timestamps remained unchanged; no child or effect was
replayed. No API provider, billing fallback, account-permission change, or
independent refresh/logout test was involved. Private transcripts are not committed.

Live evidence covers one successful child path on Arch. Cancellation, owner
death, denial, timeout, and unknown recovery remain fixture evidence. Parallel,
recursive, cross-provider/model, remote, and child-MCP execution remain outside
P6. Documentation was reconciled with the implementation and actual results.

## P7 expanded local MCP, 2026-10-15

Implemented exact configured resource URIs and prompt names through the existing
SDK, host approval, descriptor binding, intent journal, and unknown-outcome
boundary. Discovery fetches metadata only. Resource text and prompt messages
remain bounded untrusted tool data, with no automatic prompt execution or linked
resource loading. Added optional per-server native enforcement, independently
of the shell setting. Reused existing packages; no new runtime dependency.
See the [developer contract](mcp.md) and [operator guide](../operator/mcp.md).

### Fixtures and source baseline

Focused fixtures cover resource-only/prompt-only capability negotiation, no
automatic content fetch, exact approval targets/arguments, headless denial,
durable provenance, descriptor drift, duplicate/missing metadata, malformed
prompt arguments, cursor/page ceilings, URI mismatch, binary/embedded content,
oversized results, and unknown recovery without replay. Generic protocol errors
after dispatch now stop as unknown, since an effect may have happened before
the server reported an RPC failure. Valid ordinary tool error results remain
reported errors. Schema fixtures cover the exact built-in Draft 2020-12 marker,
narrow nullable pairs, bounded inert defaults, and continued rejection of
references/combinators/remote loaders. Config fixtures cover default fingerprint
compatibility and rejection of selected secrets in public fields across every
configured server. Child environments remain server-specific; known private
values are checked/redacted across the host catalog, arguments, identity, and
retained text.

Arch source build, both Elixir 1.20/1.18 formatters, warnings-as-errors compilation,
and the original credential-free demo passed. Ordinary suite: **222 passed,
26 enforcement checks excluded**. Actual Linux enforcement included: **235 passed,
13 Mac checks excluded**. Native stdio fixtures prove workspace writes, denied
outside/symlink/network access and process-group escape, child-only loader
environment with a positive control, setup cancellation, owner death, and
confirmed ordinary-descendant cleanup. Hosted macOS CI also passed the four new
stdio enforcement cases: direct args/environment with outside-file denial,
loader injection with a positive control, setup cancellation, and owner death
with ordinary-descendant cleanup.

`mix run scripts/demo-mcp.exs` passed three exact approved SDK-to-SDK calls:
scratch write, fixed resource read, and prompt retrieval. This uses a scripted
model and contacts no model service. The notice-complete Arch archive and final
fresh-extraction verifier passed, including bundled tool/resource/prompt calls,
delegation, fresh-home workspace behavior, and helper/lock checks with a utility-only
PATH. [Supported-host CI passed Linux x86_64 and macOS 14 arm64](https://github.com/lexlapax/ipse/actions/runs/38799753085),
including source, native Mac enforcement, bundled tool/resource/prompt and
delegation round trips, and the independent Mac sandbox probe.

The [first P7 CI run](https://github.com/lexlapax/ipse/actions/runs/38798892424)
passed Linux source/package checks and the Mac ordinary suite. The Mac enforcement
step passed the new native cases but failed its repeated ordinary initial-server-
exit cleanup fixture: stdout was retained, yet the helper's final `X` record was
missing. Its log did not reveal which fixed error frame was sent. Added twenty
bounded real cleanup iterations with exact status/frame diagnostics and explicit
error-frame rejection, preserving the cleanup and completion requirements. All
twenty iterations passed locally on Linux. The replacement CI passed both Mac
invocations of this stricter fixture (forty helper runs), alongside all other
checks. The original missing completion record was not reproduced and its cause
remained unknown at P7 closure; no runtime policy was relaxed or root-cause fix
claimed. The later [local load investigation](#macos-stdio-cleanup-load-2026-10-15)
reproduced the symptom with a decoded drain error. The original CI log still
does not establish whether it failed through that same path.

### Pinned independent interoperability

The separately reviewed MIT `rust-mcp-filesystem` 0.2.0 at
[commit df98dc38](https://github.com/13thx-mcp/filesystem/tree/df98dc38c969c92f25c778d37691e7a3f1914367)
uses rmcp 3.4.0. Its locked dependencies were downloaded, then built offline
inside the Linux native sandbox under the developer's explicit approval.
An initial SDK-only diagnostic exposed the canonical `$schema` marker and
negotiated revision 2025-11-25. Nesting Ipse's process-group supervisor inside
an outer sandbox failed by design; the group-escape denial was retained.

The full Ipse adapter subsequently passed with the client outside and only the
server inside the native profile. The optional
`mix run scripts/verify-independent-mcp.exs /path/to/reviewed/filesystem-server`
copied the reviewed executable into a fresh scratch workspace, discovered three
allowlisted tools, approved exact read/list/write calls separately, verified
synthetic file/result bytes and journal intents, and resumed idle without journal
changes. The actual generated schemas exercised the canonical dialect, nullable
`Option<String>` path and inert false overwrite default. This is real independent
protocol interoperability with a scripted model, not live model evidence. The
server is not installed, bundled, added to default tests, or required by CI.

### Live ChatGPT subscription check

A separate interactive source session explicitly selected
`chatgpt/gpt-6.1-sol` and two configured servers. The independent Rust server
ran read-only inside its per-server native profile; the bundled SDK catalog
example ran in the explicitly displayed trusted mode. Individually approved
`read_text_file` with `path: fixture.txt`, the fixed `notes://guide` resource,
and `summarize` with `topic: scratch verification`. Verified the exact synthetic
independent marker `LIVE_INDEPENDENT_MCP_OK`, guide text, role-delimited prompt
text, three approved durable intents/results, and streamed `LIVE_MCP_P7_OK`.
No retrieved prompt was executed. Idle CLI resume followed by EOF preserved
journal event count and fixture timestamps; no model request or MCP call replayed.
Explicit `/exit` records cancellation separately; it is not a replay event.

This live check used the existing Ipse subscription sign-in, with no API billing,
provider fallback, permission change, or new refresh/logout check. Private
transcripts and credentials are not committed. The final approval target-display
addition was verified by fixtures; the live run used the preceding display.
At P7 closure, other independent servers, live providers, Mac independent/live MCP,
network transports, templates/subscriptions, and persistent connections remained unverified
or unimplemented. The existing macOS detached-descendant limitation remains.
Subsequent independent memory-server evidence is recorded
[below](#second-independent-local-mcp-server-2026-10-15).

## macOS stdio cleanup load, 2026-10-15

Local host: macOS 26.7.2 arm64, Elixir 1.20.3, OTP 29 / ERTS 17.0.5,
Rust 1.97.1. The checkout started clean at `8a97b3a`; origin fetch succeeded
after an initial connection timeout and confirmed it was current.

The original helper passed 300 synthetic trials at concurrency eight. At
concurrency sixteen, one of 1,000 trials returned stdout `done`, helper status
zero, and `E: stdio output did not drain`, without `X`, after 519 ms. No delayed
write occurred. A second 1,000-trial run with temporary process-group tracing
reproduced this once. At the deadline, `/bin/ps` showed a live `sleep` in the
original group, reparented to PID 1, after the first group-wide SIGKILL.
Tracing inspected only that fixture group and was removed from the helper.

This supports a fork during group-signal delivery as the cause of the local
reproduction. Apple's published [group iteration](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_proc.c)
collects member PIDs before signaling them through the
[group-kill callback](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sig.c).
That source review is supporting evidence, not a trace of the host kernel's
exact fork timing. The earlier CI failure's error frame remains unavailable;
its cause is still unconfirmed.

The stdio supervisor now repeats group SIGKILL on idle five-millisecond drain
polls, stopping after a failed signal or pipe EOF. The original 500 ms drain
deadline, output/error frames, watchdog, and sandbox policy remain in force.
An ordinary descendant left by the first signal can therefore release its pipe
before the drain expires. This is best-effort group cleanup, not a new process
containment boundary.

The diagnostic passed two 1,000-trial trusted-mode runs at concurrency sixteen
and 100 actual native trials at concurrency four after this change. Each required
exact output, one successful completion, no error frame, and no delayed write.
A new 200-run concurrent regression preserves those strict completion checks.
A separate native test deliberately detaches a pipe holder: it must still emit
the drain error without completion within two seconds. After release, the
surviving child proves outside-file denial, preserving the documented lifetime
limitation.

Initial macOS stdio enforcement failed before launch because fixtures used the
host's `0755` state home. The suite now uses isolated `0700` homes without
changing host permissions or weakening cache checks. All eighteen focused
stdio tests then passed with five Linux tests excluded. An initial concurrent
native diagnostic also exposed expected cache-lock contention; the diagnostic
serializes preparation rather than changing runtime locking or retry policy.

Final source build, formatting, warnings-as-errors compilation, and isolated
credential-free demo passed. Ordinary tests: **223 passed, 27 excluded**.
The full suite with actual macOS enforcement included: **237 passed,
13 Linux enforcement tests excluded**. The focused stdio suite above includes
the new concurrent regression and detached-pipe negative control.

Built `dist/ipse-0.1.0-darwin-arm64.tar.gz` and verified that exact archive with
`elixir scripts/verify-package.exs dist/ipse-0.1.0-darwin-arm64.tar.gz`.
Fresh isolated HOME/IPSE_HOME and a utility-only PATH passed help, demo,
default and explicit workspaces with spaces, bundled MCP tool/resource/prompt
and delegation checks, and OTP/helper lifecycle and lock checks. Bundled Mac
native file denials and ordinary-child timeout cleanup passed. No archive was
published. The documentation check passed all 295 local links and heading
anchors across 36 tracked Markdown files.

Hosted [Checks run 38822941399](https://github.com/lexlapax/ipse/actions/runs/38822941399)
subsequently passed for fix commit `b3db345` on Ubuntu and macOS 14. Both jobs
passed source build, formatting, warnings-as-errors compilation, ordinary tests,
demo, packaging, and fresh-package verification. The Mac job also passed native
enforcement and the experimental App Sandbox probe.

These are synthetic lifecycle and actual Mac file-enforcement checks. No live
provider, independent MCP server, or Linux enforcement rerun is implied.
Detached descendants can still survive with workspace access, and OS-managed
sandbox containers persist. The original CI failure's cause remains unconfirmed.

## Linux return after macOS cleanup, 2026-10-15

Serenity returned with a clean `main` fast-forwarded to `39bdc8e`, including the
cleanup fix `b3db345`. Fetch confirmed no further origin changes. Host: Arch
Linux x86_64, kernel `7.2.9-arch1-1`, glibc 2.44, Elixir 1.20.4,
OTP 29 / ERTS 17.0.6, Rust 1.99.0.

The source build, formatter check, warnings-as-errors compilation, and
`mix test --include native_sandbox` passed: **236 passed, 14 macOS tests
excluded**. This includes actual Linux native enforcement and the new 200-run
concurrent stdio cleanup regression with exact output/completion, no error
frames, and no delayed child writes. The credential-free source demo passed
under a fresh temporary `IPSE_HOME`. Initial sandboxed Mix invocations could
not acquire their loopback TCP lock (`:eperm`); checks passed through the tool's
permission flow without changing tests, TLS, or sandbox policy.

Built `dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` with
`IPSE_NOTICES_DIR=/tmp/ipse-toolchain-notices`, reusing the version-matched
Elixir 1.20.4 and OTP 29.0.6 upstream notice collection recorded above. Checked
the archive for those notices, provenance/header inventory, Telemetry's NOTICE,
and NimblePool's README notice. Ran:

```sh
elixir scripts/verify-package.exs dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz
```

Fresh isolated HOME/IPSE_HOME and utility-only PATH passed help, demo, default
and explicit workspaces with spaces, bundled MCP tool/resource/prompt and
delegation checks, and OTP/helper timeout, owner-death, and lock checks.
No archive was published. Developer/operator guidance and source CLI help were
reviewed; all 298 local file links and heading anchors across 36 tracked
Markdown documents passed validation, as did `git diff --check`.

No regression required a runtime fix. No live provider, fresh authentication,
independent server, macOS enforcement, or extra stdio load diagnostic was run
in this return check. Earlier Mac evidence remains separate; the original CI
failure's cause is still unconfirmed, and detached-descendant cleanup remains
best effort. P0–P7 remain complete within their documented scope; broader
independent local-server interoperability was proposed next. The following
section records the subsequent second-server check.

## Second independent local MCP server, 2026-10-15

Started from clean `main` at `f44bc8d` on the Serenity Arch x86_64 host recorded
above. Selected the separately implemented Apache-2.0 `mcp-memory` 2.0.0
published crate, pinned by its verified registry SHA-256 and included Cargo.lock;
see [source, dependencies, and exact patch](dependencies.md#second-independent-mcp-investigation-memory).
This version implements MCP itself rather than using the first server's rmcp
SDK. An earlier SQLite candidate was rejected during source review because it
hard-codes protocol revision 2024-11-05; Ipse's pinned revision was retained.

The unmodified memory crate failed to build on Rust 1.99/x86_64 at an incorrectly
typed prefetch pointer. Applied only the documented pointer cast in temporary
upstream source, then built successfully offline inside the Linux native
sandbox. No protocol source or Ipse runtime policy changed. This evidence covers
that patched 2.0.0 build, not an unmodified or current upstream release.

The optional verifier passed:

```sh
mix run scripts/verify-independent-memory-mcp.exs /path/to/reviewed/mcp-memory
```

It copied the reviewed executable into a fresh workspace, used an isolated
owner-only `IPSE_HOME`, selected per-server native enforcement and stdio, and
allowlisted only `create_entities`, `get_entity`, and `search_nodes`. It set the
server's existing synchronous durability option. Startup/discovery creates an
empty scratch binary log; it does not create the synthetic entity.

The first proposed write was explicitly denied: the log bytes remained identical
and the journal contained no dispatch intent. Four subsequent calls received
separate approvals with exact nested arguments: create one synthetic entity,
retrieve it, search for it with a one-result limit, and retrieve a deliberately
missing name. Exact create/get/search content passed across fresh server
processes. The last call returned a valid `isError` tool result, journaled as
`error`, rather than an unknown transport outcome. The verifier checks approved
intent arguments, server fingerprint, requested native policy, all five outcome
records including denial, and unchanged journal events/log bytes on idle resume.
Its initial search assertion expected a graph object; inspection confirmed the
upstream array format and the checker was corrected to require the exact entity
array. No runtime compatibility fix was needed.

Source build, formatting, warnings-as-errors compilation, and the isolated
credential-free demo passed. `mix test --include native_sandbox` passed
**236 tests, with 14 macOS tests excluded**. All 304 local links and heading
anchors across 36 tracked Markdown documents passed; `git diff --check` passed.
Reviewed operator/developer guidance and kept the optional check separate from
normal server configuration and the bundled SDK demo. No packaging or runtime
code changed, so packaging was not rerun; the preceding Linux return record
retains the separate fresh-package evidence.

No live model/provider, authentication, Mac independent-server run, resources,
prompts, network transport, concurrent memory writers, cancellation, interrupted
write recovery, or power-loss durability was exercised here. The script removes
its scratch state and restores the previous `IPSE_HOME`; the reviewed source,
Cargo cache, and executable remain in `/tmp` only. No server was installed,
bundled, enabled in normal sessions, or added as a default/CI dependency.

## P8 skill resources, 2026-10-15

Added explicit skill-relative text reads through the existing bounded source
reader, without a new dependency. The bundled review skill/checklist and source
demo exercise the feature. Focused fixtures passed precedence, inert script/link
content, path/symlink/credential rejection, invalid UTF-8 and size/depth bounds,
current-byte hashes, outside-workspace user skill resources, and saved-content
resume after a file change. No automatic reload or effect replay occurred.

Arch source build, formatting, warnings-as-errors compilation, and the isolated
resource-enabled demo passed. Full Linux enforcement suite: **239 passed,
14 macOS tests excluded**. Hosted
[Linux/macOS source/package CI passed](https://github.com/lexlapax/ipse/actions/runs/38844821382)
at `4a19bb3`, including Mac native enforcement and resource-enabled bundled demo.
See [skill contract](architecture.md#skill-resources) and
[operator usage](../operator/usage.md#skills). Provider validation is recorded
separately; these fixtures/demo require no service or credentials.

## Live provider acceptance follow-up, 2026-10-15

On the recorded Serenity Arch host, the developer explicitly authorized reading
provider keys privately from the Git-ignored repository `.env` and paid API
validation. Ollama 0.40.1 used the installed `qwen3.5:9b`; Anthropic used
`claude-haiku-4-5`; OpenAI API used `gpt-4.1-mini`. All three passed streamed
visible output, one exact individually approved synthetic write, native
continuation, idle resume with unchanged journal events, a further model turn
without tool replay, and a surfaced unavailable-model error. No provider/billing
fallback or model download was used. Scratch transcripts were removed afterward.

Each provider separately passed a live summary/checkpoint request over seeded
synthetic history, subsequent inference retaining its marker/license, and idle
resume without recompression or tools. Anthropic initially returned exactly one
JSON Markdown fence; Ollama initially returned empty visible content. Both failed
closed and retained history. The repair accepts one exact JSON fence while
retaining the strict schema/tool/byte checks, and supplies Ollama's documented
structured-output schema, disabled thinking, zero temperature, and a 4096-token
summary cap only for compaction. Ordinary turn requests are unchanged. Focused
fixtures verify both repairs and continued rejection of prose, multiple JSON
documents, invalid keys, and tool calls. No hidden reasoning was displayed.

All three also passed two separately approved native MCP calls against the
previously reviewed independent Rust filesystem executable: exact synthetic
write and read, followed by idle resume without replay. A safe explicit
`overwrite: false`/`expected_revision: null` proposal from OpenAI was initially
denied by the harness's omitted-argument expectation; the next request used that
exact fully specified proposal and passed. Serial delegation passed with one
exact approved task/context, a real same-provider child reply, parent completion,
and idle resume without starting another child. Initial natural-language task
wording varied the proposed arguments; explicit JSON proposals resolved this
without broad approval or changed host policy.

These are actual provider requests with synthetic data, distinct from fixture
tests and the original ChatGPT subscription evidence. Compaction history was
seeded, not a claim about an extended natural conversation. No live allowance
exhaustion, paid-account eligibility, token revocation, concurrent external
writers, or Mac provider check was performed. Provider keys and private
configuration remain outside Git; only sanitized outcomes are recorded here.

## P9 parallel local delegation, 2026-10-15

Added explicitly enabled two-child groups with serial defaults, exact group/child
approvals, separate journals, and the same provider/model. Nine focused fixtures
pass overlapping tasks, deterministic result order, recursion/MCP exclusion,
mutation serialization, exact approval routing, file and shell wildcard conflicts,
hardlink rejection, complete parent death/cancellation cleanup, sibling shutdown
after failure, headless/default denial, budgets, and concurrency-bound idle resume.
Owner-death checks wait for the coordinator, child sessions, and provider tasks
to stop; readiness is emitted only once per child in the test provider.

Live checks passed on installed Ollama `qwen3.5:9b`, Anthropic `claude-haiku-4-5`,
and OpenAI API `gpt-4.1-mini`: one exact approved group, two real child responses,
parent completion, separate child relationships, and idle resume without starting
children again. OpenAI initially proposed serial calls; those were denied with
no child start. A clearer exact parallel-tool request passed on the same model
without changing approval policy or billing. These are synthetic-data checks,
not arbitrary shared-workspace stress coverage.

Credential-free source and bundled parallel demos verify the approved group,
two child relationships, and idle resume. Source build, formatting,
warnings-as-errors compilation, isolated demo, and **249 tests with Linux native
enforcement included (14 Mac tests excluded)** passed. The exact rebuilt
`dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`, with version-matched runtime
notices, passed fresh-home/utility-only-PATH verification including bundled
serial and parallel delegation. Hosted [Linux/macOS source/package CI passed](https://github.com/lexlapax/ipse/actions/runs/38846368587)
at `4e5f922`. No dependency was added. Reads are not isolated from
writes; unrelated processes and detached descendants retain the documented
limits. Remote/recursive agents and child MCP remain unavailable.

## P10 Streamable HTTP MCP, 2026-10-15

Implemented explicit MCP 2025-11-25 Streamable HTTP POST with JSON/finite SSE
responses, verified HTTPS, optional server-specific static bearer authentication,
and session headers/best-effort DELETE. Reuses the existing SDK, SSE parser,
strict admission/catalog/schema checks, approvals, and synced intent journal.
Existing Req/Finch/Mint provide streaming HTTP/1 with private guarded pools;
no dependency or external runtime was added. See the
[transport contract](mcp.md#streamable-http-boundary) and
[operator setup](../operator/mcp.md#configure-a-network-endpoint).

Twelve network fixtures plus five HTTP profile tests passed: explicit endpoint
and token identity/rotation, JSON/SSE handshake and private session lifecycle,
exact resources/prompts, full approvals/headless denial, authentication errors,
redirect rejection without another request, body/header bounds, incomplete or
mixed malformed streams, wrong IDs, unmatched ping, changed sessions, descriptor
drift, post-dispatch disconnect with unknown/not-started outcomes, idle resume
without replay, cancellation, and owner death closing the client socket. Private
Finch root/children/guardian exit is separately confirmed on borrower death and
normal return. Final review found abrupt request-worker death discarded the
worker identity before waiting for the pool guardian. The regression holds that
guardian open: the old path incorrectly confirms cleanup and fails the assertion;
the repair retains the identity until confirmed shutdown and passes. HTTPS fixtures passed trusted matching-host discovery/tool calls,
untrusted-CA rejection, and trusted-certificate hostname mismatch without HTTP
dispatch. Trust was changed/restored only inside the isolated test VM. An initial
fixture asserted the wrong TLS alert name; the actual hostname rejection was
retained and the fixture now accepts the supported OTP alert names. A later
redirect fixture used the wrong OTP socket-info module; correcting that fixture
restored the full focused pass without changing production policy.

The optional independent verifier passed against the previously reviewed,
checksum-pinned and explicitly patched Apache-2.0 `mcp-memory` 2.0.0 executable.
Its authenticated literal-loopback HTTP endpoint returned finite SSE responses.
A disposable graph check denied one create without dispatch/intent, approved
exact synthetic create/get/search/missing-record calls, checked persisted bytes
and ordinary tool errors, and resumed idle with unchanged events and no replay.
The daemon received only a synthetic server token and selected durability flag,
then its ordinary process group was closed. This was not an arbitrary public
HTTPS service, OAuth server, current upstream release, or remote-isolation test.
See [the exact upstream source/build record](dependencies.md#second-independent-mcp-investigation-memory).

Actual live Ollama `qwen3.5:9b`, Anthropic `claude-haiku-4-5`, and OpenAI API
`gpt-4.1-mini` each passed two exact individually approved create/get calls through
that authenticated HTTP server, parent completion with the synthetic marker,
network-origin intent records, and idle resume without replay. Provider keys
were loaded privately from the ignored `.env` and were never supplied to the
server. These are synthetic-data checks on Arch, separate from fixture and
original ChatGPT subscription evidence. No ChatGPT HTTP MCP check, live remote
cancellation guarantee, OAuth flow, long-lived GET stream, reconnection/event
resumption, other model/host acceptance, or general server compatibility is claimed.

Source build, formatting, warnings-as-errors compilation, isolated demo, and
**262 tests with Linux native enforcement included (14 Mac tests excluded)**
passed. Rebuilt the exact `dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` with
version-matched runtime notices and passed fresh-home/utility-only-PATH verification,
including the new bundled HTTP MCP round trip and serial/parallel delegation.
The HTTP demo uses only OTP sockets and the extracted runtime. Hosted Linux/macOS
source/package checks [passed at c404da5](https://github.com/lexlapax/ipse/actions/runs/38849383383);
verification of the final worker-death ownership repair is pending.
