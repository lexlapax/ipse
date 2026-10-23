# Review a project or develop a capability

Use a bounded review to answer an architectural question before authorizing
repairs. For a new capability, describe the result and select the smallest
supported mechanism. When Ipse changes its own code, keep the running application
separate from the candidate checkout.

## Request a review with inspectable evidence

Record the repository commit and existing edits. Start an interactive session
with your configured provider:

```sh
ipse chat --provider chatgpt --cwd /path/to/project --max-steps 20
```

This makes real subscription requests after submission and sends selected source
to that provider. Choose another route explicitly if your data policy requires it.
Without `--yes`, inspect each full command before approval. Read-only intent does
not create a read-only OS sandbox.

```text
Use $review to assess the current diff and surrounding code. Keep this read-only.
Trace cancellation and recovery across the change. Read applicable AGENTS.md
files and tests. Report actionable findings with severity, file/line, trigger,
consequence, and evidence. Separate confirmed defects from hypotheses. Do not
fix files, install dependencies, or publish anything. List checks actually run
and coverage you could not complete.
```

For a subsystem review, replace the diff scope with one concrete question, such
as ownership of an approved shell action through cancellation and saved recovery.
Narrow a task that cannot fit its step/context allowance. Reaching a model limit
is not completed review coverage. `/diagnostics` inspects progress without inference.

