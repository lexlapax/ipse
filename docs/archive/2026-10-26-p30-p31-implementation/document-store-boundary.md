# Document Collection boundary — 2026-10-28

This is synthetic available-host component evidence for the first P31C1b
backend increment. It does **not** qualify the accepted 1,000 sources / 20 MiB
extracted evidence / 10,000 chunks / 5,000 entities / 20,000 assertions profile,
its complete 256 MiB peak, migration, rebuild, turnover, or installed Word use.
Current operator procedures remain in the [Corpus manual](../../operator/corpus.md)
and [permission manual](../../operator/knowledge-permissions.md). Full acceptance
remains in the [plan](../../plan.md).

## Fixed profile and explicit authority

The reviewed generic SDK gap uses existing Collection records, manifests,
generation/revision CAS, native filesystem transactions, and retained locks.
Ordinary notes callers retain their original 6 KiB value / 24 MiB data / 64 MiB
total budgets. A separate fixed `document_graph_v1` profile permits 64 KiB
internal values and 160 MiB logical data. Its native allocation is at most
192 MiB, reserving the complete existing 64 MiB notes envelope within the
256 MiB target. These are host constants, not worker quota arguments. Their
population and peak qualification remain open.

The document profile is included in the hashed root pointer and trusted read
cache. Notes/legacy roots refuse document interpretation, and document roots
refuse notes interpretation. There is no implicit root migration. Native
transaction ceiling validation now admits the fixed 192 MiB maximum; existing
notes/control callers retain their existing requested ceilings, and existing
filesystem/kernel admission and transaction geometry remain unchanged.

An independently registered operator instance must explicitly declare the new
`host.collection.store` capability and receive this trust entry:

```json
{"collection_bindings":[{"version":1,"instance":"documents","id":"documents","scope":"project","profile":"document_graph_v1"}]}
```

The worker request is closed:

```json
{"op":"collection.store","scope":"project","request":{"op":"snapshot"}}
```

The host resolves only an already admitted ProjectIdentity outside Session,
then Session binds its exact identity, request, current job and session before
journaling an action. The dedicated namespace is derived only from that project
and the fixed profile, so aliases and artifact revisions cannot multiply the
allocation. Final execution rechecks the owned intent and existing project
binding. Mutations use normal full-argument approvals; headless denial remains.
No SemanticAdmission or saved note consent is reused, and no workspace, shell,
MCP, path, quota, profile or project-admission authority is granted by the request.

The optional `collection_binding` identity field is inserted only when selected.
Old identities retain their original absent-field shape and digest. A synthetic
retained earlier-host identity passes inert projection replay and fails fresh
runtime admission. Explicit `collection_binding:null` is rejected.

## Bounded inbound values and reclamation

An ordinary SDK object remains limited to 16 KiB, strings to 8 KiB, and depth
to 12. Large values cross `value.open`, exact-offset `value.append` parts,
`value.seal`, and one consuming `commit`. A body is at most 60 KiB, each raw
part at most 6 KiB, with at most ten parts. Actual encoded SDK envelopes must
also fit their unchanged bounds; escaping is never silently truncated.

Sixteen fixed reusable slots contain a header, bounded parts and sealed value.
Each header binds a random epoch, project/session/artifact identity, opening
invocation, target key/revision, original byte count and complete raw SHA-256.
Explicit continuation by the same session and identity retains opening-invocation
provenance. Seal checks ordered offsets, full original bytes/hash, duplicate-safe
JSON decoding and the existing complete ResultDocument validator. It atomically
publishes the sealed value and removes its part records. Commit consumes up to
eight sealed refs and atomically publishes their selected values while deleting
their ready/header records. The internal plan is bounded to 32 changes; the old
notes public eight-change contract is unchanged. Values remain unselected until
that final CAS. Competing generations, wrong revisions, epochs, owners or digests
refuse; nothing is retried automatically.

`value.read` returns bounded UTF-8 fragments of the exact original encoded body,
with complete hash, count, offset, next offset and revision. `stage.list` exposes
bounded stage descriptors. Slots expire after one hour on the host clock.
Expired append/seal/commit requests refuse. An admitted explicit `value.reclaim`
requires the exact expired slot epoch and removes its retained header, ready
value and parts in one CAS. It can reclaim an abandoned prior Session's slot;
live slots cannot be reclaimed. Explicit abort remains available to its owner.
No idle or disabled-feature background cleanup runs. Stale epochs cannot alter
a reused slot. The finite 32,768-operation ledger remains unchanged and must be
included in eventual build/rebuild/turnover measurement.

