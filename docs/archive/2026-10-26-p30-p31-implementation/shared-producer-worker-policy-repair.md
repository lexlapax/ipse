# Producer worker policy checks — 2026-10-29

This is a partial repair of the blocking source-policy gap in the
[first-page review](shared-producer-first-page-independent-review.md).
The original `92c215...` cohort is unchanged and remains on HOLD. Approval of
a destination or full embedding input is not permission to waive source
eligibility. The [plan](../../plan.md) owns acceptance.

The [manifest](shared-producer-worker-policy-repair/manifest.json) pins the
candidate worker/source/test snapshots, original counterexample, focused logs
and strict-built candidate artifact. This record qualifies worker checks only.
It does not claim the absent trusted Host approval/dispatch fence or a new
native/current-source inference qualification.

Manifest SHA-256:
`7f880bd4bc594fea9dfb8026c1aaa530e98b958ddf8f568bcb758b88225b9ad7`.
Four source snapshots, three logs, twenty-six candidate artifact files and the
unchanged original ancestor are pinned. Read-only `47153` verifies all thirty-four
rows, with zero hash/size failures.

The worker now authenticates source bundles and actual native head revisions
before claiming. It applies the existing `Evidence.current?` policy at worker
UTC: observation is not in the future, historical is false, and finite expiry
is strictly later than now. It rechecks eligibility before claim publication,
before every embedding batch and after the final batch. Before each batch it
reloads the exact pending claim, pins a fresh native read epoch and checks
captured catalog, selected-root (including absence), Job, pending and source
head revisions/hashes. A change stops without a retry/adoption token and leaves
pending uncertainty intact.

The private claim is explicitly **version 2**, recipe
`ipse.evidence.shared_producer.first_page.v2`. Public arguments remain version
1; existing shared vector bytes remain unchanged. Ordered source bindings add
source key, native head revision/hash, complete bundle hash, chunking hash and
observed/expiry/historical facts. Claim/ready metadata still must fit 8 KiB.
Old private v1 records are refused rather than silently reinterpreted/adopted.

`47145` runs the desired expired-source control against the exact original
artifact: it demonstrates four modeled inference calls and `page_ready`, then
fails the desired refusal. This concrete counterexample is retained. It is a
closed-host fixture, not a new native or model-service call.

`47146` strict-compiles current feature source in an isolated worker and passes
eight focused controls (6.1 s outer / 2.8 s nested). Expired, historical and
future-observed inputs make zero claims and zero inference calls. Expiry
during the preceding batch, and source/root/catalog mutation, stop before a
second inference call. Unknown outcomes still do not replay. A finite-TTL
positive remains supported: four calls / twelve effects / 114 reads, ready
metadata 4,795 bytes, unchanged 45,064-byte shared page and 12,759-byte maximum
host frame. No finite-TTL support was permanently excluded. The separate
`47147` candidate artifact builds strictly with zero diagnostics.

Worker time checks cannot cover a subsequent human approval delay, changes
before actual Host dispatch, or a clock/source race after returning a request.
No later query filter or unselected storage is an egress fence. The Host needs
authenticated current project/store and exact source/root/Job/pending binding,
actual bundle eligibility and chunk/input facts, then host UTC and exclusion at
the owned dispatch boundary after approval. Source heads contain bundle refs,
not observation/expiry/historical fields, so a worker deadline alone is not
sufficient. Host must authenticate bounded private bundle reconstruction; no
full source can be sent through one SDK object with an 8 KiB scalar limit.

This cohort is frozen before the separate temporary public page gate. No
aggregate capacity, acquisition, native Session or live-model run was repeated.
Full producer, finite-TTL Host admission, recovery, operation/journal/physical
budgets and C1b/F qualification remain open.
