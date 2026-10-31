# Installed packaged document setup

2026-10-31, additive verification of source commit
`ad2b25e9af46ee60bb9a8c3ba58d378cc00f2850`. This closes the bounded installed
setup prerequisite in the [source record](documents-setup-20261031.md), not full
P31D1/P31F or original-goal acceptance. Current instructions belong to the
[Corpus manual](../../operator/corpus.md#set-up-packaged-word-support) and
[developer exercise](../../developer/knowledge-extensions.md#follow-packaged-document-selection).

## Exact package and controls

The isolated clean source checkout built the standard PDF-enabled archive:

```text
ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz
SHA256 904d7716b71bfccb52342329dacd8bee972bf2ae708fad4a0f31f7532a3c78a1
```

Build log: `/tmp/ipse-package-ad2b25e-build.log`. Bundled documentation reports
52 documents, no missing targets and exact source ref `ad2b25e`. The previous
`fd69375` archive/checksum remains separately preserved under
`/tmp/ipse-package-fd69375-original-evidence`.

The general `installed package` verifier passed private setup, doctor, demo,
MCP/delegation/extensions, native helpers/ownership/locks, historical-result and
resume controls, and the synthetic 100-record/100-query Memory fixture. Its final
report has `passed: true`, unchanged inventories and no system toolchain on
runtime PATH. Log `/tmp/ipse-package-ad2b25e-verify.log`, SHA256
`385ba280fcba45457483e900231deb923d61d9dbd3fe3f0f671e0105a5bd6086`.

The reusable [document verifier](../../../dev/verification/documents_setup_installed.exs)
validates the archive checksum, extracts into fresh private state and invokes
the actual packaged CLI/native input through the existing committed fixture.
It requires exactly the shipped State Corpus, Collection Corpus and Knowledge
catalog entries. Both document imports come from that extracted catalog; no
externally built Corpus artifact is supplied.

Six executed cases all exited zero:

- State and Collection: exact native setup, preserved provider/profile/role,
  ordinary write approvals, workspace Word acquisition, exact Unicode quotation
  and original binary hash, Saved reconstruction, identical evidence after
  close/resume, reviewed disable and changed-configuration resume refusal.
- Cancel, stale code, changed configuration during review and piped input:
  refused without artifact import, saved trust/selection or notes-control state.

Collection explicitly builds its lexical index before namespace query. Source
and stored text remain distinct from any main-model request; no model dispatch
occurred. Notes-control state remains absent throughout both positive journeys.
Domain code stays in its worker; Corpus is not loaded into the host VM.

The [structured receipt](documents-setup-installed-20261031.json) records exact
package/build/fixture identity and six fixture-log hashes. Final output root:
`/tmp/ipse-documents-setup-installed-final-20261031`; report SHA256
`fe2d7775d72c010235d6c235c0e4f37940d2a989fcbbf1d1a875197e16a5a164`.
All extracted file contents/links remain unchanged after the six cases.

## Harness and qualification limits

Preparation uses the developer's Elixir/OTP, Rust and `tar`, copies the existing
precompiled ExUnit library and compiles the synthetic PTY before runtime launch.
Runtime code origin is checked against the extracted package. Runtime PATH has
only utility symlinks plus package-owned ERTS tools, including its bundled
`erlc`; system Elixir/Mix/Rust/Cargo are unavailable. This is synthetic PTY
automation with a test-library overlay, not human terminal use or a machine
without any developer installation.

The first local harness attempt incorrectly required `erlc` to be entirely
absent, although the release launcher prepends its own bundled ERTS directory.
That launch assertion failed before setup. Its files/log remain under
`/tmp/ipse-documents-setup-installed-20261031`; the corrected fresh run and final
reusable verifier require any observed compiler to be package-owned.
No runtime policy, capability or test expectation was weakened to make a
document effect succeed.

Real-Word rendered fidelity, representative retrieval quality, full capacity,
rebuild/GC/migration peaks, optional local-model setup and complete lifecycle
qualification remain open. No account access, model calls, downloads or release
publication ran. The complete regression pass, adversarial audit and original
reviewer handoff remain required.
