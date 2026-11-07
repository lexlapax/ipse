# Focused State document and signed-draft Session checks — 2026-11-06

This dated record covers synthetic controls, not P31 acceptance. The immutable
input was `_build/verification/integration-snapshot-20261106-06/source`,
assembled from base `8304dd4c5357b0786b27540713d3c868f39cb0f1`, patch SHA-256
`4b458b4ec0161fb51c64710a39c63676043730127edf987ebc3581fc4dcec9cc`, and
11 allowlisted new files; it is not a clean build of that commit. The separate
run checkout was `_build/verification/p31-focused-run-20261106-04/source`.
At the time of these Session runs, after excluding generated `_build`, bundles
and native runner, its source matched the frozen source except for the reviewed
test-helper retention overlay. A later test-wrapper-only correction is recorded
in [the wrapper repair](completed-backup-wrapper-repair-20261106.md).
The modified helper SHA-256 is
`81bcee8cee9a68fde81d4cae0a41658bd440c59d9210b45e0ec466eb6d4144e7`; the
frozen helper is `ff289233f6c6d16840c6e8653c6dab0750ffd129293614a5b140b4365114f9fb`.
The overlay retains the operator-discovery fixture home.

The run used isolated offline dependency compilation, `sh dev/build-native.sh`,
`mix compile --warnings-as-errors`, and
`mix run --no-start --no-compile --no-deps-check dev/build-bundles.exs`.
The operator recorded exit 0 for each bounded process; separate exit receipt
files were not created. The dependency compile emitted an `elixir_uuid`
`use Bitwise` deprecation warning; the host warnings-as-errors compile generated
the application. The build log reports four bundles. The generated runner hash
is `5884a3141282c8d6ed98363a5f3f1f225fc2195921ae7597ee73a03d342555e6`.
The bundled State Corpus manifest and Corpus BEAM hashes are respectively
`d7783022d9d1264a77f834902209946dd52a9bf1faf06bb83116909703f63aaf` and
`0784de62b8b253b7b44a07930ea0c300d73a972907ca577cb7cb91d6ec5ee324`.
The Collection manifest and Corpus BEAM hashes are respectively
`421163ca248563e4447f39c7226c2da7f0e1657c35911a8c36b9c1bca121f97a` and
`425dfd4d14c4c4af0288d610f8f3e563c8b516cdb2ce21547ae31950dbce1152`.
The two State tests each built and imported their own State artifact; these
bundle hashes alone are not evidence that those tests used the bundled artifact.

All three commands used `mix test --no-compile --no-deps-check`, the retained
fixture flags `IPSE_TEST_WORD_KEEP=1` and `IPSE_KEEP_DRAFT_FIXTURE=1`, and
bounded process groups. The operator recorded exit 0 for each; full logs are
retained in `_build/verification/p31-focused-run-20261106-04/`:

- `test/extensions/knowledge/document_acquisition_session_test.exs:813`: one
  passed, 36 excluded; unrelated State root insertion during the workspace check
  conflicts with the selected generation. Log `state-generation-session.log`,
  SHA-256 `ff8c5ed7e3dfb1a7b55a5d7c183e5b731309a2b18edf6b33b7791dbcbda4417b`.
- The same file at `:863`: one passed, 36 excluded; current query expiry during
  the workspace check refuses while an explicit historical selection remains
  usable. Log `state-expiry-session.log`, SHA-256
  `8360e5d080d903a40833603b069a3916c92bbf46832813843abd30d4c123650b`.
- `test/ipse/session/draft_vertical_test.exs --only anthropic_signed_draft_carryover`:
  one passed, 21 excluded; synthetic Session/Saved cancellation and acceptance
  cover signed-thinking continuation removal. Log `anthropic-signed-session.log`,
  SHA-256 `9517bdd395be67a1134d54a46ca523a996557728c9f017bb6dd6a55d459c695a`.
  Acceptance is a synthetic journal fixture, not a real terminal acceptance or a
  live Anthropic service result.

The document Session test source hash was
`7c3e9ad06c7b570c9e634e0f44fc9e7ea389400d55c6b39370989fd39d60c660`; the
signed-draft test source hash was
`24aa8b0975eb56c08b2cdf413415b9bc0a63e8c8a55a5b5056c5d468744e37bd`.
Fixture roots remain under `/tmp/ipse-snapshot04-session-check-20261106-01/tmp`:
two `ipse-document-acquisition-*` directories, one `ipse-draft-vertical-*`
directory, and the retained `ipse-test-operator-302` home. These controls do
not establish installed-package verification, real Word quality, MCP/Collection
race coverage, live inference, or the broader current-source and P31 requirements.
