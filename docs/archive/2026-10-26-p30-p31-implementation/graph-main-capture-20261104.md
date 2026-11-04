# Main-tool Graph capture over existing State sources

Dated **2026-11-04**. Historical implementation and verification record, not a
current-behavior manual. The [Graph procedure](../../operator/graph.md#capture-through-the-main-model)
and [knowledge training](../../developer/knowledge-extensions.md#capture-relationships-through-the-main-tool-path)
own current guidance; [P31G](../../plan.md#p31-usable-knowledge-and-prompt-assistance)
owns acceptance. This is one stored-source increment, not completion of P31G.

## Change and source identity

Against source checkpoint `6adb7aca314ac1afa5aa53c3b31813ab0dfa7f21`, Graph
adds the model-visible `capture` tool over an already stored, currently eligible
State source. The ordinary main provider supplies one to eight relationships
with exact support quotes, polarity, inferred flag and optional validity times.
Graph independently checks source ID/generation, unique full-source quote
occurrences and at most two derived chunks, constructs existing Evidence
citations/facts, then reuses projection claim/explicit adapter/commit CAS.

Only `graph.ex` and tests change. Existing capabilities, core, native protocols,
limits and dependencies remain unchanged. Capture does not call a secondary
model; the separate optional extraction command/presets retain their contracts.
The tool is not a new `/ext` command. Ordinary outer-tool and State-write
approvals remain separate.

| Identity | SHA-256 |
| --- | --- |
| Graph source preimage | `4735ac1cdf8bb04eda40ae577e32106c1e1927cb87ba46003d0df31f27852840` |
| Private qualified Graph source, before main formatting | `b3aa83e098daa03249e758ea8fd44a2aa70de56150ad7636df60ff4a8fa2f636` |
| Original four-file source/test export | `6a57f08bf6a261594c4e5b592e7bace5d01fe31eb275cc50fd0b94f66fc6ebbe` |
| Applyable export, new-file metadata repaired only | `9b669c38cf6c28a108eb3458551ccd4ee6a0bed2492f0484434ab0b031a702ed` |
| Exact built Graph artifact | `262a29cdfcb6b08a41dfb5ac4cf733d792f69e5c6864ca39c076d28e41199856` |
| Complete private SDK manifest | `1d87efb35401d580abcda914c59e46d0728e6f704523b470db5f36b0fc211423` |
| Private SDK native helper | `ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b` |

The private host closure contains 16 applications and 241 Ipse modules; it is
the existing frozen SDK, not a new current-main build. The Graph artifact was
built from the candidate source. The later main integration is identified
separately below; its source hashes do not replace these private qualification
identities.

## Checks actually completed

- Complete Graph artifact build passed without warnings. Its manifest is
  **9,928 bytes**, with **26 modules**, **333 unique resolved imports** and no
  unresolved imports or new dependencies. Decode/import and the capture export
  checks pass; capabilities are unchanged and the explicit preset has no
  `host.model` capability.
- **Ten isolated protocol tests passed.** They cover the closed model-visible
  schema, exact citation derivation, forged/ambiguous quotes, source-generation
  mismatch and replacement interposition, expiry, polarity/conflict/inferred/time
  handling, source replacement/forgetting, retained prior facts and deduplication,
  invalid profiles/bounds, and denied/unknown mutation stop.
- **One fresh four-case actual StateSession cohort passed.** An in-process
  scripted main provider selected the real tool, with actual ordinary outer-tool
  and State-write approvals. The positive published relationship was queried
  with its exact quote and source generation. Wrong generation and denied State
  publication left every State file hash unchanged.
- The fourth case killed its fresh Session at the incoming successful first
  State.put result, before the Session journaled that result. The actual effect
  may have written a projection draft/root claim; this is not a claim of final
  fact commitment. Strict Saved reconstruction and actual fresh idle resume
  added no effect intent and replayed no write.
- State deltas were one modified file for positive publication, zero for wrong
  generation, zero for denial and one for the interrupted claim. All input,
  full-private-runtime and runtime-pathset postchecks returned zero.

The actual cohort used no Input channel, HTTP request or live model service.
Scripted provider callbacks are integration fixtures, not extraction-quality
results or independent human use. No failed fixture or unknown operation was
resumed. Private transcripts, State/journal bodies and synthetic approval codes
remain outside Git.

## Retained first failures

The first protocol run passed five of seven tests. Two expectations incorrectly
required an empty claims array after invalidation; existing publication supplies
an `open`/`semantic_support_unassessed` placeholder. Only those expectations were
corrected. The later ten-test candidate adds bounded lifecycle controls.

The first actual completed the source seed with five known State writes, then
stopped at the ordinary outer main-tool approval. Its command-only fixture had
accepted only State approvals. The journal contains no Graph tool invocation;
strict Saved reconstruction passes. A relative-preimage/absolute-postimage
pathset comparison also reported a difference, while exact normalized pathsets
and all runtime hashes matched. The fresh second cohort fixed those fixture
boundaries only, with unchanged product and artifact. Both fixture roots and
the original failed results remain preserved.

The original four-file export also needed new-file metadata repaired before
`git apply --check`: the three new tests now use `/dev/null` and mode 100644.
No product or test body changed. The raw export remains retained separately.
An initial artifact-reporting script mistook the decoded map for the imported
artifact struct; its failed log remains retained and the artifact did not change.

The [safe packet](graph-main-capture-20261104/) contains code, scoped review,
public counts/hashes and failure dispositions. Its original public export
manifest has SHA-256
`f44024a2dca93772631fcdb914f2c59d1539d393de3c029ec65c92f043254bf0`;
the archive's complete inventory also includes the metadata-corrected patch.

## Main integration

The four-file product/test patch was applied to the main worktree at the source
checkpoint above, followed by `mix format` on those four files. Their normalized
Elixir syntax trees match the private qualified sources; the formatted source
hashes are recorded in [integrated-source.sha256](graph-main-capture-20261104/integrated-source.sha256).
The normal main test entry points then ran together:

```sh
mix test --no-compile --no-deps-check --seed 0 --max-cases 1 \
  test/extensions/knowledge/graph_capture_test.exs \
  test/extensions/knowledge/graph_population_test.exs
```

The command exited zero: **three outer tests passed in 23.9 seconds**. The
capture wrapper builds its artifact from current formatted main source and
requires its ten protocol and four actual Session cases to pass. Those nested
counts are not added to the three-test aggregate. See the retained
[main output](graph-main-capture-20261104/integrated-focused.log) and
[exit status](graph-main-capture-20261104/integrated-focused.status).
No live model, external HTTP service or operator Input channel was used.
The full combined final regression remains open; this focused result does not
alter any prior full-suite failure.

## Remaining scope and manual review

Graph remains optional and experimental. This path consumes the retained State
source; a copied receipt establishes no current authority over an original
Session/file. Managed-note-derived State writes retain the host refusal.
Reversible entity aliases/merges, managed graph publication/current-use,
cross-store correction/suppression, C1b graph capacity, installed capture and
real extraction quality remain open. Traversal's case-insensitive node matching
is not verified identity resolution. Earlier failed P30 simultaneous-delivery
cohorts retain their original dispositions.

The complete operator Graph and developer knowledge-extension chapters were
reviewed together. The operator flow now distinguishes direct explicit commands,
main-tool capture over a stored source and separately selected model extraction;
the explicit fact-authoring examples remain. Developer guidance follows the
ordinary main tool through source validation, projection CAS, result/unknown
recovery and tests. Audience entry points link to those owners rather than a
new feature-status manual.

The unmodified canonical documentation checker passes on the private candidate
tree: 1,171 Markdown files, 9,624 local links and manual/archive rules, zero
errors. Both new capture JSON examples validate against the actual tool schema;
their worker continuation proposes only a State scan before any host execution.
The retained explicit-authoring example executes as a pure helper and its output
validates against the extract command schema. All 22 shell blocks across the two
chapters parse, CLI option grammar checks pass, and the configuration generator
writes a disabled Graph instance with exact trust. These checks start no Session,
Input channel or service. The explicit helper now names its already-built SDK
path, avoiding an unavailable-module warning without changing its output.

An earlier documentation-check invocation used the wrong working directory and
an overbroad scratch-tree inventory; its result is not a documentation verdict.
The corrected private tree contains tracked public inputs plus the explicit
candidate files, and the checker runs from that tree without changing its code.
That private candidate check did not change the original manuals or Git index.
Main promotion subsequently applied the reviewed manuals and entry points; the
integrated check above is distinct from the private candidate receipt.
The unmodified checker also passes on a clean main-public-input mirror after
integration: **1,171 Markdown files, 9,627 local links, zero errors**. The mirror
contains tracked public inputs and this explicit candidate only; unrelated
private diagnostic trees are excluded from its input set.
