# P30/P31 work in progress

The P30 decision-engine and P31 knowledge/prompt-assistance goal is paused at
the user's request. This commit is a handoff of unfinished work, not milestone
acceptance. Read `AGENTS.md` and `docs/plan.md` before continuing. The objective
still includes the full milestones, required tests, an adversarial audit, and a
reviewer handoff.

The worktree changes in this commit include multiple overlapping P30 and P31
increments. Their focused receipts do not establish a passing integrated
baseline. The last large filtered run on an older candidate had 4,337 passes
and one failure. A current-source build and demo passed before the latest
retirement integration, not on this exact commit. Verify the exact committed
source and do not infer that the current implementation is release-ready.

The most recent completed focused fix before this checkpoint was commit
`d9014d1f`, which avoids retrying an unconfirmed assessment close. P31F
retirement has separately passed native lock and Session owner-loss controls;
the assembled candidate still needs a combined-source build and tests, as well
as documentation review. The P31H provided-source dispatch remains disabled;
its replay and delivery boundaries need further work.

Local isolated candidates, if still present, are under
`_build/verification/retirement-standalone-d9014d1f-20261108-01/` and
`_build/verification/p31h-result-replay-v3-20261108-01/`. The retirement
candidate's `final-candidate-01/source` has later documentation corrections;
its `standalone.patch` is stale and must be regenerated. The P31H v3 candidate
was formatted but not built or tested. Neither isolated candidate is included
in this commit.

The user declined a recall check on the retained 2,000-note notebook and an
equivalent replacement recall consumer. Do not run either or alter that
notebook, its records, retained unknown outcomes, or existing lock inodes. The
user permits normal cleanup of new disposable fixtures for deliberately
simulated unknowns; permission for cleanup after unexpected unconfirmed
outcomes has not been given. Preserve such outcomes and prior fixtures.

On this machine, the longer working log is `P30_P31_RESUME_HANDOFF.md` in the
worktree and its restart copy is `~/ipse-tmp/P30_P31_RESUME_HANDOFF.md`. These
local files and ignored `_build/verification/` candidates are not part of this
commit and may not exist in a fresh clone. Treat old log entries as historical;
inspect current processes, receipts and files before acting. The preserved
accidental snapshot under `current-root-build-20261108-01/source` contains
historical lock-named entries and symlinks; do not follow or delete them without
safe classification.
