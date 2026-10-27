# Independent synthetic first-use MCP audit

Historical-only evidence, 2026-10-27. Review of private patch `draft-mcp-first-use.patch` SHA-256 `39ccdaee126e2c38d7b5cac3d73e86d526af3ec2dfd8a2d25cc574b616467c25` against repository commit `52652f8`. A separate graph was constructed from `git archive` of that commit, with copied dependencies and the existing native helper (SHA-256 `d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`). No production MCP endpoint was contacted.

The setup intent is recorded before configured server discovery. Replay checks bind setup results to their pending operation type, ID and session; a catalog snapshot is bound to the reference before model dispatch. A pending setup, or an observed setup without its snapshot, is treated as interrupted. Cancellation settles a pending operation as unknown before cancellation. No additional concrete bypass was established in this review under the trusted local journal model. The journal is not cryptographically authenticated, and configured discovery may execute a configured stdio server or contact a configured HTTP server. Identical endpoint fingerprints do not authenticate a compromised endpoint. Synthetic wire observations and process-cleanup fixtures do not establish behavior for arbitrary production endpoints or descendants.

Strict test compilation passed with `MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix compile --warnings-as-errors`. The independent focused run used the ten listed files with seed 20270318 and one case at a time:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/session/draft_acceptance_test.exs test/ipse/session/draft_lineage_test.exs test/ipse/session/draft_native_test.exs test/ipse/session/draft_projection_test.exs test/ipse/session/draft_vertical_test.exs test/ipse/mcp/catalog_session_test.exs test/ipse/extension/session_test.exs test/ipse/extension/history_test.exs test/ipse/extension/subscriptions_test.exs test/ipse/extension/feeds_test.exs --seed 20270318 --max-cases 1
```

Result: 114 passed, using synthetic local fixtures. Auto-excluded tags: native_sandbox, macos_sandbox, macos_filesystem, memory_scope. This is not a full repository test, live account test, platform qualification or production MCP evidence. Compile log SHA-256 `60accf7cafd00a16315066623055b3152e9e019729d5dee5fe58de43dd5b9188`; focused log SHA-256 `b144c1b6740636c2c04ad47940eaaa20aaed6abf618c60b50b92b798f9c66e1c`.
