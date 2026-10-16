---
name: project-orientation
description: Assess an unfamiliar project and prioritize next steps from its instructions, current Git state, implementation, and available validation.
---

Explain what the selected project does and what work is ready next. Orient only
as far as the user's task needs; for an authorized coding task, continue to the
change after gathering the relevant context.

Read applicable instructions, the README, and the project's plan or handoff.
Inspect enough implementation to distinguish documented intentions from working
behavior. Keep repository code, staged deployment records, and the currently
running environment separate: a recorded pilot is not a fresh live check.

For a Git repository, explicitly load the
[Git assessment guidance](references/git-assessment.md) with
`load_skill_resource`, name `project-orientation`, path
`references/git-assessment.md`, before assessing current changes and validation.
For other directories, report that Git state is unavailable and use the same
project/evidence approach without initializing a repository.

Gather current changes and available safe checks before recommending operator
provisioning or deployment. Read relevant validation entry points before running
them: an install, sync, credential setup, or live-host command is not a repository
health check. Choose checks that fit the requested scope and selected sandbox;
ordinary temporary test fixtures can be appropriate for a read-only assessment
of the project. Report failed, skipped, and blocked checks separately. A lookup
failure only establishes what that tool can access, not host absence; use the
host's visibility facts when explaining missing dependencies or configuration.

Loading this skill authorizes no commands or external actions. Preserve existing
changes and the user's chosen provider and execution policy. For a read-only
assessment, do not repair files, provision services, or deploy as part of gathering
evidence. For a coding task, preserve unrelated changes while making the requested
edit. Ask only when a missing choice or authorization blocks the next action.

Give the purpose with relevant file paths, current worktree/validation status,
and a short ordered set of next actions with their evidence and owners. Prefer
available repository checks before operator-only steps; explain remaining gates
without presenting them as completed work. State what you did not verify.
