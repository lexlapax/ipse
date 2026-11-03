# Pending-candidate shadow assessment — 2026-11-03

This is a focused synthetic result for an isolated candidate, not a promoted
change, P30 completion, a quality evaluation, or evidence of a live account.
It assesses one actual main-tool-created pending proposal from a closed prior
Session under a separately reviewed local shadow grant. The candidate remains
pending: advice cannot publish, accept, change evidence or grant permission.

The frozen base was `131f67e5b715894bad27565c3d91e8a485486395`. The
exact formatted source and test files introduced with this record, the
[overlay manifest](p30-pending-assessment-20261103/overlay-final.sha256),
[full source inventory](p30-pending-assessment-20261103/source-final.sha256),
[compiled-artifact inventory](p30-pending-assessment-20261103/build-final.sha256)
and [evidence manifest](p30-pending-assessment-20261103/manifest.sha256) are
retained. The overlay manifest is directly verifiable from the repository root
at the commit that introduces this record; the full inventories identify the isolated snapshot and
are not, by themselves, archived copies of every source or build artifact.
The snapshot remains at `/dev/shm/ipse-p30-pending-131f.tomQN8EE`, which is
volatile. Source, overlay and build inventories matched before and after tests.

The candidate adds a purpose-specific pending read only for the separately
approved assessment route. Live admission checks the actual installed artifact,
its digest-checked sidecar and the current bundled-shadow inventory before
releasing the value. The version-7 dependency identifies a signed pending
proposal as `never_current`, binds its record, source, policy, root and deadline,
and passes through the existing current-use owners. A Session-created
historical classification receipt binds the recorded parent, artifact,
descriptor, pin, request, result and dependency hashes. Replay checks their
consistency under the existing trusted-journal assumption; the receipt is not
independent cryptographic proof that a wholly fabricated, self-consistent
historical journal came from the bundled artifact.

Before reservation, the host checks the decision input against the exact
candidate ID, text, assigned category and reason and checks the two permitted
choice IDs. The focused fixture does not mutate the choice IDs. The question's instruction text is supplied by the digest-pinned
bundle; the new check does not independently bind an exact instruction string.
This increment supports the bundled `pending.<64-hex>` recipe; it does not add
general proposal-prefix support or relax generic pending get/scan containment.

The following ran against the formatted source using isolated fixture homes,
`MIX_ENV=test`, `TMPDIR=/dev/shm`, two BEAM schedulers and local synthetic
services. Native helpers, strict project compilation and both Knowledge
bundles were built before the tests. The compile output includes upstream
dependency warnings. Changed files were formatted; no full-suite result is
claimed. The logs show command output, not independently encoded invocation
flags or exit status; these details come from the recorded execution.

* The [positive Session](p30-pending-assessment-20261103/pending-session-positive.log)
  created the pending proposal through the actual main tool, closed its source
  Session, obtained native decision approval in a fresh Session, and checked
  the decoded loopback decision request against all four proposal fields. It
  checked the v7 receipt, directly tested rejection of a changed candidate by
  `pending_input_bound?/2`, rejected tampered receipt fields on replay,
  observed advice, verified no second publication and
  compared the Collection snapshot before and after. It also restored and
  reopened the consumer Session without a repeated call.
* [Original source loss before decision](p30-pending-assessment-20261103/pending-source-before.log)
  produced no decision request or reservation. [Loss before output release](p30-pending-assessment-20261103/pending-source-output.log)
  recorded release of the already-settled advice as withdrawn; no recorded
  main-model request contained the assessed result. Each
  control restored and checked the original source inode and hash.
* [Native denial](p30-pending-assessment-20261103/pending-denied.log) sent no
  decision request. [Revocation before a fresh Session](p30-pending-assessment-20261103/pending-revoked.log)
  prevented the decision path. Grant expiry held at
  [preflight](p30-pending-assessment-20261103/pending-expiry-preflight.log)
  prevented dispatch; expiry held at
  [result admission](p30-pending-assessment-20261103/pending-expiry-result.log)
  left the dispatched operation unknown with its call reserved and no accepted
  decision response. These are grant-expiry controls, not a separate signed
  proposal-deadline expiry test or revocation interposed at output release.
* A [malformed dispatched response](p30-pending-assessment-20261103/pending-unknown.log)
  retained an unknown charged reservation; reopening the same Session did not
  repeat the request. [Low-confidence advice](p30-pending-assessment-20261103/pending-low-confidence.log)
  abstained.
* An [admitted alternate artifact](p30-pending-assessment-20261103/alternate-artifact-test.log)
  made a marked read that failed without a managed-read receipt or decision.
  The fixture separately checks its reconstructed assessment mapping and the
  bundle classifier's refusal; it does not trace the classifier inside the
  actual action, so the generic failure does not independently identify its
  precise cause. Three existing
  [generic containment controls](p30-pending-assessment-20261103/pending-generic-containment.log)
  passed, covering missing/expired originals and a removed custom proposal
  recipe, including get and scan cases.

The first [Knowledge worker test](p30-pending-assessment-20261103/knowledge-capture-test.log)
ran all 13 inner cases successfully but failed because the outer harness still
expected 12. Its captured inner output also reports a compile-order warning for
the Knowledge contracts module. The later outer log suppresses that inner
output and does not establish whether the warning remained. Only the expected
count was corrected; the
[subsequent run](p30-pending-assessment-20261103/knowledge-capture-test-corrected.log)
passed. Both outcomes and the pre-correction overlay manifest are preserved.

An independent whole-document review covered the proposed operator and
developer manuals. Their archived copies have SHA-256 values
`12725004aef793f1504a9a9f2a5da28daf5c2dd984252c84c0d5b2be27c42ccf`
and `90827f8c01852f066b4f93c2ef9b0433c12d7b3c2b5e2ac6d9d81db25e6cec16`,
respectively. The [first documentation check](p30-pending-assessment-20261103/docs-check-first.log)
in a sanitized indexed mirror reported one missing test target: the new
focused Session test had not yet been copied into that mirror. After the exact
tested test file was copied and staged there, the
[recheck](p30-pending-assessment-20261103/docs-check-with-fixture.log) passed
with 1,117 Markdown files, 9,190 local links and zero errors. This checks link,
anchor and manual/archive rules; it does not promote the candidate.

The separate [historical-v3 resume investigation](pending-legacy-resume-control-20261103.md)
observed two startup refusals but did not measure the listener after the linked
failure or test withdrawal during a successful compatible resume. That inherited
question, broader integrated validation, installed behavior, live-provider
access and decision quality remain open.
