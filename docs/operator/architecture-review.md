# Request and inspect an architecture review

Use Ipse for a bounded read-only assessment before a risky change or when a
subsystem is difficult to understand. Decide what question the review should
answer and what evidence the reviewer may access. A useful review names concrete
failure paths and file locations; a general approval is hard to act on.

## Define the scope

Choose the repository and a specific change or subsystem. Record its current
commit and existing edits before the review. If the scope is a local diff, leave
those edits intact and tell the reviewer which changes belong to you.

Start an interactive session with your chosen provider:

```sh
ipse chat --provider chatgpt --cwd /path/to/project --max-steps 20
```

This uses real subscription model requests after you submit work. Repository
content supplied to the model leaves the machine through that provider. Select
a local provider instead when that matches your data-sharing decision. Use an
explicit [profile](model-profiles.md) for a repeatable route.

Do not add `--yes` for a review that needs per-command control. Read-only intent
does not create a read-only OS sandbox. Approve only commands whose full arguments
match the review, and deny writes, installations, sign-in, publication, or unrelated
network access.

## Give the reviewer a question it can finish

For a change review, enter a prompt such as:

```text
Use $review to assess the current diff and surrounding code. Keep the review
read-only. Trace cancellation and recovery across the changed boundary. Read
applicable AGENTS.md files and relevant tests. Report actionable findings with
severity, file/line, trigger, user-visible consequence, and evidence. Separate
confirmed defects from hypotheses. Do not fix files, install dependencies, or
publish anything. List checks you ran and coverage you could not complete.
```

For an architecture question, replace the diff scope with the precise ownership
question, for example:

```text
Explain how an approved shell action is owned from admission through cancellation
and saved-session resume. Follow the implementation and tests. Identify any path
that can repeat an uncertain effect or release ownership too early. Keep this
assessment read-only and cite files for each conclusion.
```

Ask the model to narrow the task if the files and questions cannot fit the step
or context limits. A model stopping at a limit does not establish completed
coverage. `/diagnostics` shows phase, requests, and context size without another
model call.

## Inspect each finding

Check the cited file and surrounding code yourself or ask for the exact execution
path with no changes. A finding should let you answer these questions:

- What input, event, or failure triggers it?
- What actually happens, and what behavior was expected?
- Which saved state, process, file, or service can be affected?
- Does a test exercise the claimed case, or only a nearby success path?
- Is the evidence source inspection, an executed reproduction, or a hypothesis?

A passing test does not establish that an untested failure path is safe. A source
claim without a reproduction can still be useful, but retain that distinction.
When a safe reproduction is needed, request its exact command and expected
outcome, inspect it, then approve only that bounded check. Tests can have effects.

If you want a separate child review, enable [subagents](subagents.md) and select a
review role deliberately. Provide only the scoped files and question. A child
shares the workspace and is not independent external assurance. Do not describe
another pass by the same assistant as an independent security certification.

## Turn findings into reviewed work

Ask for a disposition table containing finding ID, evidence, accepted/rejected/
needs-more-evidence decision, proposed repair, and verification. Keep the review
phase read-only until you authorize a concrete repair. A proposal should separate
a missing generic host guarantee from behavior that an extension can implement;
see [Feature requests](feature-requests.md).

After a repair, review the actual diff and rerun the relevant checks against the
exact candidate. Findings about ownership, approvals, persistence, cancellation,
or accounting need failure-path evidence as well as a successful example.
A later commit requires its own review scope; an earlier assessment cannot certify
new code.

## Retain a report and handle interruption

If you want a report file, request its path explicitly and review the write before
approval. Exclude credentials, private transcripts, authorization URLs, and
unnecessary source excerpts from material you plan to share. Preserve unresolved
questions and skipped checks in the report.

Resume an interrupted review using the original configuration:

```sh
ipse diagnose --resume SESSION_ID
ipse chat --resume SESSION_ID
```

Add the original state directory where needed. Idle resume starts no review
calls. Inspect the last completed coverage, then send a new bounded continuation
prompt. If retained context or pinned configuration prevents resume, create a
reviewed [handoff](recovery.md). Never infer a finished review from process exit
or from a report that was interrupted before its coverage and findings arrived.
