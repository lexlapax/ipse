# Security context and reporting

Ipse is a local AI harness running with an operator's account. This document owns
the review threat model and finding criteria. It is context for reviewers, not
permission to execute code, access credentials, install tools or publish findings.
The [architecture](docs/developer/architecture.md) and linked contracts describe
implementation; the [review protocol](docs/developer/self-hosting-evaluation.md)
owns scan execution, triage and revision coverage. The
[verification record](docs/developer/testing.md#current-evidence-and-next-checks)
distinguishes tested behavior from open review gates.

## Reporting

Keep vulnerability details, exploit artifacts, credentials and private transcripts
out of public issues, pull requests and Git. Share a report with the project
operator through an agreed private channel. If no channel is established, ask the
maintainer how to send it privately without including the vulnerability details.
This policy does not establish a monitored security address or promise that
GitHub private vulnerability reporting is enabled.

Include the affected commit/release, host/toolchain, selected configuration,
attacker-controlled input, required permissions, reproduction with synthetic data,
expected versus observed behavior and impact. Identify any proposed repair and
test separately from the original observation. Do not send real keys or account
data to demonstrate a problem. Retain raw reports privately; publish only reviewed,
sanitized findings or fixes with the operator's authorization.

## Assets, inputs and authority

The primary assets are operator credentials and files; private conversation,
provider-native and tool data; approved effects; durable session/accounting state;
and ownership of active processes, connections and quotas. There is no default
public Ipse server or hostile multi-tenant execution boundary.

| Input or actor | Authority and review focus |
| --- | --- |
| Operator CLI and operator-owned configuration | Select providers, billing, endpoints, trust, private grants and session policy. Check that project or model input cannot impersonate this authority |
| Project/directory configuration, instructions and skills | Data or instructions under documented discovery/trust rules; loading does not install dependencies, execute scripts or grant effects. Inspect scope, precedence and resume identity |
| Model output, fetched sources and MCP responses | Untrusted content, including tool arguments and apparent instructions. They cannot grant approval, widen roots/private views or silently change execution/billing |
| Imported extension artifacts | Import is inert and hashes are not authenticity. Execution requires separate operator trust/selection and runtime/capability validation; reviewed worker code then runs with user permissions, outside the shell sandbox |
| Provider/auth/MCP network peers | Operate only through the explicitly selected interface and credentials. Validate TLS/hostname/redirect policy, malformed/oversized responses, continuation handling and owned cancellation |
| Saved journals, state, artifacts and budget files | Operator-controlled storage with protected/cooperative locking, not a hostile same-user isolation mechanism. Nonetheless, saved records must satisfy documented source, identity, approval and recovery checks before use |

Treat prompt injection as an attack input, not proof of an exploit by itself.
Identify the concrete authority or confidentiality boundary crossed. Trusted code
can still return malformed data or fail; host admission, receipts and ownership
must retain their promised behavior under those failures.

## Invariants to challenge

- **Effects and authority:** validate exact arguments, schema, scope, selected
  identity and current lease before execution. Interactive mutations and model
  egress need their documented approval; headless mutations require explicit
  `--yes`. Approval of an enclosing tool, a skill load, an event notification or
  an operator's clarification answer cannot approve a different action.
- **Durability and recovery:** journal intent before an effect. Interrupted work
  may have happened; unknown outcomes retain uncertainty and are never replayed
  automatically. Validate saved source/approval/result bindings and policy identity
  before repair, continuation or accounting reads. Idle resume performs no model
  inference or effect replay.
- **Privacy and routing:** private prompt/answer/tool/history/text views require
  separate scoped grants. SDK payloads and optional diagnostics must not receive
  host authentication credentials, arbitrary host state or hidden reasoning.
  Granted conversation/tool views can contain secrets supplied by the operator
  or returned from the selected workspace; a grant is not automatic redaction.
  Helper and mixed-provider
  child calls use the selected profile's credential reference, without inheriting
  the main conversation or silently falling back to another provider/billing mode.
- **Ownership:** session, task, worker and HTTP lifetimes must preserve their
  documented cancellation and cleanup contracts. Test owner/worker loss during
  approval, dispatch, streaming, lock acquisition and shutdown. PID death alone
  cannot manufacture acknowledged cleanup or a known remote outcome.
- **Policy composition:** distinguish native shell/server confinement from
  host-side file-tool checks. Review check/use races, shared scratch grants and
  transient credential staging across concurrent commands and server launches;
  owner-only modes are not isolation between processes with the same UID.
- **Concurrency and accounting:** preserve cross-process locks and lock inode
  identity, atomic publication, registered child origin and shared tree admission.
  Main, summary, child and accounted helper calls cannot evade configured quota,
  settle twice, reset usage on resume or turn unknown liability into zero.
- **Bounds and compatibility:** refuse malformed/unsupported protocols and
  capabilities, changed artifact/runtime/configuration identity and unsupported
  resume changes. Bound data, queues, request/action chains and accepted results;
  overload or incomplete delivery must remain visible. Disabled optional features
  must not initialize workers, stores, connections or model calls.

Contracts for [configuration](docs/developer/configuration.md),
[artifacts/workers](docs/developer/extension-artifacts.md),
[host calls](docs/developer/extension-host-calls.md),
[model calls](docs/developer/extension-model-calls.md),
[lifecycle coverage](docs/developer/lifecycle-events.md#supported-lifecycle-coverage),
[accounting](docs/developer/usage-accounting.md) and
[budgets](docs/developer/budgets.md) define the exact supported boundaries.

## Boundaries and accepted limitations

Approval, process supervision and OS confinement are separate. Default shell
execution uses the user's permissions. Workspace file-tool checks reject escaping
paths and symlinks but are not race-proof against a hostile same-user filesystem
writer. The concurrent writer may itself be another sandboxed command with workspace
write access; native process confinement does not make host path checks atomic.
An already-authorized arbitrary shell command or trusted BEAM artifact
reading user-accessible files is not by itself a privilege escalation.
That assumption must not excuse a bypass of an explicit host/API/native policy.

Explicit native shell and per-server MCP sandbox selections fail closed when
their backend is unavailable. The shell flag does not sandbox provider inference,
extensions or every MCP server. Linux's selected namespace/Landlock/seccomp
profile and macOS's signed App Sandbox profile have different capabilities;
see the [native contract](docs/developer/sandbox.md). macOS detached descendants
can survive timeout/cancellation with workspace access under the accepted
best-effort cleanup boundary. Neither workers nor native per-process limits are
an aggregate process/heap/disk quota or protection against a hostile administrator
or kernel compromise.

Artifact digests and protected file modes do not defend against every malicious
same-user writer or establish code authenticity. Private journals intentionally
retain original messages, native responses and effect evidence; they are not a
sanitized diagnostic export. Secrets inside an explicitly accessible workspace
remain accessible. Unknown usage and interrupted inference may carry liability;
configured estimates/reservations do not promise an invoice ceiling.

These limitations are inputs to impact assessment, not blanket exclusions.
Report misleading claims, a reproducible breach of the stated boundary, or a
stronger reachable impact separately from a restatement of an accepted limit.
Unsupported embeddings/audio, future package distribution and production knowledge
engines are not implemented attack surfaces unless reachable current code supplies
the claimed path. Architectural gaps can still be recorded for planned capabilities.

## Safe review and evidence

Use an exact committed snapshot and disposable least-credential homes/workspaces.
Exclude ignored `.env`, auth stores, private journals and unrelated projects from
review uploads. Use synthetic keys, loopback servers and bounded scratch files;
keep TLS verification and assertions intact. Follow the existing
[build/test instructions](AGENTS.md#commands); do not weaken tests, execute unknown
artifact code or add a scan dependency to obtain a result. A review instruction
is not approval to contact real services, change billing or publish a report.

For each finding record reachability, attacker prerequisites, affected invariant,
severity/impact, exact revision and inspected sources. Distinguish source-based
reasoning from a successful runtime reproduction; record unavailable platforms and
coverage limits. Test a proposed repair against the original failure. Disposition
findings with evidence, retain residual risks and refresh affected review coverage
after changes. A completed scan, a green test suite or no findings alone does not
establish security. P24/P25 acceptance remains with the review protocol and plan.
