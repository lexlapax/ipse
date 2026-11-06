# Indexed Word row context — 2026-11-06

Historical bounded source-runtime evidence. Current procedures are in the
[Corpus manual](../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace)
and [Knowledge extension training](../../developer/knowledge-extensions.md);
the [plan](../../plan.md) owns remaining acceptance.

The indexed Collection namespace path already hydrated and revalidated sources
for positive BM25 hits, but did not expand a matching table row as the direct
snapshot path did. After the existing source and recomputed-score checks, the
indexed ranker now uses the same bounded context expansion. Positive hits retain
priority; remaining `top_k` positions can contain exact cited chunks from another
cell of the same source and row. The path adds no storage reads. It refuses a
nonpositive supplied indexed row and does not expand a query without a hit.
Coverage retains the single-block scope and explicit truncation; it does not
claim semantic support or complete rows.

The isolated pure row-context fixture passed one test using the existing SDK,
including indexed/direct parity, exact citation, limit, no-hit, expired source,
altered score and cross-source containment. Its first attempt failed before the
new assertions because the fixture converted list pairs to a map without first
converting them to tuples. The corrected fixture passed in a separate run; the
failed attempt is not counted as a pass.

A fresh private checkout of `2014e0dce02d74cc0ba49addbe2545fc9c021f97`, with
the reviewed source and Session-test overlays and a private copy of the
16-application SDK and `priv`, ran the canonical four-bundle builder. The single
selected Collection public Session case completed in **32.6 seconds**:
**one passed, 34 excluded, zero failures or skips**. It indexed a synthetic
two-cell Word source, checked the positive hit and unmatched same-row companion,
namespace coverage and exact citations, then required both selected and namespace
queries to withhold evidence after the original file changed. The fixture used
its own project, home and workspace, direct Session approval and a provider that
fails if called. It did not request terminal Input, start a listener, use a real
model or access the retained notebook.

Source, original SDK, copied runtime, overlays and runner inventories matched
before and after the applicable work. The bounded owner exited zero, its process
group was empty, and an independent host process check found no matching run
processes. These checks qualify this synthetic source-runtime case only.

| Input or evidence | SHA-256 |
| --- | --- |
| `extensions/knowledge/src/evidence.ex` | `688c2e41878426f444c48b70c400eeaa9ad739ca6d2a7136aa34a980d5df6e9a` |
| Pure fixture | `01b473849a4e4508ccb41bfb3aee7650227b21daff228ff84ec4bd73c8bc9a0c` |
| Public Session fixture | `18787619d47fdd699a16ab53a047485d8f5299026f8c2caecbb56c8055a6201e` |
| Original SDK inventory | `81ba04e00c06b710120dab79b6bafd8bf8597f2bb23b6ebd30f3d3749b25c088` |
| Copied runtime inventory after bundle preparation | `955a8f6bb6c98407f2aa8375651a3ab9f8b58d62643149e64d1866512ac6f2ce` |
| Private source inventory after bundle preparation | `ead815f7a043874ad029f74e5b6275cd68ce8981a5008a7c02a4ec63d987fa5b` |
| Public-case log | `fbc17f7cbebb217b217650257406c2c469a6aa361df884bb30a9c1b339b21af3` |
| Bounded runner packet manifest | `81290d0ab2c34e46380308857c7c1d197ae052ae4e7244f079e23debe265ce4a` |

The complete affected operator Corpus and developer Knowledge Extensions manuals
were reviewed around their current task flows. They describe the indexed path,
hydrated-source limit, citation and coverage meaning alongside the existing
snapshot path. Canonical Elixir 1.18.5/OTP 27 formatting was applied to the changed
Elixir files; the documentation gate is a separate integration check.

This does not qualify an installed package, broader Word fidelity, or semantic
retrieval quality. In particular, it does not repair or reclassify the
[installed no-token-overlap misses](../2026-11-05-word-installed-row-context/index.md).
