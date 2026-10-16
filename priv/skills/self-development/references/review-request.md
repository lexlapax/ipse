# Bounded review request

A child review is a separate read-only task, not blanket permission to execute
scripts or change files. Sharing a worktree is not OS isolation.

Select one question: for example, can this import transfer an approval or execute
a saved effect? Supply the exact acceptance contract, at most two relevant files
or a bounded diff, and the independently run test summary. Ask for one or two
targeted reads, then findings with file/line, trigger and consequence. Use $review
and its checklist when available. Do not ask a six-step child to rediscover the
whole repository, implement repairs and run a full suite.

A result with no findings is evidence only for the reviewed scope. The parent
checks claims against source and actual test results. If the child exhausts its
budget or returns unknown, inspect its journal/workspace, keep the failure record
and explicitly narrow a subsequent request. Do not automatically replay the call,
raise budgets, change providers or relabel an incomplete review as passed.
