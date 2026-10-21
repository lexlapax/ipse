# Approved MCP calls and bounded result reads

This independently compiled extension uses the public SDK to request an
operator-bound MCP call, then reads its durable text through bounded windows.
Its command does not call the conversation provider. It holds the accumulated
text in private worker state and returns a small byte-count/hash summary.

Build the inert artifact and run the credential-free proof from the repository
root after building Ipse:

```sh
IPSE_MCP_ARTIFACT=$(mktemp -d)/artifact
elixir scripts/build-artifact.exs mcp-actions --sdk _build/dev/lib/ipse/ebin --output "$IPSE_MCP_ARTIFACT"
elixir scripts/verify.exs source mcp \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_MCP_ARTIFACT"
```

The verifier imports into temporary homes and explicitly grants the artifact's
capabilities and one `documents` alias for `mcp__fixture__fetch`. Local stdio and
loopback HTTP fixtures return more than 8 KiB of synthetic UTF-8 text. The stdio
fixture uses the current runtime's Erlang executable and bundled Elixir files;
it does not depend on an `elixir` command on `PATH`.

The twelve checks cover independent worker loading, full descriptor-bound
approval, both transports, source persistence before the public descriptor,
complete UTF-8 windows, inert idle resume, twenty reads before an effect under
an explicit mixed grant, denied dispatch, pre-discovery alias refusal, descriptor
drift, source corruption and the unchanged sixteen-effect ceiling. Source
Session tests separately exercise cancellation, timeout, owner loss, cross-
invocation readers, damaged windows, source retention through a pending operator
question and the original version-one action limit. The question exercise uses
an explicit `host.question` grant and a descriptor-only continuation checkpoint.
These are transport and recovery fixtures; they measure no retrieval or model
quality.

Run the same proof against an extracted release:

```sh
elixir scripts/verify.exs installed mcp \
  --archive /path/to/ipse-archive.tar.gz --input "$IPSE_MCP_ARTIFACT"
```

Replace the archive placeholder with the exact path printed by `scripts/package.sh`
for the actual host. The wrapper hides system
Elixir/Erlang/Mix/Rust executables, runs the proof through the extracted host,
and verifies that the archive and release files remain unchanged. Temporary
state is removed. A successful source run alone does not establish an installed
release result.

The [shared verification guide](../../docs/developer/testing.md#prove-an-independent-artifact-without-rebuilding-the-host)
explains pre-launch compilation, input inventories and isolated runtime ownership.
