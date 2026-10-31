# Owned managed inference send and publication

Recorded 2026-10-28. Historical integration evidence for the P30/P31 worktree;
this is not production, installed-release, live-account or whole-milestone
acceptance. Current instructions belong to the [developer manual](../../developer/index.md)
and current scope to the [plan](../../plan.md). This record replaces the earlier
unwired transport experiments only for the integration and controls listed here.

Managed inference now uses the existing native provider adapters, authentication,
body encoders and parsers through a controlled Mint transport. Connection and TLS
setup finish before the exact-owner, one-use request continuation. Current source,
identity, Consent, root and expiry checks surround that continuation; locks are
released while awaiting generation. The owner independently reconstructs the exact
selected target and serialized body, including output caps narrowed by the existing
shared budget. The original inference task explicitly registers its actual native
transport peer in its own resource scope before any inference send.

Response text remains private until native parsing, socket closure and controlled
child cleanup are confirmed. Publication reacquires current authority and admits
one exact result digest in the Session owner. Normal Task/helper completion consumes
that request/phase/result seal once. Later reuse retains the producer dependency
union and passes through the separate preflight again. A preflight verdict or
completed HTTP response alone does not authorize publication.

TLS uses Mint's public connection/send/close APIs and public `ssl` information
queries on the opaque socket. It does not inspect or modify SSL socket internals.
The local tests install a generated CA temporarily and verify TLS normally. The
actual ChatGPT subscription adapter reads isolated synthetic credentials through
the normal Auth path; no live sign-in or model account was used. Production fixed
endpoint and billing policy are unchanged; only the existing Mix-test-only loopback
allowance additionally accepts HTTPS.

The implementation follows the public contracts for
[Mint request and socket information](https://mint.hexdocs.pm/Mint.HTTP.html)
and [OTP TLS close and information APIs](https://www.erlang.org/doc/apps/ssl/ssl.html).

## Executed controls

| Receipt | Selection | Result | SHA-256 |
| --- | --- | --- | --- |
| [46766](owned-send-integration/sol-owned-wire-controls-46766.log) | Exact one-use send/body/deadline, exact one-use owner result seal, verified TLS closure | 3 passed; 25 excluded; 0.7 s | `dc26defa964961a29bdf067e900f2e5648e1d121568b1ac227f1d80e875072a0` |
| [46767](owned-send-integration/sol-owned-send-section-46767.log) | Registered HTTP/TLS Session boundary controls | 13 passed; 28 excluded; 21.0 s | `4ab95f158154f015ffe25ed8a7e87f6893026f8f35a466245d9e912dde512701` |
| [46765](owned-send-integration/sol-owned-send-tls-46765.log) | First integrated actual ChatGPT TLS controls | 4 passed; 35 excluded; 6.3 s | `c912cf3214c20633ac267d2e2f820fa2e368f95f96bc6a47a60b9111ec420aef` |

The 13-case final selection covers current worker-to-assistant reuse, changed-root
withdrawal, opaque-history zero-send refusal, historical self-write facts, current
and stale helper inputs, HTTP/TLS invalidation during generation, current ChatGPT
TLS, revocation during TLS setup, Session owner loss, an actual saved-policy
deadline crossing while a native response is held, and shared-budget narrowing.
The generation controls successfully mutate the collection while the response is
held, then withhold all generated text. TLS owner loss observes connection EOF;
connection-time revocation observes no inference headers or body.

The final selections ran in `_build/operator-assertion-sol`, whose isolated native
diagnostic helper additionally admits the available host kernel. Its exact helper
SHA-256 is `86d6226c868b7095c6ba7460cc0b42832e98fb70feea0779fb3473ac7bb28a6a`.
Production native admission was not widened. A strict compile passed during
integration; the final selected run compiled the later budget-body binding change.
No aggregate suite or paid/live inference was run for this section.

## Retained evidence and limits

The [manifest](owned-send-integration/manifest.json) hashes the copied logs and a
post-run capture of the eight transport-owner source files. This is a scoped
source capture, not an immutable snapshot of the entire shared dirty worktree or
every dependency. The actual Session and verifier integration also relies on the
separately tested [preflight and expiry work](managed-use-preflight.md).

These controls prove local protocol and ownership behavior, not semantic model
quality or hosted account compatibility. The transport deadline control crosses
the real saved policy deadline; a short literal-v4 record deadline during actual
transport has not been separately exercised. Cross-platform, installed packaging,
live provider/cache behavior, all adapter protocol combinations, full stale-source
withdrawal journeys and final milestone acceptance retain their own gates.

The completed publication gate above covers native inference text/results only.
Raw extension-worker results retain their full read/inherited unions and are
checked before later model/helper reuse, but direct extension-result delivery
does not yet acquire current source/expiry authority around its own release.
That separate P31C0 publication gate remains open; these receipts do not qualify it.
