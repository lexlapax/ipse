# Planning MCP replay binding

The later [mode-checkpoint follow-up](planning-mcp-mode-checkpoint-followup.md)
replaces the original-header-only mode handling described below. The remaining
dispatch and journal-authentication limitations still apply.

2026-10-27. This uncommitted replay foundation extends the
[operator-only declaration](planning-mcp-operator-followup.md). Session still
denies planning and draft MCP calls: no production path writes the new intent.

`Session.PlanningMCP` checks that a restricted MCP `tool_started` is immediately
preceded by a versioned planning-read intent bound to the operator declaration,
the exact start record, the current recorded MCP catalog, and the admitted model
request and call arguments. It rejects a missing intent even if the MCP manifest
is deleted but the namespaced tool name remains. It also checks the original
mode's approval and ceiling and refuses resource manifests. A pre-start intent
at the end of a journal does not dispatch a call; a subsequent lifecycle epoch
can discard it. The check runs during saved reconstruction and context validation.

Synthetic tests cover approved and configured-allow cases, ordinary planning,
drafts, missing or duplicated intents, altered arguments and turn, missing
catalog or policy, read-only and denied modes, and a forged start inserted into
an actual Session journal. The working-tree draft and MCP selection passed 34
tests with 17 unrelated tests excluded (seed 20270513). An isolated graph based
on `668e6a3` passed 41 tests with 17 exclusions (seed 20270514), tree
`0bf2c8da1be4df9d62dd40aaf4ea57bd4fdee4f6`. After adding two test-only approval
and non-draft planning cases, tree `f1c87e5a064a0d8005777c11b46a9669dd3c515a`
passed the expanded replay test (seed 20270516) and forced strict compilation of
143 project files; tracked bytes matched its index.

Current SHA-256 values: `lib/ipse/session/planning_mcp.ex`
`94109a598c1dbbf65e3442e91557eb969d8c8e686fe602eb8564d017e458b386`;
`lib/ipse/session/saved.ex` `14a4e36c24e7a37a77d196f64bdd3ae8da91e89c60b495448c23d0c00a39be4b`;
replay test `121f5568d816af0c99b4a962a45589a9a651af01aee06feb789e7c2855292eda`;
Session test `e495c51fcea7fb35fad45f8ab1e739486c3cc62818f9d5d78dbf92e1e955e07a`.

The validator currently uses the original header mode. A resumed Session can
legitimately change approval or narrow its ceiling; an authenticated per-epoch
mode/activation contract and compatibility rules are required before a live
path can rely on this check. Recovery when lifecycle recording has stopped also
needs an explicit safe treatment of a pre-start intent. Neither record is an
independent anti-tamper authentication of an arbitrary journal. Before enabling
dispatch, integrate operator review, current policy/catalog revalidation,
approval, resource cleanup, evidence and interrupted-effect reconstruction;
test the actual Session and installed user journey. These controls do not qualify
P31I, a native profile or the full P30/P31 goal.
