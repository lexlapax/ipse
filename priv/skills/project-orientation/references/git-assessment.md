# Git assessment

Use the selected workspace and applicable instructions. When it is a subdirectory,
check repository identity without expanding file access to the entire parent:
`git rev-parse --show-toplevel` identifies the boundary, not an access grant.

Inspect current state before choosing work. Useful local commands, subject to
ordinary shell approval, include:

```sh
git --no-optional-locks status --short --branch
git diff --stat
git diff --cached --stat
git log -5 --oneline
```

Read relevant diffs and implementation where they affect the task. Keep staged,
unstaged, and untracked work distinct; do not assume an existing change belongs
to this session. Avoid reading credential files or dumping remote URLs and
configuration values that may contain secrets. Do not restore, clean, stash,
reset, stage, or commit unrelated work to make the assessment easier.

Remote-tracking parity is local evidence. Unless a fetch actually succeeded in
this task, describe it as parity with the saved tracking ref, not proof of current
GitHub state. Orientation alone does not require fetching, pulling, pushing,
creating branches, opening PRs, or changing Git configuration. If fresh external
state is part of the user's task, use the already authorized Git/GitHub tools
and report the actual result; do not install an adapter or change credentials.

Find documented checks, then inspect their entry points and relevant callers
before selecting commands. Distinguish fixture tests and static checks from real
account operations, installation, deployment, and network-dependent integration.
A failing check caused by an existing change is still a failure; identify the
connection without silently fixing it. Hidden sibling repositories and missing
host environment variables can limit native checks. Report those limitations
without expanding roots, changing execution policy, or cloning replacements.

Base next steps on this combined evidence. A clean status is not a test pass;
a fixture pass is not a live deployment; an old verification note is historical.
Name checks not run and why, and identify any operator decision needed for the
next live action. For read-only work, compare status afterward and verify the
relevant existing diff remains unchanged if checks could have touched it.
