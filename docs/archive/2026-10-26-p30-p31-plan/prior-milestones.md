# Prior P30 and P31 scopes

Historical snapshot archived 2026-10-26 from `caf7221`. Original path:
`docs/plan.md`, P30 and P31 sections. The original bodies and numbering below
are preserved; the relative media-reference link was rebased for this location.
Use the [current plan](../../plan.md) for the revised P30, new knowledge P31
and deferred voice P32. See the [planning record](index.md) for the rationale.

## P30: advisory decision engines

**Proposed; no decision operation is implemented.** Candidate services are
[OpenAI Decisions](https://developers.openai.com/api/docs/guides/decisions) at
`POST /v1/decisions` and TypeSafe's
[System One API](https://docs.typesafe.ai/api/system-one) for Jev. OpenAI's current
official guide describes general availability, superseding the earlier beta
description. Both return typed choices, scores or probabilities rather than
generated prose. Zev remains a local-engine candidate; its exact source, license
and protocol compatibility need primary-source verification before selection.
Recheck external contracts before adapter work; this proposal installs no engine
or SDK and establishes no live account access.

This is a separate operation, not a chat provider, following the pattern of the
P27 embedding contract:

1. A versioned request of bounded context plus questions (choice, score and
   yes/no predicate), with explicit option sets, ordered score levels or a
   probability contract. Validate one typed answer per question: an allowed
   choice, a finite in-range score/probability, an explicit uncertain/insufficient
   outcome or a refusal. Scores may fall between rubric levels; probabilities
   are not boolean permissions. Invalid, missing or partial answers refuse the
   whole decision.
2. Adapters for OpenAI Decisions, hosted SystemOne and loopback SystemOne,
   each with operator-configured endpoint, credential, destination facts,
   usage/cost accounting and budgets. There is no fallback between engines or to
   a language model.
3. Exposure through a new `host.decision` extension grant beside `host.embedding`
   and an optional model tool. Results are advisory data. They never approve an
   effect, grant a capability, choose a provider or profile without operator
   confirmation, or bypass journaling.
4. One measured first use, such as suggesting a profile or route for a task, with a
   small independently labeled workload and published agreement before the
   suggestion appears to operators. Later uses, including memory capture gating,
   skill selection and Research/Graph classification, need their own evaluations.

Acceptance: fixture engines for valid, out-of-set, uncertain, slow, oversized and
disconnected responses; owner death and cancellation; accounting and budget
refusal with zero dispatch; no-fallback checks; and separately recorded opt-in live
checks. Zev or another local engine is an operator-run external service, not a
bundled or required dependency; calling it adds nothing to the dependency
inventory, but the operator manual documents it as an optional endpoint.

## P31: voice and realtime media

**Deferred; unimplemented. Archived records call it P28, and earlier P24.**
Keep the requested scope for a future delivery; it is no longer ahead of
architecture/security review or self-development.
Build on the owned text/provider and P23 accounting foundation. Start with a
chained STT → admitted text agent → TTS extension/client; then add a versioned
realtime provider/session capability for bidirectional transport, interruption,
turn control, playback acknowledgment and reconciliation of generated versus
played history.

Voice choice, STT/TTS/device adapters and UI belong in extensions/clients. Core
owns resource lifetime, admission, approvals, cancellation, flow control and
provider continuation integrity. Use a separate media data plane, ephemeral raw
audio by default, canonical transcripts/usage and explicit endpoint/device/billing
choices. Text subscription authentication does not establish audio eligibility.

Acceptance: synthetic split/slow/disconnected media, revised interim transcripts,
barge-in, stale/unplayed frames, owner death, approval waits and no-replay recovery;
source/package checks and separately recorded opt-in live account/device checks.
Evaluate maintained Elixir/Rust/OS facilities and approve/inventory external
dependencies before adoption. No codec, frontend runtime or service is selected.
See [media boundaries](../2026-10-18-before-manual-rewrite/docs/developer/runtime-capabilities.md#text-and-media-are-distinct-from-diagnostics).
