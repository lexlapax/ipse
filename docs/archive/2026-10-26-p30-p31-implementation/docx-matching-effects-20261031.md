# Matching DOCX alternate style graphs

Dated 2026-10-31. Bounded parser compatibility evidence, not P31F completion.
Current procedures are in [Corpus](../../operator/corpus.md); implementation and
limits are taught in the [Knowledge guide](../../developer/knowledge-extensions.md#inspect-the-extraction-boundary).
The [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance) retains the
remaining Word, storage and quality gates.

## Original-byte exploration

Three existing small documents from Microsoft's MIT-licensed
[Open XML SDK repository](https://github.com/dotnet/Open-XML-SDK) were selected
from a public inventory before inspecting extraction results. They are development
inputs, not independent held-out quality material or a rendered-Word comparison.
No upstream code or SDK was installed or executed. The files remain temporary
data outside this repository. The [machine record](docx-matching-effects-20261031.json)
retains the exact source revision, file paths, Git blob and SHA256 hashes, license
hash, both outcomes, owning source hashes and independent artifact proof reports.

All three original files refused recipe v12 with
`unsupported_docx_style_relationship`. Each contains both a normal styles part
and `stylesWithEffects.xml`. Microsoft's
[style-part documentation](https://learn.microsoft.com/en-us/office/open-xml/word/how-to-extract-styles-from-a-word-processing-document)
describes the two parts used for version round-tripping; the
[SDK part contract](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.packaging.styleswitheffectspart?view=openxml-3.0.1)
identifies the alternate styles part. Merely ignoring that part would leave its
visibility semantics unchecked.

Direct parsing through the existing bounded style parser found equal graphs in
the border fixture. The table and comment fixtures contain additional definitions
in the primary part. Original input bytes were not edited to make them pass.

## Narrow admitted subset

Recipe **v13** admits only the exact internal Microsoft relationship, canonical
part target, exact content type and both present, linked style parts. Both parts
use the existing parser and aggregate expansion bound. Their parsed graphs must
agree on all style IDs/types, inheritance/link relationships, defaults and hidden
flags. Presentation properties outside that graph may differ. Missing or
ambiguous authority, differing graphs, entities and unsupported effect namespaces
still refuse before body text is returned. No external target is fetched.

The original border fixture now yields its exact one-character body and
paragraph-one locator. It remains **partial**, with ordinary unsupported-content,
omitted-part and unexamined-relationship warnings. The other two original files
still refuse with `unsupported_docx_style_visibility`; their differing graphs
were not merged or ignored. One readable document is not broad Word fidelity.

Existing results are not silently migrated. DOCX source/citation bindings use
`ipse-documents-v13`; text, Markdown and PDF remain v2. No new dependency, helper
protocol, source permission or managed-output gate changes.

## Verification and retained failures

The new positive fixture first failed against v12, 0/1 passed. The first changed
run reached its assertions but failed the warning guard on a redundant type
check; that guard was repaired. The first adversarial run passed 1/2 cases and
failed only an incorrect expected expansion-error name, corrected to the existing
`:expansion_limit`. These logs remain under `/tmp/ipse-docx-matching-effects-*.log`.

Final checks:

- Extraction/fidelity/native parser files: **40 passed**, 41.3 seconds, including
  a separately built artifact with matching and mismatched table style graphs.
- Parser-stage/PDF files: **1 passed, 4 skipped**; skips establish no backend
  support. The separate source/installed proofs below did exercise the available
  native PDF backend.
- Native acquisition and ingestion: **22 passed**, 64.2 seconds. After removing
  constant-branch fixture warnings, the complete acquisition file passed again:
  **16 passed**, 62.7 seconds, warning-free. Both ordinary and dual-style tables
  use actual workspace reads, explicit storage approvals, exact Unicode quotes,
  original hashes, v13 cell locators, Saved reconstruction and confirmed close,
  without inference. The unchanged six ingestion cases belong to the first run.
- Verifier driver: **34 passed**, 84.9 seconds.
- Independently built v13 Corpus artifact: **7 source and 7 installed checks
  passed** with unchanged inventories/private homes and no system development
  toolchain on runtime PATH. These include matching-style extraction, differing
  graph refusal, the native PDF backend and dependency notices. The host is the
  exact previously verified `e25d235` archive; its bundled catalog is not claimed
  to contain this later artifact.
- Root build, warning-free compile and credential-free demo passed; native helper
  SHA256 remains `c6768890455697de64284463092806fa2e30305a7ea7b8e6ee60c625f3f0ccff`.

The affected operator/developer chapters retain their whole-document editorial
review and integrate the new subset and explicit reacquisition rule in their
existing extraction workflow. Format, link and final scoped source checks are
recorded with the committed increment. Logs use `/tmp/ipse-docx-effects-*20261031.log`;
original documents/results and probes are in `/tmp/ipse-word-public-20261031`.
The failed whole-source baseline, real Word rendering, complete source-change
tracking, large ingestion and model-quality qualification remain open.
