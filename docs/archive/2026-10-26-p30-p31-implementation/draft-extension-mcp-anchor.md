# Private draft MCP catalog anchor checkpoint

Historical experimental evidence, 2026-10-27; this is not production behavior or milestone acceptance. This snapshot supersedes the catalog replay protection in `draft-extension-mcp-v2.md` and applies to commit `52652f825e7437ac32ac630092b69095d2049a3c`. The current scope remains in `docs/plan.md`.

An independent review reproduced that the previous snapshot's saved replay accepted a modified MCP description when the definition self-hash was recomputed. The new snapshot stores both base and MCP tool definitions and checks their combined digest against the most recent earlier `reference_admitted` catalog digest. `Saved.restore` also validates the reference journal independently. Synthetic Session replay tests now reject both changed descriptions and changed schemas even after their self-hashes are recomputed. The check assumes the Session's journal and reference admission are trusted; it is not an authentication mechanism against rewriting that entire history. Legacy sessions without an admitted reference cannot start this MCP draft.

`draft-extension-mcp-anchor.patch` SHA-256 `07b35b3913b8bd43aeb511e9216768c36996c83d25096d6a34372c48d08f2505`. The focused test log `draft-extension-mcp-anchor-20270214.log` SHA-256 `906e47112bd9b1c94dfb6336caafdf0952c6efa9c95466b52c92d1abd7823bfb` records 55 passing tests after strict compile. From the private graph:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/session/draft_acceptance_test.exs test/ipse/session/draft_lineage_test.exs test/ipse/session/draft_native_test.exs test/ipse/session/draft_projection_test.exs test/ipse/session/draft_vertical_test.exs test/ipse/mcp/catalog_session_test.exs test/ipse/extension/session_test.exs --seed 20270214 --max-cases 1
```

The separate log `draft-extension-feed-helpers-20270214.log` SHA-256 `aeffa11d0f77c6afdfed9926ac4f817ef3b20c6c2e3198e48a6f4ede7df190a7` records two synthetic tests. One checks draft content does not reach a configured feed, cancellation followed by ordinary work, and refusal to draft while a feed remains live. The other exercises local unregistered model, embedding and decision helper calls after draft acceptance. The saved-consent ordering test in the 55-test run injects a synthetic descriptor to exercise branch ordering; it is not a valid protected consent grant. The separate command was:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/extension/feeds_test.exs:443 test/ipse/extension/inference_dispatch_session_test.exs:264 --seed 20270214 --max-cases 1
```

The prior checkpoint's limits still apply: `history.read` remains refused after drafting, registered inference and a positive saved-consent journey are unqualified, opaque provider data fails closed, and this snapshot has not had a full baseline, live account qualification, or release documentation review. It awaits independent adversarial audit. Synthetic terminal, feed, MCP and helper fixtures are not live provider or MCP evidence.