For each finding, inspect its trigger, expected/actual behavior, affected state,
and whether a test establishes that path. Source inspection, executed reproduction,
and a hypothesis are different evidence. Ask for an exact safe reproduction before
approving it. Then request a disposition with accepted/rejected/needs-evidence,
repair, and verification. Authorize concrete repairs after reviewing that result.
An optional child review uses [delegation](usage.md#delegate-a-bounded-review);
shared-workspace children are not independent external certification.

## Specify an optional capability

Provide scope, allowed services/models, data that may leave the machine, spending
limits, writable files, and invocation timing. For example:

```text
I want an explicit command that recalls project notes for a release checklist.
Keep data local and show the retained source excerpts. Propose the smallest
supported mechanism, including configuration, grants, retention, limits, export,
and recovery. Do not install or enable anything until I review its source and
configuration.
```

| Need | Start with |
| --- | --- |
| Repeat a procedure using current tools | Skill or scoped instructions |
| Access an existing external service | Explicitly configured MCP |
| Add a typed tool or local command | Extension invocation |
| Annotate a prompt or format presentation | Selected transform |
| Read selected notifications/feeds/text | Extension consumer with exact private-view grants |
| Run finite recall/maintenance at a prompt/answer boundary | Event job with separate action approvals |
| Rank sources, enforce note policy, or report totals | Extension with supported host calls/bound services |
| Add shared ownership, approval, persistence, accounting, or transport guarantees | Small generic core change |

Require a mapping to actual [extension contracts](extensions.md), including exact
inputs, timing, private views, effects, grants/bindings, destinations, and limits.
For storage, specify scope, revisions, concurrent writes, retention, deletion,
export, and migration. Deleting a current value does not erase earlier journals,
exports, context, or transfers. For asynchronous work, specify owner death,
cancellation, deadlines, incomplete cleanup, and no-replay recovery.

Inference needs named accounted text/embedding profiles. Arbitrary worker calls
are outside host budgets. A separate VM is not an OS sandbox. A feed acknowledgment
does not certify storage, and after-turn work cannot revise an admitted answer.
Skills cannot grant their own trust or execute scripts on load.

Review source, manifest, schemas, license, dependencies, options, and verification
before importing an inert artifact. Test allowed/refused effects, isolation,
uncertainty, resume, and behavior when disabled. Algorithm quality needs separate
examples. Try synthetic data in a scratch workspace before persistent selection.
Use a necessary core change instead of bypassing a missing contract with hidden
inference, borrowed credentials, or unbounded background work.

## Keep a frozen runner outside its candidate

For self-development, you need a compatible release archive, source checkout,
source toolchain, and chosen model service. Replace the first two paths below.
The candidate directory/branch must be new; inspect existing state rather than
removing or resetting it:

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

Record the archive identity/base commit and keep the extracted runner unchanged.
The demo must pass without a model. Existing edits remain in the original checkout.
Keep configuration/sessions in the private trial directory. Use Ipse's own login;
never borrow another tool's credentials. `--state-dir` moves journals/budgets,
not authentication or shared operator skills.

Save this complete configuration as `$IPSE_TRIAL/config.json`, mode `0600`:

```json
{
  "version":1,
  "settings":{"subagents":true,"subagent_concurrency":1},
  "profiles":{"main":{"provider":"chatgpt","model":"gpt-6.1-sol","reasoning_effort":"high","credential":"ipse-auth"}},
  "roles":{"main":"main","review":"main"}
}
```

```sh
"$IPSE_STABLE/ipse" status
"$IPSE_STABLE/ipse" config --config "$IPSE_TRIAL/config.json" \
  --no-project-config --profile main --cwd "$IPSE_CANDIDATE"
"$IPSE_STABLE/ipse" chat --config "$IPSE_TRIAL/config.json" \
  --no-project-config --profile main --cwd "$IPSE_CANDIDATE" \
  --state-dir "$IPSE_TRIAL/sessions" --sandbox off
```

If needed, run the stable runner's `login` first. Submitted work makes real
subscription requests. This example deliberately selects trusted shell execution
for Git, caches, package access, and paths outside the worktree, with per-action
approval. The worktree is not confinement. Select native policy explicitly if
appropriate and accept its visibility limits, without silent fallback.

Give the author one observable change and an explicit publication override:

```text
Use $self-development for one supervised change. The installed runner is frozen
outside the candidate. Read AGENTS.md, relevant source, and tests.
Task: [one concrete defect and required behavior].
Preserve: [existing behavior and unrelated edits].
Acceptance: [observable checks].
Ask about material scope choices. Request a bounded read-only review through the
configured review role and verify its findings. Review each effect with me.
Do not install dependencies, change provider/billing, enable MCP, modify other
worktrees, commit, merge, or push during authoring. This overrides repository
automatic-publication rules until I authorize publication. Finish with the diff,
actual checks, and remaining limitations.
```

Use each proposal's approval code. Stop and narrow repeated scope expansion.
A child review has six-call/two-minute limits; inspect its evidence yourself.

## Check idle resume and the exact candidate

At a settled idle boundary, inspect changes, enter `/exit`, and wait for close.
Only after exit, snapshot the journal and diff from another terminal with the
same variables. Replace `SESSION_ID`:

```sh
IPSE_SESSION=SESSION_ID
shasum -a 256 "$IPSE_TRIAL/sessions/$IPSE_SESSION.jsonl" > "$IPSE_TRIAL/idle-journal.sha256"
git -C "$IPSE_CANDIDATE" diff --binary > "$IPSE_TRIAL/before.patch"
git -C "$IPSE_CANDIDATE" status --short > "$IPSE_TRIAL/before.status"
"$IPSE_STABLE/ipse" chat --config "$IPSE_TRIAL/config.json" \
  --no-project-config --profile main --cwd "$IPSE_CANDIDATE" \
  --state-dir "$IPSE_TRIAL/sessions" --sandbox off --resume "$IPSE_SESSION"
```

Before submitting another task, check from the other terminal:

```sh
shasum -a 256 -c "$IPSE_TRIAL/idle-journal.sha256"
git -C "$IPSE_CANDIDATE" diff --binary > "$IPSE_TRIAL/after.patch"
cmp "$IPSE_TRIAL/before.patch" "$IPSE_TRIAL/after.patch"
git -C "$IPSE_CANDIDATE" status --short > "$IPSE_TRIAL/after.status"
cmp "$IPSE_TRIAL/before.status" "$IPSE_TRIAL/after.status"
```

Hash new/untracked files separately; Git diff omits them. This configuration has
no recording/capture extension that intentionally appends resume facts. With one
selected, distinguish expected metadata appends from forbidden effect/inference
replay. Pending questions need their explicit saved answer flow. Inspect interrupted
effects before another attempt; use [handoff recovery](recovery.md) for incompatible
runtime/context instead of editing history.

Stop authoring, inspect the complete diff/test changes, and run focused checks.
Then, from the candidate, run `./dev/build.sh`, formatting, strict compile,
`mix test`, and `./bin/ipse demo`. Follow [developer verification](../developer/testing.md)
for platform/package/installed proofs and independent review. Recheck after repairs.
A source pass proves no browser login, paid inference, or unexecuted native check.

Authorize the exact reviewed publication step after acceptance. Exclude private
configuration, authentication, prompts, journals, and exports. Follow current
repository commit/push policy and required platform checks. Retain runner and
private evidence long enough to inspect pinned old sessions. Do not replace the
runner during the trial or delete the candidate until its changes are preserved.
