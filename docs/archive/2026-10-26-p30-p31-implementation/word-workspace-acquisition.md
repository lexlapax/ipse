# Bounded workspace Word acquisition through native reads

Dated **2026-10-28**, branch `codex/p30-p31`, continuing the
[explicit-payload bridge](word-source-bridge.md). This is implementation and
synthetic Session evidence, not full P31F, installed Word or retrieval-quality
qualification. The [plan](../../plan.md) owns status and the
[Corpus manual](../../operator/corpus.md) owns operator procedures.

## Explicit host boundary

The existing `read` tool accepts optional `encoding: "base64"`, `max_bytes`
1..4096 and an optional lowercase `expected_sha256`. Binary mode rejects line
options; text mode retains its original line behavior and rejects binary-only
options without the explicit encoding. Native text output and its extension
4096-byte result ceiling are unchanged. Only an explicit binary read permits
an extension result up to 8192 bytes, still within the existing SDK limits.

Binary mode uses the existing workspace/path checks. It refuses symlink paths,
nonregular or multiply linked files, excess bytes and an expected-hash mismatch.
It compares path/descriptor identity and size/protection/timestamps, performs two
matching complete bounded reads, then rechecks the path and resource scope.
Stat comparisons use POSIX timestamps on both APIs. Its JSON text envelope is:

```text
version=1, encoding="base64", path, byte_count, sha256, data, complete=true
```

The validator decodes exact bytes and rechecks count, hash, requested path,
complete flag and expected hash. It never returns a lossy/truncated binary read
as complete. These are observed read bytes, not an atomic filesystem snapshot
or protection against coherent hostile same-user rewriting.

Corpus's existing source command adds `read_document` with closed arguments:

```text
source_id, generation, expected_revision, title, path, expected_sha256,
uri, observed_at_ms, event_at_ms, expires_at_ms
```

Only new explicitly selected `state-documents` and `mcp-documents` presets grant
`host.tools`; all existing presets retain their capability lists. The tool family
continues to use its ordinary host checks and mutation approvals. Native reads
are ordinary read-authorized actions (`not_required`), not knowledge consent or
an exception for workspace/shell mutations. Source State writes still require
their existing approvals. The worker never opens a path itself.

An initial generation-1/revision-0 acquisition can use `expected_sha256: null`.
The first actual host read computes the hash; no shell/manual hash is mandatory.
Refresh requires a concrete expected hash, which the ordinary native read tool
can return to the main model/user. The extension extracts the acquired bytes,
then requests a second host read pinned to that exact hash before proposing any
source write. Each request goes through the existing current Session/action/
artifact/workspace/resource admission. A changed file, failed read or interrupted
owner stops the continuation. The new descriptor records the actual final
read operation ID and relative path, not a worker-supplied acquisition receipt.

## Transport representation repaired by the actual Session test

The prior pure State fixture accepted a deeply nested receipt that the actual
State transport correctly refused. The repair preserves core JSON limits:
Store retains a version-3 `document_extraction` storage envelope containing
canonical JSON `document` bytes and their `sha256`. The body is the original
version-1 supplied receipt or version-2 workspace receipt (which includes its
acquisition descriptor). Evidence checks the envelope/digest/canonical bytes,
validates the typed body and source spans, then derives the same version-2
public document citation and partial-coverage gaps. Raw v1/v2 source receipt
validation remains available; no stored citation silently upgrades its origin.

Store now checks the actual State result wrapper's JSON depth before proposing
any immutable page/root write. It no longer mistakes a naked-value fit for a
transportable value. Metadata-only root/draft checks still cannot provide source
text or citations; full hydrated content validation remains mandatory.

## Focused checks

The host check compiled Tools and external-call adapters against existing SDK
beams into a private overlay, with no compiler diagnostics. The
[binary selection](word-workspace-acquisition/binary-46733.log) passed **10 tests**,
seed 46733, max-cases 1, exit 0. Log SHA-256:
`11410638d8bd5e9ee7f9b3d7829dedcdf4210e265afe4c0d0f61199845c6d4be`.

