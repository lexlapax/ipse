# Installed Word packed-numbering verification

2026-11-03. This is a bounded synthetic verification increment, not completion
of [P31F](../../plan.md). The [earlier installed numbered-Word journey](word-numbering-installed-20261103.md)
used two paragraphs and did not exercise packed spans. Current operator
procedures and limits belong to the [Corpus manual](../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace).

## Result

A parser-free Linux package based on commit
`8d1f5d7dcfc55efdab07389a8f35a626b159ad25` passed the installed synthetic
setup gate on qualified tmpfs: State, Collection, cancel, stale approval,
configuration race and piped input, six of six. The [gate output](word-packed-numbering-installed-20261103/gate-tmpfs.log)
and [machine report](word-packed-numbering-installed-20261103/report.json)
record the outcomes. There were no model calls. The runtime used synthetic PTY
input and copied precompiled ExUnit with the installed package's Ipse code;
the system development toolchain was absent from its runtime path.

The two positive profiles each acquired a generated 40-block DOCX containing
numbered paragraphs, a plain paragraph, Unicode and a numbered table cell. The
actual extraction returned 40 original segments and a smaller packed document
map. Native setup and approved staged acquisition led to lexical retrieval of
a v16, multi-block document citation. Assertions checked its ordered nine-field
span map, exact source and quote byte offsets, table coordinates, numbering
ordinals and labels, literal UTF-8 text, original binary hash and partial
coverage. Replacing the original caused a live query refusal without evidence;
after restoration, close and resume returned identical evidence.

Separately, after closing the Session, the test loaded Documents and Evidence
from the same imported package, reconstructed a synthetic source and called
`Evidence.valid_span?/2`: the valid multi-block citation passed and an altered
numbering label failed. This is a pure validation control, not an installed-store
tampering or output-release test.

## Source and build boundary

The package archive SHA-256 was
`c74ddee6f68aaff6164b4311aed516becd6489cd3a9a7b08ca91f2c5f9de3bf7`.
The [tested `documents_setup.exs` overlay](word-packed-numbering-installed-20261103/tested-documents-setup.exs) had SHA-256
`5adcdd880e36a489ca212dba62b6487e9ecc847fa5100ab60bc169c273325766`.
It initially failed the final formatting check; its formatted
[repository version](../../../test/support/documents_setup.exs) has SHA-256
`8bcd53725549ad62398b9ad798731d5c82dc58f323176aa6100918ea8e5ad2c2`.
A parsed-code comparison with source-location metadata removed confirmed the
two versions equivalent; the installed gate was not rerun after formatting.
The [documents_setup_installed.exs](../../../dev/verification/documents_setup_installed.exs)
overlay had SHA-256
`a5eafcfdd8ca5ed4d35456ef642471dc1a252ad6699aba7658c3f046236947bd`.
They are not runtime changes. The latter used a private `IPSE_HOME` in its
child commands while retaining the invoking `HOME`.

The isolated checkout was extracted from the named commit, with locked
dependency sources copied from an earlier isolated build. `mix.lock` SHA-256
was `c6be0ff68446834973ed443028e318f86782ee9f6061b9fd911da419184f86c0`;
the copied offline Hex registry cache SHA-256 was
`b71c170ce801727e34eb9a3094b80f259390d07b5d2b4c4285f2384cbe230287`.
No Hex configuration or credentials were copied. The build used
`HEX_OFFLINE=true`, `CARGO_NET_OFFLINE=true`, `IPSE_BUILD_PDF=0` and
`ERL_FLAGS='+S 2:2 +A 2'`; independent Mix, Hex, Ipse and temporary paths were
used. The [build excerpt](word-packed-numbering-installed-20261103/package-success-excerpt.log)
records 52 packaged documents and zero missing local targets.

The checkout omitted the large duplicate `docs/archive` and linked that path
to the workspace archive for the package's source-target existence checks.
The package removes its archive copy and rewrites omitted historical links to
the exact source commit. All 347 distinct rewritten archive targets found in
the release documentation were independently checked to exist in that commit;
the sorted URL-list SHA-256 was
`1d2a3392e054cb11736f169436f6dbe58e54d25609f5e5d4b93d1b9f950c3835`.
This was not a wholly self-contained frozen source checkout. The release
inventory remained unchanged during the installed gate.

## Preserved failures and limits

The first extraction of a duplicate full source archive stopped at a temporary
filesystem quota. After excluding the archive, the first package attempt on
tmpfs also stopped while writing a BEAM file with `disk quota exceeded`; its
[sanitized excerpt](word-packed-numbering-installed-20261103/package-quota-excerpt.log)
is retained. A project-filesystem rebuild produced the package above. An initial
installed gate on that Btrfs filesystem passed State, but Collection stopped
before acquisition with a generic [configuration-save refusal](word-packed-numbering-installed-20261103/collection-btrfs-excerpt.log).
The existing configuration remained intact and no project identity index was
published. The host kernel was `7.2.11-arch1-1`, and the existing native
protected-storage profile does not admit Btrfs on that kernel. This known
incompatibility is consistent with the failure; the generic error does not
identify the actual first failing operation. The same package and fixtures then
passed all six cases on tmpfs without changing storage policy. An initial test
launch with a mistyped working directory failed before any test process started.
The archived refusal excerpt normalizes CRLF to LF; its raw bytes remain at
`/tmp/ipse-word-packed-btrfs-excerpt-raw.log`, SHA-256
`f53c8b1b25ca5724b45f3c43ac5020de1aafe29a2ffbb7f521a0f93a4749d8e7`.
An independent whole-document review covered the relevant operator and developer
manuals; a sanitized git-backed documentation check passed 1,102 Markdown files
and 9,067 links with zero errors.

This synthetic result does not establish independent Word rendering fidelity,
general Word or large-corpus capacity, standard PDF-enabled release integration,
other operating systems, complete document lifecycle, or the remaining P31F
acceptance. Unsupported numbering still reports partial coverage or refuses as
described in the manual.
