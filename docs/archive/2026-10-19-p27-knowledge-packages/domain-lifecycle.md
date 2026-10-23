# Public domain lifecycle controls, 2026-10-19

Historical verification increment after `12dbc73`. The commit containing this
record adds barrier-controlled Graph and Corpus checks and runs them in source
and extracted-runtime environments. Use the current
[contributor exercise](../2026-10-22-before-structural-consolidation/docs/developer/knowledge-extensions.md#exercise-delayed-publication-and-interrupted-inference)
for commands and execution flow. The [plan](../../plan.md#p27-optional-research-graph-and-rag)
retains the complete P27 acceptance scope. These controls do not establish
held-out quality or complete P27.

## Exercised boundary

The fixture imports independent `graph/state-model` and `corpus/state-dense`
artifacts through normal host APIs. Production knowledge modules remain absent
from the host VM. A selected public Session registers its source/projection draft
and approves inference against an owned loopback endpoint. The fixture returns
scripted text or two-coordinate vectors. No model weights, actual model service,
downloads, paid inference or new dependency is involved.

Each package runs seven cases:

| Case | Direct observation |
| --- | --- |
| Delayed result racing forget | After actual provider dispatch, another Session sharing the operator configuration, home and workspace publishes suppression; the delayed projection refuses, inspection stays suppressed, and queries return no evidence before and after idle resume |
| Cancellation after dispatch | Cancellation completes, the provider socket closes, retained uncertainty has no successful typed result, and resumed inspection finds no projection |
| Session death after dispatch | Socket and Session lock cleanup are observed, the missing Session acknowledgment stays unconfirmed, reservations remain, and idle resume neither dispatches nor publishes a projection |
| Selected deadline | A held request reaches its explicit one-second profile deadline, closes the socket, retains uncertainty and leaves no projection after resume |
| Shared Session quota | The first projection completes; another attempt in the same one-request budget refuses before a second HTTP request and preserves the selected projection through resume |
| Malformed output | A malformed fact object or wrong vector width publishes no projection; ordinary canonical accounting retains the actual request |
| Provider unavailable | HTTP failure produces no successful projection, automatic retry or alternate route; accounting retains the dispatched attempt |

The controller waits for accepted HTTP input before applying each interruption
or competing mutation. It uses no arbitrary sleeps. The timeout case changes only
that case's explicit profile; production deadlines and existing assertions remain
unchanged. Every resume starts idle and preserves the prior action-intent sequence
before an explicit inspection. Provider counts stay at one per case.

Unknown work retains at least the declared 4096 input-token reservation. Text
extraction also retains its 4096 output reservation; embeddings retain zero
text-output liability. The quota case distinguishes two canonical attempts from
one provider dispatch and one admitted reservation. No cost is inferred from
these synthetic observations.

## Direct receipts and retained failures

Local verification used macOS arm64, Elixir 1.20.3 and OTP 29. Both standalone
source commands pass seven cases each. Both installed commands pass the same
seven cases each, with development tools hidden and unchanged archive/host bytes.
The archive remains the earlier local verification package with SHA256
`d5d2517e87cf358cfe6b6d82060719e6be52ce0e5fcf7920fc4729df7d5c8a4f`.
No release was published or rebuilt for this increment.

The original eight-check abort exercise also passes in source and through the
unchanged two-argument installed interface. Its zero-dispatch denial remains
separate from these synthetic provider calls. The extended wrapper's explicit
third argument selects Graph or Corpus lifecycle checks. CI runs both source
and installed variants against its independently built presets.

Earlier failed attempts remain retained. The first fixture omitted the required
instance `lifetime` and refused configuration before any provider dispatch.
Adding the ordinary persistent lifetime allowed both package controls to run.
The first installed attempt then caught a strict namespace mismatch: the fixture
used the macOS `/var` temporary-path alias while Session used its canonical
`/private/var` workspace. Canonicalizing the fixture workspace fixed the
calculation. The namespace assertion and host behavior were preserved.

The early two-package wrapper run passed both tests in 16.4 seconds. Adding
token-liability checks and the existing abort wrapper passed three tests in
20.3 seconds. Adding explicit timeout controls passed three tests in 25.1
seconds. The final standalone source and installed runs additionally verify
post-resume projection inspection and canonical workspace identity. The final
three-test wrapper run also passes in 27.1 seconds. Formatting, pinned CI action
policy and 226-document/2546-link checks pass.

Fixture process cleanup is reported as `fixture_cleanup: "confirmed"`. Session
owner-loss cases retain `session_cleanup: "unconfirmed_owner_loss"` and remain
listed separately in `session_cleanup_unconfirmed_cases`. Socket closure or lock
release does not substitute for a missing Session acknowledgment.

The exact-source [hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39229781991)
at `e98575e9a9cf11e73d31c86d297d4bda8b667cc8` completed successfully on both
Ubuntu and macOS. All 24 job steps were inspected per host: 24 succeeded on
macOS, and 22 succeeded on Ubuntu with only the two macOS enforcement steps
skipped. The knowledge step includes both source and installed Graph/Corpus
lifecycle commands. This establishes that revision's platform gate, not a
later domain repair's gate or held-out quality. Earlier unexplained MCP
discovery failures remain separate negative evidence.

## Remaining scope

These State-backed domain controls supplement the earlier generic host,
MCP/CAS, exact-abort and malformed paging checks. They do not claim an independent
remote store's internal concurrency, real-model quality, erasure of prior
transcripts or complete memory co-selection/capacity/resource coverage. The
complete execution freeze, matched held-out comparison, independent semantic
review and engine selection remain open. Held-out corpus, qrels, manifest and
evaluator remain sealed at this checkpoint.
