Historical scoped review, 2026-10-20. Original report body below is unchanged. Current guidance: [architecture](../../developer/architecture.md). Scope and execution evidence: [implementation record](index.md#give-shared-json-operations-one-owner).

# JSON ownership migration review B

## Identity and scope

Frozen patch: `/tmp/ipse-p27-json-current.patch`, SHA-256 `cdec3f713f4777e73910c795a6b9d4555202d7e1b8a57b11385497d1b5be92fb`. Before inventory: `/tmp/ipse-p27-json-source-before.json`, SHA-256 `f7ca064c9ee5de954b9826bdc111258d73529e388e55ed332e68e22bd19cf3b0`. Base: `bfe8ca5d62b4a270ec26a72e60622d8c08c9847d`. The current `git diff HEAD` matches the frozen patch except for the new, untracked `test/json_test.exs`, which the frozen patch includes.

## Actual checks

- Read the review rubric, design record, grounded migration contract, core implementations, selected callsites, generated child-VM expression, registry host closure, package entry points, current manual changes, and the new JSON tests.
- Searched current source, examples, scripts, tests, private packaged resources, and current manuals for removed `Manifest.decode_json`, `Manifest.sha256`, and `Compaction.digest` calls. Found none. Dated archives retain historical references.
- Checked `Ipse.JSON` calls and aliases for accidental resolution to another `JSON` module, and checked standalone child invocation paths for the host code path.
- Ran one separate Elixir VM against the current `lib/ipse/json.ex`, with the existing Jason build. `digest([])` returned `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945`; iodata SHA-256 returned the expected `abc` hash; escaped duplicate keys returned `{:error, :duplicate_key}`; invalid limit returned `{:error, :invalid_json}`.

## Structural verdict

No findings. The migrated generic bounded decoder, raw hash, and canonical list digest now live in `Ipse.JSON`; the old APIs were removed in the same wave. The moved implementations preserve the old guards, parser path, canonical byte construction, and SHA-256 encoding. The inspected generated expression, host closure, and current manuals use the new owner. I found no reachable correctness, security, ownership, or complexity regression in this bounded review.

This review did not run the full test suite, build a package, execute the precompiled SDK artifacts, or verify model quality or P27 acceptance. The brief reports a 602-outcome synthetic oracle comparison and focused tests; I did not rerun those checks.
