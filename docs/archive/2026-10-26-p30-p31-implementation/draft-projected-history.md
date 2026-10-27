# Private draft projected-history checkpoint

Historical experimental evidence, 2026-10-27. This is a private prototype, not production behavior or milestone acceptance. It supersedes `draft-extension-mcp-anchor.md` and applies to commit `52652f825e7437ac32ac630092b69095d2049a3c`; current scope is in `docs/plan.md`.

Extension history reads now project draft journal intervals as `draft_withheld` gap rows. The prototype derives bounded ranges from the validated owning draft lifecycle, checks cached row sources and ranges on replay, preserves old snapshots, and refuses malformed, incomplete, or oversized projection inputs. An actual synthetic extension test exercises cancellation, pagination, replay, restart, and a forged-gap rejection; another exercises history access after accepted draft and unregistered extension inference helpers. A subscription replay repair accounts for draft model requests when normal subscription receipts are deliberately suppressed. This has not yet received independent adversarial sign-off.

The preceding snapshot's catalog hash cannot authenticate against coordinated local journal rewriting: the auditor demonstrated rewriting the cached MCP description and admitted reference digest, and a native-terminal test confirmed that the rewritten definition reached the resumed model request. The new snapshot therefore fails closed on pending MCP draft dispatch after restart because no independent catalog anchor is available. The test bearing the older name about resuming the catalog now asserts this refusal both with and without the correlated synthetic rewrite. MCP use after interrupted draft remains incomplete.

`draft-projected-history.patch` SHA-256 `3447d1b6e785af93e06c967d49f3dc20b28345467c18fdcf60afa72235715516`; it passed `git apply --check` against a clean archive of the base. After strict compile, `draft-projected-history-20270222.log` SHA-256 `c9b50910f9f2157009458e7a0dbab0b7497453bc2ec2dea3b3762321ae79daed` records 110 passing synthetic tests:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/session/draft_acceptance_test.exs test/ipse/session/draft_lineage_test.exs test/ipse/session/draft_native_test.exs test/ipse/session/draft_projection_test.exs test/ipse/session/draft_vertical_test.exs test/ipse/mcp/catalog_session_test.exs test/ipse/extension/session_test.exs test/ipse/extension/history_test.exs test/ipse/extension/subscriptions_test.exs test/ipse/extension/feeds_test.exs --seed 20270222 --max-cases 1
```

`draft-projected-history-helper-20270222.log` SHA-256 `e0d29653b07f52b504cc63afcfd43afad082931c3f42491bb81edcc7e1b50358` records one additional actual synthetic worker test:

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp ERL_FLAGS='+S 2:2' mix test --no-compile test/ipse/extension/inference_dispatch_session_test.exs:264 --seed 20270222 --max-cases 1
```

History projection intentionally caps examined prefixes at 32 MiB and 65,536 records and fails closed beyond those bounds; concurrent pending draft history is refused. Registered inference, a positive protected saved-consent journey, opaque non-ChatGPT provider continuation, full baseline verification, and release documentation review remain unqualified. The synthetic saved-consent test checks branch ordering using an injected descriptor, not a real grant. No live-provider or live-MCP qualification is claimed for this snapshot. Earlier private ChatGPT tests consumed four authorized subscription calls, without retaining private transcript content.
