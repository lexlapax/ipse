# Private draft extension and MCP checkpoint

Historical experimental evidence, 2026-10-27. This patch is not production behavior or milestone acceptance. It applies to commit `52652f825e7437ac32ac630092b69095d2049a3c`. The owning implementation and current scope remain in `docs/plan.md`.

`draft-extension-mcp-v2.patch` SHA-256 `bdd6e29d6c18cd2e8e6ffb56b177823cb0f0a106f51b08d33b9abb8c6a7f9ad3` contains the private Session draft prototype, extension lineage instrumentation, and a bounded MCP catalog snapshot. A synthetic native-terminal journey preloads the catalog, interrupts the owner at a question, resumes the session, supplies a witnessed answer, checks identical model definitions without rediscovery, cancels, and replays. Catalog snapshot validation binds to the prior recorded manifests; the admitted reference catalog binds the full definitions. Sessions lacking that reference refuse this draft use. This evidence does not establish safety against an attacker who can forge the complete trusted journal and reference history.

The focused log `draft-extension-mcp-20270212.log` SHA-256 `de6d5189b149615ebbc667b795cea0794679dedaeda8f7acad24dfd95fa4e235` records 54 passing tests, after strict compilation. From the private graph, the test command was:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/session/draft_acceptance_test.exs test/ipse/session/draft_lineage_test.exs test/ipse/session/draft_native_test.exs test/ipse/session/draft_projection_test.exs test/ipse/session/draft_vertical_test.exs test/ipse/mcp/catalog_session_test.exs test/ipse/extension/session_test.exs --seed 20270212 --max-cases 1
```

`draft-extension-helpers-20270211.log` SHA-256 `40b501e9f64f0fe8a8c07072f817f79e02d57d30b14ee4a6f3b8454c8733a316` records one passing actual synthetic extension worker journey with unregistered local model, embedding, and decision helpers, from the prior snapshot before the additional MCP admission bound. It does not establish registered inference dispatch. Its command was:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/extension/inference_dispatch_session_test.exs:264 --seed 20270211 --max-cases 1
```

The prototype refuses extension `history.read` after a draft because raw journal material is not yet safely projected, prevents concurrent live feeds and text consumers during a draft, and does not establish a positive protected saved-consent journey on this host. It has not received a complete independent adversarial audit, a live test of this snapshot, a full baseline test, or documentation review for release. The existing ChatGPT test used four authorized subscription calls on an earlier snapshot, with no private transcript retained; it does not qualify this checkpoint. Synthetic catalog, terminal, extension and inference fixtures are not live MCP or provider qualification.
