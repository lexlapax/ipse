# Packaged lexical document selection

2026-10-31, implementation after `18f4d44`. This is dated source-runtime
evidence, not full P31D1/P31F acceptance. Current procedures belong to
[Corpus setup](../../operator/corpus.md#set-up-packaged-word-support) and
[configuration training](../../developer/knowledge-extensions.md#follow-packaged-document-selection).

## Delivery change

The previous package contained only the native notes bundle. Earlier installed
Word proofs explicitly loaded an externally built Corpus artifact. The build now
ships three separately compiled inert artifacts: native Knowledge, Corpus
state-documents and Corpus collection-documents. No bundle is enabled by presence.

`documents setup --profile state` previews an ordinary operator selection.
Collection requires explicit `--profile collection --scope folder|repository`.
Only a fresh native challenge on `--write` imports the selected artifact and saves
the exact capability/trust/options proposal. Collection also explicitly admits or
revalidates the selected identity. Provider profiles and unrelated configuration
are preserved. The writer checks the actual installed Registry composition before
saving setup. Disable does not require successful admission of unrelated enabled
artifacts, retains trust/data, and changes new-session selection only.

The shared existing private writer now uses a retained native `CONFIG.lock` around
exact-byte checks, optional inert import/admission, backup and atomic publication.
Provider setup uses the same lock. This coordinates Ipse setup writers, not hostile
directory replacement or arbitrary editors. Failed save can leave an inert
artifact or explicitly admitted identity, without a saved extension selection.
Running sessions keep their pins; ordinary resume still needs original
configuration bytes. No protected notes policy or secondary inference is created.

## Source verification

- `./dev/build.sh`: passed, 177 host modules and all three bundle builds.
  `/tmp/ipse-documents-setup-build-final-20261031.log`.
- Format check, warnings-as-errors compile, five-file setup/bundles/notes/private
  file selection: **40 passed, 31.5 seconds**.
  `/tmp/ipse-documents-setup-tests-final2-20261031.log`.
- Final strengthened document file: **6 passed, 19.2 seconds**, with actual
  `Config.runtime` admission, same cited evidence after close/resume, changed-file
  configuration resume refusal after disabling, and absent real notes-control
  state before/after the journey.
  `/tmp/ipse-documents-setup-runtime-final-20261031.log`.
- Credential-free demo passed. Native helper remains SHA256
  `c6768890455697de64284463092806fa2e30305a7ea7b8e6ee60c625f3f0ccff`.
- Whole affected operator/developer chapters and navigation reviewed. Corpus now
  starts with installed setup, then teaches independent source-built alternatives.
  The existing Collection procedure now includes its missing explicit namespace
  lexical-index build. Link check before this record: 968 Markdown files,
  8083 local links, zero errors.

Native journeys are synthetic PTY automation, not human terminal attestation.
Both profiles acquire a synthetic Unicode Word file through the actual workspace
read path, approve ordinary writes separately, retrieve its exact quotation and
original binary hash, reconstruct Saved records, close/resume and disable.
Collection builds its namespace index explicitly before querying.
Cancel, stale code, pipe and configuration change during review refuse without
import/trust/selection. An attempted write can retain its empty lock inode.
The privacy control checks digest-only disabling and replacement collision review.

The first test attempt retained a stale lock-file expectation and old CLI error
substring; a later attempt exposed the omitted Collection index step. Their logs
remain in `/tmp/ipse-documents-setup-tests-20261031.log` and
`/tmp/ipse-documents-setup-tests-v2-20261031.log`. The latter is a documented
workflow prerequisite, not evidence that ingestion creates a namespace index.

## Remaining acceptance

An extracted-package journey with these bundled artifacts is still required;
the earlier external-artifact installed receipts do not qualify this change.
Full capacity, rebuild peaks, migration, rendered real-Word fidelity and retrieval
quality remain separate. No model calls, model downloads or account access ran.
The full original goal remains active, including lifecycle/quality qualification,
the complete regression pass, adversarial audit and reviewer handoff.

## Additive installed follow-up

The subsequent [installed receipt](documents-setup-installed-20261031.md) qualifies
the six bounded synthetic journeys against the exact package built from
`ad2b25e`. It replaces the extracted-package prerequisite above only within that
scope; it does not close the other acceptance gaps.
