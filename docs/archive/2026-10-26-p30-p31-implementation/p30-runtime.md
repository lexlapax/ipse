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
