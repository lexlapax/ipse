# Headless CLI argv and stdin capture controls — 2026-10-29

Two distinct Linux controls exercised `Ipse.CLI.run` in a separate child OS
process, once with task text in argv and once with a regular file redirected to
the child's stdin descriptor. Each used a fresh private home and
project, a genuine native interactive setup for the saved headless knowledge
grant, no `--yes`, and a registered local loopback synthetic Ollama fixture.
The provider is a test fixture, not a live model or account. The accepted
[source-tool runtime](managed-source-tool-preflight-independent-review.md) was
used unchanged, including its documented omission of the later separate
DocumentEmbedding Session delegates. Its 668 runtime hashes all reverified
before this record; helper SHA-256 is
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.

In each actual Session, the journal records the exact task as `input.original`
with `unattended_input` origin and default-headless approval. The synthetic
provider requested a real read and then `source_list`/`source_read`, selected
that actual input occurrence and supplied its exact handle and text to the
knowledge capture tool. The host performed its own source read and quote;
read-only journal inspection matches origin, occurrence, version, chunk, content
hash and original-session provenance between those operations and the capture
request. The saved-consent capture invocation was admitted, but its reported
outcome was **unknown** and the CLI and turn ended in error. In each separate
store the native Collection inspection returned generation zero and an empty
visible page; no managed publication action intent was recorded. Neither a
literal nor a pending proposal was observed. These are not confirmed semantic
source-refusal or pending-creation results, and the unknown operation was not
retried. The real read returned attributed file prose; workspace write and shell
were denied and their target files were absent.

Saved reconstruction passed for both original journals. Each current release
sidecar verifies as a `signed_release_claim` for its matching journal owner and
intent in the read-only inspection; that signed claim alone is not an
independent observation of native cleanup. The input-mode fixture also checked
the headless policy and empty Collection result during each actual run. Archived
journal copies are evidence, not replacements for the original SourceOrigin
identities under the retained temporary homes.

The [evidence](headless-cli-untrusted/) includes exact fixture, provider and
PTY-driver source and driver binary, complete output logs, distinct synthetic
journals and release sidecars, the read-only inspection script and output, and
the runtime hash verification. The retained fixture source is the exact version
executed; the working copies were formatted afterwards without a rerun. The first sandboxed argv launch failed at the
loopback listener with `EPERM`, before consent or Session creation. Its log is
retained; both actual controls ran under the authorized isolated execution.
Earlier separate in-process `Ipse.CLI.run` controls are also retained: their
stdin case used a BEAM `StringIO` group leader rather than an OS stdin file.
No aggregate suite, external model call or old-operation replay ran. The
separate model-selected capture controls that stored a note still failed their
final turn, and this evidence does not change that limitation.

Reproduce from the repository root, using fresh paths and a matching frozen
graph; the local loopback and native PTY require their normal OS permissions:

```sh
rustc --edition=2021 -D warnings -O docs/archive/2026-10-26-p30-p31-implementation/headless-cli-untrusted/sources/operator_pty.rs -o /tmp/ipse-cli-untrusted-pty-20261029
/tmp/ipse-cli-untrusted-pty-20261029 --knowledge elixir -pa '/home/lexlapax/projects/lexlapax/ipse/_build/source-tool-preflight-sol-20261029/_build/dev/lib/*/ebin' docs/archive/2026-10-26-p30-p31-implementation/headless-cli-untrusted/sources/headless_cli_untrusted_process.exs /tmp/ipse-cli-untrusted-process-argv-20261029 argv
/tmp/ipse-cli-untrusted-pty-20261029 --knowledge elixir -pa '/home/lexlapax/projects/lexlapax/ipse/_build/source-tool-preflight-sol-20261029/_build/dev/lib/*/ebin' docs/archive/2026-10-26-p30-p31-implementation/headless-cli-untrusted/sources/headless_cli_untrusted_process.exs /tmp/ipse-cli-untrusted-process-stdin-20261029 stdin
elixir -pa '/home/lexlapax/projects/lexlapax/ipse/_build/source-tool-preflight-sol-20261029/_build/dev/lib/*/ebin' docs/archive/2026-10-26-p30-p31-implementation/headless-cli-untrusted/sources/inspect.exs /tmp/ipse-cli-untrusted-process-argv-20261029 /tmp/ipse-cli-untrusted-process-stdin-20261029
```

The paths above identify the original retained homes; use new private paths for
any later control, never replay those unknown captures. The runtime source and
full inventory are frozen in the earlier source-tool evidence, not duplicated or
silently rebuilt here. This record does not qualify non-Linux, a bundled install,
headless pending promotion, or the full P30/P31 milestone.
