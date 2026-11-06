# Publish retained sources through bounded transactions

Choose the owner before changing retained storage. Protected native capture uses
the authenticated schema-3 Collection path through its explicit SDK version.
The current Session publisher admits one new V3 record; a historical V2 managed
object remains valid protocol data but refuses live publication before intent or
reservation. The separately admitted unmanaged `collection.call` publisher keeps
its own permission and execution checks. Follow the
[SDK capture boundary](collection-sdk.md#follow-one-capture-across-its-owners)
when selecting a host route.

Corpus/Graph/Research source stores use explicit State or remote CAS contracts;
the experimental document Collection uses a separate fixed profile and host-owned
stages. Choose that profile's [publication fence](#fence-document-stages-before-metadata-maintenance)
before changing its metadata. None of these owners treats a successfully written
orphan page as published content. Start with
[retrieval training](knowledge-extensions.md) and the
[operator source workflow](../operator/corpus.md).

For source stores, read `extensions/knowledge/src/store.ex`, its `store/state.ex` and `store/mcp_cas.ex`
adapters, then entrypoint source/projection continuations. The adapters propose
approved host calls rather than opening storage or network connections themselves.
Generic State knows opaque values/revisions, without enforcing domain root counts
or inspecting note/source fields. The operator's
[explicit Memory workflow](../operator/memory.md) retains that State contract;
[native knowledge permission](../operator/knowledge-permissions.md) does not
implicitly migrate State records or admit them to protected native recall.

## Publish one fresh record with authenticated metadata

Start with `Collection.NormalizerV3`, `Collection.ManagedPages` and its local
`Planner`. NormalizerV3 prepares an unchanged public insert plus authenticated
sidecars; `Collection.execute_managed_v3/6` performs the atomic storage commit.
These are internal host components. A worker's `metadata_version: 3` request must
pass the Session's new-record shape gate before `ManagedCollectionCall` can
dispatch it to this interpreter. The older `Collection.execute_managed/6` and
version-2 Normalizer retain their historical protocol; their presence does not
open the Session publication gate. A version field supplies no domain capability
or saved permission: the host still checks the exact selected recipe, sources,
effect mapping and admitted new-record shape.

The owning adapter must authenticate original sources and current protected
permission before entering Identity → Consent → Collection. Pass the actual
Identity callback's scoped `domain_cap` and `catalog`, and the actual held
Collection `witness`/`read` closure. A matching shaped map proves none of that
provenance. NormalizerV3's exact options are `request`, `recipe`, `constraints`,
`verified_sources`, `policy_sha256`, `now_ms`, `domain_cap` and `catalog`.
It verifies the recipe/constraint/request bindings and authenticated evidence
members, then checks format and selected page MACs before interpreting old rows.

Only one fresh revision-zero public record is supported: a literal at
`note.<lineage>` or a proposal at `pending.<proposalidentity>`. The original
commit must explicitly advance the destructive import floor. Literal categories
are ordinary, preference or current; a proposal remains `never_current` even
when its text quotes a native source. Existing public values or retained live
identities and exact candidate rejection markers refuse. No replacement, typed correction, pin, forget, retention
change or stored choice/retirement is admitted by this automatic interpreter.

First use needs native-confirmed absence and the matching prepared Identity
catalog. `ManagedCollectionCall` uses the two-argument publication authorizer:
Identity selects fresh or active state under its retained lock before supplying
`fresh?`. The authorizer checks sources and policy, and for fresh state checks
actual absence in one ReadView, closing it before Identity writes prepared state.
It never infers absence from a busy verifier or another probe's failure. Inside
publication, Collection checks absence again under its actual native owner.
Initialization emits format plus the anchor and live zero-fence pages. An active
catalog requires the exact authenticated format already present. An existing
root with missing format, unsigned V2 pages or a disappeared active store refuses.
A prepared catalog also refuses rather than replaying the first attempt. No
implicit adoption, reseal, reset or import path exists. Follow the
[Identity callback contract](persistence.md#keep-project-domain-attestations-private)
for selection, authorization and activation ordering.

Keep final Identity activation separate from a successful inner Collection call.
Before returning a first-publication witness, the host opens one new actual
ReadView, checks current root and receipt generation/operation/revisions/value
hashes, verifies the format MAC, and closes it successfully. Changed page values
are bound by their hashes to the normalizer's captured, host-sealed output; this
post-publication read does not separately reopen their MACs. The witness binds
that actual root hash and the catalog fence. Native-owner loss
after Collection committed can leave durable data with Identity still prepared
and an unknown outer outcome. Inspect it; never replay or infer activation from
the inner success alone.

### Preserve clocks and bound each local repair

The anchor retains separate literal and proposal first-admission/baseline clocks.
Later policy can shorten a deadline; recapture, reading or a persistent category
cannot renew it. Admission at or after the retained deadline refuses. Null
deadline is supported only where the reviewed recipe permits persistence.
Worker clock fields do not establish host time or authority.

Live rows preserve all four exact hashes: lineage, current value, historical
recipe and historical publication policy. They also retain first/deadline and
category/eligibility. Historical policy need not equal today's checked policy.
Pages authenticate their actual Collection key, operation ID, revision and raw
body through the private Identity domain key. A new page binds old **global
generation + 1**, even when the inherited page has an older revision. Every
selected nonsingle leaf is checked for its immutable minimum occupancy and range
before a local repair. Parsing a management capsule mints no review authority.

Every lookup uses the actual shared closure. A neighbor request costs four units
including nil positions; a selected value costs another. NormalizerV3 enforces
the closure's 32-unit ceiling and caches repeated exact requests only within
that unchanged held callback. Proposal admission includes its rejection-marker
absence and bounded pending-summary checks. The combined anchor and
live plans permit at most five metadata changes: four nonnull values and one
deletion with its exact positive old revision. Format is never rewritten or
deleted. Every complete wrapped value remains at most 6144 bytes; the closed
normalization receipt is at most 2048 bytes and lists the exact extra changes in
publication order, including canonical value hashes and null only for deletion.
The SDK reserves four full sidecar values and one possible deletion for version
three, including complete envelopes and normalization bytes. Version two retains
its two-sidecar reserve. Neither version admits an arbitrary plan or raises the
Collection read/repair limits. Native reviewed management uses its separate
[retained-target contract](collection-sdk.md#manage-a-retained-note-through-native-review).

### Exercise actual Collection and domain authentication

After building the bundled helper and matching Mix graph on a supported native
allocation profile, run the complete author integration controls:

```sh
mix test test/ipse/extension/collection_normalizer_v3_integration_test.exs --max-cases 1
```

This file combines trusted-function fixtures with actual
Collection/Identity/DomainAuth controls. Sources and recipes
are explicit trusted synthetic fixtures, not SessionSource or human-origin
attestations. The actual path calls the same internal seam an adapter uses:

```elixir
Collection.execute_managed_v3(root, namespace, options.request, operation_id,
  Ipse.JSON.digest([options.recipe]), fn witness, read ->
    Ipse.Extension.Collection.NormalizerV3.normalize(witness, read,
      Map.merge(options, %{domain_cap: cap, catalog: catalog}))
  end)
```

Here `cap` and `catalog` come only from the current
`ProjectIdentity.with_domain_publication/6` callback; the runnable test supplies
the complete admission and post-publication verification around this excerpt.
Follow its `publish/4` and `verify_publication/5` helpers when implementing an
adapter. Check that initialization has three extras, follow-on publication
preserves the original format revision, new page revisions use actual global
generation, and live hashes/clocks invert exactly. The 27-publication series
crosses a live split using actual writes, without seeded metadata. CAS conflict
and duplicate IDs cannot enter the callback. Owner-loss tests preserve prepared
Identity and durable Collection state without automatic retry.

The separate `collection_normalizer_v3_test.exs` reproduces the maximum
shrink/redistribution plus live split with 14 charged reads and five changes, using actual
Identity tags but trusted Collection observations. Its proposal repair plus
pending-summary control uses 23 units. The actual small literal series uses
11/13 units and does not exercise that merge. These controls establish neither
current-note recall nor sustainable 2,000-note/annual capacity. Source expiry,
withdrawal, lifecycle management, SDK reservation/dispatch and migration retain
their own integration and qualification requirements.

### Budget native effects before an endurance run

Count the actual supported mutation shapes before choosing a workload driver.
The primitive storage driver batches its 2,000 initial records and calls generic
one-key update/delete/recreate operations “cycles”. Those operations do not
exercise native correction or authenticated forgetting. The current native
new-record route admits one new public record per publication.

After building the checkout, inspect both explicit cycle interpretations without
starting Ipse, opening storage or publishing anything:

```sh
elixir --erl '+S 2:2' \
  -pa _build/dev/lib/ipse/ebin \
  -pa _build/dev/lib/jason/ebin \
  -pa _build/dev/lib/telemetry/ebin \
  dev/knowledge/storage_workload.exs --native-operation-floor
```

Expect two JSON rows. At the initial annual intake floor, including the declared
day-90 doubled workload and 100 initial native pin reviews, 10,000 mixed
operations require at least 23,080 IDs; 10,000 complete update/correct/forget
cycles require at least 43,080. The Collection's retained operation-ID ceiling is
32,768. The complete-cycle lower bound therefore
already exceeds it, before expiry, imports, compaction or recovery operations.
The developer [selected 10,000 mixed changes total](../archive/2026-10-26-p30-p31-implementation/workload-change-count-20261102.md),
additional to the normal annual workload. Use `:mixed_operations` when freezing
that preflight; keep the three-action row as a comparison. The selected lower
bound does not establish that the complete workload fits.

Both rows report zero actual native operations/turns and false qualification.
Ratify pilot-derived intake and account for the complete supported effect ledger
before freezing an endurance run. Include proposal-management effects: each
native rejection uses one management operation and retains a public suppression
descriptor/value while deleting the selected pending record and live row. Its
shared source anchor and original journals remain. Do not treat removal from the
pending queue as removal of all storage costs. Pending correction similarly
uses one atomic publication and retains a
candidate-specific suppression while replacing one pending/live identity. Its
net pending count stays unchanged, but the retained marker, operation receipt
and journal still add costs. A later acceptance is a separate publication.
Explicit `knowledge defer` is a checked read and adds no publication ID, marker
or resource reservation; it preserves the original pending deadline.
Selected batch review still publishes and accounts for each accepted candidate
separately. Its immutable manifest is repeated in each accepted event/journal and
measured input; grouping the UI does not reduce the operation or physical-byte
ledger to one batch entry.

Next construct an action calendar instead of treating every retained note as
one Collection slot. This plain-VM command models the initial intake floor:

```sh
elixir --erl '+S 2:2' \
  -pa _build/dev/lib/ipse/ebin -pa _build/dev/lib/jason/ebin \
  -pa _build/dev/lib/telemetry/ebin \
  dev/knowledge/storage_workload.exs --native-calendar 20
```

The calendar keeps 40 planned main turns/day and the doubled day-90 workload.
It spreads the additional 10,000 changes evenly across the year, cycling through
update/correct/forget: 3,334 temporal updates, 3,333 ordinary corrections and
3,333 forgets. This is a balanced working fixture choice, not a developer-fixed
ratio or ratified pilot mix. Native target aliases are expectation data, not
source handles or authority. The historical value and its corrected replacement
both keep the old ordinary deadline;
temporal history keeps 365 days after its update. One initial current statement
has its first update on day 100. Pins/preferences and 50 current slots survive.

Expired-record cleanup uses only daily operation capacity left after required
changes, with a conservative next-day deadline margin. It retains every removal's
anchor and counts each reclamation as another publication. At intake 20 this
schedule has 7,972 reclamations and 31,052 initial-plus-annual publications,
before the listed unplanned requirements. A higher intake that exceeds the daily
limit reports its full required actions and excess instead of trimming capture.
No native publication, main request or actual turn runs in this command.

Check the protected Consent representation as well as this ID count. The
31,052-ID schedule leaves 30,988 compacted rows after retaining 64 full receipts.
With 13-digit calendar times, the older v2 compacted object alone needs at least
6,713,291 bytes, even with six single-digit resource counters. It cannot fit the
unchanged 6,225,920-byte reserved-write budget. Consent storage v3 packs only the
terminal rows' two digests and status, preserving the logical accounting and
public inspection described in the [SDK contract](collection-sdk.md#keep-approval-and-replay-facts-distinct).
Reads retain old bytes; migration happens only during a successful authorized
mutation. Keep the matching host installed after that mutation.

Before a long run, encode its actual six-resource vector geometry and all 64
recent receipt bodies, then apply the same maximum-maintenance calculation as
the writer. The focused synthetic control uses 31,052 IDs, 64 full eight-KiB
receipts and a conservative six-digit input-byte vector; it is a representation
bound, not a measured annual workload. A passing byte preflight still leaves
native allocation entries, signed metadata, source/management journals, expiry,
process-tree peaks and complete-day latency to measure. Count the 10,000 mixed
changes once: they already occur in the calendar's 28,952 scheduled effects.
Do not extrapolate the first day's 57 effects to every annual date.

Plan filesystem inspection separately from record, ID and encoded-byte limits.
`Runner.storage_allocation/1` has a five-second observation bound and visits at
most 40,000 entries per declared root, including the root directory at depth zero,
all child directories and retained files. Depth may not exceed four. Paths must
be canonical and private to their owner; regular files must be singly linked.
A successful measurement establishes allocation, not publication or source
authority. In the complete resource inventory, count original journals,
release sidecars, management records,
locks, inputs, reports, logs and closure receipts as well as selected values.
Two disjoint directory owners have separate entry ceilings; adding their counts
does not turn that sum into one walk, while inspecting their common parent may
exceed its bound. Never move an original journal or replace its lock merely to
make a measurement fit.

Choose the layout for new fixture evidence before creating it, then bind and
audit the actual owner paths. Every individual approval, operation, receipt and
historical record must survive any execution grouping. Sequential samples of
disjoint owners are observations at different times, not an exact simultaneous
disk peak. Keep observation spans, missing components, parent metadata and
fixed runtime/artifact costs explicit. A guarded byte inventory alone does not
measure physical allocation or sharing; an unavailable dimension remains null.
Measure one complete actual day under the selected layout before using it to
assess longer horizons; a calendar or codec preflight supplies no such result.

Before building a continuation, inspect the bounded segment geometry:

```sh
elixir --erl '+S 2:2' \
  -pa _build/dev/lib/ipse/ebin -pa _build/dev/lib/jason/ebin \
  -pa _build/dev/lib/telemetry/ebin \
  dev/knowledge/storage_workload.exs --native-segments 20 8
```

This working case reports 3,784 segments and 28,952 effects after the seed,
with 14,600 planned turns and zero actual operations or turns. Each segment
stays within a day and has at most eight effects; a target created in that
segment waits for a later one. A higher-intake plan retains its over-quota day
and reports it rather than silently dropping effects. The eventual driver must
authenticate resolved targets and preserve closure/unknown-effect recovery;
the [segment preflight](../archive/2026-10-26-p30-p31-implementation/native-calendar-segments-20261102.md)
does not implement that driver.

The short seed and turnover probes add a fixed day offset to the current real
clock. For a long-running continuation, use a per-day anchor that compensates
for elapsed real time; otherwise the simulated calendar drifts. This example
plans day 21 after 27 real hours without executing an effect:

```sh
elixir --erl '+S 2:2' \
  -pa _build/dev/lib/ipse/ebin -pa _build/dev/lib/jason/ebin \
  -pa _build/dev/lib/telemetry/ebin \
  dev/knowledge/storage_workload.exs --native-clock \
    1800000000000 21 1800097200000 1801728000000 1800097200000
```

The result has offset `1717200000` milliseconds and virtual start
`1801814400000`; it reports zero operations and turns. Persist the actual day's
anchor before dispatch and reuse its offset across that day, including restart.
Check the latest unshifted real time against the last verified virtual time and
the day's exclusive end before and after each effect. The end is the next UTC
midnight, matching the saved-consent quota period; it may leave less than 24
hours for a simulated workday. A changed anchor, backwards time, reaching that
boundary or unsupported offset refuses admission; crossing after dispatch leaves
the effect unconfirmed and must not trigger replay. Confirm that seed operations do not
occupy the first continuation quota period. The
[clock preflight](../archive/2026-10-26-p30-p31-implementation/native-calendar-clock-anchor-20261102.md)
and its [quota correction](../archive/2026-10-26-p30-p31-implementation/native-calendar-quota-clock-20261102.md)
do not persist the anchor or implement the live driver.

Inspect the returned record lower bound before running the calendar. The current
page profiles permit at most 122 anchor rows and 26 live rows per page, even at
their minimum charged row weights. Every admitted lineage retains its anchor;
each present literal/history needs a live row, plus the format record. The
working calendar reaches 6,903 public notes and requires at least **7,326 total
Collection records**. This lower bound is below the unchanged 8,192-record limit;
actual packing and the full workload may still exceed it. If every public value at
that peak occupied the 6-KiB ceiling, those values alone would occupy 42,412,032
bytes, above the 24-MiB logical limit. This is a
conditional payload bound, not an actual native maximum-record result.

The lower bound does not qualify any workload or freeze intake. An earlier
calendar incorrectly renewed corrected replacements; the [correction record](../archive/2026-10-26-p30-p31-implementation/native-calendar-correction-deadline-20261102.md)
preserves that error and its effects on the storage assessment. This calendar
does not model offline/concurrent owners, imports, compaction, consent renewal,
proposal bursts, maximum-payload production, resource peaks or independent
quality. Use its explicit actions for lifecycle scheduling and verify those
other boundaries through their separate journeys. Authenticate every actual
target, source and deadline at execution; a pass in one journey does not fill
another journey's missing observations.

Plan a fresh native permission review before the saved grant expires. The seed
starts before the 365 annual dates, so a one-year grant from seed creation does
not cover the last annual days. A scoped [clocked control](../archive/2026-10-26-p30-p31-implementation/native-consent-renewal-20261102.md)
checks expiry refusal and a new native capture after review, while preserving the
original saved source and signed stored note. It does not establish old-note
delivery to a model or complete annual continuity. A separate
[renewed-recall control](../archive/2026-10-26-p30-p31-implementation/native-renewal-recall-20261102.md)
checks delivery to a synthetic loopback provider in a fresh Session and withholding
when the original source is unavailable; it does not establish live-model quality
or continuity of an already running Session.

Resolve an impossible budget through an explicitly reviewed storage design;
do not reset identities, discard liabilities, raise a limit to hide failure or
count primitive churn as native lifecycle coverage. The
[frozen qualification contract](../archive/2026-10-26-p30-p31-implementation/qualification.md#storage-and-performance)
owns the workload floors; a preflight is no replacement for its actual runs.

Check serialized receipt overhead separately from ID count. From the same built
checkout, this plain-VM probe writes synthetic metadata measurements without
starting Ipse, opening a Collection or changing a limit:

```sh
elixir --erl '+S 2:2' \
  -pa _build/dev/lib/ipse/ebin -pa _build/dev/lib/jason/ebin \
  dev/knowledge/native_receipt_geometry.exs --output /tmp/ipse-native-receipts.json
```

It compares unbound and managed receipts, zero and 2,000 public record
descriptors, and a scenario where every operation advances the destructive
floor. Its earlier 22,980-ID scenario, before accounting for initial pin reviews,
with 2,000 public descriptors occupies 4,899,325 packed bytes. This remains a
historical geometry measurement, not a measurement of the revised 23,080-ID
minimum. At 42,980 managed receipts, the three-action comparison occupies 8,026,433 bytes
without records, or 8,639,325 bytes with the 2,000 descriptors. The latter exceeds
the current 8-MiB canonical-state ceiling before authenticated sidecars or
migration overlap. The unchanged encoder refuses the larger ID set independently.
Raising only the ID count would not make that comparison fit. Qualification must
measure the selected workload's actual receipt/sidecar mix and cleanup overhead.

These are metadata geometry controls, not authenticated notes, value objects,
native allocation, actual workload composition or latency measurements. Use the
[dated receipt](../archive/2026-10-26-p30-p31-implementation/native-receipt-geometry-20261102.md)
to distinguish the measured scenario from a proposed storage redesign. Preserve
exact operation inspection, duplicate detection, original generations and unknown
liabilities when evaluating a new representation.

### Populate through actual native statements

Use `native_notes_seed.exs` to establish a native initial population before
building an endurance driver. It calls the actual Session input-channel,
statement/category review and capture paths, then standalone native pin review;
it does not insert trusted records through a normalization seam. Each statement
uses the current 1,024-byte original-quote bound with deterministic varied bytes.
The resulting record size is measured, not padded to the separate 6-KiB ceiling.

Build the checkout first and use Linux/glibc x86-64 with the supported native
storage/terminal profile. Rust compiles only the existing PTY and process-clock
fixtures. Start with a fresh nonexisting `/tmp/ipse-native-seed-*` path:

```sh
mix test test/dev/knowledge/native_notes_seed_test.exs
mix run --no-start dev/knowledge/native_notes_seed.exs --init /tmp/ipse-native-seed-smoke-example smoke
mix run --no-start dev/knowledge/native_notes_seed.exs --run /tmp/ipse-native-seed-smoke-example all
mix run --no-start dev/knowledge/native_notes_seed.exs --audit /tmp/ipse-native-seed-smoke-example /tmp/ipse-native-seed-audit-smoke-example.json
```

The smoke plan makes seven native notes and one pin across two fresh processes
at simulated days 0 and 1. Require eight retained Collection IDs, settled control
usage, signed category/clocks, exact public values, strict saved Session release
claims and unchanged prior source journals. Both processes probe their actual
protected stdio child clock; an unrelated environment canary must stay absent.
This checks the driver, not 2,000-note capacity or an annual workload.

For the complete initial plan, choose another fresh root:

```sh
mix run --no-start dev/knowledge/native_notes_seed.exs --init /tmp/ipse-native-seed-initial-example initial
mix run --no-start dev/knowledge/native_notes_seed.exs --run /tmp/ipse-native-seed-initial-example 1
mix run --no-start dev/knowledge/native_notes_seed.exs --run /tmp/ipse-native-seed-initial-example all
mix run --no-start dev/knowledge/native_notes_seed.exs --audit /tmp/ipse-native-seed-initial-example /tmp/ipse-native-seed-audit-initial-example.json
```

The plan has 2,000 captures followed by their required pin reviews within each
bounded segment: 100 pins, 50 preferences, 50 current assertions and 1,800 other
ordinary notes. Its **2,100 publications** use 21 seed days with 100 operations
per day, split into 273 segments of at most eight effects. It preserves the
existing grant and quota. This population happens before the normal annual
workload; the arithmetic floor includes its 100 initial pin reviews.
Pilot-derived intake and the complete annual ledger remain separate prerequisites
for endurance acceptance.

Initialization copies SDK/dependency BEAMs and shipped assets, freezes their
hashes and the runner sources, and creates a disclosed private clock adapter.
Only that private Runner's two stdio environment maps propagate the fixture
preload/offset; production files and the machine/kernel clock do not change.
No inference is allowed. A run checks those frozen bytes, earlier source hashes,
the prior actual root and complete visible values before more effects. Each
segment uses a new Session and OS process. It records actual per-staging allocation,
capture latency, post-segment BEAM memory and separate Collection, control,
identity, management-journal and source-session accounting. These are component
samples, not complete worker/process-tree RAM peaks or reference-hardware latency
qualification. Original journals remain outside the Collection's selected record
objects and are reported separately rather than omitted from resource evidence.

Keep every `inflight.json`, log and checkpoint. A failed/unknown segment retains
its marker and refuses further execution. Do not delete it, replay the segment,
replace the root, or reset IDs to continue the same cohort. A known completed
segment needs both its verified report and a parent-observed exit-zero closure;
`--run` continues only after those closed segments. Completed plans also refuse
further execution. A changed frozen file refuses before another marker/effect.
All reports keep `annual_workload_qualification: false`: this tool does not run
daily intake, corrections/forgetting/supersession, reclamation, concurrency,
offline imports, compaction or the additional 10,000 mixed changes. Keep
maximum-shape, mixed-lifecycle and persistent-metadata results separate from this
population report; it supplies no qualification for those boundaries.

A [small turnover pilot](../archive/2026-10-26-p30-p31-implementation/native-turnover-pilot-20261102.md)
continues a separately audited smoke seed through seven real lifecycle effects,
with closed segments and a final signed-read audit. Its fixed scratch script
does not implement the calendar or 40-turn days. When building the annual
continuation, retain its exact target/source checks and stop on an unknown effect;
then measure the complete workload rather than extrapolating this smoke result.
A [lock and interruption follow-up](../archive/2026-10-26-p30-p31-implementation/native-turnover-lock-20261102.md)
illustrates why standalone management needs its own cleanup owner, and checks
refusal after a completed effect whose driver report was interrupted. It does
not establish active-effect or concurrent-restart safety for a full driver.
The later [batched smoke](../archive/2026-10-26-p30-p31-implementation/native-turnover-batch-20261102.md)
checks confirmed-batch restart and reuse of one persisted same-day clock anchor.
Its fixed actions and stated real-clock assumption do not replace a reviewed
calendar driver or long-running clock and failure tests.

### Audit the complete retained population

Run `--audit ROOT OUTPUT` only after all segments have their closed markers.
An inflight or incomplete plan refuses before creating audit output; an existing
output or companion file also refuses. Use a fresh absolute
`/tmp/ipse-native-seed-audit-*` output path. The audit starts no Session, terminal
review, model or publication. Its native reads retain the actual Identity and
Collection owners for each selected record.

The caller copies its current source beside the output and uses the cohort's
frozen SDK, clock and helper for the child process. The cohort's original runtime
files remain frozen; updating the audit caller does not change which publisher
produced those notes. Require exact last-closed root and control state, complete
visible values, unchanged original journals, strict saved-Session reconstruction,
and actual signed category, recipe, policy and nonrenewed retention clocks for
every note. Session reconstruction is discarded after each source check.

The summary binds a separate `OUTPUT.rows.json` containing the checked per-note
metadata, plus the exact copied caller and original cohort manifest. Preserve
those files with `OUTPUT.log` and the cohort checkpoints. It reports actual
Collection allocation and separate control, identity, management and source-Session
allocation, together with their measured sum. The sum adds actual control bytes
rather than counting the Collection's reserved control allowance again. Installed
artifacts, the frozen SDK and the benchmark oracle are outside that measured sum;
whole-process RAM/disk peaks still need their own measurement.

`recorded_event_times` counts retained journal events and gives maxima for a
small set of recorded timestamp fields. Use it to compare the seed's recorded
timeline with the planned first continuation day. Those selected fields are not
an upper bound on physical completion and do not prove the host clock was
monotonic; establish and record a defensible start bound before dispatch.

A successful smoke audit proves the seven-note smoke population, not the full
initial plan. A successful full audit proves only its current initial population:
maximum-record, annual lifecycle, cleanup, concurrent-owner and independent
semantic qualification remain separate. Both report fields
`full_6_kib_record_payload_qualification` and `annual_workload_qualification`
remain false.

## Fence document stages before metadata maintenance

The fixed document profile has an internal metadata-maintenance fence in
`Collection.DocumentMaintenance`. It is separate from the State and MCP source
operations below. No general maintenance-open/close SDK operation, garbage
collector or adoption procedure exposes this entry point. The separate
[document import contract](#restore-completed-document-collection-data) uses a
purpose-bound maintenance owner. A trusted host caller must establish ordinary
approval and project authority before using the internal entry point; an epoch
or a shaped owner map supplies neither.

An open transition checks the actual locked generation, current epoch and
absence of another maintenance/import owner. It increments the persisted epoch
and reserves exactly two distinct operation IDs: the open publication and its
named close publication. The complete ID reservation must fit before opening. The
active metadata binds the project, Session, artifact and invocation owner, plus
the opening descriptor/checkpoint commitment. Reload reconstructs that commitment
from the immutable opening state and receipt. Ordinary document mutations refuse
while active; inspection remains available. Close requires the same owner and
reserved ID, retains the new epoch and leaves records, checkpoints, destructive
floor and receipt history intact. There is no automatic expiry, adoption or
unknown-operation replay.

For an admitted document operation, `Collection.with_document_admission/4` reads
the actual protected snapshot and binds its epoch and idle/active status to the
canonical root path, project namespace and trusted owner. Never replace this
step with a worker-supplied counter. The final native CAS compares that context
again. An admission captured before open, or while active, cannot publish after
close even with a refreshed generation. A fresh admission after close can publish.
Plain document commits without that context fail closed after the first fence.

`DocumentStage.execute/6` enters one tracked file-effect owner before installing
its publication guard and admission context. Nested Collection calls stay in
that owner. The entry explicitly carries only a validated inherited deadline
across a newly created effect peer, narrows it against the requested deadline,
and refuses nested publication guards. Do not copy arbitrary process dictionary
state or make a callback depend on running in its caller's process.

Stored stage headers bind the opening maintenance epoch internally. After a
fence, a legacy or older stage cannot append, seal or publish. Exact owner-bound
abort and expiry-bound reclaim remain reducing operations, subject to the current
native fence. Supplying a newer counter cannot renew an older stored stage.
Checkpoint rollback does not reset the persisted epoch.

The document snapshot exposes this consistency condition separately from
authority. At epoch zero it retains the version-two `document_store` descriptor;
after a fence, version four adds `maintenance_epoch`, `maintenance_status` and
`progress: 1`. The prior version-three descriptor remains valid historical epoch
data but does not advertise native progress.
New mutations carry the captured `maintenance_epoch` in their inner SDK request.
Missing means exactly zero, not the current epoch. Before any effect the host
requires the actual idle epoch to match, then repeats its trusted root, namespace,
owner and epoch checks at the native CAS. Historical legacy action validation
remains available without granting a current write. See the
[SDK contract](collection-sdk.md#stage-ordinary-documents-under-their-own-grant).

The Source adapter captures the snapshot epoch once for each logical put. Epoch
zero retains its version-three continuation and original plan hash. At a later
epoch, version five carries the complete native progress receipt as well as the
captured epoch and public `epoch_binding_sha256`. The existing `plan_sha256`
remains the actual source-body hash used by acquisition and workspace guards;
the native head's separate plan also binds the expected revision, profile and
unit geometry. Version-four public-digest continuations remain historical data,
but cannot be upgraded into a native head after a fence. Recomputing their epoch
and hashes cannot authenticate earlier completed work.

That native Source plan fixes the source body and logical target, rather than
authenticating the original catalog snapshot. The checkpoint's `base` is an
optimistic catalog consistency stamp. The controller rereads the target and
catalog, verifies immutable values and prepared metadata, and publishes with
the current exact CAS revisions. Projection separately binds its rendered root.

The first actual Source unit allocates its head and reserves three transport
slots atomically. If its immutable value already exists, `value.verify` checks
the actual current revision and decoded logical bytes/hash while allocating and
advancing the head; a bare read cannot count as completion. Each continuation
must match an owner-bound inspection of the complete native receipt, including
its unit, prepared refs, active descriptor and reserved slots. Native CAS checks
the same head revision, epoch and actual owner again for every effect. Partial
transport changes the native revision/offset without advancing the logical unit.
The final three-stage metadata commit consumes the head and reservations in the
same publication. Unknown outcomes stop without replay.

Projection uses the same native contract, with two reserved slots and its own
body/plan identity. The document-only metadata admits at most eight live heads;
actual occupied slots, encoded metadata, operation-ID capacity and allocation
can reduce admission further. Ordinary allocations use the native
`stage.available` view so another writer cannot take reserved slots. The Corpus
`source` action `abort_collection_draft` exposes bounded same-owner retirement
for both kinds through `Collection`'s `:progress_abort` client. It captures one
current idle epoch, inspects the actual owned head, and removes its active stage
before its prepared stages. Each separately approved native CAS must return the
same opening identity, plan, body, unit and frozen retirement epoch, with exactly
the requested stage removed. The next request uses that actual returned revision
and generation. Three reductions suffice for the Source slot bound; Projection
needs at most two. An empty head needs one real retirement operation.

Known terminal completion releases the reservations. A known refusal after
partial cleanup is reported as incomplete; unknown supplies no replay token.
Another fence refuses the stored retirement epoch, even on a later explicit
command. This does not adopt another Session/artifact or remove immutable public
values. Do not edit tokens or metadata to recover capacity; general GC and
cross-owner recovery remain separate work.

The lexical Index adapter binds its continuation to the stored job's epoch, so changing
the token alone cannot adopt an older job. Its read-only inspection and query
remain available. After close, an explicit Index `abort` can mark the exact
older job aborted under the current idle epoch, retaining its old job identity
and discarding its earlier publication checkpoint. A bounded partial retirement
returns `aborting` with a version-four continuation: use it only for `abort`,
at its frozen retirement epoch. It cannot resume indexing or adopt old stages.
Only a confirmed `aborted` result permits an explicitly new `begin`; old staged
values still consume capacity, so this promises no unconditional progress or
stage-pool reclamation.

Generic shared-generation Jobs retain a native job record that supplies that
independent epoch anchor. Legacy Job1/2/3 and token1 keep their epoch-zero shapes;
Job4/5/6 add a positive epoch to the corresponding group, ordinary reduction and
paged reduction schemas. Normal token2 retains that same epoch. Append and
finalization require the exact stored job ID, physical revision and epoch to
match the token and current idle snapshot. Inspection preserves the old stored
epoch rather than refreshing it. An explicit new begin resets progress; it does
not adopt an older immutable prefix or metadata stage.

When a caller needs to freeze a selected result before appending a group, use
the internal `Job.start_bound/2` and `Job.bind_input/2` contracts. They are not
public Corpus command actions. Opt-in Job7 (epoch zero) and Job8 (positive
epoch) start with `input_binding: null`; existing Job1–6 formats and default
creation remain unchanged. An older reader refuses these new closed formats.
Ordinary writes cannot create a prebound Job or convert an older Job into one.

Follow one known, stage-free group through these transitions:

1. Prepare its vector pages while the Job is unbound. The checked producer
   path still requires the actual stored Job revision and current idle epoch.
2. Capture the selected reference from the actual parent `invoke.command`
   arguments under the current version-three operator binding. Bind its
   reference digest and declared raw-body digest, the current catalog group's
   source-set digest and cursor, and the actual physical Job revision **before**
   this binding write. The stored owner fixes project, Session and extension
   identity; a worker-supplied reference or owner cannot replace that context.
3. Append using that exact persisted binding and owner. The host retains the
   existing current-source, summary, revision and epoch checks. Successful
   append clears the binding for the next group. The final group converts Job7
   to Job1 or Job8 to Job4 at `manifests`, preserving the existing finalization
   formats and raw hash joins.

Reference capture proves which reference the operator selected and which digest
it declares. It does not prove that the original result exists, authenticate its
bytes or classify its contents. A caller must separately establish the
[original-result lease and producing-action provenance](extensions.md#consume-an-explicitly-selected-historical-result)
before using those bytes. The binding adds no read permission or publication
authority. Once bound, the checked producer egress path refuses another model
request; it cannot keep producing against the earlier unbound revision.

A bound Job can instead take an exact owner-bound reducing abort. It retains its
opening epoch, cursor, summaries and facts, removes the binding, and returns to
the corresponding legacy `aborted` format. This path may use the current idle
epoch after a fence without requiring the old Sources to remain current. Only
the host-derived bound-abort purpose bypasses that source-current check;
Registry/current-intent, stage expiry and native owner/root/epoch CAS checks
remain. An unbound abort follows its separate ordinary transition. Neither path
adopts another Session's binding, transfers active stages or supplies a token
for unknown work. Keep this private integration bounded to known, stage-free
progress; the legacy handoff procedure is not a cross-Session adoption route
for bound Jobs.

Explicit Job abort retains the exact older job's ID and epoch while staging only
new reducing metadata under the current idle epoch. A bounded partial abort
returns token3 with the old job epoch and a separately frozen `retirement_epoch`;
only abort can consume it. Its plan digest includes that retirement epoch, and
native stage headers retain their actual opening epoch. A known same-epoch
continuation resumes its exact stage and offset; after another fence it refuses.
Unknown work supplies no safe replay token. Producer claim writes retain their
opening epoch, and the held reader requires the claim, stored Job and current
idle epoch to agree before each inference admission. A later fence cannot recall
an already admitted request. General maintenance, adoption and garbage
collection remain closed.

Exercise the internal lifecycle and the real SDK boundary with disposable native
storage on a supported profile:

```sh
mix test test/ipse/extension/collection_document_maintenance_test.exs --trace
mix test test/ipse/extension/collection_document_stage_test.exs
mix test test/ipse/extension/collection_store_session_test.exs --only document_maintenance_session
mix test test/extensions/knowledge/collection_adapter_session_test.exs --only source_maintenance_epoch
mix test test/extensions/knowledge/collection_adapter_session_test.exs --only projection_maintenance_progress
mix test test/extensions/knowledge/collection_draft_abort_test.exs
mix test test/extensions/knowledge/collection_adapter_session_test.exs --only document_draft_abort --only document_draft_abort_three_slots
mix test test/extensions/knowledge/collection_split_append_native_test.exs --only lexical_maintenance_stale --only lexical_maintenance_fresh
mix test test/extensions/knowledge/collection_adapter_session_test.exs --only generation_maintenance_session --max-cases 1
mix test test/ipse/extension/collection_job_input_guard_test.exs
```

The Session controls prepare approved work, open/close the internal fence and
check old-stage and stored-Job refusal, fresh guarded publication and exact
retirement. They reconstruct closed journals without invoking a model. The
Source token case includes a fully recomputed public continuation with a
fabricated native head, actual immutable verify/reuse, and complete receipt
tampering. Projection controls exercise both vector and fact publication.
Index controls exercise actual native jobs and
retrieval. These are lifecycle checks, not destructive GC, migration or
full-capacity qualification.

For the private input-binding contract, also exercise direct prebound creation,
ordinary rebinding and abort attempts against the actual Host predicates. The
[component record](../archive/2026-10-26-p30-p31-implementation/document-job-input-binding-20261106.md)
separates 21 no-application checks (seven new and 14 legacy, with five native
cases excluded) from one selected native component case. The latter uses actual
DocumentStage operations and a retained-reader source precheck with trusted
synthetic inputs. It does not qualify a public Session caller, operator approval,
original-result materialization or whole-capacity behavior.

## Claim a draft before writing immutable pages

A put/open reads a bounded snapshot and validates its partition. New-root admission
uses the actual missing target at revision zero plus captured namespace generation.
Revision and optional generation are checked atomically under the State lock.
Distinct creators that observed the last free root slot cannot both claim it.
Existing-root/page writes omit that generation fence so their own earlier writes
do not invalidate publication. Root CAS still binds exact revision/source generation/
content hash/draft. A positive-revision generic tombstone at a root key is corrupt,
not an available source slot.

Each partition permits 32 roots. Capacity checks cover all root creation, including
suppression import, using actual added record/root counts. A suppression export has
no plaintext source ID; use its destination key rather than reconstructing the ID.
Local checks alone cannot protect concurrent publication without the atomic fence.
Unrelated namespace writes can conservatively conflict; no retry is implicit.

Draft claim precedes content/chunk pages, which precede final root selection.
Unselected pages remain inert. Large text uses explicit open/contiguous append/
publish, binding draft, expected revision, and byte offset. Final publication
checks whole-body length/hash. Resume never completes a partial draft. Every root
mutation advances storage revision; source generation identifies complete text,
not arbitrary storage mutations.

Stored root/page values independently fit 6000 encoded bytes and SDK validation.
Packing/effect planning uses actual envelopes, including escaping. Generic State
supports 256 retained records/1 MiB per namespace, including other partitions,
orphans, old generations, and tombstones. Local plans conservatively account for
record wrappers; qualified MCP has the stricter 88-key ceiling below. Collection
replaces unreachable pages with tombstones, so it reclaims content bytes, not slots.

## Plan projection capacity before model egress

Source-bound fact/vector drafts return selected chunks, opaque token, and a capacity
plan. Check read/effect allowance before inference. Explicit facts pack actual
encoded pages before claim; model extraction receives an affordable allowance.
Count ceilings do not reserve worst-case records. Returned data must fit the plan,
current source/chunks, and live draft before final CAS. An oversized result leaves
inspectable/abortable work, without partial successful projection.

Eight heads per source bind kind/profile consistently at admission/publication.
Updating an existing head remains possible at the ceiling; a ninth identity refuses
before inference. New vector drafts/plans/tokens bind version two and authenticated
selection. Old drafts remain inspectable/exactly abortable but cannot be promoted
or continued with a fresh token. Compatible chains append; explicit replacement
selection starts with `previous: null`, leaving old pages detached until collection.
See [embedding identity](knowledge-extensions.md#authenticate-embeddings-and-their-complete-vectors).

Two 4096-coordinate vectors need twelve coordinate pages, manifest, final CAS,
draft claim, and embedding call, totaling sixteen effects. State indexing admits
one/two selected chunks. MCP admits one and still may refuse capacity. Every MCP
call is an effect, including reads; result windows have their own read allowance.
Preflight cannot promise capacity after competing writers, so exact abort remains
necessary after later refusal.

## Make suppression survive delayed publication

Follow this intervention through the real continuation:

```text
claim generation 4 → dispatch extraction
forget generation 4 → commit permanent suppression
release old extraction → refuse stale or suppressed publication
```

Suppression roots keep hash/generation/partition without text/title/URI. Imports
and delayed drafts cannot restore them. Forget increments generation until its safe
integer ceiling; at that ceiling it keeps generation and advances CAS revision.
Terminal suppression still blocks resurrection. Queries revalidate all supporting
sources rather than rebuilding missing heads.

Older partitions above 32 roots refuse whole snapshots with root-capacity error.
Addressed inspection/export/existing-root maintenance remain available within byte/
record/effect limits and remote snapshot constraints. Another root refuses;
suppression preserves a root and cannot repair excess count. Keep data for deliberate
migration, without truncating tokens or widening query bounds.

Before sharing a binding with new artifacts, drain old Sessions/admitted effects
and retire their writer configuration. Optional State conditions cannot constrain
a trusted writer that omits them. Valid format-one stores within bounds require
no automatic data rewrite.

## Export complete bytes and migrate explicitly

Choose the store contract before implementing export. State/MCP source export
below transfers source text and provenance for explicit rebuilding. The
experimental document Collection path transfers a complete recognized set of
packed values through operator-selected saved results. Neither route turns
historical data into current evidence or resumes old work.

### Restore completed document Collection data

Read the native
[`DocumentMigration`](../../lib/ipse/extension/collection/document_migration.ex),
the host
[`CollectionStore.Restore`](../../lib/ipse/extension/collection_store/restore.ex)
and the Knowledge `Store.Collection` backup state machines together. Native
code owns snapshot identity, operation receipts, allocation and atomic
publication. The host owns explicit selection, original-result leases and the
current validator identity. Knowledge owns the meaning and completeness of the
stored document set. Do not move that domain classifier into Core.

The client is experimental and admits at most **32 native records in four
selected pages**, with up to eight records per page. This is a bounded completed
set, not a full-capacity backup facility. The optional
`document_completed_v1` input-validation selection is available only for the
Corpus `collection-documents` and `collection-dense` presets with an actual
Collection store. It creates an explicit version-three document binding whose
closed `input_validation` is:

```json
{"command_id":"source","action":"restore_validate_page","export_action":"backup_page","plan_action":"backup_plan"}
```

The binding retains `source_use` separately; it does not add a capability,
change ordinary approvals, admit protected note writes or enable a worker.
Follow the [Corpus operator procedure](../operator/corpus.md) for selection and
full command arguments. A descriptor or JSON input file alone grants no restore
authority. The [bounded public Session journey](../archive/2026-10-26-p30-p31-implementation/document-result-restore-public-20261106.md)
qualifies same-target import, rollback, abort and checkpoint removal with eleven
records across three pages. It includes denial, stale-floor refusal and strict
Saved/idle checks. Changed-target restore, installed execution and full capacity
remain unqualified; this same-target control does not establish recovery across
a changed destructive floor.

Follow one input through the actual owners:

| Step | Binding that must survive |
| --- | --- |
| `backup_status`, then `backup_page` | One actual native generation, fixed project namespace, complete packed-value layouts and exact chunk hashes |
| `backup_plan` | The operator's exact selected page references, ordered native record/operation metadata, full descriptor and complete page membership |
| `restore_validate_page` | The actual selected plan and all its pages, reconstructed bytes, native origins and complete domain joins |
| `restore_open`, ordered `restore_page`, `restore_commit` | Original selected plan/page digests, one import owner, expected native generation/epoch and ordinary approval for each effect |

The host captures references from the real `invoke.command` arguments; a worker
cannot substitute an arbitrary result later. `StoredSources.with_result/3`
retains each inactive original Session's OS lock/file/origin and actual project
binding. Source and consumer must use the same canonical cwd and admitted
project. Same-Session input, active/copy/hardlink/legacy sources, incomplete work
and changed input refuse. The helper returns complete managed dependencies;
Restore requires a known empty union rather than interpreting protected JSON
as unmanaged data. See the
[leased-result flow](extensions.md#consume-an-explicitly-selected-historical-result)
for lock ordering and the pre-CAS/postcheck contract.

The exporter supplies the data, but cannot authenticate its native epoch by
writing `maintenance_epoch` into that data. The host derives `origin` from the
strict-Saved-validated producing invocation's successful `backup.metadata` or
`backup.describe` action results. Every matching native descriptor must agree
with the exported descriptor: project/profile, generation, maintenance epoch,
floor/lineage and record, operation and envelope digests. The compact descriptor
replaces the full lineage with its count while preserving its digest. The
origin also binds producer command/action, artifact, actual owner and a digest
of those native action records.

`restore.input.read` returns at most 6,144 raw bytes per call with exact delivery,
offset, hash and the same origin on every chunk. Its complete SDK wrapper must
still fit 16 KiB. The current validator's actual artifact SHA, command and
`restore_validate_page` action must match the selected policy. Its recorded read
trace must reconstruct exactly the original selected bytes and carry the
configured `backup_page` origin. The historical exporting artifact is data
provenance and may differ from the current validator. The plan separately needs
its native descriptor and configured `backup_plan` origin. Missing provenance,
a copied neighboring invocation's receipt or a self-claimed future epoch cannot
substitute for these joins.

The domain predicate `Projection.completed_backup?/3` independently checks each
packed envelope and every reference within the complete selected set. It
rejoins Source blocks/heads/catalogs, lexical roots and completed Jobs, vector
and fact projections, shared generations and ready Producer records using their
existing codecs. Unknown schemas, live work, missing referenced pages and orphan
stages refuse the whole set. Known authority-bearing stored Job/Index epochs
must not exceed the actual source descriptor's epoch; arbitrary Source JSON is
not recursively scanned for fields named `epoch`. Selected completed data is
queryable data, not a resumable native Job or controller claim.

Distinguish three identities during import. The backup retains the original
native record envelope (`key`, revision, operation ID, physical SHA and size).
Its packed value retains the original UTF-8 part boundaries, logical bytes and
hash; decoding the domain object is validation, not a rewrite. The target
native envelope is deliberately rebased to the actual target page publication's
revision and operation ID. Never rewrite an embedded schema or invent native
generations to make its old continuation run. Historical operation receipts
remain recognized for duplicate/refusal behavior.

Opening requires idle, quiescent target state without another import or retained
checkpoint. It captures the original target epoch and enters
`max(source_epoch, target_epoch) + 1`, retaining the exact project, Session,
artifact and invocation owner. This prevents imported old work from aliasing a
fresh target counter. Each ordered page and the final CAS recheck that owner,
epoch, input bindings and actual generation. No imported continuation is adopted.

The destructive floor remains independent. The source floor cannot be below the
target's, and its lineage must extend the target's actual lineage with matching
operation receipts. A same-floor commit may retain one checkpoint of the prior
target records; advancing the floor returns no rollback checkpoint. Rollback
requires the exact checkpoint, owner, plan/dependency binding and unchanged
floor, and advances the maintenance epoch again. Dropping the checkpoint retains
the epoch. Ordinary document rewrites/deletions advance the floor and invalidate
that checkpoint. An older backup cannot undo subsequent updates or resurrect
data below the current forgetting floor. This is not general changed-store
recovery.

Abort is an explicit reducing operation under the captured owner; it releases
import staging without erasing observed historical operation identities.
Retained physical objects and receipts still consume allocation. Neither abort
nor checkpoint removal is general garbage collection. Unknown effects stop
without replay; a lost original-input or project postcheck after native commit
must not be reported as a known no-effect failure.

Verify the layers separately when changing this public Session protocol:

```sh
mix test test/ipse/session/stored_result_lease_test.exs
mix test test/ipse/extension/collection_restore_test.exs
mix test test/ipse/extension/collection_document_migration_test.exs
mix test test/ipse/extension/collection_document_migration_native_test.exs --max-cases 1
mix test test/extensions/knowledge/collection_backup_test.exs test/extensions/knowledge/collection_completed_backup_test.exs
```

The isolated domain controls preserve raw parts, reject unsupported or incomplete
sets and bind stored epochs to native source provenance. Host controls test
explicit selection, actual origin joins, forged future epochs, changed chunks,
current-validator identity and complete frame bounds. Native controls exercise
allocation, owner/epoch CAS and floor/checkpoint behavior on disposable stores.
Keep those component results separate from actual public command routing and
complete Session close/idle evidence. Neither the component controls nor the
bounded same-target journey qualifies changed-target recovery, installed runtime
or maximum capacity.

### Export State or MCP source text

Export captures one generation and returns contiguous UTF-8 prefixes, bounded by
limit×4096, 8192, and remaining bytes; limit is 1..4. It shrinks a prefix until the
whole envelope fits 12000 encoded bytes and SDK bounds. Quotes/control characters/
newlines can require smaller parts. Complete single-part form repeats source.text
only when the whole envelope fits; otherwise metadata and top-level text stay
separate. Never infer raw capacity from unescaped text size alone.

Import reconstructs bytes/hash and accepts only cursor-zero, no continuation,
complete source up to 8192 raw bytes. A complete final fragment at another cursor
is not a full import. Larger migration uses reviewed open/append/publish while
preserving historical import provenance. Head metadata is disclosed; projection
contents are omitted and require explicit rebuilding.

Foreign copies remain historical assertions. Indexing/extraction preserves that
flag, so they remain ineligible as current evidence. Promotion needs explicit
fresh replacement with greater source generation, inspected root revision, no
historical-import marker, and new projections. Reindex alone cannot do it.
Suppression erases no other store, backup, journal, or earlier transfer.

## Abort the exact draft instead of replaying work

For State and MCP source stores, abort requires inspected root revision and exact
draft ID for source/fact/vector work. Native Collection progress instead uses the
[owner-bound head retirement](#fence-document-stages-before-metadata-maintenance)
described above. A source-only predicate additionally protects append/publish; clearing a fact
draft does not convert it into source content. Wrong IDs/revisions, stale completions,
newer drafts, and suppression refuse. Corpus index-abort checks both committed
root generation and next revision before success, not merely cleared draft state.

```sh
mix test test/extensions/knowledge/store_test.exs test/ipse/extension/state_test.exs
mix test test/extensions/knowledge/index_abort_test.exs
elixir dev/verify.exs source knowledge-recovery \
  --sdk _build/dev/lib/ipse/ebin --input /path/to/graph-state-model
```

Use an independently built Graph state-model artifact. The eight-check recovery
proof denies model egress, inspects the draft, and approves its exact abort without
Corpus or a model service. Installed mode uses the same artifact and a matching
archive. These establish lifecycle behavior, not semantic extraction quality.

## Implement a compatible remote CAS owner

Read `store/mcp_cas.ex` with the independent atomic fixture in
[`dev/fixtures/knowledge.exs`](../../dev/fixtures/knowledge.exs). The service must enforce
partition access and transaction conditions internally. Receipts prove service
assertions, not its implementation or authorization policy.
New record-adding work requires explicit `ipse-cas-v3`. Inner envelope is version
three; outer MCP call/text-window transport remains one. Never infer contract
upgrades from replies. This is a complete empty-store request/reply pair:

```json
{"version":3,"contract":"ipse-cas-v3","partition":"manual","request_id":"11111111111111111111111111111111","action":"snapshot","args":{}}
```

```json
{"version":3,"contract":"ipse-cas-v3","partition":"manual","request_id":"11111111111111111111111111111111","action":"snapshot","status":"ok","generation":0,"value":{"records":[],"count":0,"bytes":2,"complete":true}}
```

Echo version/contract/partition/action/fresh lowercase 32-hex request ID. Status is
ok/conflict/refused, generation a nonnegative safe integer, and value an object.
Unknown fields or mismatches refuse as store-response. Failed actions must not
mutate the partition. Action argument/success-value shapes are closed:

| Action | Exact args | Exact success value |
| --- | --- | --- |
| snapshot | Empty object | records/count/bytes/complete:true |
| get_many | keys, 1..8 hashes | records in requested order/complete:true |
| put_immutable_many | pages, 1..2 key/value/expected_revision:0 objects | records in page order |
| cas_root | key/expected_revision/expected_generation/expected_source_generation/expected_content_sha256/draft_id/next_root | record |
| collect | 1..12 distinct keys/snapshot_generation | records in requested order |

Records contain exactly key/revision/deleted/value. Keys are lowercase 64-hex.
Missing is revision-zero/deleted/null; live is positive revision/object; tombstones
keep positive revision/null. Directory rows instead contain key/revision/deleted/
kind, with positive revisions and root/page/tombstone kinds. Keys are unique,
count equals rows and is at most 256, and declared storage bytes at most 1048576.
These wire bounds do not override atomic 88-record admission.

Directory/groups must agree on revision/deletion and generation. Get-many includes
missing records explicitly. Immutable writes need unused keys and exact revision-one
values. Collection checks snapshot generation and all live/draft reachability under
one atomic owner, tombstoning only unprotected pages and advancing revisions/store
generation once. CAS JSON result permits 60000 bytes, read in 4096-byte exact-bound
MCP text windows. Requests fit SDK, 15000 encoded bytes, and 32768-byte approval bounds.
Write batches test the real selected envelope before choosing one/two pages.

### Enforce root conditions and capacity atomically

New roots require revision zero plus captured store generation. Existing roots
use null store-generation condition, keeping exact revision/source generation/
hash/draft. Check every condition atomically before replacement; suppression refuses.
Success returns exact next-root and target revision+1, with captured generation+1
for conditioned creation. V2/v3 records/conflict revisions cannot exceed store generation.

Root conflicts return exactly value.record summary containing key/revision/deleted/
source_generation/content_sha256/draft_id. Missing/deleted use null source fields;
suppression retains generation with null hash/draft; live roots report hash and
nullable draft. At least one requested condition differs. A fully matching summary
cannot claim conflict, and no source body is disclosed.

Qualified v3 owners atomically enforce at most 88 retained keys in the partition,
including pages/orphans/tombstones/roots, across every accepted writer/version route.
Per-client counting is insufficient. Store also checks 88 records/32 roots/encoded bytes/
remaining effects locally. Draft claims reserve no future slots; competition can
still refuse final publication and leave an exactly abortable draft.
A full snapshot needs one directory plus ceil(records/8) effects, twelve at 88.
Further writes/rechecks/model work must fit the sixteen-effect lane. Result-window
reads do not make underlying MCP calls free.

Inherited partitions above 88 fail full snapshots before addressed inspection/export/
abort. Use the service's reviewed administrative export/migration; ordinary commands
cannot bypass that bound. Selected-only query has separate coverage semantics below.
The qualified ceiling prevents Ipse's own writers from creating unreadable snapshots.

### Cut over without rewriting stored bodies

V1/v2 keep original read envelopes and zero-record maintenance. Existing-root open,
exact abort, forget, and collection can work within snapshot/byte/effect bounds.
Put replacement still adds immutable pages and needs v3; append/publish/projection
work adding records refuses atomic-capacity-unavailable on legacy profiles. V1
missing-root CAS also lacks atomic root admission and refuses separately.

Drain older Sessions/effects, qualify the partition-wide rule for every writer,
then select v3 in fresh reviewed config/Session. Retire bypassing routes. The
contract changes neither local State data nor persisted root/page formats and
falls back to no older contract/service.

## Implement selected remote retrieval

Corpus `mcp_query` uses query-v1 on an MCP store, with separately bound storage/query
aliases and equal partitions. Research remains captured-source BM25. Follow
[operator remote selection](../operator/corpus.md#retrieve-server-selected-passages)
for complete options/bindings with mcp-lexical. The closed request/reply shape is:

```json
{"version":1,"contract":"query-v1","partition":"manual","request_id":"22222222222222222222222222222222","query":"release quiescence","top_k":5,"as_of_ms":1700000020000}
```

```json
{"version":1,"contract":"query-v1","partition":"manual","request_id":"22222222222222222222222222222222","status":"ok","generation":0,"algorithm":"fixture_terms","algorithm_version":1,"scanned_sources":0,"scanned_chunks":0,"complete":true,"refs":[]}
```

Only ok/complete is accepted. Echo identity and captured generation. Algorithm
names use 1..64 ASCII letters/digits/underscore/dot/hyphen, version positive safe
integer, scanned sources 0..32/chunks 0..1024. Query permits 1..1024 UTF-8 bytes,
top-k 1..10, as-of nonnegative safe integer. Each real call gets a fresh ID.
Nonempty refs contain exactly source_id/source_key/generation/content_sha256/
chunk_id/score. IDs permit 1..256 UTF-8 bytes without controls; keys equal raw source-ID
hash, generation positive, hashes lowercase 64-hex, score finite. Unique source-key/
chunk pairs cannot exceed top-k. Text result is at most 65536 bytes.

Store reads only selected roots/pages at reported generation, checks bytes/source/
chunk/time eligibility, and revalidates roots. Stale/suppressed/historical/forged/
wrong-partition refs refuse the whole result. Empty refs abstain without Store reads.
No full-directory root-count validation occurs. Scores remain server-asserted,
not local BM25 or proof of the server's index/access policy. The
[public MCP proof](../../dev/verification/knowledge_mcp.exs) tests selected-only reads,
denial, wrong partitions, incomplete/forged/stale replies, exactly one empty-query
call, and inert interrupted recovery. It establishes protocol, not ranking quality.

## Implement the Research search/fetch gateway

An arbitrary search tool is not a compatible gateway. Bind exact reviewed tools
through MCP; no worker networking or automatic provider installation occurs.
These complete synthetic JSON objects show search-v1 request and reply:

```json
{"version":1,"contract":"search-v1","query":"release quiescence","limit":2}
```

```json
{"version":1,"contract":"search-v1","status":"ok","hits":[{"source_id":"manual:release","uri":"local:release-policy","title":"Release policy","snippet":"Release requires quiescence."}],"coverage":{"complete":true},"next":null}
```

Hit fields are exact, bounded to 256/512/128/1024 bytes respectively, and count cannot
exceed requested limit. Incomplete/paginated results do not become complete coverage.
Fetch uses the selected hit URI exactly:

```json
{"version":1,"contract":"fetch-v1","uri":"local:release-policy"}
```

```json
{"version":1,"contract":"fetch-v1","status":"ok","requested_uri":"local:release-policy","observed_uri":"local:release-policy","media_type":"text/plain","observed_at_ms":1700000000000,"text":"Release requires quiescence.","body_sha256":"abbba53d88fbef3ff61fa825de40691302cb2837fefec6b4701c41ec69ff5010","complete":true,"start_byte":0,"end_byte":28}
```

The example hash/span actually match. Real gateways report actual requested/observed
URI, media type, capture time/text/hash, complete body and byte span. Coordinates
address captured UTF-8, not original HTML. Requested URI must equal selection;
changed observed URI is explicit provenance, not independently approved egress.
Results permit 65536 bytes through same-invocation windows; investigation body/output
limits still apply. Bad fields/JSON/hash/span/completeness/receipts refuse.
The host proves recorded calls, not source truth or gateway internals.

## Exercise delayed publication and interrupted inference

Build the actual independently selected artifacts, then run public Session controls:

```sh
IPSE_LIFECYCLE_ARTIFACTS=$(mktemp -d)
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LIFECYCLE_ARTIFACTS/graph" --package graph --preset state-model
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LIFECYCLE_ARTIFACTS/corpus" --package corpus --preset state-dense
elixir dev/verify.exs source knowledge-graph-lifecycle --sdk _build/dev/lib/ipse/ebin --input "$IPSE_LIFECYCLE_ARTIFACTS/graph"
elixir dev/verify.exs source knowledge-corpus-lifecycle --sdk _build/dev/lib/ipse/ebin --input "$IPSE_LIFECYCLE_ARTIFACTS/corpus"
```

Each has seven synthetic provider requests/checks and no model weights. Follow
[`knowledge_lifecycle.exs`](../../dev/verification/knowledge_lifecycle.exs): claim,
approve/dispatch, hold response, forget through another Session sharing the binding,
then release. Delayed publication must refuse and inspection/query retain suppression.
Other controls cover cancellation, owner death, profile timeout, exhausted one-request
budget, malformed output, and provider unavailable. Assert socket/lock closure,
uncertainty/reservations, no selected projection, and inert resume separately.
Malformed/unavailable Corpus also explicitly aborts and verifies committed generation/
revision without another provider request.

Graph selects native structured facts and validates actual wire schema/max-items;
Corpus uses typed embeddings. Unknown embedding work retains input but no text-output
liability; unknown extraction retains both. Read canonical records and budget
settlement, not only attempts. The selection scenario additionally uses two equal-
name/width services with different vectors and reported-model/timeout changes.

```sh
mix test test/extensions/knowledge/lifecycle_proof_test.exs test/extensions/knowledge/index_abort_test.exs
elixir dev/verify.exs source knowledge-selection --sdk _build/dev/lib/ipse/ebin --input "$IPSE_LIFECYCLE_ARTIFACTS/corpus"
```

Repeat source scenarios in installed mode with matching archive and the same artifacts.
An older expected revision in the forget control must fail its expected-success
assertion; restore it to prove the actual competing mutation occurred.
[Testing](testing.md) owns inventories/cleanup and complete gates. These fixtures
establish transaction/identity/recovery behavior, not held-out semantic quality.
