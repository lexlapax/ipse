# Pure managed recipes and activation data

Dated **2026-10-26**, prepared after Core storage checkpoint `8ec3361` on
`codex/p30-p31`. This is an internal engineering record, not a shipped operator
workflow or P31E acceptance. It follows the
[pure managed-reference checkpoint](managed-reference-component.md).
[The plan](../../plan.md) owns milestone status and
[the collection SDK chapter](../../developer/collection-sdk.md) teaches current
host boundaries. The parent owns atomic normalization, live read views,
Session activation and dispatch integration.

## Authorized implementation and ownership

The parent approved three pure contracts and matching tests:

- [`ManagedRecipe`](../../../lib/ipse/extension/managed_recipe.ex): closed reviewed
  selectors, fixed original-source/proposal identities and supported candidate
  extraction, without clocks, IO or domain callbacks.
- [`SemanticConsent`](../../../lib/ipse/extension/semantic_consent.ex): explicit
  version-2 named constraint/recipe registries, bounded activation data, resolution
  helpers and exact effect matching, preserving version 1.
- [`Activation`](../../../lib/ipse/extension/activation.ex): data validation and
  overlay catalog derivation, without preparing executable identities or changing
  ordinary configuration fingerprints.

Session, Invocation, Turn, Saved, Journal, provider, native and Collection files
were not edited by this component. There is no new runtime/tooling dependency.
JSON/schema work reuses the existing Jason and Ipse adapters. No model call,
account, download, private qualification input or terminal test was used.

## Exact policy version and limits

Top-level Consent policy version remains 1. Its `settings.version: 2` is explicit;
`prepare/3` requires a version-2 selection with all new fields. Old selections
retain their original exact key set and implicit settings version 1. Unknown
fields or version relabeling do not migrate an old grant.

Version 2 keeps the old settings fields and additionally requires `constraints`,
`recipes`, and `activation` (explicit null when absent). Each registry allows eight
entries keyed by `Ipse.JSON.digest([value])`. Missing entries, aliases under wrong
hashes, unreferenced values, duplicate base mapping identities and cross-registry
prefix/evidence/origin mismatches refuse. Registries deduplicate repeated reviewed
schemas across exact outer exports; they do not widen SDK objects.

| Mapping | Required version-2 fields beyond the four exact base identity fields |
| --- | --- |
| `collection.publish` | `constraints_sha256`, `recipe_sha256`; inner op exactly `collection.managed` |
| `collection.read` | `managed_read`: sorted unique list of 1..8 recipe hashes; inner op `collection.call` |
| Existing helper class | No additional fields; original exact operation/class/outer/inner identity |

`constraints/2`, `recipe/2` and `managed_recipes/2` resolve only pinned data. A
worker effect cannot carry those policy fields. Authorization still requires the
exact Session pin, current policy hash/epoch, mode, origin/exclusions, source
generation, route and finite reservation. A stored mapping does not replace the
protected current check or publication settlement.

The existing limits remain unchanged: **16,384 bytes/depth twelve** for settings,
**32,768 bytes** for the policy, and **65,536 bytes** for its saved descriptor.
The actual native capture note and proposal schemas, two recipes, three mappings
and activation produce **9,279 settings bytes / 9,807 policy bytes** in the final
fixture. Both pass the existing lexical-depth check. The four native retention
schemas remain sidecar/UI data; this initial capture grant does not give Main
automatic pin or retention operations.

## Recipe identity and extraction

A recipe contains exactly `version`, `kind`, `key_prefix`, `constraints_sha256`,
`evidence_path`, `lineage_path`, `text_path`, `category_path`, `rules`, and
`override_prefix`. Version is 1; kind is `literal_source`, `proposal`, or
`operator_override`. It fits 4096 bytes. Paths contain 1..8 identifier segments
and select JSON fields only. Rules contain bounded category, max-age and sorted
source-origin data. Automatic pin/history rules refuse. Null literal age requires
an explicit permitted persistent category; proposal rules always have a finite
age no greater than seven days.

`source_identity/1` implements fixed `source.identity.v1`, byte-identical to the
existing capture lineage: select Session/occurrence/version IDs, exact byte span,
quote/content SHA256; sort key/value pairs, encode their JSON arrays and hash.
`proposal_identity/2` applies the same canonical pair encoding to `{lineage,text}`.
The latter matches the actual proposal key, not merely the lineage.

`extract/4` requires a closed candidate object and an exact selected proof member
of the host-authenticated set (1..8 receipts). It structurally validates the stable
14-field source receipt but does not authenticate it. Literal extraction requires
one declared source, exact quoted text, matching lineage and key, strong admitted
origin and ordinary classification for typed outcomes. Proposal extraction may
retain paraphrased or weak-source text but always returns `never_current`.
Literal candidates return `pending_host`, not `eligible`.

The candidate includes only version/kind/recipe hash, lineage/key/text/category,
reviewed max age, selected sources and that status. Worker creation, observation,
update and expiry clocks establish no host facts. The caller must also apply the
pinned CollectionPolicy schema/origin constraints; extraction alone is not a
publication approval.

`operator_override` extraction returns
`{:error, :managed_recipe_requires_typed_choice}`. Its target lineage must come
from an exact typed host choice/target record, not the new operator answer's own
source identity. Native text `2` cannot bless an assistant premise or select a
worker-proposed pin policy. Typed acceptance/override adoption remains separate
work.

## Activation remains data until actual host admission

