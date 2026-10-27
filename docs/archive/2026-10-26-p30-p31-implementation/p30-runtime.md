# P30 decision runtime component record

Dated **2026-10-26**, based on `a91dedb`. This historical component record
supplements the [frozen contracts](contracts.md); the [plan](../../plan.md#p30-advisory-decision-engines)
owns integrated delivery status. It does not establish a qualified consumer or
live engine access.

## Public interfaces and selected implementation

The [OpenAI create reference](https://developers.openai.com/api/reference/resources/decisions/methods/create)
and [TypeSafe System One reference](https://docs.typesafe.ai/api/system-one)
were fetched on this date before implementing transport. The existing pure
adapters remain the native text subsets. OpenAI uses `/v1/decisions` and the exact
`gpt-6-luna` model. TypeSafe uses `/v1/systemone`; a profile can separately bind
its requested model alias and exact expected reported model. A changed identity
fails closed until the operator updates that expectation. Compatibility is not
proof of self-hostable Jev.

`Ipse.Config.Decisions` admits at most eight operator profiles. Each explicitly
selects its provider, model and service ID. A compatible server needs an explicit
loopback endpoint. Hosted service credentials are isolated from the compatible
transport. Public snapshots retain destination origin/target digest, model and
expected identity, billing mode, service ID, native subset and bounded timeout.
Pricing, processing/storage region, cache retention and account-control disclosures
are nullable operator statements; absent information remains unknown. No account
control, regional capability, price or retention guarantee is fabricated.

`Ipse.Provider.Decision.Transport` uses existing `Ipse.HTTP.bounded_request/3`
and its borrower-owned client guardian. Native responses are limited to 65,536
bytes and decoded by existing duplicate-key/depth validation. Strict complete
result validation runs before any advisory answer is returned. Errors expose
fixed codes rather than remote prose. There is no provider/model/billing fallback,
redirect follow, model acquisition or automatic request retry.

`Ipse.Extension.DecisionCall` provides the `decision.create` effect contract,
profile/destination binding, complete approval validation and journal source/result
validation. It reuses the ordinary `Ipse.Extension.Inference` owner lifecycle.
The Session must journal intent, admit canonical usage and reserve shared budget
before invoking transport. A successful advice result grants no effect permission.
Unknown/cancelled remote work must retain existing conservative liability.

Decision accounting uses version 3 with explicit `operation: decision`;
admissions also bind the service ID and expected reported model. Session metadata
must select usage version 3 and retain its admitted public decision-profile
snapshot. Version 1 text and version 2 embedding events keep their existing shapes.
Old metadata rejects new decision intents and admissions. Response records retain
normalized usage so contradictory completion counts fail reconstruction.
Own-session usage pages use version 3, and child accounting uses snapshot version
5/page version 3; earlier page versions cannot carry decision records.

Rate-card version 3 requires an explicit decision operation row. Ordinary text
prices never supply a decision price. Absent cache partitions stay null, so a
cache-split estimate remains partial until those counts are known. No price is
hardcoded. These endpoints expose no enforceable output-token cap; decision
admission refuses a shared output-token budget before dispatch. Explicit request,
input-token and money policies retain ordinary conservative reservations, including
when local work is cancelled or remote settlement is unknown.

No dependency was added. Existing Finch/Mint, Jason, bounded JSON and HTTP ownership
were evaluated and reused. A separate response parser is unnecessary; the existing
wire conversion validates this protocol's exact selected shape.

## Bounds and verification scope

The pure neutral contract permits 16-KiB input and a 32-KiB total request.
The extension SDK has an existing 8,192-byte string limit. `decision.create`
therefore rejects a larger input before approval/egress even when the pure contract
would accept it. It never truncates. All other SDK aggregate bounds also apply.

The focused command uses a separate build directory to avoid unrelated concurrent
compilation:

```sh
MIX_BUILD_PATH=/tmp/ipse-decision-component-build mix compile --warnings-as-errors
MIX_BUILD_PATH=/tmp/ipse-decision-component-build mix test \
  test/ipse/provider/decision_transport_test.exs \
  test/ipse/config/decisions_test.exs \
  test/ipse/extension/decision_call_test.exs \
  test/ipse/decision_test.exs test/ipse/provider/decision_test.exs \
  test/ipse/usage_test.exs test/ipse/usage/decision_test.exs \
  test/ipse/usage/embedding_test.exs test/ipse/usage/costs_test.exs \
  test/ipse/usage/budget_test.exs test/ipse/extension/usage_read_test.exs
```

Strict compilation and **100 focused tests passed** after the shared inference
lifecycle admitted the new kind, under Elixir 1.20.4/OTP 29 on Linux. Existing
text/embedding accounting, costs, budgets and usage pages are regression-tested
alongside the self-authored synthetic decision protocol tests.
The separate existing `test/ipse/usage/integration_test.exs` run passed **3**
Session usage lifecycle tests. The documentation checker passed with 472 Markdown
files and 4,296 local links; `git diff --check` reported no whitespace errors.
They inspect real local HTTP bodies, exact model identity, absent credentials on
compatible requests, unknown disclosures, invalid provider/profile/endpoint fields,
duplicate-key and malformed responses, response byte limits and request bounds.
Accounting tests alter metadata versions, selected service/expected model,
endpoint, response identity, completion usage and selection digest; each forged
binding refuses. Cancellation retains reservation liability. Old rate-card
versions refuse decision rows; missing cache partitions never become free spend.
During a real blocked HTTP request the test kills its borrower, observes guardian
exit and confirms the server's socket closes. This demonstrates local cancellation,
not that a remote server stopped billing or computing.

No paid OpenAI/TypeSafe calls, local model calls, model downloads, independent
semantic qualification or human/macOS checks were allocated to this component.
Live eligibility, useful consumer benefit and paid costs remain unverified.
Elixir 1.18/OTP 27 and macOS require their own verification. Integrated Session
decision admission/denial and saved reconstruction belong to the integrating
owner and cannot be inferred from component success. Pure accounting recovery
and conservative reservation tests are included above.

## Operator configuration and capability integration

The subsequent independent integration carries `decision_profiles` through
configuration validation, resolution, fingerprinting, runtime admission and setup
preservation. Trusted project files cannot add, replace or erase that registry.
Absent registries add no fingerprint field; existing captured provider/configuration
facts retain their historical values. Editing a source file still changes its hash.
Selecting advice never selects or changes the conversation provider.

The optional `host.decision` capability requires `host.actions` in the inert SDK
catalog. Artifact declaration and the operator trust ceiling must both include it.
The Host dispatches an admitted `decision.create` through its owned inference
lifecycle. Decision source/response records are recognized by transform recovery
only outside active transforms. Successful action binding can use the closed
`DecisionCall.bound_response?/2` helper; it checks operation/request/attempt,
selection, reported identity, usage, result and payload digest together.

Only an explicitly child-enabled decision extension carries decision profiles
into a child; named child-route selection preserves that admitted subset.
Child approvals remain `ask`, MCP remains unavailable and recursive delegation
remains disabled. Profile availability grants no capability or approval.

`TYPESAFE_API_KEY` is included in the provider-secret policy and native inherited
environment scrubber. Main MCP configuration and extension MCP environment-name
validation consequently reject it. The native helper was rebuilt with
`./dev/build-native.sh`; the two focused Runner credential/conformance tests passed,
including actual shell execution with every registered provider key replaced by a
synthetic value. These checks do not exercise a native terminal or an engine.

Strict compilation and a combined **88-test** focused run passed across setup,
decision loading, artifact/capability/children, MCP configuration, existing
profile/catalog/registry tests and decision accounting/bindings. Setup replacement
retains the registry and its exact previous-file backup. No live model service,
download, new dependency, package build or release was involved in this checkpoint.

## P31 native input component checkpoint

This dated component checkpoint does not complete P31. The integrating owner
retains SourceIndex native-answer admission, knowledge consent/capture integration,
whole-manual review, the combined baseline and independent adversarial audit.

The CLI selects exactly one reader through a bounded, compile-bound native probe
of matching actual terminal descriptors and protected channel-lock availability.
Only an explicit nonterminal result selects the existing pipe reader. Helper
identity/security failures, mismatched terminals and lock contention refuse;
native input never switches to `IO.gets` later. Piped chat stays unattended.
`--yes`, argv, interactive flags, copied codes and legacy role labels confer no
native origin. Machine PTY automation can exercise the boundary; terminal
observation does not establish that a human supplied the bytes.

Protocol v1 retains its original 8-KiB limit and unchanged termios behavior.
Explicit v2 supports an exact UTF-8 line up to 1 MiB and independently bounded
escaped display up to 16 MiB. Valid edits have at most 1 MiB each of old/new
content; worst-case JSON escaping expands that combined payload to about 12 MiB.
The display allowance includes bounded paths and approval text. Exact-limit and
limit+1 tests enforce whole-display acceptance/refusal. Unrepresentable full
arguments are denied before approval/effect; no argument is truncated. Oversized
or invalid input receives a visible whole-line refusal and produces no witness.

V2 avoids canonical line truncation with a temporary noncanonical mode. A native
guardian and reader in separate process groups retain independent original-state
copies, peer-liveness pipes and the channel flock. Readiness binds both process
IDs and nonce. The guardian reaps the reader, restores termios and flushes old
input before its restoration receipt; that receipt retries for at most 500 ms
under output backpressure. Reader-side restoration covers guardian loss with a
distinct receipt that cannot substitute for confirmed cleanup. An independent
Elixir controller is tracked by Session resources/lock ownership. Cancellation
requests cooperative cleanup; missing restoration/exit receipts or an expired
cleanup deadline report unknown cleanup. Retained native locks fence replacement
while an old holder remains. Individual process faults are covered; simultaneous
loss of both restorers and arbitrary same-user tampering are outside the guarantee.

The locked Session binds input to its actual subscribed client, persistent reader,
channel generation and closed purpose. Single-use prompt tickets preserve native
provenance across the existing 16-entry/1-MiB queue. Cancellation and client/channel
death invalidate them. The reader requests another display only after the client
has processed its preceding line. Native questions use host-created question,
call/arguments hashes, fresh render IDs/codes and the exact channel. The Session
parses raw input itself. Atomic `operator_answer` v2 records contain the committed
message and closed original-text/hash/observation receipt. Saved reconstruction
requires the actual question checkpoint, exact message hash and unique source/
observation IDs. V1 answers remain unverified; clarification never grants effects.
Standalone review has not been added or given a registration bypass: Input still
requires the actual held Session lock.

Verification used Linux, Elixir 1.20.4/OTP 29 and synthetic fixtures only. Strict
compilation and whitespace checks passed. The serial native suite passed 15 tests
with one internal subprocess entry ignored; after the final receipt retry, all
five v2 tests passed again. Those cover exact 1-MiB/Unicode input, limit+1 and
malformed input, reader/guardian kills, stopped reader plus host loss, and exact
termios restoration. Three actual CLI/channel fixtures cover stale/fresh codes,
literal answers, queued tickets, cancellation, reader/Input-service death, Session
close/death during reads, and abrupt VM death with independent restoration.
Three pure answer/replay tests passed alongside them. Existing pipe/CLI and v1
witness regressions passed. One new replay fixture initially lacked its required
Session header; its repaired focused rerun passed. Display-boundary, malicious
frame and missing-restoration deadline tests also passed.

Logs are `/tmp/ipse-operator-native-final.log`,
`/tmp/ipse-operator-v2-native-final.log`, `/tmp/ipse-operator-replay-cli-final.log`,
`/tmp/ipse-operator-regression-tests.log` and `/tmp/ipse-operator-deadline-final.log`.
CLI checks used helper SHA-256
`7f39f8aa4d83f76c175f9f25e06d586b0e5a843982b44793d9fe10fc20127e7e`.
The integrating owner must rebuild/rebind the final combined helper including the
later receipt retry and independent storage changes. There were no live model
services, paid calls, qualification inputs, downloads or new dependencies. Native
changes use the existing Rust standard-library/OS FFI boundary. Elixir 1.18/OTP 27,
macOS, human operation and the final combined build require their own verification.

### Queued prompts at native question EOF

The follow-up `Session.question_eof/2` is restricted to the registered subscribed
client, its current input channel and an actual pending question. It closes the
question with normal cancellation cleanup, clears question renderings and answer
pieces, and calls `Input.cancel_read/0` so only prompt tickets already staged by
the host survive. The CLI uses this path both when EOF arrives at a question and
when accepted queued work asks a later question after EOF. It starts no further
reader and creates no new observation. Explicit cancellation, close, reader/client
death and channel replacement continue to invalidate the queue.

A nonterminal Session regression passed with synthetic host-state observations;
that fixture tests ownership and queue transitions, not native attestation. It
checks wrong-client/channel refusal, repeated EOF questions, exact admitted queued
text, invalidation of unstaged observations, clearing of question codes/pieces,
and ordinary cancellation of remaining tickets. Strict compilation and all ten
focused EOF, answer-replay and terminal-rendering tests passed. Receipts are
`/tmp/ipse-operator-eof-test.log`, `/tmp/ipse-operator-eof-regression.log` and
`/tmp/ipse-operator-eof-compile.log`. Actual CLI EOF/PTY verification remains pending
the next coordinated native-test window and is not claimed by this checkpoint.
