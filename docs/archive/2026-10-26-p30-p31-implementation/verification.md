# Fixed-revision verification receipts

Dated **2026-10-26**; historical evidence for the [implementation record](index.md).
Each result belongs to its exact source revision and tested scope. None closes
P30/P31 or establishes model, human or installed-platform qualification by itself.

## Foundation `f9149f5`

An isolated clean local clone, with its own dependency/build directories, passed
`./dev/build.sh`, `mix format --check-formatted`, strict compilation and the full
source suite: **1,805 passed, 36 excluded**, seed recorded in the retained raw
test log. Elapsed suite time was 1,057.9 seconds. Exclusions are the declared native
sandbox, macOS filesystem/sandbox and memory-scope groups, not silently skipped
failures. Expected process-loss/TLS refusal logs are not test failures. The
combined command exited zero. The pre-repair 1,794-test result remains historical
and is not substituted for this final foundation receipt.

Raw local receipts are `/tmp/ipse-foundation-fixed-build.log` and
`/tmp/ipse-foundation-fixed-tests.log`; they are diagnostic temporary files, not
portable permanent artifacts or a source of credentials to publish.

The same clone then passed the credential-free demo under an isolated operator
home, `./dev/package.sh`, and the installed `package` verification scenario using
`examples/memory-corpus.json`. The Linux x86_64/glibc-2.44 archive contains 48
manual documents with zero missing local targets. Installed CLI, standalone checks
and explicit-memory verification passed under a utility-only PATH without a
system development toolchain. This is foundation packaging evidence; it does not
qualify new knowledge, terminal or control workflows that are absent from that
revision. Raw package/installed logs use the same `/tmp/ipse-foundation-fixed-`
prefix.

## Control `241841a`

The combined focused suite passed 62 tests. Native helper tests passed 39 with
one deliberately ignored subprocess entry. The [incremental audit](control-audit.md)
records findings and independent closure. A full local source run in a separate
fixed clone passed **1,819 tests, 36 excluded**, in 1,061.3 seconds. Build, local
formatting, strict compilation, documentation and CI-policy checks also passed.
This receipt covers the control revision; new operator-channel work is not included.

The branch was pushed to origin. Both configured CI platforms built this revision,
then failed formatting under Elixir 1.18: one long `if` in consent eligibility was
formatted differently by local Elixir 1.20. The
[first CI run](https://github.com/lexlapax/ipse/actions/runs/40411106583)
is retained as a failure. Tests/package/installed checks were skipped after that
failure and supply no pass. Commit `512ddf3` rewrites the expression as a multiline
`do` block, preserving semantics; its fourteen focused consent tests pass. Later
CI evidence must name its repaired revision rather than relabeling this run.
