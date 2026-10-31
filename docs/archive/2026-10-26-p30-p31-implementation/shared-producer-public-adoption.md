# Public Corpus first-page adoption — 2026-10-29

Production Corpus `generation_produce` action `page` now delegates to the existing
guarded producer. This adoption follows the accepted
[actual Session review](shared-producer-guard-session-independent-review.md),
[finite-TTL review](shared-producer-finite-guard-session-independent-review.md)
and [minimal reopening direction](shared-producer-public-page-reopening-direction-independent-review.md).
Those native controls executed private artifact `8de1ae…b229`; this new canonical
artifact is qualified by source/contract comparison, strict build and focused
protocol controls, **not by a repeated native positive**.

## Change and checks

The production Corpus AST equals the private tested Corpus AST, ignoring location
metadata. Adapters source bytes are identical. Producer differs only by removing
the obsolete selection coverage `source_dispatch_available: false`: configured
profile metadata establishes neither unavailable dispatch nor current admission.
No replacement availability field or readiness API is invented. Configured model
metadata still has `reported_model: nil`; actual responses undergo the existing
model/input/vector checks.

The explicit generator flag `--collection-source-use shared_producer_v1` emits
binding v2 only for `corpus/collection-dense` with a Collection store. Its absence
preserves exact v1 bindings and existing call defaults. The existing
`--inference-config` now accepts an explicit map-valued `inference_services`
registry alongside profiles and budget and passes it unchanged. Normal Host
configuration validation supplies the existing closed registry semantics; the
generator neither discovers nor chooses a service. Invalid source-use choices,
wrong presets/packages and non-map registries refuse. Generated instances remain
disabled until explicitly selected.

| Focused check | Result |
| --- | --- |
| 47222 strict canonical build/Catalog | Passed before the later selection-field correction; retained as the first build. |
| 47223 public entry protocol | One case passed, 21 excluded; public delegation equals direct Producer continuation; forged extra input refuses without an effect. |
| 47224 configuration | One case passed; default-v1 exact compatibility, explicit-v2 binding, unchanged configured model/service map and existing Host closed service validator. |
| 47225 final strict canonical build/Catalog | Passed after removing obsolete availability coverage. |
| 47226 final public protocol/selection shape | One case passed, 21 excluded; additionally proves read-only selection supplies no availability claim or observed model. |
| 47227 actual config generator/static relation | Passed; invokes config.exs, validates generated extension selection and service registry with existing Host validators; canonical descriptor shapes equal native-tested private artifact. Zero inference/storage effects. |

Final canonical artifact manifest SHA-256:
`a7eba4d0daf79bcd6ec2d268a22b12e41b16bdae55d839f17284372218b8a5e6`.
It is retained at `_build/shared-producer-public-adoption-20261029/artifact-current`.
An earlier native gate test is retargeted to read-only public `inspect` on an
absent claim; its new assertions are formatted, but that longer Session fixture
was not rerun in this adoption. Its old gate receipt remains historical. Default
guarded Session fixture builds now use canonical source; prior exact private
fixture source/artifacts remain frozen in the native receipts.

## Authority and limits

Binding v2 restricts **every embedding request** from that instance to authenticated
source use. Use a separate v1 instance for ordinary unguarded query embedding.
The public route supplies the same v3 range claim, mandatory selection pin and
closed guard as the actual native-tested private route. Host still requires the
same live invocation's confirmed real claim commit, known batch sequence, current
source/job/catalog/root and final one-use admission after approval. It does not
accept a worker-supplied committing operation ID or a resumed/adopted claim.

An unsupported v1 binding can leave an approved inert pending claim and then
refuse guarded inference without egress. Inspect it; there is no automatic retry,
adoption token or provider/billing/namespace fallback. Later pages, facts, headers,
group completion, full public producer accounting, populated capacity/rebuild,
GC/migration and representative Word quality remain required work. Executed
receipt validation does not change historical model-provenance claims.

The operator Corpus and developer knowledge/Collection chapters integrate setup,
registered routes, exact selectors, full approvals and recovery around their
existing procedures. No whole-repository test or docs checker was run here;
the parent owns the batched documentation check.

## Provenance

[Manifest](shared-producer-public-adoption/manifest.json), SHA-256
`2b503a998c9eaa03dd3b3a878fd2c2a9dbdcd33e40d35209e05ca896ad16c098`, pins 14 source/manual
snapshots, two scripts, three generated synthetic configuration files, nine log
snapshots, both 26-file artifact inventories and native-cohort/review ancestors.
The log wildcard also retains two earlier historical gate logs and an empty
in-progress freezer-log snapshot; neither is credited as a new passing check.
[Verifier](shared-producer-public-adoption/verify.exs) and
[log](shared-producer-public-adoption/verify.log) check exact hashes only. Runtime
and native helper remain bound by the reviewed actual Session ancestors; no Core,
native, quota, platform admission or model-service change occurs in this slice.