Activation version 1 contains exactly kind (`reviewed.bundle`), artifact ID/SHA,
sidecar SHA, instance, options, capability ceiling, service references, order,
session lifetime and `allow_children: false`, plus version. Artifact ID is the
exact SHA. Options allow 1024 bytes, the complete descriptor 4096 bytes, capability
list 32 entries and service references eight entries. No service/profile
definitions, executable path, credential or child widening can be added.

`matches_policy?/2` binds the artifact, instance and each disclosed service/profile
reference to exactly one policy route. `derive/2` validates a version-2 policy and
returns only a catalog, activation digest and stable virtual operator source.
It refuses instance/artifact-trust collisions and catalog capacity; it never
overrides base entries. The virtual source binds project and exact activation
definition, without depending on a mutable enable epoch.

Actual Registry preparation must verify the installed reviewed bundle/sidecar,
manifest/option schema, complete capability ceiling, services, host/runtime and
generation. The returned pure catalog is neither a prepared identity nor an
execution capability. Fresh selection must read protected current policy;
resume must reconstruct only its saved selection, including historical absence.
Ordinary configuration fingerprints remain intact and live revocation still
gates effects. This checkpoint does not wire that Session bootstrap step.

## Clock/footprint review supplied to the parent

The read-only review approved separate permanent first anchors for durable notes
and pending proposals: a pending seven-day clock must not cap a genuinely later
supported literal, and text rephrasing must not renew a pending source lineage.
Both saved baseline deadlines are required. The effective deadline is the minimum
of the saved baseline and first-anchor plus current reviewed age; changing a
shorter policy to a longer one cannot renew expiry. Null represents infinity only
when the corresponding first anchor is present. Legacy raw override JSON without
a trusted host sidecar refuses adoption.

The proposed parent normalizer packs bounded host-owned anchor/live pages under
`host.validity.*`. No record may be evicted to renew an expired lineage. Worker
adapters must deny reserved-prefix reads/writes even through legacy calls; trusted
direct storage maintenance owns that namespace separately.

An isolated synthetic encoding probe used maximum safe integers/hashes and found
3321 bytes for sixteen conservative anchor rows, and 3897 bytes for four live rows
with eight source-version pairs. Under that illustrative shape, 21,600 anchors,
2000 live rows and 2000 full 6144-byte note values sum to 18,719,850 logical bytes
and 3850 keys before indexes, pending values, metadata, receipts or transient
allocation. This is **not** actual Collection/native capacity or performance
qualification. The parent subsequently refined the clock row to retain both
baseline deadlines; the final physical layout still needs its own measurements.
The probe remains `/tmp/ipse-managed-recipe-20261026-01/footprint.{exs,log}`.

## Actual verification and preserved first outcomes

The focused harness compiles the three source modules and their new test files
with `Code.with_diagnostics/1`, failing on any warning/error. It uses read-only
existing dependency/runtime BEAMs from
`/tmp/ipse-collection-call-build-20261026-07`, and writes only its own replacement
modules under `/tmp/ipse-managed-recipe-20261026-01/managed_override/ebin`.
That directory name deliberately does not masquerade as the `ipse` application.
The existing actual protected-admission fixture uses its unchanged private helper
108c and an isolated operator home; it does not invoke a terminal or inference.

| Log under `/tmp/ipse-managed-recipe-20261026-01` | Actual result |
| --- | --- |
| `tests-first.log` | 32 pass, but compiler warned about stale original BEAM export metadata; not accepted as warning-clean verification |
| `tests-second.log` | Strict compile clean, 31/32; replacement ebin under an `ipse-*` application-shaped root shadowed native `priv`, so actual protected identity correctly refused |
| `tests-third.log` | Corrected private override path; diagnostics empty; 32/32, actual protected branch verified |
| `tests-fourth.log` | 32/33; new synthetic SDK-2 identity lacked its mandatory `invoke.result.pages` capability |
| `tests-fifth.log` | Fixture corrected without weakening Registry; 33/33 |
| `tests-final.log` | Final 33/33; seed 20261026; 1.0 seconds; source and test diagnostics empty; actual protected branch verified |
| `compile118-final.log` | Three modules compile under Elixir 1.18.5 with empty diagnostics; host OTP 29 |
| `format118-final.log` | All seven owned code/test files match Elixir 1.18.5 formatting |

Elixir 1.20.4 focused compilation and formatting also pass. No OTP-27, full suite,
installed runtime or model-quality claim follows. The legacy SemanticConsent
suite remains included. Fixtures test actual capture schemas, canonical
Unicode/escaping identities, literal/paraphrase distinctions, exact proof
membership, typed-outcome restrictions, refusal of untyped override choices,
explicit v2 prepare/admit/authorize/resume, missing/aliased/mixed registries,
unchanged settings/depth limits, activation absence, collisions, child widening
and route substitution.

The complete collection SDK developer chapter was reviewed and integrated around
validation/admission ownership. Operator procedures remain unchanged because
the live activation/managed adapter is not connected by these pure functions.
The documentation checker result is recorded with the component handoff.

## Independent read-only storage review

At the parent's request this author also read the four Core atomic-managed
storage files and three matching test files before its checkpoint. No concrete
correctness issue was found in that limited read: original CAS/duplicate/fence
checks precede normalization, exact original changes remain a subset, extra
non-null keys are reserved/bounded, read closures are process/token/cap-bound,
explicit v5 roots preserve managed hashes through imports, canonical decoding
rejects downgrade and flat legacy decoding refuses new receipt fields.
The parent's Core test execution was not repeated or claimed by this component.
This read is not the full independent post-implementation audit. Semantic
normalization, reserved-prefix denial, every-dispatch revalidation and successful
publication pairing still require their actual integrated controls.
