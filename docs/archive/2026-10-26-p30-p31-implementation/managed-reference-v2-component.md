# Explicit managed absence dependencies

Dated **2026-10-26**. This extends the earlier
[pure managed-reference checkpoint](managed-reference-component.md). It is an
internal contract increment, not Session integration, current recall, a live
freshness check or milestone acceptance. The [plan](../../plan.md) remains open.

## Contract and compatibility

[`ManagedReference`](../../../lib/ipse/session/managed_reference.ex) accepts a
closed dependency version 2 with `version`, `project_id`, `namespace`,
`pin_sha256`, `policy_generation`, `collection` and `subject`. The existing
version-1 contract remains readable unchanged. No version is inferred from a
missing field, and an eligible refresh cannot change dependency version.

Version-2 `collection` contains exactly `project`, `generation`, `floor`,
`floor_anchor`, `root_state`, `root_sha256` and `manifest_sha256`. Absent means
generation/floor zero, null floor anchor and null hashes. Present requires real
root and manifest hashes. An anchored materialized empty store remains present.
An imported floor may exceed local generation. These shapes match the distinction
established by [native read-view v2](collection-empty-read-view-component.md), but
this pure module does not open or authenticate that view.

`subject` has one of two closed shapes:

- `kind: record`, plus `record` and `validity` using the prior normalized
  key/revision/value and host validity contracts. Only a present root permits it.
- `kind: absence`, plus a `selector`: either `kind: record` with one exact `key`,
  or only `kind: collection` for a genuinely empty collection. It contains no
  fabricated recipe, lineage, source version, expiry or record digest.

An incomplete or filtered scan cannot use the collection-empty selector. Such a
query needs a separately reviewed completeness/window contract. An absence is
still a dependency: the original producer's whole message, inherited paraphrases
and checkpoints remain subject to the same union and withdrawal rules. Absence
does not certify a statement's truth or grant permission.

An eligible refresh preserves exact version/project/namespace/pin/policy and
subject identity. Record refresh additionally preserves recipe, lineage and source
versions, and observes exclusive expiry. Absence refresh preserves the complete
selector. Both refuse root/floor regression or a changed root at the same
generation. A host can prove that the same key is still absent at a later root;
the pure function never performs that proof. A first publication may instead
invalidate the observation and withdraw its entire occurrence.

All prior dependency/dictionary/index/event byte and count bounds remain. There
is no new dependency, custom serializer, IO, native operation, Session writer or
SDK permission. Replay remains IO-free and returns `live_pending: true`.

## Source-bound verification

The isolated graph is `/tmp/ipse-managed-reference-v2-20261026-01`. It copies the
earlier native CLI repair graph and replaces only the managed-reference source
and test. It excludes the concurrent decision-policy increment and later empty
read-view implementation. Its actual helper digest is
`6f431b5aedde35ecb6f8737e7714dbd197df83c7e8d52e909243e0a39152a55d`;
these pure tests do not exercise that helper.

| Check | Actual result |
| --- | --- |
| Full isolated compile | 128 source files, warnings as errors, pass |
| Focused suite | 24/24, seed 20261107, 11.3 s |
| Managed/reference/replay/wire/context/source-index regression | 81/81, seed 20261108, 11.9 s, maximum two cases |
| Source/runtime inventory | 1,104 regular project/build inputs identical before and after both test runs and compatibility compile |
| Elixir 1.20.4 formatting | Both changed source/test files pass |
| Elixir 1.18.5 | Both files formatted; three managed-reference modules compiled with empty diagnostics on OTP 29 |
| Independent adversarial audit | Owned 24/24 and fresh 12/12; no actionable finding; all 1,104 inputs unchanged |

The first compatibility harness incorrectly appended a second newline to the
formatter result and failed before compilation. The retained inspection diff
shows only that extra newline. Correcting the harness, without changing source
or test, produced the passing check. This is not an OTP-27 run.

The four new tests exercise closed/missing fields, fabricated absent hashes,
absent record substitution, unsafe/filtered selectors, first-publication withdrawal,
unchanged-absence clearance, exact subject/version substitution refusal, real-root
identity at materialized emptiness, imported floors, exclusive record expiry and
inert replay. The original 20 tests pass unchanged. Inputs are synthetic; no
qualification gold, model, account, human or installed package was used.

The durable owner-only copy is
`p31-verification/managed-reference-v2` under this task's artifact root. It retains
1,117 payload files, including the complete regular source/runtime graph, logs,
manifest, failed compatibility harness evidence and corrected harness. Symlinked
dependency source is omitted; the exact regular dependency BEAMs used by the
graph are retained. Copied executable files are data with mode 0600. Copy to a
fresh working directory before any rerun. The
[runtime receipt](managed-reference-v2-runtime.json) binds hashes and limitations.

The [independent report](managed-reference-v2-audit.md), finalized on October 27,
retains the first 11/12 driver result: its unfinished assistant tool-call fixture
correctly refused planning before withdrawal. Adding its matching synthetic result
and removing an unused default reached the intended unsafe-withdrawal check;
all production assertions remained unchanged. Fresh tests also measured exact
8,192/8,193-byte dependencies, 4-MiB dictionaries, negative inheritance/checkpoint
unions, mixed-version batch verdicts, cross-request replay, maximum safe expiry
and 2,048/2,049 dependencies. The auditor reran the owned 24, not the author 81.
Its separate 1,166-file evidence preserves the complete graph, original/corrected
drivers, failures, diff and all before/after checks.

## Editorial and remaining work

The complete developer context chapter, relevant persistence flow and operator
knowledge-permission procedure were reviewed. The context chapter now teaches
the pure v2 shape and its limits beside source paging; operator behavior is
unchanged. The old checkpoint remains historical and links forward here.

This is not the post-implementation milestone audit. Protected provenance,
current eligibility, raw-read taint, successful-publication facts, Session and
assistant/checkpoint inheritance, SourceIndex lineage, effective-input projection
after queue waiting, and every-dispatch admission remain separate integration
gates. A worker map or an imported structural hash cannot satisfy them.
