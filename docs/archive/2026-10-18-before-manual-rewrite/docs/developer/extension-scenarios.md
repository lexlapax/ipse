> Historical reference only. Snapshot of `docs/developer/extension-scenarios.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../2026-10-22-before-structural-consolidation/docs/developer/extensions.md#trial-an-independently-built-package).

# Extension adoption scenarios

Design walkthrough reviewed on 2026-10-16 against `96369a4` and the proposed
[P22 SDK](extensions.md). These are architectural scenario tests and future
acceptance cases, not executable scenario results. Subsequent P22A work supplies
the [inert artifact store and explicit worker API](extension-artifacts.md), plus
[scoped selection configuration](../operator/extensions.md) and
[initial session hooks](extension-hooks.md). The complete scenarios below remain
in progress. The operator requested bundled configurable
extensions, third-party installation, assisted setup and generated permanent or
temporary features. The purpose is to expose foundational gaps before freezing
the SDK, without implementing every distribution feature in P22.

## Findings and changes

The earlier plan covered precompiled examples and feature callbacks, but required
rebuilding Ipse for each external module. It also treated enablement mainly as
one configuration boolean. Those assumptions were insufficient for installation
without a core rebuild, independent versions, temporary leases and assisted
authoring. The revised plan separates three identities:

- **Package/artifact:** immutable executable bytes, SDK/runtime requirements,
  dependencies, license/provenance and a content digest. Bundled, installed and
  generated packages use the same descriptor contract.
- **Installed/trusted record:** where those bytes live, how they were obtained,
  validation status and the operator's permitted capabilities/scopes. Installation
  alone does not start the code or enable it in sessions.
- **Activation instance:** exact artifact plus instance alias, selected hooks,
  options/configuration digest, lifetime, state namespace and session generation.
  One artifact may have several independently configured instances.

The SDK uses backend-independent serializable values. Precompiled trusted modules
can run in-VM; externally installed/generated packages use owned worker processes.
P22 proves one local Elixir worker import and session-scoped trial. Network package
management, turnkey generation/build UI and live activation can follow without
replacing the package or callback model. See the
[worker rationale](extensions.md#worker-boundary).

## Scenario tests

Each row traces the expected path, the flaw found in the earlier design and the
boundary between P22 foundation and later delivery. A design pass means the
revised contract has an explicit route; implementation still needs its fixtures.

| Scenario | Walkthrough and expected result | Foundation required in P22 | Deferred feature |
| --- | --- | --- | --- |
| Bundled, disabled extension | Release contains prompt/format examples; list/inspect sees static metadata; ordinary startup never runs disabled callbacks/init. | Metadata independent of activation; builtin backend; default-off parity. | Additional bundled features. |
| Enable/configure with config or flags | Resolve operator/project/session overrides for an installed trusted ID; validate options/order; pin exact effective instance. | Generic selector/options/provenance handling; no feature-specific CLI cases; project values within operator grants. | Rich configuration UI/presets. |
| Two configurations of one feature | Enable two instances with different annotations or memory namespaces; disable one without changing the other. | Separate package ID and instance alias; deterministic order and isolated state. | Cross-instance composition UI. |
| Third party provides compatible package | Import a local validated immutable artifact; select it for a new session; no Ipse rebuild, host code-path change or startup download. | Manifest/compatibility contract, local import/registry and standalone worker proof. | HTTPS/git/catalog download convenience, signing/trust-store services. |
| Source-only third-party project | Inspect source/lock/dependencies, build explicitly in a separate workspace, validate output and import it. Build can execute code and needs its own authorization. | Build-recipe/provenance fields and artifact validation; clear toolchain prerequisites; core never compiles package source during discovery. | Managed build runner/cache and dependency resolver UI. |
| Operator asks Ipse to install/configure | Ipse proposes exact source/version/digest, effects, configuration scope and activation; operator-authorized host operations stage and commit them. | Typed management proposals using ordinary host approval/intent/outcome contracts; no self-issued trust. | End-to-end conversational installation assistant. |
| Operator asks for a permanent feature | Author/test in a separate workspace; trial exact artifact; promote it into durable installed/configured state under explicit operator scope. | SDK/template/conformance contract, stable artifact identity and promotion/state rules. | Turnkey author/build/publish workflow. |
| Operator asks for a temporary feature | Create/import an artifact with session lifetime, use it in an explicitly fresh trial session and expire activation on close. Global/project defaults stay unchanged. | Session activation lease, transient configuration, artifact retention and cleanup/recovery rules. | One-turn leases and convenient trial-session orchestration. |
| Use the feature in the current conversation | Authoring does not mutate the live catalog. Initial P22 offers a reviewed handoff/new session; later idle activation uses a host transaction and new generation. | Generation identity and unsupported-transition refusal; no implicit hot load or inference. | Idle activation API and UI with provider/catalog compatibility verification. |
| Upgrade while another session runs v1 | Install v2 alongside v1; fresh sessions can select v2; existing instance stays pinned to v1. | Immutable side-by-side artifacts and worker-per-instance version separation. | Version discovery/update policies. |
| Failed install/build or interrupted activation | Stage failure leaves prior installed/default selection intact; incomplete executable effect is unknown, not rerun. | Transaction boundaries, locks, intent/provenance and recovery; validate before publishing selection. | Network retry/cache management. |
| Rollback, disable, uninstall or expired trial | Future sessions select an explicitly approved older artifact or no extension; active work is not secretly switched; referenced artifacts are not silently deleted. | Retention/reference policy, disable/revoke semantics and explicit missing-artifact resume error. | Automatic garbage collection and migration helpers. |
| Package adds capabilities or changes bytes | New digest/capabilities invalidate prior executable approval; unknown required SDK/runtime capability refuses before startup. | Digest-bound trust, capability negotiation, compatibility diagnostics and no fallback. | Signature/catalog-based trust policies. |
| Project contains a ready-to-run extension | Project discovery shows a data-only candidate; no `.exs`, build hook or worker runs until authorized installation/activation. | Canonical paths, bounded manifest parsing, source provenance and scope limits. | Repository extension recommendations. |
| Turn observability off while work runs | Stop optional sinks without losing approvals, accounting, visible output or recovery evidence. | Separate host capture/egress gate, sink-stop and durable versus sampled channels. | OTLP/dashboard extensions. |
| Inspect a failing extension | Use synthetic callback/worker inputs and sanitized correlated events; no effect-journal replay or raw-state observer access. | SDK conformance runner and bounded developer trace ownership. | Visual timeline/IDE integration. |
| Report costs with tracing disabled | Read durable request facts, including children/compaction; missing usage stays unknown; rates carry identity. | Request/attempt IDs, canonical usage facts and generic report surface. | P23 report extension and budget host capability. |
| Consume text while generated | Read ordered private visible-text chunks with bounded flow/cancellation; saved provider history stays unchanged. | Content subscription and slow-consumer/terminal policy, separate from diagnostics. | Stateful incremental rewrites. |
| Add voice or duplex audio | Negotiate owned media/provider capabilities; unsupported audio refuses until implemented. | Versioned resource/data-plane boundary and explicit billing/approval ownership. | Deferred P28 voice/realtime transport/playback capability. |
| Maintain a graph from prompts | Original/final-effective subscriptions and boundary-scheduled extraction jobs are implemented; a job proposes scoped writes separately. | Shared event IDs, private-view authority, separate action approval, bounded job admission, causation and duplicate/gap handling; exercised in the independent installed lab. | P25 researches extraction/graph choices; production algorithms defer to P26/P27. Fully concurrent effectful jobs need negotiated core support. |
| Recall memory for the current answer | Await a selected pre-request hook and commit its bounded evidence snapshot before inference. | Ordered recall seam; background completion cannot alter an admitted request. | Retrieval/ranking quality and production backends. |
| Resume or catch up a subscriber | Restore committed receipts without executable startup/replay; explicit bounded catch-up is a new approved job over authorized history. | Source IDs, unknown outcomes, retention gaps and tombstone/revision checks against delayed resurrection. | Durable external broker/cursor integrations, if separately justified. |
| Subscribe from another system | Use a reviewed typed adapter with configured endpoint, authentication and export authority. | Same event/view/delivery contract; no default listener or implicit private-feed export through MCP. | Remote transport adapters and optional CloudEvents mapping. |
| Enable memory/research/graph/RAG independently | Select known instances/hooks/providers; disabled packages start nothing; retrieval need not create permanent memory. | Context/store/retrieval contracts, provenance, approved jobs and explicit package capabilities. | P25 research/selection followed by deferred P26/P27 default-off packages. |

All scenarios now have a defined route. The key correction is that package
acquisition, building, executable approval, configuration and activation are
separate operations, even when a single operator-reviewed request authorizes a
specific combination. Asking Ipse to author a feature does not make the output
automatically trusted; the operator can authorize a concrete trial as part of
that task without repeated approval for already authorized steps.

The runtime cases are analyzed with primary-source comparisons in
[runtime capabilities](runtime-capabilities.md). Observability/developer controls
are specified in [observability](observability.md); the requested default-off
knowledge extensions are mapped in the [knowledge design](knowledge-extensions.md),
with planned P25 research and deferred P26/P27 production delivery. P24's
[independent adversarial review](self-hosting-evaluation.md#independent-adversarial-architecture-validation)
challenges these routes before the trial, without assuming every future feature
already fits the current SDK.

## Package and installation contract

Use one versioned, bounded data-only manifest with a stable namespaced string ID,
display version, SDK/protocol requirements, required/optional capabilities,
hook/tool/command declarations and option schema. Include declared backend and
entrypoint, runtime/OS/architecture/ABI requirements where relevant, dependency
lock/build provenance, files/digests and licenses. Display versions are labels;
the content digest identifies the artifact. Do not invent module atoms from
package IDs or treat a manifest command as a shell string. Document validation
limits before accepting untrusted archives or descriptors.

Keep the host's manifest/configuration schema closed and versioned, with bounded
namespaced options/metadata for feature-specific data. SDK minor capabilities
can be negotiated; unsupported required capabilities or breaking major versions
refuse before startup. A new feature should extend its own option schema, not
add top-level host configuration fields. The local import supports a deliberately
small dependency shape first; unsupported package relationships fail clearly,
rather than silently starting an incomplete service graph.

For the first local package, a canonical directory and bounded regular-file
inventory suffice. Resolve/copy into private staging, reject escapes/symlinks,
verify bytes and limits, then publish an immutable store entry under a lock.
Do not accept archive extraction until traversal, links, expanded size and file
count are validated. Reading/validating the manifest must not load BEAM modules,
run `on_load`, install dependencies or call the package to discover metadata.
Recheck artifact identity before startup; never execute a mutable staging path.
If a package requires setup/migration effects, represent them as separately
approved/journaled operations, not activation callbacks.

Proposed logical locations are an operator artifact store, isolated candidate
build directories and session activation/state records. A project may contain
source/configuration, but code runs from the reviewed pinned artifact. Physical
paths are configurable through the existing application-home conventions;
there is no hardcoded repository, registry, host or service endpoint. Installed
catalog changes alone do not rewrite configuration fingerprints or active
sessions. Updates publish a new artifact; they never overwrite old bytes in place.

Runtime compatibility is verified before execution. A portable-looking `.beam`
does not establish compatibility with every OTP version, and NIFs/helpers need
explicit target constraints. The first external fixture uses Elixir and declared
tooling; arbitrary downloaded runtimes or other-language build dependencies need
their own approval/inventory. An extracted Ipse release must not claim to include
Mix or a full developer toolchain merely because it includes ERTS/Elixir apps.

## Configuration, lifetime and activation

The proposed generic configuration section maps instance aliases to installed
package selectors, `enabled`, hooks/order and schema-validated options. Apply
existing precedence with field provenance, plus an operator capability/scope
ceiling: project settings and flags cannot override revocation or expand the
approved capability set. CLI flags select instances/options for this invocation;
they do not save operator/project defaults. Use structured option files or typed
arguments and credential references, keeping secret values out of argv/journals.
There are no per-extension CLI switches and no network fetch from an unknown ID.

Keep the enabled set in the session manifest, with exact artifact/runtime digest,
instance ID, option/configuration digest, schemas/capabilities, lease and generation.
Resolve once before admission; replay reconstructs committed derived snapshots,
not callbacks. Installing another version does not switch an existing instance.
Changing global configuration can still trigger P15's conservative resume refusal;
an extension installer must not bypass that existing policy to claim seamless
updates. New-session/handoff is the initial explicit recovery path.

For permanent use, explicitly persist the selected operator/project configuration
after a successful trial. Temporary use defaults to a session lease and private
scratch state, with no durable enablement outside that session. Expiry stops its
worker and removes transient bindings; it does not undo external writes or erase
private journals/projections. Retain artifact identity and referenced bytes under
a documented private retention policy so resume is reproducible. An expired lease
requires explicit reactivation of the same artifact or a fresh session; missing
bytes refuse without downloading/rebuilding a substitute. Promotion reuses exact
reviewed bytes, chooses explicit configuration/state scope and never silently
copies scratch memory into a long-term store.

Initial activation is at new-session startup. Runtime enable/disable requires a
future host-owned idle transaction: no in-flight model/tool/approval/question,
validate and prepare a candidate generation, commit activation identity/catalog/
configuration atomically, then admit a new prompt. Failures retain the prior
generation and stop prepared workers; an incomplete commit refuses recovery.
Initial activation has generation zero; later transitions require an explicitly
negotiated host capability. Reject stale-generation calls/replies. Preserve
original provider continuation and verify the selected provider supports catalog changes; otherwise require a
new session. P22 must version this boundary and reject unsupported transitions,
without implementing arbitrary hot reload. Revocation must block further work,
cancel owned workers or stop owning sessions, and preserve unknown-effect outcomes.
It cannot promise to undo completed OS effects or unload arbitrary trusted in-VM code.

## Assisted authoring and management

The agent may propose download, build, local import, configuration, trial,
promotion, rollback or removal using typed host operations. Host arguments must
show source identity, digest, target paths, capability scope, effects and lifetime.
Reuse existing structured questions when scope/retention is ambiguous and existing
approvals/journals for effects. Installation and code activation remain explicit
operator authority; neither a skill, package, generated source nor a successful
test is a permission grant. An explicitly reviewed combined operation can cover
several steps; avoid redundant confirmation once that scope is authorized.

Generation/build is ordinary supervised development against the SDK: candidate
workspace, fixed inputs/dependency lock, meaningful conformance tests and a trial
artifact. Compilation can evaluate code; it is not passive parsing, as described
by [Elixir's compilation API](https://elixir.hexdocs.pm/Code.html#compile_file/2).
Run it outside the live host VM, using declared tooling and the selected trusted
execution/sandbox policy. Failure must not affect the current session or replace
the installed artifact. Preserve build/source/lock provenance, but do not treat
a digest as publisher authentication or infer permission from model authorship.

## P22 acceptance mapping

P22A defines package/instance/activation identity, serializable SDK contracts,
configuration/lease/provenance, the worker bridge and local immutable import. P22B
proves bundled default-off configuration/flag behavior and both pre/post examples.
P22C adds a separately built local worker using the SDK after core is frozen,
including a temporary session trial and explicit persistent configuration. It also
exercises the memory/workflow coverage gate and the [prompt-event graph proof](lifecycle-events.md#knowledge-graph-acceptance-proof),
including background indexing versus awaited recall. P22D verifies compatibility,
concurrent pinned versions, crash/interruption/owner cleanup, expiry/revocation,
invalid artifacts/configuration and package/source operation on Linux/hosted Mac.

Before declaring P22 complete, run executable fixtures for the foundation in the
table. Deferred download/build/live-activation scenarios need contract cases that
refuse unsupported operations clearly; do not report them implemented. Keep
network catalogs, automatic builders, signature services, automatic upgrades,
one-turn leases and live catalog replacement as follow-ons with named host
capability additions. Changes to the core for those generic host capabilities
remain foreseen, versioned enhancements; feature logic stays in extensions.
