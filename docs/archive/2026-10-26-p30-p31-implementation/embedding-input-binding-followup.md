# Embedding input binding follow-up

2026-10-27. This is an uncommitted adapter correctness repair, not local-model
identity, protected knowledge, retrieval quality or P31 qualification.

The corpus adapter previously accepted any well-formed input hash in a vector
page as long as it stayed consistent across that vector's pages. A synthetic
two-input control returned the second input's host-canonical hash on the first
vector: the adapter accepted it and assigned the vector to the first chunk.
The isolated package test failed as expected before the repair (seed 46416).
This demonstrates an unchecked mismatch in synthetic host results; it does not
show that the current trusted host produced a mismatched result.

The adapter now computes the public SDK canonical digest of each exact input it
dispatched and checks it on every result page before accepting coordinates.
Tests cover swapped first and second vector hashes, a changed hash on a later
page, valid Unicode inputs, multi-page vectors and invalid numeric coordinates.
Synthetic fixtures that had used opaque or raw text hashes were corrected to use
the host's canonical input digest. The corpus, graph, storage, evidence, profile,
adapter and provider selection passed 92 tests, seed 46418. A separate run passed
13 tests, seed 46419, including a newly built `corpus/state-dense` artifact
probed with a minimal public SDK. The latter also includes the later multi-page
and built-artifact controls; the 92-test run predates those test-only additions.
The built-artifact Session lifecycle suite also passed three tests, seed 46420,
using local synthetic providers for forget races, interruption, quota, failures,
endpoint changes and explicit reindex. It did not call an actual model.

This binds returned pages to their dispatched inputs. It does not authenticate
arbitrary pre-existing stored rows, prove provider honesty, identify model weights,
bind a future preprocessing template, or establish current source/consent
authority. The P31 storage, model-identity and retrieval gates remain open.

## Existing stored rows at query time

A subsequent synthetic corpus control supplied a structurally valid stored
vector with the current chunk ID and compatible model selection but a different
input digest. Dense retrieval used it before this repair (seed 46421). Corpus
now compares that digest with the SDK canonical digest of the current raw chunk
before selecting the vector. A mismatch follows the existing missing-embedding
policy: strict dense/hybrid queries refuse, while explicit lexical fallback
reports a partial result and a gap. The row remains stored and may be replaced
by an explicit reindex; no historical source or vector is silently deleted.

The isolated package, built corpus artifact, domain regression and provider
selection passed 13 tests, seed 46422. The additional lexical-fallback control
passed in the isolated package test, seed 46423. These controls establish the
current raw-chunk binding; a future preprocessing recipe needs its own versioned
binding. Matching a digest does not authenticate the provider or its weights.

An expanded selection on seed 46424 finished with 95 of 96 tests passing. The
remaining graph-fusion fixture launched the evidence module without the public
SDK on its code path, causing a compiler warning to contaminate its JSON output.
The fixture has been corrected to include the SDK; the failed run is not a
passing full selection. A focused rerun of the graph-fusion, built-artifact and
package selections passed five tests, seed 46425. The corrected expanded
selection passed 96 tests, seed 46426; native sandbox and other platform tags
were excluded. This is a focused selection, not a full-project qualification.

## Projection admission and older rows

Store previously accepted a new structurally valid vector whose digest belonged
to another input. A two-chunk State fixture demonstrated the acceptance before
the repair (seed 46427). Store now validates every vector against its source
chunk before publishing the projection; a mismatch refuses the whole commit.
The store fixtures' former opaque hashes were replaced with host-canonical
input digests. A first positive retry on a two-chunk MCP fixture hit the
existing effect limit (seed 46428); the corrected control uses two chunks for
State and one for MCP, matching their supported batch sizes. It passed on seed
46432 and verifies the failed commit changes no stored records. A separately
constructed, self-consistent old mismatched row remained readable and was
successfully replaced by explicit reindex on both synthetic backends (seed
46431). A broader eight-file storage, corpus, graph, built-artifact and Session
fixture selection passed 51 tests (seed 46430); it started before the later
recovery control and the two-chunk expansion, which were run separately as
described above. Platform-specific tags were excluded. These fixtures do not
authenticate the provider or model weights, and are not a full-project regression.

## Session upgrade control

A separate synthetic upgrade control builds two corpus artifacts. The first is
deliberately altered in an isolated source copy to admit and store a wrong input
digest; it models the old storage shape rather than claiming to be a released
historical binary. A real Session indexes through a local fixture provider and
closes. A fresh Session with the current artifact and the same isolated State
binding refuses dense retrieval, returns explicitly partial lexical fallback
with a missing-embedding gap, reindexes, and then retrieves densely. The test
also checks fixture-request consumption and confirmed Session cleanup. It
passed on seed 46433. The expanded control, seed 46435, additionally removes the
query guard from the deliberately altered artifact and shows that it retrieves
the mismatched vector before upgrading. All four updated lifecycle tests passed
on seed 46436. The host does not load the domain modules, no actual model is
called, and this does not prove protected Collection or model identity.
The affected six-file storage, package, provider and lifecycle selection passed
60 tests on seed 46434; it started before the additional old-artifact query
control, which was verified separately as described above. Platform-specific
tags were excluded.
