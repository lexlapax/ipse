# P30/P31 continuation after enhancement integration

2026-10-27. The developer confirmed that the resumed goal is **P30/P31**, then
asked to switch to Terra 6.1 when ready. They explicitly chose **keep work in this
agent** when asked about independent-review subagents. Do not spawn subagents
without a later authorization. P30/P31 and the experimental enhancement increment
are not accepted as complete. Publication is not authorized.

## Preserve the current work and running check

Branch: `codex/p30-p31`. The focused checkpoint containing this handoff integrates
the previously independently reviewed main-Session draft patch and the `/enhance`
terminal adaptation. It preserves all older individual prototype records. The
[integration record](enhance-integration.md) owns actual observations and limits;
the [receipt](enhance-verification-20261027.json) binds selected source and outputs.

The pre-existing managed SDK-v3, Mint transport, egress/witness and capacity-driver
experiments remain dirty/untracked in the original working tree. They were excluded
from the feature's isolated source selection and must not be swept into a commit
or overwritten. The earlier [worktree snapshot](handoff-worktree-20261027/README.md)
still identifies them. The `.serenity-*` ledgers/backings, devices and retained
fault outcomes were untouched; do not clean, bind or replay them.

The already authorized full regression process is still active at this handoff:

- Unified-exec session ID: **88188**. Poll it with `write_stdin` and empty input;
  do not start a duplicate run or infer completion from a quiet log.
- Root: `/home/lexlapax/projects/lexlapax/ipse/_build/enhance-verification-52d8ac809e70`.
- Source: that root's `source/`; log: `full-test.log`.
- Command: `TMPDIR=ROOT/tmp mix test --seed 20270322 --max-cases 2`, with output
  redirected to the log. Standard native/macOS/memory-scope tags are excluded.
- Frozen source tree: `bb489636c768d275c0060fb8d2a79f348f1622e1`, base `8af77bf`,
  43 explicitly selected paths. Source tar, selected paths/hashes and private index
  are retained alongside it. Neither private source graph has a Git commit.

This run has already observed native-profile refusals and environment-induced
context/quota failures: `ROOT/tmp` is inside the outer repository. **Use
`/var/tmp/ipse-enhance-tests.slGYaYCG` for subsequent test workspaces.** It is a
private Btrfs directory outside the repository, created with explicit approval.
Its corrected workspace run passed 12 tests; the broader focused run passed
204 tests, exit 0. A full corrected baseline is still required. First retain the
current run's final summary and exit status; no final status was available when
this handoff was written. Keep source/build/helper bytes fixed during a run.

## Resume the unresolved verification

1. Collect the active full-suite result. Retain the original failures and classify
   them against native refusal and repository-boundary contamination. Do not
   relabel the 204-test focused run as a full pass. A corrected full run should use
   a clean committed source graph and the outside-repository temporary directory.
2. Diagnose the **installed package permissions timeout**. The bundle builds,
   but its installed `package` scenario exits 1 after four preceding checks pass.
   `package.log` and `installed-package.log` are in ROOT. The exact archive is
   `ROOT/package-source/dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`.
   `dev/verification/package.exs:214` constructs the fixture; its receive loop
   waits for successful completion and ignores the earlier error cause. Observe
   the actual native request and terminal events before changing anything. A
   reference-selection fixture defect is only a hypothesis; it is not proven.
   Do not increase deadlines or weaken behavior to obtain a pass.
3. Rebuild a final candidate with a real source-commit identity before treating
   a package as distributable. The current synthetic graph falls back to the old
   `v0.1.0` documentation source reference. No release was created or published.
4. The ordinary private build already strictly compiled 141 project files.
   Formatting, CI policy, and documentation pass. The additional standalone
   strict-compile command encountered the sandbox TCP-lock refusal; rerun with
   the normal permission flow when it cannot race the active build/test graph.

## Feature scope and remaining delivery work

`/enhance TEXT` uses the current Session/main route. It supports next-line and
multiline replacement, exact native acceptance, bounded questions, cancellation,
source/history withdrawal, accepted provenance and MCP catalog revalidation.
The terminal has a dedicated draft-ready event, shows the current ID/revision,
and clears pending input/acceptance on cancellation. All six native terminal
tests pass. Current procedures are in
[usage](../../operator/usage.md#refine-a-request-before-submitting-it) and
[context training](../../developer/workspace-context.md#withdraw-draft-intent-before-ordinary-work).

The feature remains experimental. Live carryover, protected saved-consent and
registered-inference positive paths, knowledge/document clarification, planning
MCP reads, deferred decisions, whole-source/platform verification and human
journeys remain open. Non-ChatGPT opaque continuation can conservatively refuse
projection/continuation. The prototype's prior independent audit does not cover
the subsequent adaptation; the current review was by the implementation author.

The host is still `7.2.11-arch1-1`; production protected allocation admits only
7.2.10. No allowlist or test-only helper override was used or added in this work.
The writeback/allocation and current-root/egress gaps in the earlier handoff remain.
Do not wire the dirty inference prototypes or claim positive protected publication
from unsupported-host refusals. P30 consumer selection/experiments depend on the
first usable protected notes journey; the [plan](../../plan.md) retains its gates.

Prior finite allowance accounting recorded 106/300 ChatGPT subscription calls,
zero local Ollama calls and 3,963,324,792 downloaded bytes. This integration made
**zero** live model calls/downloads. Verify the original receipts before further
use. Hosted/API decision engines have no selected paid account or spending cap.
Use only Ipse's public authentication; no Codex credentials or private transcripts.

Before claiming completion, finish the required full/source/native/installed and
separate platform/model checks, review current manuals as whole chapters, retain
failed evidence, and provide the requested copyable external-review prompt.
