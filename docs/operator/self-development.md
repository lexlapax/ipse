# Use an installed Ipse runner to change Ipse

Keep the running application separate from the candidate checkout it edits.
Freeze a known runner, give it one bounded change, approve its effects, then
inspect and verify the candidate independently. This workflow is supervised:
a model's final explanation is not acceptance evidence.

You need a compatible release archive, an Ipse Git checkout, the source build
toolchain, and an explicitly selected model service. Source checks require
Elixir 1.18+, OTP 27+, Rust 1.85+, a C linker, dependency access, and local sockets.
Use [the developer manual](../developer/index.md) to build/verify a release if you
do not already have one. Do not run a Linux archive on macOS or the reverse.

## Separate the runner, candidate, and private state

Run these commands in one terminal, replacing the first two paths. Worktree path
and branch names must be new. Inspect an existing directory rather than removing
or resetting it.

```sh
IPSE_REPO=/absolute/path/to/ipse
IPSE_ARCHIVE=/absolute/path/to/compatible-ipse-release.tar.gz
IPSE_TRIAL=$(mktemp -d)
chmod 700 "$IPSE_TRIAL"
IPSE_STABLE="$IPSE_TRIAL/runner"
mkdir "$IPSE_STABLE"
tar -xzf "$IPSE_ARCHIVE" -C "$IPSE_STABLE"
"$IPSE_STABLE/ipse" --help
"$IPSE_STABLE/ipse" demo
git -C "$IPSE_REPO" status --short --branch
git -C "$IPSE_REPO" fetch origin
IPSE_BASE=$(git -C "$IPSE_REPO" rev-parse origin/main)
IPSE_CANDIDATE="$(dirname "$IPSE_REPO")/ipse-selfdev-candidate"
git -C "$IPSE_REPO" worktree add -b trial/ipse-self-development "$IPSE_CANDIDATE" "$IPSE_BASE"
```

Record the archive identity and `IPSE_BASE` privately. The demo must pass without
credentials or a model service before the trial. Existing edits stay in the
original checkout. Keep the extracted runner unchanged, outside the candidate.
The candidate can build/test its own code while the assistant continues running
from the extracted release.

Keep trial configuration and sessions under the private `IPSE_TRIAL` directory.
`--state-dir` relocates journals and associated budgets, not credentials or shared
operator skills. Use Ipse's own login; never borrow another tool's tokens.

## Select a provider and execution policy

This example uses an explicitly named ChatGPT subscription profile. Create the
file without replacing your normal operator configuration:

```sh
cat > "$IPSE_TRIAL/config.json" <<'JSON'
{
  "version": 1,
  "settings": {"subagents": true, "subagent_concurrency": 1},
  "profiles": {
    "main": {
      "provider": "chatgpt",
      "model": "gpt-6.1-sol",
      "reasoning_effort": "high",
      "credential": "ipse-auth"
    }
  },
  "roles": {"main": "main", "review": "main"}
}
JSON
chmod 600 "$IPSE_TRIAL/config.json"
"$IPSE_STABLE/ipse" status
```

If needed, run `"$IPSE_STABLE/ipse" login` and complete browser sign-in. Work
submitted under this profile makes real subscription requests and sends selected
candidate content to that provider. If you prefer another service, review an
explicit [profile](model-profiles.md) before starting. Failure does not authorize
a provider/billing change. An optional local routine role requires an already
available local model; do not download or substitute one implicitly.

Inspect configuration, then launch:

```sh
"$IPSE_STABLE/ipse" config --config "$IPSE_TRIAL/config.json" \
  --no-project-config --profile main --cwd "$IPSE_CANDIDATE"
"$IPSE_STABLE/ipse" chat --config "$IPSE_TRIAL/config.json" \
  --no-project-config --profile main --cwd "$IPSE_CANDIDATE" \
  --state-dir "$IPSE_TRIAL/sessions" --sandbox off
```

