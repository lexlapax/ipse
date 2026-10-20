Historical scoped review, 2026-10-20. Original report body below is unchanged. Current guidance: [architecture](../../developer/architecture.md). Scope and execution evidence: [implementation record](index.md#give-shared-json-operations-one-owner).

# JSON ownership migration review a

## Reviewed identity

- Base HEAD `bfe8ca5d62b4a270ec26a72e60622d8c08c9847d`, verified locally.
- Frozen patch `/tmp/ipse-p27-json-current.patch`, SHA-256 `cdec3f713f4777e73910c795a6b9d4555202d7e1b8a57b11385497d1b5be92fb`, verified locally.
- Source inventory `/tmp/ipse-p27-json-source-before.json`, SHA-256 `f7ca064c9ee5de954b9826bdc111258d73529e388e55ed332e68e22bd19cf3b0`, verified locally, 462 files.

## Actual checks

Read the supplied design and grounded contract, reviewer prompt, rubric and code-quality lens. Inspected the moved implementations, callers, new JSON tests, Registry identity closure, public SDK source, packaged resource changes, package inclusion, generated child-VM expressions and launch code paths. Read all three edited developer chapters and searched current developer/operator manuals and root instructions for removed APIs. Historical archives were excluded from stale-call conclusions.

A separate Elixir VM ran the retained synthetic before/after oracle using existing `_build/dev` libraries. All 602 outcomes matched, including decoder returns, malformed-input errors, raw hashes and canonical list hashes. No build or Mix test command ran.

A read-only `/tmp` probe compared parsed ASTs for all 119 changed caller files after normalizing exactly the intended API moves, removing alias declarations and source-location metadata. All 119 matched. The three implementation owners were checked directly against their previous implementations. The same probe read all 462 inventoried public files and found no remaining `Compaction.digest`, `Manifest.decode_json` or `Manifest.sha256` references and no `Ipse.JSON` alias shadowing builtin `JSON`. Additional source searches covered imports, captures, alternate aliases and dynamic call patterns. The generated query projection and storage-inventory expressions use the new owner and their launch paths include the Ipse and Jason libraries.

A separate VM inspected existing compiled exports. `Ipse.JSON` exports both bounded-decoder arities, both retained unique-decoder arities, `sha256/1` and `digest/1`. The four removed Manifest/Compaction exports are absent.

## Structural verdict

The scoped move gives the existing JSON owner the generic bounded decoder and hash operations, removes the old implementations and migrates repository callers without compatibility wrappers. Registry already includes `Ipse.JSON` in the ordered host closure. No reachable correctness, security, ownership or complexity defect was found.

This review does not establish full platform runtime checks, packaged execution, precompiled SDK compatibility, model quality or P27 acceptance. The SDK baseline summary was inspected as capture metadata only. No sealed workload, private evaluation, real journal, environment dump or paid/model endpoint was accessed. No repository files were edited.

## Findings

No findings.
