# Supervised self-development

The bundled `$self-development` skill now supplies the reusable supervision,
bounded review and evidence checklist used for subsequent trials. It is inert
instruction, not permission to execute scripts or publish. Explicitly load its
`references/evidence-checklist.md` and `references/review-request.md` resources as
directed. The completed P18 Mac runbook below retains its concrete task/authority;
adapt its separation and review procedures to a newly scoped trial rather than
repeating its already integrated feature. Other hosts use their repository/platform
checks and matching runtime. Use the local
[context recovery tools](recovery.md) for diagnosis or explicit handoff.

Next comes P24's external adversarial architecture validation and baseline OpenAI
security audit, followed by P25's larger independent Codex/Ipse research and
self-development comparison. Neither review nor the trial has run. The
[review and evaluation protocol](../developer/self-hosting-evaluation.md) defines
the critique, dispositions, source-based comparison, Ipse-authored repairs,
held-out reruns and final architecture/security reviews. The
[plan](../plan.md#current-priorities-and-status) owns scope and order; former-P24
voice/media is deferred to P28 and does not block this text/research work.

Prepare a pinned, sanitized repository/design packet and a passing candidate from
the [verification record](../developer/testing.md#current-evidence-and-next-checks).
Normally ask an independent external reviewer, such as Claude, to challenge it
before scanning. Establish reviewer/service access, source-sharing authority,
authentication, billing and resource limits before sending material. Prior
ChatGPT permission does not authorize another provider. Exclude `.env`, auth
files, private journals and unrelated projects; retain raw findings privately.
This runbook provisions no service and installs no external review/scan tooling.

Triage counterexamples and scan findings against actual code, repair applicable
blockers and refresh affected reviews on the changed revision. Freeze P25's runner
only after its checks and P24 gates pass. Brief preparation/access checks can
proceed earlier; earlier passing releases do not verify later runtime changes.
Keep the external critique separate from the initial A/B research inputs, record
operator decisions and assistance, and review architecture deltas plus security
again on the final candidate before accepting the trial.

The credential-free fixture `mix run scripts/demo-self-development.exs` verifies
bundled discovery, both explicit resources and journal provenance with effects
denied. It is scripted, not live model or self-development evidence. The extracted
package verifier runs the same fixture without a development toolchain.

P21 subsequently exercised a larger Serenity/Linux handoff-import change using
that skill and a frozen P20 package. The completed trial passed focused tests,
independent Linux/package checks, a separate bounded live child review and hosted
Linux/Mac checks. Its actual scope and limitations are recorded in
[P21 evidence](../developer/testing.md#p21-supervised-serenity-trial-and-independent-checks).
Repeated orientation required supervisor narrowing, and retained-context recovery
used a reviewed manual handoff into a fresh author session. The completed live
session also passed unchanged idle resume. This does not establish unattended
development. New runtimes support [fresh-chat handoff import](recovery.md);
an older frozen runner may require manually supplying the reviewed note instead.

This is the P18 operator runbook. The local Mac trial on 2026-10-16 produced an
Ipse-authored `sessions --json` candidate with passing independent source,
Mac native and extracted-package checks and a completed bounded review. The operator
subsequently delegated final review and publication to the supervisor. PR #1
merged after hosted Linux/macOS CI passed. P18 is complete within this supervised
trial's documented scope. Keep the running harness separate from its target. See the
[local evidence](../developer/testing.md#p18-macos-supervised-self-development-evidence).

## P18 selected change and completion criteria

The selected task is **add `ipse sessions --json`**. It gives the trial a small
runtime change with observable behavior and meaningful tests:

- Preserve the current human-readable `ipse sessions` output.
- JSON mode emits one JSON array, sorted by session ID, containing only `id`,
  `provider`, `model` and `cwd`. Missing metadata fields become JSON null.
- Reuse existing journal listing behavior, including empty/missing directories
  and skipped invalid journals. Do not export complete metadata or conversations.
- Fixtures prove valid JSON, ordering, empty input, unchanged text output and
  exclusion of synthetic private metadata/messages. Use isolated session stores.
- No authentication, inference, network retrieval or journal mutation for listing;
  no new dependency. Update CLI help, operator usage and developer verification.

This was the bounded first Mac change, not a pending implementation request.
Choose a fresh acceptance task for a new trial and use the existing review skill
without also building a new self-development framework.

## 1. Create a stable runner and a candidate worktree

Use the Mac's existing Git, Elixir 1.18+/OTP 27+, Rust 1.85+ and C linker.
Check those installations locally; this guide does not install toolchains.
Dependency fetching needs network, and tests need loopback sockets.

Run in the Mac's terminal, adjusting the repository path if necessary:

```sh
IPSE_REPO="$HOME/projects/lexlapax/ipse"
cd "$IPSE_REPO"
git status --short --branch
git fetch origin
IPSE_BASE=$(git rev-parse origin/main)
IPSE_STABLE="$(dirname "$IPSE_REPO")/ipse-stable-macos"
IPSE_CANDIDATE="$(dirname "$IPSE_REPO")/ipse-selfdev-macos"
git worktree add --detach "$IPSE_STABLE" "$IPSE_BASE"
git worktree add -b trial/macos-self-development "$IPSE_CANDIDATE" "$IPSE_BASE"
```

Record `IPSE_BASE`. Existing edits in the original checkout stay there. These
commands require fresh worktree paths and branch name; if they already exist,
inspect them and resume deliberately or choose new names. Do not delete/reset
existing work. Variables below refer to the same terminal session.

Build and check the frozen runner before starting model work:

```sh
cd "$IPSE_STABLE"
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
./bin/ipse demo
```

Stop and diagnose a failing baseline. If Mix needs Hex/Rebar, provision them
explicitly as described in the [README](../../README.md#build-and-try-it).
The source runner uses the installed Mac toolchain; a separately built matching
Mac release can replace it. Never run the Linux archive on macOS. Keep the stable
checkout unchanged throughout the trial. Candidate tests may execute candidate
code, but the assistant itself continues running from `IPSE_STABLE`.

## 2. Select explicit execution profiles

Keep trial configuration and transcripts outside the target checkout. Create a
new private directory, without replacing the operator's normal configuration:

```sh
IPSE_TRIAL=$(mktemp -d "$HOME/ipse-macos-trial.XXXXXX")
chmod 700 "$IPSE_TRIAL"
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
"$IPSE_STABLE/bin/ipse" status
```

If necessary, run `"$IPSE_STABLE/bin/ipse" login` on the Mac and complete browser
sign-in there. Use Ipse's own protected auth; do not copy another application's
credentials or move tokens/transcripts through Git. Subscription analysis sends
selected repository context to that provider under the operator's authorization.
Provider/billing changes must remain explicit.

For a smaller local routine worker, first inspect `ollama list` on the Mac. If a
suitable model is already installed, add a `local` profile with provider `ollama`,
its exact installed model name, `max_steps: 4` and `timeout_ms: 120000`, then set
`roles.routine` to `local`. An optional endpoint belongs in that profile's
`base_url`. Review [profile configuration](model-profiles.md) first. Do not assume
Serenity's model is installed on the Mac, download one implicitly or substitute
another provider on failure. The single-profile configuration above is sufficient.

Inspect the selected settings, then launch:

```sh
"$IPSE_STABLE/bin/ipse" config --config "$IPSE_TRIAL/config.json" \
  --no-project-config --profile main --cwd "$IPSE_CANDIDATE"
"$IPSE_STABLE/bin/ipse" chat --config "$IPSE_TRIAL/config.json" \
  --no-project-config --profile main --cwd "$IPSE_CANDIDATE" \
  --state-dir "$IPSE_TRIAL/sessions" --sandbox off
```

This deliberately selects trusted local shell execution for Git/Mix/package work,
which can require caches, network and paths outside the worktree. Approvals remain
required; the worktree is not an OS sandbox. No MCP service is needed or enabled.
Use `--sandbox native` only as an explicit alternative with its documented limits;
do not fall back silently. Shared operator skills still follow the Mac's HOME.

## 3. Give Ipse the bounded task

Paste this after choosing the proposed task:

```text
This is a supervised self-development trial. Your running harness is frozen in
a separate checkout. Work only on the candidate checkout selected by --cwd.
Read AGENTS.md and the relevant implementation/tests. Use $project-orientation
first. Propose a short implementation and verification plan before edits.

Implement the proposed `ipse sessions --json` contract from
docs/operator/self-development.md. Preserve default text output, use a closed
field allowlist, reuse existing journal listing and add meaningful isolated
fixtures, CLI help and operator/developer documentation. Add no dependency.

Use ask_operator once before edits to confirm the selected task/scope, and for
any material unresolved choice. Answers grant no effect permission and a
recommendation must not be submitted automatically. If a routine local profile is configured, delegate
one small read-only fixture/edge-case analysis to it; otherwise keep that work
local to the parent. Request one bounded read-only review using the configured
review role and $review. The parent must verify findings independently.

Review each proposed effect with me. Do not start MCP, change provider/billing,
install dependencies, touch other worktrees, commit, merge or push. These are
explicit trial constraints overriding the ordinary automatic commit/push rule.
Finish with the diff summary, actual test results and remaining limitations.
```

Approve only concrete calls you have reviewed. Child approvals are separate;
delegation does not approve later writes/shell work. Read-only review is a task
instruction, not filesystem enforcement. Children share the worktree and have
six-step/two-minute limits; return unresolved findings to the parent. Do not use
`--yes` for this supervised trial. See [subagents](subagents.md).

## 4. Exercise interruption and resume

Record the printed session ID and trial directory. At an idle boundary after a
small settled edit, inspect `git diff`, then exit the idle chat with `/exit` and
wait for that process to finish. **Only after exit, and before launching resume,**
record the journal and workspace snapshots from another terminal with the same
path variables. Replace `SESSION_ID` with the real ID:

```sh
IPSE_SESSION=SESSION_ID
shasum -a 256 "$IPSE_TRIAL/sessions/$IPSE_SESSION.jsonl" > "$IPSE_TRIAL/idle-journal.sha256"
git -C "$IPSE_CANDIDATE" diff --binary > "$IPSE_TRIAL/diff-before-resume.patch"
git -C "$IPSE_CANDIDATE" status --short > "$IPSE_TRIAL/status-before-resume.txt"
```

A snapshot taken before `/exit` is not a valid unchanged-resume baseline: exit
can append a `cancelled` event even while idle. The first Mac comparison failed
for exactly that reason; the supervisor confirmed that prior bytes matched
cryptographically, then passed the comparison with a post-exit/pre-resume snapshot.
This corrects the verification procedure, not the runtime cancellation behavior.
Also record private file hashes (including new/untracked files) at this same
post-exit boundary; Git diff alone does not cover their contents.

Resume explicitly, keeping the same configuration:

```sh
"$IPSE_STABLE/bin/ipse" chat --config "$IPSE_TRIAL/config.json" \
  --no-project-config --profile main --cwd "$IPSE_CANDIDATE" \
  --state-dir "$IPSE_TRIAL/sessions" --sandbox off --resume "$IPSE_SESSION"
```

Before sending another prompt, verify no model/tool call restarted and compare
the journal bytes and diff from the other terminal:

```sh
shasum -a 256 -c "$IPSE_TRIAL/idle-journal.sha256"
git -C "$IPSE_CANDIDATE" diff --binary > "$IPSE_TRIAL/diff-after-resume.patch"
cmp "$IPSE_TRIAL/diff-before-resume.patch" "$IPSE_TRIAL/diff-after-resume.patch"
git -C "$IPSE_CANDIDATE" status --short > "$IPSE_TRIAL/status-after-resume.txt"
cmp "$IPSE_TRIAL/status-before-resume.txt" "$IPSE_TRIAL/status-after-resume.txt"
```

These checks must pass for unchanged idle resume. Git diff omits untracked files:
also inspect and record `shasum -a 256` digests for any new files before/after.
If a structured question is pending, save and restore its explicit
waiting state instead. For unexpected interruption during an effect, inspect
the actual workspace/outcome before requesting continuation; never assume rollback
or automatically replay the action. Keep the same configuration throughout resume.

## 5. Review, verify and publish deliberately

From the candidate checkout, independently inspect the diff and tests before
executing them. Run focused behavior tests, then the required baseline:

```sh
cd "$IPSE_CANDIDATE"
git diff --check
git diff
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix test test/macos_sandbox_test.exs test/stdio_runner_test.exs --include macos_sandbox
./bin/ipse demo
./scripts/package.sh
elixir scripts/verify-package.exs dist/ipse-*.tar.gz
```

Use a fresh candidate so the archive glob selects only its new Mac archive.
Record toolchain/OS/architecture, baseline hash, exact commands, failures/exclusions,
structured-question behavior, actual routing and resume evidence. Keep journals,
auth and private prompts out of commits. A separate reviewer should inspect the
allowlist and tests; the authoring session's own approval is insufficient evidence.

After that review and operator authorization, the operator or supervisor stages
the exact feature/test/doc files, inspects `git diff --cached`, commits the trial
branch and pushes it to origin. Create a PR
through the operator's usual GitHub workflow. Wait for Linux/macOS CI, review the
exact commit and merge deliberately; do not let the running trial replace its own
stable checkout. Update P18 with actual local Mac evidence before declaring it
complete. Failed checks remain failed until repaired and rerun.

See the [plan](../plan.md#p18-supervised-self-development-on-the-operators-mac),
[verification guide](../developer/testing.md#p18-macos-supervised-self-development-evidence)
and [configuration recovery](configuration.md).
