# Private MCP revalidation checkpoint

Historical experimental evidence, 2026-10-27. This private prototype is not production behavior or milestone acceptance. It supersedes the pending-MCP refusal in `draft-history-dense.md` and applies to commit `52652f825e7437ac32ac630092b69095d2049a3c`; current scope is in `docs/plan.md`.

A previous checkpoint demonstrated that coordinated local rewriting of the cached catalog and its journaled reference digest could reach a resumed model request. This candidate journals a bounded revalidation intent before reconnecting to the already configured MCP server, compares the returned manifests and complete tool definitions with the pinned draft catalog, and records the outcome before dispatch. It refuses a changed catalog, missing snapshot, exhausted attempt budget, or an interrupted discovery intent on replay; an interrupted attempt is not automatically retried. The comparison uses the currently configured server as independent of the local journal, not as a promise that the server is trustworthy. Discovery is an external interaction, even though these synthetic requests contain no draft text; it must be reviewed against operator authority and the draft contract before production use.

The [patch](draft-mcp-revalidate.patch) has SHA-256 `e4b7e37e1d13c214c3161426d74c2daf303755f698b0571525935971cb5ac0c0`; clean base `git apply --check` passed. After strict compile, the [focused log](draft-mcp-revalidate-20270303.log), SHA-256 `72ccf47650a04b4a3b9af224ee05bd37950b63f7330197067ee50a8583eb60fb`, records 112 passing tests:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/session/draft_acceptance_test.exs test/ipse/session/draft_lineage_test.exs test/ipse/session/draft_native_test.exs test/ipse/session/draft_projection_test.exs test/ipse/session/draft_vertical_test.exs test/ipse/mcp/catalog_session_test.exs test/ipse/extension/session_test.exs test/ipse/extension/history_test.exs test/ipse/extension/subscriptions_test.exs test/ipse/extension/feeds_test.exs --seed 20270303 --max-cases 1
```

The later [boundary and wire log](draft-mcp-revalidate-boundary-20270305.log), SHA-256 `ab814c55160874a65f3541e4bb2172cc1a00a60b6700b331e3f88db83bb49f10`, records one test containing four local synthetic native-terminal Session journeys: matching discovery, changed server metadata, correlated local catalog/reference rewriting, and owner death during discovery. The last three avoid the model dispatch; an interrupted intent is retained without automatic rediscovery. Synthetic RPC tracing checks the transmitted discovery messages for the draft request and answer and checks that no resource read or prompt invocation occurred. The boundary test also checks mismatched, duplicate, and 17th revalidation records. The test-only wire tracing and replay-order assertions were added after the 112-test run:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/mcp/catalog_session_test.exs:255 --seed 20270305 --max-cases 1
```

This snapshot awaits independent adversarial review, the full baseline, live qualification, and release documentation review. No real MCP endpoint was contacted. It does not qualify the actual external discovery authority, server trust, protected saved consent, registered inference, opaque non-ChatGPT provider continuation, or general P31 completion. The previously recorded projected-history limits and near-cap memory measurements still apply.
