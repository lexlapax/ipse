# Main-Session request enhancement integration

Development record, **2026-10-27**, resumed from `8af77bf` and its
[interrupted worktree handoff](handoff-worktree-20261027/README.md).
The developer confirmed P30/P31 as the resumed scope. The [plan](../../plan.md)
owns status; [terminal usage](../../operator/usage.md#refine-a-request-before-submitting-it)
and [context training](../../developer/workspace-context.md#withdraw-draft-intent-before-ordinary-work)
own current procedures and implementation flow. No milestone or release is accepted
by this integration record.

## Scope and source selection

The integration starts from the exact [first-use MCP draft patch](draft-mcp-first-use.patch),
SHA-256 `39ccdaee126e2c38d7b5cac3d73e86d526af3ec2dfd8a2d25cc574b616467c25`.
Its prior [independent review](draft-mcp-first-use-independent-audit.md) covers that
private patch, not the subsequent `/enhance` adaptation. It applied cleanly to
the resumed source without overwriting the existing managed-collection, inference
transport, dependency or capacity-driver experiments.

The imported workflow runs a bounded draft turn in the actual Session, retains
the ordered tools, enforces the temporary execution ceiling, records native
questions/read evidence, and accepts only the exact rendered revision through a
fresh native-terminal witness. Cancelled/private intervals stay in the original
journal and are projected out of later model and eligible source inputs. Accepted
provenance remains conservatively attached across later model/tool/extension
operations. Configured MCP discovery is journaled before setup, bound to the
initial catalog, and revalidated after a pending question resumes. It is not an
MCP tool grant or proof that arbitrary configured descendants are confined.

The adaptation exposes `/enhance` instead of the private `/draft` vocabulary,
supports inline original requests and ID-specific acceptance, and includes the
current draft ID/revision/status in Session inspection. The full command line is
retained as witnessed input; only the effective instruction removes its prefix.
Replay recomputes that transformation. No provider, endpoint or billing route is
substituted, and no dependency is added for this feature.

## Retain first failures and repaired controls

Before adaptation, the imported patch passed **114 focused tests**, seed 20270318,
with one case at a time on the working tree. A new inline terminal journey then
failed: **23/24 passed**, seed 20270319, with the inline case reaching ExUnit's
60-second watchdog. A diagnostic rerun with a 90-second observation watchdog
retained the unchanged driver's own 60-second failure in
`/tmp/ipse-enhance-inline-diagnostic.log`. It showed the stale ID being refused
but no draft ID being rendered: the generic status handler replaced the new
message with `Running…`. A dedicated `draft_ready` event repairs that UI path.
The unchanged inline journey then passed, seed 20270320.

Source review also found that `/cancel` during single-line draft/replacement
entry retained the pending client action, while cancelling at the acceptance
display did not abandon the completed draft. The client now clears entry state
and abandons a displayed acceptance explicitly. A new actual PTY journey checks
ordinary input before/after these boundaries, absence of replacement/acceptance/
consumption records, unchanged revision, retained cancellation and safe replay.
All **six terminal tests** pass, seed 20270321. These are synthetic operator-channel
controls, not a human usability trial.

The initial whole-working-tree build and 37 P30 protocol/admission tests passed
before draft integration. Those results do not qualify the final feature or the
uncommitted experiments. Final isolated-source and package results are kept
separately below.

## Isolated source and unfinished broad verification

A private Git index selected only these 43 feature/document paths over `8af77bf`,
excluding the pre-existing experiments. The complete archived source tree is
`bb489636c768d275c0060fb8d2a79f348f1622e1`, retained under
`_build/enhance-verification-52d8ac809e70`. Its source copy has its own Git index;
`git diff-files --quiet` confirms tracked bytes remain unchanged. Dependency sources
were copied and retain the existing lock; this is not a hermetic-build claim.
The [receipt](enhance-verification-20261027.json) binds completed logs, selected
source bytes, native helper, source archive and local bundle.

The private ordinary build compiled **141 project files with warnings as errors**
and built the inactive knowledge catalog. Existing upstream dependency warnings
were printed separately. Formatting, CI policy and documentation checks pass;
the private documentation check found 635 Markdown files and 5,190 links with zero
errors. A separate standalone `mix compile --warnings-as-errors` attempt was
blocked by the sandbox's TCP lock policy; it supplies no additional pass.

The first full suite uses seed 20270322, maximum two cases, and the normal
platform exclusions. It is **still running at this checkpoint**, unified-exec
session **88188**; its retained output is `full-test.log` under the private root.
There is no final result or exit status yet. Native-dependent cases refuse on
the unadmitted kernel. Its `TMPDIR` was also incorrectly placed under the outer
repository, so synthetic non-repository workspaces inherited the outer AGENTS
and README. This caused workspace, context/quota and conformance fixture failures;
the first run must remain a failed/environment-contaminated observation even
after those fixtures pass elsewhere.

The developer reauthorized a previously declined outside-directory recheck.
All **12 workspace tests pass** with `/var/tmp/ipse-enhance-tests.slGYaYCG` as
`TMPDIR`, seed 20270323. A broader unchanged-source run in that same directory
passes **204 tests**, exit 0, seed 20270324, one case at a time: the ten enhancement/
MCP/extension suites, workspace, conformance, journal, and ten P30 suites. Expected
quota-loss GenServer logs are retained; they are not failed assertions. This
focused success does not replace the unfinished full baseline or establish native
protected publication.

## Local bundle and retained installed failure

A separate packaging graph has the identical source tree. Default PDF-enabled
packaging passes, retaining exact-version upstream Elixir/OTP notices and the
existing 60-crate PDF notice closure. Its documentation archive check reports
51 manual documents and zero missing targets. Initial sandbox attempts failed
at GitHub notice acquisition and the existing sccache compiler wrapper; the
authorized outside-sandbox operations succeeded without weakening TLS or inventory
checks. The local archive is not a release/publication. Because the synthetic Git
graph has no commit, its documentation source reference falls back to `v0.1.0`;
the exact source-tree receipt is authoritative for this local candidate, and a
final distributable needs a real source-commit binding.

Installed verification **fails**, exit 1, in the session-permissions proof with
`permission proof timed out`. Its preceding archive/build-identity, offline doctor,
setup/private configuration/demo and Grok offline/missing-registration checks
passed. No complete installed pass is claimed. The fixture consumes events until
`done: :ok` and does not preserve a prior `done: :error` cause; diagnose the actual
request/event path before changing its five-second watchdog or expectations.
The failure is unresolved, not attributed to a product or fixture defect by this
record. Its log remains `installed-package.log` in the private root.

The [model-switch handoff](handoff-20261027-enhance.md) preserves the active full
test session and next checks. The developer chose to keep work in this agent;
no subagents were used for the integration or its author review.

## Remaining qualification

Protected storage still refuses the actual `7.2.11-arch1-1` host; the production
allowlist is unchanged. No test-only kernel override is selected for this
integration. Current knowledge eligibility, protected saved-consent/registered
inference journeys, sustainable storage, planning MCP reads and integrated recall
remain separate gates. Native drafting does not supply the missing current-root
barrier. Live provider carryover, other opaque continuation contracts, whole-source
verification and macOS/human journeys remain unqualified. No live model requests,
downloads, paid decision calls or device effects were made in these controls.
