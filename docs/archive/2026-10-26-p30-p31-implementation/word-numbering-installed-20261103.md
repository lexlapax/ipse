# Numbered Word retrieval in an installed package

2026-11-03. This is a bounded synthetic verification record, not completion of
[P31F](../../plan.md). The operator procedure and its actual limitations remain
in the [Corpus manual](../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace).

The extracted, parser-free Linux package based on commit
`03d2f01d3dfd459f2b53e1b7802f22c80f803619` passed the installed setup harness
after its catalog expectation was updated for the shipped decision-shadow
artifact. The archive SHA-256 was
`2a9504dfb2883ecc9001c38a4916037e239037a632dd7db15d4688b802e61175`;
the extracted release inventory was unchanged by the tests. Its public Corpus
artifacts came from the package, not from a separately rebuilt artifact.

The [fixture](../../../test/support/documents_setup.exs) SHA-256 was
`9c2fa193f6079c782dafa4627e15c72e13d94919dbb1b952cee0413eb73e6913`.
The [verifier](../../../dev/verification/documents_setup_installed.exs) SHA-256
was `97d9e7a80ed4949b0398f8d261a228b869c8f71f1fe0ef2f3fc4aab21c1d1861`.
These are test-side overlays on the named commit; they are not bundled runtime
changes. The fixture uses a handwritten two-paragraph DOCX with a direct,
single-level decimal list starting at 3.

Both State and Collection execute native setup, approved acquisition and
lexical retrieval through actual Sessions. They require partial document status,
the original binary hash and v16 recipe, literal quoted text without the derived
number, and a source-bound locator with the second item's ordinal 4 and label
`4.`.
Replacing the original file must refuse and return no evidence; restoring it
and resuming the Session must return the same evidence. The earlier unnumbered
setup and resume checks remain in place. Cancel, stale approval, concurrent
configuration change and piped-input setup controls also passed. The
[gate output](word-numbering-installed-20261103/gate-2.log) and
[machine report](word-numbering-installed-20261103/report.json) identify the
six cases, synthetic fixture logs, archive and observed runtime. There were no
model calls. The installed runtime used a synthetic PTY and a copied precompiled
ExUnit library; it did not use the system development toolchain at runtime.

The snapshot used independently copied locked dependency sources and a private
temporary home. The package command had `HEX_OFFLINE=true`,
`CARGO_NET_OFFLINE=true`, `IPSE_BUILD_PDF=0`, and `ERL_FLAGS='+S 2:2 +A 2'`.
The isolated Hex home contained a copied registry cache, SHA-256
`b71c170ce801727e34eb9a3094b80f259390d07b5d2b4c4285f2384cbe230287`;
no Hex configuration or credentials were copied. The
[build log](word-numbering-installed-20261103/package-cached.log) reports
52 packaged documents and no missing local targets.

The successful commands ran in the isolated checkout. `IPSE_ARCHIVE` below
denotes the exact archive above, and `OUTPUT_ROOT` a fresh nonexistent directory;
the verifier creates a private root and refuses an existing one:

```sh
HOME="$PRIVATE_HOME" MIX_HOME="$PRIVATE_HOME/mix" HEX_HOME="$PRIVATE_HOME/hex" \
  HEX_OFFLINE=true CARGO_NET_OFFLINE=true IPSE_BUILD_PDF=0 \
  ERL_FLAGS='+S 2:2 +A 2' ./dev/package.sh
HOME="$PRIVATE_HOME" MIX_HOME="$PRIVATE_HOME/mix" HEX_HOME="$PRIVATE_HOME/hex" \
  ERL_FLAGS='+S 2:2 +A 2' \
  elixir dev/verification/documents_setup_installed.exs "$IPSE_ARCHIVE" "$OUTPUT_ROOT"
```

The [first package attempt](word-numbering-installed-20261103/package.log)
stopped on the sandbox-denied local Mix lock. The
[escalated attempt](word-numbering-installed-20261103/package-escalated.log)
stopped because the isolated offline Hex registry was empty. Both precede the
successful cached build. The first extracted-package gate then
[failed](word-numbering-installed-20261103/gate-1.log) before the journey because
its [expected three-artifact catalog](word-numbering-installed-20261103/gate-1-state.log)
omitted the now-shipped fourth artifact. The corrected exact four-artifact check
passed against the same archive; no package, policy or retrieval assertion was
relaxed. The archived terminal excerpt normalizes CRLF to LF; its exact raw
version is retained at `/tmp/ipse-word-numbering-gate-1-state-raw.log`, SHA-256
`c4623b28ddec6af212746c0f7a6a0140282d1d09fd07cba365bc45c471247568`.

This proves neither independent real-Word rendering quality nor the larger
more-than-32-block packed-span path. It is not a standard PDF-enabled release
verification, cross-platform test, general document-capacity qualification,
semantic-quality evaluation, complete file lifecycle or a final milestone audit.
Unsupported numbering remains refused or partial as described in the manual.
