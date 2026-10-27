# Private draft history pagination checkpoint

Historical experimental evidence, 2026-10-27. This private prototype is not production behavior or milestone acceptance. It supersedes `draft-projected-history.md` and applies to commit `52652f825e7437ac32ac630092b69095d2049a3c`; current scope remains in `docs/plan.md`.

The previous prototype rescanned the fixed history prefix for every page. It now holds one derived range policy in the owned extension host task, keyed by directory, session, identity, and complete snapshot. Each page still checks its saved anchor; the cache is discarded with the task, and replay independently rederives and validates ranges. This assumes the active owner controls the journal and is not protection against coordinated local journal rewriting. The scan now counts records incrementally and enforces the exact 65,536-record cap; the 32 MiB cap and fail-closed behavior remain. Tests include two withdrawn drafts, an earlier history snapshot, pending-question refusal, forged-gap rejection, cache anchor mismatch, and record/byte limits. An independent reviewer reproduced this checkpoint's 112 focused tests and helper test and found no cache injection through the examined worker boundary; that run was not saved as a standalone log. The reviewer identified dense-range cost and memory as remaining limits, addressed and measured separately in the [later dense checkpoint](draft-history-dense.md).

`draft-history-cache.patch` SHA-256 `43152ff5c01ce92b2cdeb32a13894588ed186622e0128dabbce489bbcf079fbc`; clean `git apply --check` passed against the base. After strict compile, `draft-history-cache-20270227.log` SHA-256 `14160a9b3e8e3ee9b2c2bbb5a76736330a978cc188426e37284acfd9b0a8a02a` records 112 passing focused tests:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/session/draft_acceptance_test.exs test/ipse/session/draft_lineage_test.exs test/ipse/session/draft_native_test.exs test/ipse/session/draft_projection_test.exs test/ipse/session/draft_vertical_test.exs test/ipse/mcp/catalog_session_test.exs test/ipse/extension/session_test.exs test/ipse/extension/history_test.exs test/ipse/extension/subscriptions_test.exs test/ipse/extension/feeds_test.exs --seed 20270227 --max-cases 1
```

`draft-history-cache-helper-20270227.log` SHA-256 `743e5250ae98f0369e99bef8fb635093e82b4d303d57a11551ac5a71ffd8105e` records the accepted-draft synthetic extension helper/history test:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/extension/inference_dispatch_session_test.exs:264 --seed 20270227 --max-cases 1
```

On Serenity, `draft-history-cache-bench.exs` SHA-256 `f91d19bea0feda613fa5a04e7ebcead424c4c7c6d118ede712ee3f0703b78972` generated a synthetic 65,535-record, 31,510,824-byte prefix. Its log `draft-history-cache-bench.log` SHA-256 `9a46e8ee285006e69593d2a8ec91e250423383bcc12d03cee7e525b74e9a51f2` records 1.932 seconds for the initial policy and 0.634–0.735 milliseconds for three subsequent same-snapshot cached calls. This is a single local synthetic run of the history API, not an end-to-end latency or production throughput guarantee. Every new invocation or restart recomputes the policy once. The benchmark can be run from the private graph with its dependency build using `MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix run --no-compile <path-to-draft-history-cache-bench.exs>`.

Pending MCP draft dispatch after restart remains refused because the local reference digest is not an independent authentication anchor. Registered inference, positive protected saved-consent flow, opaque non-ChatGPT continuation, the full baseline, and release documentation review remain unqualified. Synthetic terminal, feed, MCP, provider and extension fixtures do not establish live qualification.
