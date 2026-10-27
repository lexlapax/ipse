# Ollama terminal framing repair

This receipt covers the standalone live provider repair, independent of the
unwired Mint transport experiment. The patch is based on commit
`af5c590b35fa08ae639ddbd289b86dceb1b8bcc4`; its only production change rejects
nonempty Ollama NDJSON frames after `done: true`. Empty trailing lines remain
accepted. [Ollama's streaming documentation](https://docs.ollama.com/api/streaming)
shows `done: true` on the final streamed object.

An independent pre-fix loopback diagnostic reproduced a completed response
followed by text and a tool call: the live adapter returned `finishedlate` and
the late tool call. With the guard, later text, tool calls and duplicate terminal
objects cause an error; the final response and its tools are not admitted.
Text emitted before a subsequent framing error can already be visible. Valid
terminal-frame native thinking and tool-call continuation remain intact, and
length-stopped responses remain incomplete. The tests are synthetic, not live
Ollama qualification.

The [standalone patch](ollama-terminal-standalone.patch) has SHA-256
`452d5c97990f0028314709a081b7ca1f70fc652fa2944358fe1718a038a6b00c`;
its [test source](ollama-terminal-standalone-test.exs) has SHA-256
`b6b8a6f4591a676f1b6a162bff99e4b207a4ef66a40ca61952e14f31b97e1b3a`.
The base Ollama source hash is
`3157d2214761ca55b3eab43ab86978710465b1b2c68fe457caf45bcb1cbc28f2`;
the patched source hash is
`d8cc26924317612ad744b590a935805c4b76f639a1bd9287937c9d075ddd0172`.
The patch dry-ran cleanly on a fresh archive of the base. Fresh private graphs
strictly compiled with a copied existing native helper; dependencies emitted
their own upstream warnings during initial compilation.

The initial author and independent runs both reported 99 passing tests, but
their original terminal outputs were not saved as files. The preserved files
below are explicit reruns on the same respective isolated graphs, commands and
seeds; they are not represented as the original logs. Both exclude native
sandbox, macOS sandbox, macOS filesystem and memory-scope tags.

- [Author rerun](ollama-terminal-author-rerun.log): SHA-256
  `e8796b190a5f46b54477cb68a8245e639d4e6c435d30437fcfa59d26dcb92ddb`,
  99 passed, seed 20270226. Command from the private project:
  `MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp mix test --no-compile test/ipse/provider/ollama_terminal_test.exs test/ipse/provider_test.exs test/ipse/provider/conformance_test.exs --seed 20270226 --max-cases 1`.
- [Independent rerun](ollama-terminal-independent-rerun.log): SHA-256
  `6eb3755bc5283b6489bfa7178712b57f72bc43acd979bc6c5c5b0806ac79abec`,
  99 passed, seed 20270227. The independent reviewer applied the exact patch
  and verified both resulting hashes. Command from that private project:
  `MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp mix test --no-compile test/ipse/provider/ollama_terminal_test.exs test/ipse/provider/conformance_test.exs test/ipse/provider/completion_witness_test.exs --seed 20270227 --max-cases 1`.

The operator recovery and developer architecture chapters describe the changed
failure and visible-streaming distinction. Neither the test fixtures nor this
receipt establish Session policy, production kernel qualification, or live
model behavior.
