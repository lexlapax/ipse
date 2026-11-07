# Knowledge MCP verifier retention candidate

Dated 2026-11-06. This is an implementation record, not a current operator
procedure; see the [testing manual](../../developer/testing.md) for verification.

The uncommitted verifier candidate retains the private runtime and its synthetic
journals, requires confirmed Session acknowledgements and backend process exit,
and checks the two MCP requests and result reads for an empty selection. Its
empty answer expects one open claim with no evidence indexes, matching Corpus
classification. A default output remains supported; an explicit new output may
be chosen for longer-lived evidence. Temporary directories and hosted runners
can be removed externally, and cleanup confirmation does not prove that every
descendant or external effect has stopped.

On the then-current source, a direct ExUnit run using the existing test ebin,
Elixir 1.20.4/OTP 29 and `ERL_FLAGS='+S 1:1 +A 1'` passed four tests (seed
544723). The invocation supplied every `_build/test/lib/*/ebin` with `-pa`, then
`-r test/test_helper.exs test/dev/knowledge_mcp_retention_test.exs`. The log is
`/tmp/ipse-mcp-retention-integrated-direct-03.log`, SHA-256
`4bc8b4944e5fe1964a60ba3f63cd7d798b2902b5c62d4bc2854d605d807d1ec0`.
It covers parser and report contracts and retained-runtime behavior using the
memory proof as a stand-in; it does not exercise an MCP Session.

The direct synthetic Corpus fixture ran with the same runtime and scheduler
limits, the test ebin paths and `-pa
/tmp/ipse-corpus-fence-candidate-20261106/filtered-ebin`, followed by
`test/support/corpus_namespace_fence.exs`. It passed all 16 controls (seed 1306),
including the exact remote-empty claim. Its log is
`/tmp/ipse-corpus-empty-claims-01.log`, SHA-256
`9e9de58f1d9d86d4f813ea158ca567739e26c9488be6814dc919b8581ed74eed`.
The fixture SHA-256 was
`a79a88da2fd2d8463f15740ffeb9937a2efb0f17518627d12402d39b9e00643d`;
Corpus was `a70d30effa964a1cb4807af3eb7c5ba5e47ae7092a5198d7a8954cfff6be3e84`
and Store was `6782be241d5189bca46446937fc54b0baa481814b28ddd45f90d1c75825b5e98`.
The verifier source was
`8947e317828b009ce8b8a71dea9a690e75052b5e48fc6b83ad1a5290ed8869c2`.
Temporary logs and helpers are not durable evidence and may be removed by the
environment.

An earlier Mix invocation failed before tests because the sandbox denied its
PubSub TCP socket; `/tmp/ipse-mcp-retention-integrated-01.log` preserves that
failure. A direct OTP 27 attempt failed before tests because the existing test
ebin was built for a newer BEAM; its log is
`/tmp/ipse-mcp-retention-integrated-direct-01.log`. Formatting returned zero
under OTP 27 but emitted a Hex loader error. These controls do not establish
source or installed native MCP verifier success. No declined notebook was used.