Outbound ResultPublication pages do not provide inbound staging. Whole-store
Collection migration fences writers and requires complete value arguments, so
it cannot implement this bounded inbound SDK path. This adapter reuses OTP,
Ipse JSON/ResultDocument, and Collection rather than adding a database, package,
workflow framework, or a second native persistence protocol.

## Declared draft expiry repair

The independent frozen locator review found an inherited defect: a valid stored
source draft with `expires_at_ms:0` could still append metadata. Source and
projection continuation/publication now check the stored deadline before each
proposed mutation. The State adapter also carries the existing generic
`write_before_ms` condition on each staged page/root put, including final CAS,
so approval waiting cannot bypass native State expiry checks. State checks
under its lock and after staging immediately before rename. Abort and explicit
expired-claim cleanup remain available without that expired condition.

Collect first CAS-clears one expired draft claim while retaining the selected
source; a subsequent explicit collect may reclaim the resulting orphan pages.
Pages stay protected until their root drops its references. This preserves the
existing selected MCP CAS service's root/reference contract. MCP request fields
are unchanged: its deadline checks remain client-side before dispatch, and this
section does not claim server-side publication expiry. An already dispatched
unknown remote effect remains unknown and is never replayed.

## Focused evidence and provenance

The [manifest](document-store-boundary/manifest.json) binds 25 source files,
207 tested host BEAMs, the actual private helper, fixed budgets and retained logs.
Source snapshots are retained under
`_build/document-store-boundary-20261028/sources`; the isolated host graph is
`/tmp/document-store-host-20261028`. The helper was built with Rust edition 2021
and warnings denied. An unchanged Runner source copied into that graph binds its
compile-time helper hash to this fixture binary. No production helper, kernel
admission, existing benchmark store, or primary test graph was changed by this
section.

- Profile/root controls: [46782](document-store-boundary/profile-46782.log),
  five passed. Both directions of root-profile refusal, exact >40 KiB internal
  read view, reservations, unknown budgets and oversized strings are covered.
- Reusable stages: [46794](document-store-boundary/stage-session-46794.log),
  eight passed across stage and Session controls. The actual 36.9 KiB body crosses
  seven parts; offset/owner/digest/duplicate JSON refusal, prepublication absence,
  exact reads, slot consumption/reuse, finite expiry and explicit reclaim pass.
- Final coherent shared host: [46802](document-store-boundary/cohort-46802.log),
  four Session controls passed. Every actual request/reply fits existing SDK
  envelopes; ten mutations display full approval arguments. Missing explicit
  grants, altered profile grants, normal denial and absent project admission
  refuse. Native publication-owner loss during append produces a journaled
  unknown, stops before seal, and resumed Session leaves files and journal
  byte-identical. Successful read namespace binding is checked.
- Expiry repair: [46795](document-store-boundary/expiry-46795.log), two passed
  with 49 excluded. Old/new sources and projections reject expired writes,
  preserve selection, allow abort, and release expired claims before collecting
  pages. An actual document-stage approval held beyond expiry receives native
  `write_deadline_elapsed` with unchanged records/generation and replayable
  historical receipt. Final shared-host queued-expiry and legacy identity replay
  controls also pass in [46801](document-store-boundary/cohort-46801.log).
- Native maximum/refusals: [native control](document-store-boundary/native-ceiling.log),
  one exact Rust test passed; 64 MiB and 192 MiB accepted, zero, excess and integer
  maximum refused. [Strict current host compilation](document-store-boundary/compile-current-cohort2.log)
  passed without diagnostics. Focused formatting and diff-whitespace checks pass.

Initial failed controls are retained. They exposed fixture revision/response/
historical-admission assumptions and a missing Mix bootstrap in the isolated
compiler; they are not capacity evidence. The independent audit additionally
found that Collection unknown publication outcomes were being mapped to known
failure in the new wrapper. That implementation defect was repaired and exercised
through the actual native-loss Session control. Frozen earlier locator evidence
is not retroactively relabeled as expiry-enforcing code.

## Remaining implementation and qualification

This first increment supplies the explicit host boundary and bounded packed-value
transport. Corpus/Graph still require an extension Store adapter, packed catalog
and selective authenticated hydration/query, logical population accounting,
complete staged rebuild/migration and measured full-profile acceptance. Current
State/MCP Corpus behavior and existing Word source limits remain separate from
this backend. No full capacity, performance, installed/native Word quality,
external account, or production kernel qualification is claimed.
