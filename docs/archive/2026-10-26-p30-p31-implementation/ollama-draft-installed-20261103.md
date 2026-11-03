# Installed Ollama draft acceptance and cancellation — 2026-11-03

This synthetic Linux check exercised the packaged Ipse runtime's no-tool Ollama
draft acceptance, cancellation and idle-reopen paths. It used release eval with
the existing native PTY and synthetic provider fixtures. It did not run the
public installed chat command, contact a live Ollama model or establish human use
or model quality.

The source was reported exported from commit
f44f2506de2de47a31c84f2b1b7617236c4d340f, with an isolated fixture assertion
and new verifier added before building. The source inventory has 8,639
regular files and one recorded symlink; the full export-to-commit comparison is
not archived. The supplied package commit label does not prove source provenance.
The exact changed-file [preimages](ollama-draft-installed-20261103/preimages.sha256),
[outputs](ollama-draft-installed-20261103/outputs.sha256) and
[patch](ollama-draft-installed-20261103/task-promotion.patch) permit a focused
reconstruction. The developer manual change was made after the runtime test.

The default PDF-enabled package was built offline. Its archive SHA-256 was
6c674c55981b85b8d11a2e093f948f0c20434817d365dee5703824fb03bc8c0c;
its checksum sidecar SHA-256 was
178e436df45bc26eb3aea59d385d81d06b16b970c555c79b55991fc8f8f57dc5.
The archive itself is not included here. The package's documentation check
reported 52 documents and no missing local targets. Dependency compilation
emitted warnings; the project build used warnings-as-errors. The test-environment
project compile also passed, with dependency warnings recorded in its log.

The [first source-control attempt](ollama-draft-installed-20261103/source-prod-failure.txt)
failed in the production build with invalid_provider_endpoint before the selected
test completed. Its log does not identify the loop iteration. Source inspection
supports the inference that the synthetic ChatGPT loopback mode was refused:
production disables those test-only endpoints. Its complete log is retained only
in private scratch. In the intended test environment, the same selected native
acceptance test passed, with eight other tests excluded; it ran basic, synthetic
ChatGPT-compatible and synthetic Ollama modes. The added acceptance assertion
compares four classes of journal intent across idle reopen before a later prompt.

The installed [result metadata](ollama-draft-installed-20261103/results.jsonl)
reports both native terminal scenarios passed and neither terminal output
contained the synthetic draft-thinking canary. Acceptance then checked the
fixture's three provider requests; cancellation checked four. On idle reopen,
acceptance compared request-admission, inference-dispatch and two extension
intent classes; cancellation compared request-admission events. Both later
continuations checked withdrawal of draft-only input and thinking. This does not
prove all possible effects or untested provider continuations.

The verifier checked that Session, draft, Ollama, Saved, terminal and Runner
BEAMs came from the extracted package, that the packaged helper was present, and
that release inventory, archive and named source-fixture hashes were unchanged
on normal completion. Helper presence and Runner provenance alone do not prove
which helper executed. Abrupt termination can bypass those postchecks and must
remain unknown. Terminal transcripts and provider-request captures contain
synthetic private content and are not included; their recorded hashes and result
booleans do not independently reproduce their contents.

HOME stayed inherited; explicit synthetic IPSE_HOME, temporary paths, and
fixture workspaces were used. No OS-level home-access trace was taken. The
[evidence manifest](ollama-draft-installed-20261103/evidence.sha256) covers the
retained patch, manifests, launchers, safe logs and metadata. Runtime manifest
entries refer to the original isolated build tree, which is not archived. The
full integrated suite and broader installed/human qualification remain separate.
