# Record-only observation and refresh experiment

2026-10-27. Working-tree component work for P31C0; this does not establish the
[P31](../../plan.md#p31-usable-knowledge-and-prompt-assistance) current-authority
barrier or qualify recall.

The existing public Collection `get` result includes the root generation. A
worker can use that field, so an unchanged selected record alone cannot prove
that an old derived message is unchanged after a new root. The internal
`Collection.ObservedRead` now also accepts a distinct `get_record` request. Its
value is exactly the selected public record or nil; the same-view root witness
stays separate. It rejects reserved metadata keys and extra arguments. This is
not an exposed extension SDK operation or a permission grant.

The pure `ManagedReference` version-4 shape binds the key, this exact request,
complete delivered-result digest, record identity and normalized validity. It
allows a later monotonic root only when those observed result and record bytes
remain bound, validity retains its lineage and supports, and expiry does not
extend. An absent result has a fixed nil-result digest. Same-generation root
substitution, rollback, altered result or record, changed pin, ineligible status
and extended expiry refuse. Versions 1–3 continue to require the same root. The
version-4 shape itself does **not** authenticate a host observation, pin,
validity or source: a caller can construct matching JSON. Before using this for
recall, Session must authenticate the owned same-view observation and complete
delivered result, journal and replay their binding, prove current validity and
suppression history, propagate all other reads and descendants, and hold the
necessary authority through actual dispatch. An unconfined worker or an omitted
root-bearing read still defeats selective reuse. These are open requirements,
not assumptions that this component satisfies.

Pure projection, replay, reference and source-window controls passed 73 tests
(seed 46486). The observed-read, view and directory selection passed 45 tests
(seed 46485) with an isolated test-only kernel override. A subsequent 14-test
observed-read run (seed 46487) combined actual synthetic Collection observations
with a manually constructed version-4 dependency and synthetic validity: an
unrelated write retained the record-only result and a selected-record update
refused it. The latter is not an authenticated Session admission, native-profile
qualification, live recall or an independent audit.

The final combined observation, directory, view, managed-reference and replay
selection passed 120 tests (seed 46488) in that diagnostic graph. It includes
record-only owner-loss refusal; the two affected module hashes matched the
working tree. The test-only helper and synthetic validity limits still apply.
An added same-floor anchor and floor-regression control passed with the 74-test
pure projection/reference selection (seed 46489); a higher floor still needs
authenticated history, which the pure check does not provide.

The internal `record_dependency/4` constructor now derives version-4 fields
from the selected request, observation and supplied pin/validity. It bounds the
observation, checks request and result digests, verifies the returned record's
canonical bytes against its stored hash and size, and checks that the decoded
root re-encodes to the witnessed root hash. This last rule conservatively refuses
a readable root stored with different JSON formatting; a synthetic test covers
that compatibility limit. A fabricated but self-consistent root or caller-supplied
validity can still pass: a digest is not provenance, and this function does not
read authenticated validity from the same view. The earlier manually assembled
projection test now uses this constructor. Sixteen observed-read tests passed
(seed 46494) in the private test-only-helper graph, including changed record,
oversized value, mismatched root, absence and noncanonical-root controls. Durable
receipt ordering, Session ownership, suppression history and current dispatch
authority remain open.

## Same-view signed metadata read

`ObservedRead.managed_record/6` now obtains a literal `note` record, format
record, selected live page and selected anchor page through the same
root-rechecked view inside an existing domain-auth callback. It verifies both
page MACs, the format MAC, the live record's value hash, lineage, category and
the anchor's first-admission/deadline clocks. It refuses missing records,
pending/history keys, retirement and stored retention choices. The returned
metadata is **not an eligibility decision**: the caller still must authenticate
sources and suppression history, recheck consent and expiry, establish lineage
and retain authority through use. The view closes before return, so the witness
is historical. The function is internal and is not wired to Session or the
extension SDK.

An adversarial synthetic fixture added an `override.<lineage>` record alongside
an otherwise valid signed note. Before the fix, the reader returned the note
despite that record (seed 46506). It now reads the override in the same checked
view and refuses any non-nil value, including malformed or benign overrides.
This is provisional fail-closed behavior, not an implementation of retention
choices or proof of suppression history.
The managed-publication, observed-read and view selection passed 56 tests after
the change (seed 46507) using the isolated test-only kernel helper; this does
not qualify the production native profile.

A subsequent adversarial control used a valid recipe with a different override
prefix. The fixed-prefix reader still returned the record (seed 46509). The
reader now takes the selected literal recipe, checks its digest against the
signed live page, and checks its override key in the same view. A different
recipe cannot select an empty override key while claiming the signed recipe.
This remains an unwired historical observation, not an eligibility decision.
The managed-publication, observation and view suites passed 56 tests (seed
46510); the alternate-prefix positive and suppression controls passed after
that suite (seed 46511). Both used the isolated diagnostic helper.

In the isolated test-only-helper graph, an actual managed publication produced
a signed record and matching pages; an unrelated publication preserved its
record and metadata under a different root. Replacing a live-page MAC via a
separate trusted Collection fixture caused refusal (seed 46496); replacing an
anchor MAC likewise refused (seed 46500). A native-owner-loss test first expected
an ordinary error, but the enclosing Identity operation reported
`project_identity_lock_lost` as **unknown**; the corrected control passed (seed
46498) and returned no record. The broader signed-metadata, observed-read and
view selection passed 54 tests (seed 46499), before the additional anchor
control. These tests use synthetic sources and the unqualified private kernel
override; they do not prove current source eligibility, Session admission,
race-free dispatch or production filesystem durability.

## Deriving the record dependency from managed evidence

A later integration control creates a synthetic interactive input receipt in a
real Journal Writer, derives its source proof, uses that proof in an actual
managed publication, closes and restores the journal, and revalidates the
proof before deriving a dependency from a same-view managed read. An altered
stored proof refuses. The focused control passed (seed 46514) in the isolated
diagnostic graph. Two earlier runs used an older graph that did not contain
the stored-proof query and refused at that query; the current Writer and
SourceIndex were then copied into the graph. The input observation and pin are
synthetic, the owner is the test process, and the test does not exercise the
Session action lifecycle, current consent, worker confinement or dispatch.
The combined source-index, journal, managed-publication, observation and view
selection passed 76 tests in that updated graph (seed 46515).

The internal `managed_dependency/6` constructor now checks the managed result
against the selected literal recipe and the exact source proof supplied by the
host. It derives the version-4 validity fields from that proof and the signed
metadata rather than accepting a separate free-form validity map. It checks
lineage, category, recipe digest, first-admission time, exclusive expiry and
the recipe's maximum age. It refuses missing or mismatched source proofs,
foreign namespaces, changed recipes and extended deadlines. The current
literal recipe also refuses older fragment-only evidence. The dependency retains
the historical publication-policy digest from the signed page and refuses a
refresh that changes it. Current consent need not have that historical digest;
the caller must independently establish that current consent permits the operation.

The same-view integration fixture now derives dependencies from two actual
synthetic managed reads and checks pure projection across an unrelated write.
Its source proof and pin are fixture inputs, not authenticated live Session
authority. The signed metadata, observation and view suites passed 55 tests
(seed 46502) in the test-only-helper graph. A caller can still fabricate a
self-consistent managed-result map or provide stale/forged source proofs; this
constructor checks consistency and does not authenticate those inputs. The
missing durable owned-read receipt, source-currentness and consent checks,
worker confinement/lineage, and authority-holding dispatch remain essential.

The signed-record, observation and projector selection passed 70 tests (seed
46503) after adding the historical publication-policy binding. The version-4
shape remains an uncommitted internal experiment; no released compatibility or
production source/consent verification is implied.

A later [historical-record repair](capture-fragment-followup.md#historical-signed-observation-repair)
adds structural recipe revalidation to signed literal observation. Old signed
native-answer and partial-source literals are refused through that path. The
embedded proof remains unauthenticated for current use, generic raw reads are
unchanged, and none of the delivery and lineage boundaries above is resolved.