This deliberately uses trusted shell execution for work that may need Git,
Mix caches, network, and paths beyond the worktree. Per-action approvals remain.
The worktree is not an OS sandbox. To use native enforcement instead, select it
explicitly and accept its [visibility limits](usage.md#shell-policy); never fall
back silently. No MCP service is required by this procedure.

## Give the author a bounded task

Choose a fresh acceptance task small enough to review. Specify observable input
and output, allowed files, behavior to preserve, and relevant tests. For example,
a narrowly scoped CLI defect with a reproduction is a better first task than a
new orchestration system.

Submit a prompt based on this template, replacing the bracketed task details:

```text
Use $self-development for one supervised change. Your installed runner is frozen
outside the candidate selected by --cwd. Read AGENTS.md and applicable source
and tests. Use $project-orientation first, then propose a short implementation
and verification plan.

Task: [describe one concrete defect and the required result].
Preserve: [name the behaviors and files that must remain unchanged].
Acceptance: [give the exact observable checks].

Use ask_operator for a material unresolved scope choice. Request a bounded
read-only $review through the configured review role, then verify its findings
against the source. Review every proposed effect with me. Do not install
dependencies, change provider/billing, enable MCP, touch other worktrees,
commit, merge, or push during authoring. These trial constraints override the
repository's automatic commit/push instruction until I authorize publication.
Finish with the diff summary, actual checks, and remaining limitations.
```

The skill supplies supporting evidence/review checklists as explicitly loaded
resources. Loading it grants no action permission. Read every proposed path,
command, and diff; use each proposal's printed approval code. Do not use `--yes`
for this supervised walkthrough. Child reviews share the candidate and have
six-call/two-minute limits; the parent must check their claims.

If the agent repeatedly expands scope, stop and narrow the task in a fresh
prompt. Additional context and repeated orientation consume model calls without
proving progress. `/diagnostics` helps distinguish running work, approval waits,
context pressure, and exhausted steps.

## Check idle resume without repeating work

At an idle boundary after a settled edit, inspect the diff. Enter `/exit` and
wait for the author process to finish. Only after exit, record a baseline from
another terminal with the same path variables. Replace `SESSION_ID` with the
printed ID:

```sh
IPSE_SESSION=SESSION_ID
shasum -a 256 "$IPSE_TRIAL/sessions/$IPSE_SESSION.jsonl" > "$IPSE_TRIAL/idle-journal.sha256"
git -C "$IPSE_CANDIDATE" diff --binary > "$IPSE_TRIAL/diff-before-resume.patch"
git -C "$IPSE_CANDIDATE" status --short > "$IPSE_TRIAL/status-before-resume.txt"
```

Also record hashes of new/untracked files privately; `git diff` excludes their
contents. A snapshot before exit is unsuitable because close can append records.
Resume with the original runner and configuration:

```sh
"$IPSE_STABLE/ipse" chat --config "$IPSE_TRIAL/config.json" \
  --no-project-config --profile main --cwd "$IPSE_CANDIDATE" \
  --state-dir "$IPSE_TRIAL/sessions" --sandbox off --resume "$IPSE_SESSION"
```

Before sending a task, verify no tool/model call restarted. In the other terminal:

```sh
shasum -a 256 -c "$IPSE_TRIAL/idle-journal.sha256"
git -C "$IPSE_CANDIDATE" diff --binary > "$IPSE_TRIAL/diff-after-resume.patch"
cmp "$IPSE_TRIAL/diff-before-resume.patch" "$IPSE_TRIAL/diff-after-resume.patch"
git -C "$IPSE_CANDIDATE" status --short > "$IPSE_TRIAL/status-after-resume.txt"
cmp "$IPSE_TRIAL/status-before-resume.txt" "$IPSE_TRIAL/status-after-resume.txt"
```

Compare the new-file hashes too. This configuration has no recording/capture
extension that intentionally appends resume lifecycle facts. If your reviewed
configuration does, compare expected fact appends separately from forbidden
inference/effect replay rather than demanding identical journal bytes.

A pending structured question needs its saved explicit answer flow instead.
For an unexpected interruption during an effect, inspect actual files/processes
and receipts first. Never assume rollback. If context or identity prevents resume,
use a reviewed [handoff](recovery.md) and retain the old evidence.

## Verify the candidate independently

Stop authoring, inspect the complete diff and test changes, then run focused
checks for the changed behavior. Run the repository baseline from the candidate:

```sh
cd "$IPSE_CANDIDATE"
git diff --check
git diff
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
./bin/ipse demo
```

Inspect commands before running candidate code. Record actual failures,
exclusions, and skipped integrations. Do not call a skipped check a pass. A green
source suite does not establish browser sign-in, paid inference, native
enforcement, or package behavior.

For packaging changes or a release candidate, build and check its archive:

```sh
./scripts/package.sh
elixir scripts/verify-package.exs /absolute/path/to/the-new-archive.tar.gz
```

Use the archive actually produced for this platform, not a stale glob match.
Run applicable native/platform checks and a bounded read-only review as described
in [developer verification](../developer/testing.md). Recheck the exact final
candidate after any repair. Keep runner version, source commit, configuration,
provider route, assistance, actual checks, and uncertainty in the trial record.

## Publish only the reviewed result

After independent review and the required repository checks, authorize the exact
files/commit/publication step. Inspect staged changes and exclude authentication,
private prompts, journals, and trial exports. Follow the repository's current
commit/push/PR policy; publication is separate from authoring approval. Wait for
required platform checks before merging. Do not let the author replace its own
frozen runner during the trial.

Keep the installed runner and private evidence long enough to inspect old
sessions. A later upgrade is a new reviewed runner choice, not an implicit
continuation of the original trial.