The completed [section selection](word-workspace-acquisition/section-46739.log)
passed **17 tests**, seed 46739, max-cases 1, in 14.3 seconds, exit 0:

- Existing native tool behavior plus exact binary/hash/bound/alias/option checks.
- Actual extension ToolAction acceptance above the legacy text result limit,
  forged-envelope refusal and unchanged ordinary text-result refusal.
- Freshly built `state-documents`/`state-lexical` artifacts and actual Session
  read→extract→hash-recheck→approved State CAS→cited query.
- Old preset refusal before any tool acquisition and unchanged grants.
- A file changed at the actual second-read admission, refusing before writes.
- Owner killed after actual read but before result commit: one read intent,
  no result/write, confirmed cleanup, and byte-identical idle resume despite
  subsequent file changes.
- The preceding explicit-payload ingestion/revision/forget/partial/CAS controls.

Section log SHA-256:
`96a0929864340e5a834e5dbc27524471604bb43a66d3a416c390a1c1b625022e`.

The separate [profile selection](word-workspace-acquisition/profiles-46740.log)
passed **7 tests**, seed 46740, max-cases 1, in 2.7 seconds, exit 0. It verifies
both explicit document presets add exactly `host.tools` relative to their lexical
counterparts, accept their corresponding store configuration, and leave all
eight old Corpus preset capability lists without `host.tools`.

After that selection, the extension also carries its two native read calls into
Store's existing other-action allowance instead of starting its write plan at
zero. Those internal counters are not accepted in public source arguments.
Only the [four acquisition Session cases](word-workspace-acquisition/budget-46741.log)
were rerun for that change: **4 passed**, seed 46741, max-cases 1, 4.0 seconds,
exit 0. Log SHA-256:
`a9ead99acef202f1987f7cd3d528e80473dfd90be69ffe11a01c65e6d60ed819`.

The Session graph was `_build/operator-assertion-sol`, using its previously
recorded private diagnostic native helper override. The changed host modules
were supplied from `/tmp/doc-binary-host-overlay-46735/ebin`; the rest of the
graph was unchanged. Fresh artifacts compiled current extension sources against
that graph's SDK. This is not a final frozen whole-source baseline or production
native-profile qualification. No model requests, live services, downloads or
release publication ran. All retained test homes/documents were synthetic.

Earlier failures remain relevant: the first binary check exposed UTC-versus-local
stat comparison; an initial launcher overlay name confused `Application.app_dir`
and failed setup; after that was fixed, the real Session exposed the transport
depth failure described above. A first file-mutation fixture did not match the
actual OTP debug event and was corrected. These failed checks are not passes.

## Scope and next work

The native binary acquisition limit is **4096 original bytes**. The earlier
source-put limits still apply: 8192 extracted UTF-8 bytes, 32 segments/chunks,
2048 bytes of typed metadata body and bounded storage/SDK envelopes. The new
storage envelope is bounded separately at 3072 bytes and still must fit the
existing root/value limits. Nothing is trimmed to fit.

This closes the supplied-payload-only gap for this bounded component. It does
not qualify normal large Word documents. Larger binary acquisition, staged
document text/locator pages, C1b capacity, file change/deletion tracking and
current-use invalidation remain required. Stored evidence is an acquired
snapshot; this section does not continuously assert that its workspace file is
unchanged. Guided installed setup/management, automatic intake, real Word
fidelity, frozen retrieval quality, full source/package/platform qualification,
manual review and final adversarial acceptance remain open.

Modified host files: `lib/ipse/tools.ex` and only the ToolAction portion of
`lib/ipse/extension/external_calls.ex`. Extension changes are in `profiles.ex`,
`spec.exs`, `corpus.ex`, `evidence.ex` and `store.ex`; focused tests are in
`tools_test.exs`, new `tool_action_binary_test.exs`, new
`document_acquisition_session_test.exs` and the preceding ingestion test. The
parent package owns shared manuals/plan/index updates and final commit/push.
No root/provider/Session/lineage file was edited by this work package.
