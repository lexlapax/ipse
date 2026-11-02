# Capture after a current managed-source read

Dated **2026-11-02 UTC** (**2026-11-01 US/Pacific**), author-run synthetic Linux
implementation and verification based on `f7653ce`. This is an engineering
record, not complete C0/P31 acceptance or independent review. The
[original failed positive](managed-collection-module-v3-20261101.md#open-positive-capture-after-a-current-literal-read)
remains preserved. The [plan](../../plan.md) owns outstanding delivery gates;
the [developer flow](../../developer/collection-sdk.md#follow-one-capture-across-its-owners)
and [operator procedure](../../operator/knowledge-permissions.md) describe current scope.

## Required positive and implementation

The original probe reads a genuine native-reviewed literal A, quotes original
unattended input B from a different Session, then attempts one new V3 pending
capture. Neither original is withdrawn and the root is unchanged. The former
CAS-only gate refuses before intent. Simply deleting that guard would leave
publication without the original A owner at its native decision.

The new `Session.ManagedCapture` adapter keeps the existing one-new-v3 predicate
and complete inherited-plus-own invocation union. Content dependencies are not
relabeled as root-only metadata. Existing payload-free root prerequisites retain
their original cache classification; scans and unclassified root observations
still refuse. Structural admission grants no effect authority.

The owned effect asks Session for its exact parent/action/dependency digest.
`ManagedUse.with_publication_dependencies/4` reuses the existing authenticated
observation, current-reference comparison, recipe/policy checks and source reader.
Original acceptance journals are retained before Session sources, outside the
publisher's Identity/Consent locks. Candidate proofs join the complete original
source set. All proofs remain bounded to 128; inactive source groups and acceptance
journals share the existing 128-owner reserve. No source or journal is evicted.

The publisher then acquires its existing Identity, Consent and Collection owners.
After normal V3 normalization, `Collection.execute_managed_capture/7` compares
the complete actual root witness with every provisional current observation and
the unchanged candidate generation. An intervening root cannot be silently
refreshed. The comparison adds no normalizer reads and does not enlarge its
32-unit closure, sidecar bound, schema or accounting reservation.

A distinct capture ticket binds the real task/job, parent, exact action and union
digest. The existing `Runner.SessionSource` protocol transfers the consuming
Session flock/control, drained Writer and inactive original sources into that
same depth-three native transaction. Accepted references additionally import
their original committed management-journal descriptions. This uses existing
OTP, Collection, Transaction and source-owner APIs; it adds no dependency, native
ABI, helper mode or protocol framework. A capture ticket cannot start a synthetic
terminal or grant ordinary workspace/shell/MCP effects.

The source/policy deadline and normalization deadline narrow the existing native
final root decision. Source/control settlement and Writer thaw precede returning
from the collection, while original-source scopes enclose Identity release.
Only their checked completion permits deferred settlement and a smaller measured
charge. Post-admission ownership loss retains full liability. A poisoned Session
can stop before appending an action result: its unfinished intent remains unknown
under strict Saved reconstruction, rather than inventing a successful cleanup.

This positive preserves A in durable conversation lineage. B's own provenance
remains unattended input and its normalization reports `never_current`; it does
not become endorsed merely because the invocation read A. A later acceptance is
a separate explicit user decision with its own source and native review contract.
This increment does not implement general cross-store derived-record lineage.

## Actual controls and retained failures

The default Session fixture now has a literal-publication mode using its actual
signed native `/remember` seed, actual source list/read/quote and registered local
HTTP main route. It carries no fabricated dependency, grant or read receipt.

The positive requires A's genuine version-4 dependency, successful B save and
turn completion, exact public stored candidate, next generation, unchanged A
journal, never-current normalization, measured settled usage, retained A in Saved's
dependency dictionary, no unknown Worker input and inert idle resume.

Two controls hold the actual Worker after B's quote input has arrived. Removing
A's original journal or revoking policy then refuses capture, preserves the root
and existing operation ledger, and reconstructs/resumes without replay. The
separate earlier stale-root A/B refusal and original-source Worker-input controls
continue to pass.

The staging fault closes A's **actual exported native source owner** after new B
storage is staged. It does not change source bytes or inject Session state. The
native write cannot select the new root; the poisoned consuming Session stops.
The journal retains one unfinished publication intent and no publication result;
strict Saved marks the interruption unknown. Full publishing/unknown liability
has null actual/receipt and survives read-only inspection and idle resume.

| Seed | Selection | Terminal result | Seconds | Exit |
| --- | --- | --- | --- | --- |
| 791725 | Original temporary acceptance probe against the integration | 1 passed, 186 excluded | 15.7 | 0 |
| 791726 | First four default controls | 3 passed, 1 failed, 186 excluded | 39.0 | 2 |
| 791727 | One-request HTTP fault fixture correction | 3 passed, 1 failed, 186 excluded | 44.2 | 2 |
| 791728 | Four new controls plus original A/B, inherited-input, registered capture, accounting and deadline regressions | 14 passed, 176 excluded | 66.8 | 0 |
| 791729 | Six complete component modules below | 89 passed | 76.6 | 0 |
| 791730 | Four new controls after the full build, including exact Saved output-union binding | 4 passed, 186 excluded | 40.6 | 0 |

Seed 791726 failed because the HTTP server waited for a second model request on
a path that must withhold continuation. Seed 791727 then exposed an incorrect
new test expectation: poisoned source ownership stops Session without a final
`done` or action result. The corrected test requires actual Session termination,
unfinished intent, unchanged root, full liability and unknown strict recovery.
No runtime fence was weakened for either correction. The temporary probe's first
launch waited for the already-running compilation's Mix build lock; this is not
a frozen/isolated runtime inventory claim. Subsequent cohorts ran serially.

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only current_literal_publication --only managed_ab_probe --only worker_inherited_union --only registered_capture --only publication_accounting --only strict_deadline_gate --max-cases 1 --seed 791728
mix test test/ipse/session/managed_tool_use_test.exs test/ipse/session/managed_use_test.exs test/ipse/extension/managed_collection_call_test.exs test/ipse/extension/collection_managed_v3_test.exs test/ipse/extension/notes_publication_admission_test.exs test/ipse/extension/collection_deadline_gate_test.exs --max-cases 1 --seed 791729
```

The full repository build, `mix compile --warnings-as-errors`, global formatting
check, diff-whitespace check and credential-free demo also exit zero. The build
rebuilds the helper and inert shipped artifacts. No package or external model
call ran. Source checks are not installed-package qualification.

## Evidence scope and remaining work

Selected post-run hashes, not a complete prelaunch/loaded-runtime inventory:

| Artifact | SHA256 |
| --- | --- |
| `/tmp/ipse-current-literal-publication-first-20261102.log` | `51d40b17c39bceec382fe3fd4285d79496617365fd2167ababe254c3d8f4b47c` |
| `/tmp/ipse-current-literal-publication-controls-20261102.log` | `debd7d134359ffebbe4f1bb92b2a1fa68e8e79f92557026c6a4eec71cd8bdbee` |
| `/tmp/ipse-current-literal-publication-controls-paired-20261102.log` | `9c4ce21497f94be163b48099e51efa00dd1e105b9cb671967e337534a1b96b68` |
| `/tmp/ipse-current-literal-publication-regressions-20261102.log` | `f01572c65b028a3af00616979519ebac82944d5a4cfb53025a2c681d93b3dcb9` |
| `/tmp/ipse-current-literal-publication-components-20261102.log` | `9773828ac3883f8eaf5e648beed8bf9958b1d3d6f7a926bd67f03357e5676222` |
| `/tmp/ipse-current-literal-publication-final-20261102.log` | `bc90a2c0641ec1be466818e9e010c8ab5ddb8624a71d37b570d3c0fbcf432a87` |
| `Session.ManagedCapture` | `e29a69dde6685bf6b7118ebab165f0c8b3b69da7895ecf5c259116aae929dc01` |
| Final Session test module | `5e63bee42067717c22e4ddad2b257702ecb7e055b77f9d2e74a727d595839095` |
| Rebuilt native helper | `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a` |

Historical/accepted-note capture combinations, maximum unions, full publication
expiry/loss combinations, complete-module/whole-suite regressions, installed
journeys, independent model quality, lifecycle/endurance and final adversarial
acceptance remain open. No focused result replaces the failed frozen module or
whole-source aggregate. The broader P30/P31 goal remains active.

The Collection SDK and Session-source developer chapters and operator knowledge
permission manual were read as whole workflows and reconciled around ownership,
pending attribution and conservative readiness. Current manuals retain the
unqualified installed/model/platform limits. Private qualification labels and
untracked `.serenity-*` directories were not opened or copied.

Documentation checking reports 1,031 Markdown files, 8,544 local links and zero
errors, with the existing private-directory discovery warnings kept separate.
The audience indexes already route these chapters; no manual was moved or added.
