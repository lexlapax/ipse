# Selected Collection cosine and hybrid retrieval

2026-10-31, source increment based on `1562060`. This implements selected-source
semantic retrieval through the existing public Corpus artifact. It does not
complete namespace-wide dense search, producer/capacity qualification or P31.
The [plan](../../plan.md) owns acceptance; current procedures belong to the
[operator chapter](../../operator/corpus.md#query-selected-shared-vectors) and
[developer training](../../developer/knowledge-extensions.md#rank-explicitly-selected-collection-vectors).

## Runtime boundary

`collection-dense` admits dense and graph-free hybrid profiles with refusal for
missing projections. `query_selected` retains the lexical argument shape for
BM25; semantic queries additionally require exact selected vector/fact identities.
It uses `Collection.Selected` for complete source/group hydration, then existing
read-only `embedding.profile` metadata to verify the configured recipe. The
actual approved query request pins that selection independently. Prefixes apply
only to query embedding; lexical ranking and citations keep original bytes.

The shared cosine/fusion implementation retains input, model, dimensions,
encoding and selection checks. The selected snapshot carries its native
Collection generation. A post-inference catalog read must reproduce both that
generation and catalog hash, including when only a projection root changed.
Current-time queries also recheck source expiry after inference. Changed state
returns no evidence/claims. Coverage remains selected-only, explicitly lacks
later-use authority and cannot turn supplied vectors into model receipts.
Returned evidence has open/unassessed semantic-support labels.

No core, SDK, native protocol, dependency, provider choice or approval gate
changed. Query consumers retain the ordinary v1 document binding; the existing
source-bound producer still requires its v2 claim on every embedding request.
The raw namespace query remains lexical and these APIs search at most eight
explicit sources. A missing/corrupt group refuses without partial evidence.

## Controls and preserved failures

The actual public artifact is built and imported into a native Session with an
explicit registered loopback service and normal embedding approvals. Trusted
fixture setup supplies the source/projection generation; it does not qualify
complete public production or historical model provenance. Synthetic vectors
make cosine order differ from lexical order. Controls retain Unicode query
formatting, Word locator/partial-document warnings, source expiry during the
approval wait, changed Collection state, no-dispatch recipe mismatch, action
validation and Saved reconstruction.

The initial two controls refused `profile_authority_mismatch`, exposing the
remaining preset-admission gate. After implementing the supported admission,
both functional paths completed but their ExUnit cleanup failed by calling
`Task.shutdown` outside its owning process. The fixture now kills only its own
remaining task PID from cleanup. A third run passed three controls in37seconds.
The new stale-recipe case then exposed a conservative unknown invocation when
sent directly to `embedding.create`; the read-only metadata preflight now
refuses that mismatch before an embedding request or dispatch intent.

Four controls passed in43.1seconds after that repair. With explicit open-support
labels and the closed missing-vector policy, four passed in40seconds; the profile
admission grid passed9tests in3.5seconds. The final strengthened root-only race
cohort passed4tests (59excluded) in43seconds. Broader profile/domain/fusion/output/
directory/producer regressions passed45tests in320seconds; final artifact/build
contracts and minimal-public-SDK proof passed5tests in4.6seconds. These are
separate selected runs, not a new aggregate baseline. First logs remain at
`/tmp/ipse-collection-semantic-selected-{first,second,third,final,preflight}-20261031.log`.

The complete documented options passed artifact construction, disabled
configuration generation, actual CLI import and configuration validation in a
temporary private home, without Session or inference-service creation. The
first launcher used a relative executable path that `System.cmd` refused;
rerunning only those remaining CLI steps with its absolute path passed. Neither
run contacted a model. Local scripts/logs use prefix
`/tmp/ipse-collection-semantic-manual`.

Operator Corpus, developer Knowledge extensions and the package README were
reviewed as whole documents; the procedures distinguish query readers from
guarded producers, selected coverage from namespace search, and protocol checks
from semantic quality. The baseline full-suite failures and unanswered managed
display policy remain separate. No live call allowance was consumed.

The [source/test inventory](collection-selected-semantic-20261031.json) pins the
six final changed implementation/test files and actual native helper. Standard
build passed180modules and three bundles; the bundles were refreshed after the
last Corpus changes. Warnings-as-errors compile, format, CI policy and the
credential-free demo passed. The documentation checker reported979Markdown files,
8148local links and0errors before this inventory link was added. Final native
log: `/tmp/ipse-collection-semantic-selected-root-fence-20261031.log`; regression
log: `/tmp/ipse-collection-semantic-regressions-20261031.log`. A fresh full-source
run remains required and cannot be replaced by these focused checks.
