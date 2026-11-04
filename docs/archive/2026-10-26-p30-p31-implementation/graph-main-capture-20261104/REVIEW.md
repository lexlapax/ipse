# Main-model relationship capture over existing State sources

2026-11-04. Isolated extension-only candidate; not applied to main. P31G remains
open. This increment implements a model-visible `capture` tool without an extra
model request, core changes, dependencies, capabilities or new permission paths.

## Data and effect path

The ordinary main model supplies an existing source ID/generation and one to
eight proposed relationships. Each proposal includes subject/predicate/object,
positive or negative polarity, an explicit inferred flag, optional validity
interval and a unique exact support quote. The worker independently loads the
existing State partition snapshot, selects the exact current source/generation,
derives source/chunk/span/hash citations, and constructs existing Evidence facts.
It refuses missing/ambiguous quotes, unsupported fields, malformed facts, more
than two selected chunks, expired/historical sources and nonexplicit profiles.

The existing Graph extraction path then performs Store projection_open,
explicit Adapters extraction and projection_commit. Generation/revision CAS and
the existing source, draft, byte, effect/read and publication limits remain in
place. Source updates between the initial snapshot and projection claim refuse.
Projection history retains prior facts and deduplicates unchanged fact IDs.
Denied/unknown effects stop the invocation; no retry or continuation is added.

## Existing reused semantics

- Evidence.fact/citation and Store.projection_open/commit own source binding.
- Evidence preserves negative polarity, inferred claims, validity intervals and
  contradictory context; quoting bytes does not prove semantic truth.
- Existing source replacement invalidates prior-generation facts. Existing
  source forgetting suppresses the source and prevents later capture.
- Query revalidation and existing public uncertainty labels remain unchanged.
- All writes remain ordinary State mutations, requiring the host's existing
  approval. Source text remains attributed data, not an instruction or grant.

## Qualification and limits

Ten isolated extension protocol controls pass. They use the established
constructed State host fixture, no application, native input, provider service
or model. They cover the model-visible descriptor/schema; citation derivation;
forged/ambiguous quotes; generation mismatch/race; source expiry; malformed and
oversized requests; explicit-only profile; polarity/conflict/inference/time;
source correction/forgetting; accumulated facts; and denied/unknown stop.

The first control run had two fixture expectations of an empty claims array.
Existing ResultPublication deliberately emits an open, semantically unassessed
placeholder when no claim is supported. Those expectations were corrected;
the failed first log is retained. No product guard was changed to pass them.

This is stored-source-bound capture, not automatic admission from live
conversation quotes, saved notes or original files. A State copy's receipt is
not original/native current-use authority. Session.Invocation's managed
State-write refusal remains unchanged: after managed notes enter the causal
union, this tool must not bypass that refusal. Full managed graph capture needs
a reviewed publication/current-use API contract and real Session qualification.

Reversible aliases/merges are still missing. Existing string entity identifiers
are not a qualified entity-resolution strategy; names must not be assumed to
identify the same person or object. No alias, false-merge or graph extraction
quality score is claimed. The graph feature remains optional/experimental.

The exact artifact also passes one fresh actual ordinary-State Session cohort
on the complete, previously frozen private 16-app/241-module SDK (not a newly
built main runtime):
scripted main-provider tool selection, real outer-tool and State approvals,
known fact publication/query, wrong-generation refusal before writes, denied
State claim with byte-identical State files, and owner interruption at the
incoming successful State.put result before it is journaled. The interrupted
write may be a projection draft/root claim; no final-fact commitment is claimed
for that case. Both strict Saved reconstruction and actual fresh idle resume
preserve the intent count without replay. Positive and interrupted cases each
modified one State file; wrong-generation and denial cases modified none.

All input/full-private-runtime/pathset postchecks pass. The artifact is 9,928
manifest bytes with 26 modules and 333 unique resolved imports. Decode/import
pass and capabilities are unchanged. No dependency was added. The actual uses
an in-process scripted provider, not a live model or service; no input channel,
HTTP request or external service is used. Installed behavior and useful real
main-model extraction remain open.

The first actual stopped correctly at its ordinary outer main-tool approval,
which the reused command-only fixture did not handle. It completed only the
source seed: five known State writes and no Graph tool invocation. Its source,
logs and root remain preserved. A relative-versus-absolute pathset comparison
also reported a false difference; exact normalized pathsets and all runtime
hashes matched. The fresh second cohort fixed only those fixture boundaries;
the product/artifact remained unchanged. Both actual fixture roots remain retained.

The simultaneous P30 cohorts remain failed and separate; their partial
pool-exclusion evidence does not qualify delivery.
