# Grok API and subscription OAuth research and verification

Research and implementation brief requested 2026-10-24 against `5bb5761`.
The developer selected implementation before the P28/P29 external audit, then
confirmed that Ipse has no xAI OAuth registration yet. The primary findings below
record the design basis; later sections retain implementation and verification
evidence separately from live-account eligibility. Current status
belongs to the [plan](../../plan.md#p29-follow-up-grok-api-and-subscription-oauth);
current procedures belong to [configuration](../../operator/configuration.md).
No account was signed in, credential inspected, paid inference requested, or
third-party software installed during the initial research. The later authorized
API attempt and its refusal are recorded below.

## Findings from primary sources

**Third-party subscription OAuth exists.** xAI's May 15 announcement explicitly
supports using a Grok subscription inside Hermes Agent and links its setup guide.
This establishes an authorized third-party integration, rather than merely
observing a first-party CLI. It does not publish a general application-registration
procedure or authorize Ipse to use Hermes's client identity.
[Official announcement](https://x.ai/news/grok-hermes).

**Ipse registration is an unresolved prerequisite.** The public API documentation,
Grok Build authentication guide, and discovery metadata reviewed here do not
provide a self-service client-registration endpoint or instructions for registering
Ipse. This is a bounded research finding, not proof that no partner process exists.
Obtain an Ipse client ID and its approved grants/scopes from xAI. Do not copy a
Grok Build/Hermes client ID, read another application's token store, or represent
an example client as an Ipse registration.
[Official Build authentication guide](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md).

**Device authorization is advertised by the issuer.** The read-only
[OIDC discovery document](https://auth.x.ai/.well-known/openid-configuration)
advertises issuer `https://auth.x.ai`, authorization, device-code, token, revocation
and userinfo endpoints beneath that origin. Its grants include authorization
code, refresh token and RFC 8628 device code; PKCE uses S256 and public-client token
authentication `none` is supported. Scopes include `api:access` and
`offline_access`. Discovery advertises server capabilities, not which ones xAI
has granted to an individual client. No `registration_endpoint` is advertised.
The future client must request only its approved scopes, rather than all advertised
account, billing or workspace permissions.

**There is a documented remote-login precedent.** Hermes's own guide describes
device authorization, browser approval, saved refreshable credentials, a distinct
`xai-oauth` route, and the Responses endpoint. It also records successful browser
login followed by inference 403 for some subscription entitlements. This conflicts
with reading the older announcement's “every tier” as a current guarantee. Treat
the guide as evidence of Hermes's behavior and observed limits; Ipse eligibility
requires its own authorized client and account check.
[Maintainer guide linked by xAI](https://hermes-agent.nousresearch.com/docs/guides/xai-grok-oauth).

**API keys are a separate billing route.** The public API uses
`https://api.x.ai/v1` and bearer authentication with `XAI_API_KEY`. Keys belong to
teams and their creating user. Console API credits and subscription authority
must not be treated as interchangeable. Choosing API mode must never silently
consume a saved subscription token, or the reverse.
[API overview](https://x.ai/api),
[key ownership](https://docs.x.ai/developers/rest-api-reference/management/auth).

**Use Responses for a new adapter.** xAI recommends Responses and labels Chat
Completions deprecated. Responses supports typed outputs, native tool calls,
encrypted continuation and optional server-side conversation state. The documented
default is `store: true`, so Ipse should explicitly request `store: false`, retain
its own admitted history, and avoid depending on a remote response ID to resume.
That setting is not a claim of zero provider retention.
[Migration comparison](https://docs.x.ai/developers/model-capabilities/text/comparison).

**Preserve native continuation privately.** The reasoning guide says Grok 4.7
returns encrypted reasoning even without an explicit include and requires passing
those items back unchanged. Reasoning effort is model-specific: documented models
support low/medium/high, with xhigh on 4.6 and later; “none” is not a documented
way to disable their reasoning. Preserve opaque items without displaying thinking
or importing another provider's ciphertext. Treat dated model support as an
admission table that must be refreshed when new IDs are added.
[Reasoning contract](https://docs.x.ai/developers/model-capabilities/text/reasoning).

**Tool and stream compatibility needs fixtures.** Local function calling returns
`function_call` items and accepts matching `function_call_output` with `call_id`.
The guide describes whole function calls in one stream chunk. Handle that case
and fragmented HTTP/SSE boundaries without assuming a Chat Completions delta
shape. A model request never grants local execution permission.
[Function calling](https://docs.x.ai/developers/tools/function-calling),
[Responses reference](https://docs.x.ai/developers/rest-api-reference/inference/responses).
The generic streaming guide still contains Chat Completions examples, so use the
Responses contract rather than combining incompatible example envelopes.
[Streaming examples](https://docs.x.ai/developers/model-capabilities/text/streaming).

**Usage is more than a price table.** xAI documents `cost_in_usd_ticks` as a
per-request billed amount, at 10^10 ticks per USD, including discounts and hosted
tool charges. Repeated running totals must not be summed as independent requests.
Preserve provider-reported cost separately from Ipse's configured estimates; an
absent value remains unknown. The wire reference contains both current
input/output-style and older prompt/completion-style usage examples: select and
test an explicit normalization policy, including contradictory/missing counters.
[Cost tracking](https://docs.x.ai/developers/cost-tracking).

**Model and quota assumptions expire.** The current catalog advertises
`grok-4.7`; aliases can move, while dated IDs identify a fixed release. Require
an explicit model, record requested and reported identities, and do not promise
that an alias pins weights. API rate limits include per-model request/token caps
and return 429. A refusal must not trigger a different model, credential source
or provider.
[Models and aliases](https://docs.x.ai/developers/models),
[rate limits](https://docs.x.ai/developers/rate-limits).

**Retention and hosted tools need explicit limits.** The API security FAQ states
that API inputs/outputs are not used for training without permission, while the
default abuse-audit retention is 30 days. ZDR is a separate team setting. Do not
claim `store: false` changes that policy, or extend an API policy to subscription
traffic without confirming it. Initial integration covers local Ipse tools only;
xAI-hosted search, code execution, remote MCP, images, voice and multi-agent
features need separate effect/accounting contracts.
[API data policy](https://docs.x.ai/developers/faq/security).

## Selected implementation shape

The [public OpenAPI cap definition](output-cap.json) was checked during
implementation. `max_output_tokens` covers visible text only, excluding reasoning
and function calls. It cannot enforce Ipse's total-output reservation: both Grok
routes must refuse `reserve_output_tokens`, while request-count policies remain
available. The schema describes inclusive legacy totals, but its examples also
show completion excluding reasoning. The selected normalizer requires a reported
total that agrees with input+completion or input+completion+reasoning; otherwise
output remains partial or inconsistent data is invalid. It does not guess a
missing reasoning charge. The [OpenAPI source](https://docs.x.ai/openapi.json)
also specifies a trailing `[DONE]`; accept that only after a complete Responses
terminal event, never as a substitute for one.

These design decisions define the checks below; their dated implementation
results appear later in this record.

| Work package | Change | Required evidence |
| --- | --- | --- |
| X0: identity and eligibility | Separate `xai` API-key and `xai_oauth` subscription selections; explicit model and labels; approved Ipse client required for login | Closed registry/config schemas; unchanged older-provider goldens; useful missing-client refusal without network |
| X1: native Responses | Reuse suitable bounded transport/Responses machinery behind provider-specific ownership; distinct replay namespace, fixed OAuth destination, stateless native history | Shared conformance plus actual body/header/endpoint checks, opaque item round trip, complete/incomplete/failed streams, limits and cancellation |
| X2: protected device login | Issuer-bound device grant, finite polling/slow-down/expiry/cancel handling, private atomic storage and cross-process refresh lock; explicit local logout/revocation outcome | Local HTTP fixtures, no secret logging, rotated refresh concurrency/recovery, client binding and unsafe-file controls; no borrowed identity |
| X3: accounting and integration | Usage normalization, raw reported cost, unknown-price behavior, profiles/roles/SDK/children/compaction/resume, setup/doctor and token scrubbing | Real Session fixtures; no cross-route continuation or credential leakage; offline doctor preserves files and performs no refresh |
| X4: operator and installed path | Runnable API/key and registered-client OAuth instructions, entitlement recovery and account/billing disclosure | Whole-manual review; full source/native/demo, installed proof and hosted Linux/macOS; separately opt-in live results |

No new SDK or language runtime is needed: use Elixir/OTP and the existing HTTP,
JSON, private-file and OS-lock owners. Evaluate dependencies before any new
protocol helper; do not add an OAuth framework solely to wrap these few bounded
requests. Existing ChatGPT registration/refresh validation must retain its own
provider contract. A shared wire format is not shared token identity or replay
authority.

## Implementation and verification

The [verification receipt](verification.json) separates exact candidates, earlier
successes, the formatter failure and the controlled scope repair. The latest
`622a2c8` installed proof passes, including all existing package/lifecycle checks
and the new offline Grok path. Its archive SHA256 is
`b3f6e27da4b40c786a179da2226fb19839aa4e9df570562fb49dbeb820a83752`
(32,089,978 bytes). All 24 runtime notices were rehashed against SHA256 and Git
blob identities, and the archive identity module matches the packaged CLI's
`622a2c8` build facts (Elixir 1.20.4/OTP 29.1.1). Its full local source/native suite
passes 1760 tests, zero failures, 19 excluded, seed 954604, 1062.9 seconds, followed
by an isolated demo and unchanged tracked source. Build, both formatting checks,
warnings-as-errors compilation, CI policy and documentation checks pass. Its
[complete hosted Linux/macOS matrix](runtime-hosted.json), run 40120009675, passes
both source suites, installed lifecycle and every independent model-service,
extension, model-call, MCP, embedding, preset, saved-result and knowledge proof.
macOS native enforcement and experimental App Sandbox checks also pass.
Ubuntu's source summary is 1779 tests, zero failures, 36 excluded (seed 188121,
1581.5 seconds); macOS reports 1744 tests, zero failures, 36 excluded and one
skipped (seed 716971, 1702.7 seconds), followed by 36 native tests, zero failures,
six excluded (seed 35166, 26.2 seconds). The earlier `b2d8386` full native suite
passes 1759 tests, zero failures, 19 excluded, seed 541413, 1066.8 seconds, followed
by an isolated demo and unchanged tracked source. That earlier full suite does
not establish the later refresh-scope repair.

The implementation includes API/subscription registry entries,
shared bounded Responses with xAI-native replay, issuer-bound device login,
private locked refresh, setup/doctor and shell/measurement key filtering.
The expanded focused set passes 341 cases (seed 493844, 64.7 seconds), and the
real child/extension/Session set passes 78 cases before the final accounting
refinement. A later 90-case affected set passes after rebuilding the native helper.
Those focused controls are distinct from the exact latest full-suite results above.

The frozen `b2d838638f03c9f0f3950f2517e54c8159657a57` installed proof passes,
including toolchain-free Grok setup, offline doctor and missing-registration
refusal without contacting model/auth services. Its archive SHA256 is
`6a3f7a92348b2471a7e2d043cba6a18aa5c5ad31dcb5657dd4af53449b7ca4ce`.
That candidate's full local result is recorded above. Its first
[hosted matrix](first-hosted-failure.json), run 40119130959, stopped on both
platforms at formatting before ExUnit/installed checks: Elixir 1.18 wraps a long
new `with` expression differently from local 1.20. A short token-result binding
preserves evaluation order and is accepted by both formatters; seven OAuth
controls pass afterward (seed 902377, 0.2 seconds). Fresh exact-source hosted
verification is required for that repair, not a rerun claim for the failed run.

The formatter-repaired `fc8393a` macOS job subsequently reached ExUnit but failed
the unchanged four-path Research evaluator fixture's 120-second watchdog during
its later `freeze_fixture` call. Six completed CLI phases took 18.791, 13.051,
10.529, 6.271, 20.621 and 27.378 seconds before that call. Its
[job receipt](format-macos-failure.json) retains the exact stack and suite summary:
1743 tests, one failure, 36 excluded, one skipped, seed 876937. The cause is
unconfirmed; neither the evaluator nor its fixture changed from the passing
`dac11dc` baseline, and no assertion or deadline was weakened. Later candidates
must obtain their own verdicts rather than inheriting this failed job.
The [complete matrix receipt](format-hosted-failure.json) records terminal failure
for run 40119384442: Ubuntu passes its full source suite (1778 tests, zero failures,
36 excluded, seed 1455, 1386.8 seconds) and all installed/independent proofs;
macOS skips native, demo, package and subsequent proofs after the source failure.

Initial verification failures are retained as distinct observations: a new
resume fixture expected an absent `status` field and a last-turn `final` value
that existing idle resume intentionally clears; the fixture now checks `phase`,
historical model and unchanged request count. Existing Session behavior was not
changed. A real shell control then reproduced forwarding of the newly introduced
`XAI_API_KEY` through the helper's fixed scrub list. Adding it to shell and
measurement filters and rebuilding closes that observed leak; MCP/extension
environment admission already derives its blocked names from the registry.
The failing shell set was 308/309 passed (seed 46749, 44.3 seconds); the corrected
341-case set is the later successful result above. No real key was used.

A subsequent review reproduced a refresh-scope defect with a narrower initial
grant: an omitted response scope incorrectly restored the initial requested
scope list. The controlled set was 7/8 passed, seed 492845. Refresh now sends the
saved grant explicitly, preserves it when the response omits scope, and rejects
expansion. This follows [OAuth refresh rules](https://www.rfc-editor.org/rfc/rfc6749#section-6).
The affected auth/provider/setup/doctor set passes 66 cases, seed 87442,
11.0 seconds, before the final explicit-request assertion; the final eight OAuth
cases then pass, seed 804653, 0.2 seconds, including omitted-scope preservation
and expansion refusal. Both supported formatters pass. Final verification
uses the repaired source for the full local suite, installed proof and complete
hosted matrix. The earlier frozen candidate does not cover this newly
reproduced edge case.

### Live API check

At the developer's request, the nonempty `XAI_API_KEY` entry in the ignored project
environment file was admitted privately. The key was never printed or saved in
the receipt. The [live receipt](live-api.json) identifies runtime `622a2c8`, API
billing, `https://api.x.ai/v1/responses`, explicit `grok-4.7`, low reasoning effort,
128 visible output tokens and a three-request maximum. The first text request
returned HTTP 403 after 268 ms. The driver stopped after one request without retry,
fallback or tool execution. Usage was unavailable; no successful inference, zero
charge or working key entitlement is inferred. The developer was asked to check
team billing and model/API permissions before a new attempt.

The developer verification driver now admits only the explicit `xai` API route in
addition to its existing Gemini/OpenRouter routes. Its real loopback three-request
fixture verifies encrypted reasoning and call-ID replay without exposing native
payloads. Six focused controls pass (seed 390654, 0.8 seconds); both Elixir 1.18 and
1.20 formatting checks pass. A standalone CLI control in an isolated checkout
admits xAI confirmation, then refuses an absent config before traffic. A proposed
nested CLI test was stopped after it waited on its parent Mix build lock; it was
removed and the standalone control was used instead. This was a developer-test
coordination issue, not evidence of a provider failure. No production deadline
or assertion was weakened.

The driver is committed at `b52c32e`; its clean-checkout focused repeat also passes
six controls (seed 466803, 0.8 seconds). Its full hosted matrix is running separately
as run 40121156399. Runtime source, native helpers, dependencies, package construction
and the installed-package verifier are unchanged from `622a2c8`; the live receipt
records the actually loaded `622a2c8` build rather than claiming a later binary.

### Open external gates

1. xAI must provide or document an Ipse client registration, approved device grant,
   scopes and entitlement/billing behavior. Implementing fixtures cannot close this
   external gate. Until then login must refuse before sending a request without
   an explicitly supplied client ID; no bundled third-party ID is permitted.
2. API inference remains unverified after the recorded HTTP 403. Subscription
   access separately needs its own registered-client/account check; the API key
   cannot establish subscription entitlement.
3. Keep P29's original completed registry/Gemini/OpenRouter acceptance separate
   from this newly authorized increment. The external auditor must see both scopes
   and any unresolved registration/live limits.

Recheck the linked sources immediately before live OAuth or release, since
model aliases, eligibility and partner registration rules may change. This record
does not authorize sending email to xAI or registering/paying on the operator's behalf.
