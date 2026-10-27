# Native transaction buffered-frame repair

Dated **2026-10-26**. This supersedes the host framing claims in the
[optional-read checkpoint](native-optional-read-component.md), preserving its
original source and runtime manifests. The [native manual](../../../native/README.md#read-the-closed-transaction-protocol)
owns current protocol instructions; the [plan](../../plan.md) owns milestone
status. This component supplies no managed recall, saved absence authority or
Session integration.

## Independent finding and repaired boundary

The independent review of `fe2383350fddc6259c349bc57fd85a28ed243b75` found P2:
a valid `H` reply followed by one extra `H` byte in the same native write returned
`:absent` or data despite an already-buffered incomplete inner frame. A later
mandatory `check` returned unknown. Correct consumers therefore withheld the
result, but the facility had returned success too early. The independent baseline
passed 34 controls; its adversarial run passed six of seven. Its ten terminal
timing attempts all observed `finished: false`; the already-terminal concern was
initially static, not a reproduced claim.

The repair applies to every command. Before sending, the controller requires
empty inner/outer buffers, no reply and no observed terminal frame. A reply must
be the sole queued acknowledgement with no buffered damage. An already observed
terminal frame invalidates nonterminal acknowledgements. Root release alone may
finish an already-buffered `X` prefix following its exact `R` sequence/depth-zero
acknowledgement, under the original deadline. Release completion requires empty
buffers and no remaining replies; any bytes after `X` refuse. Clean replies do
not wait for hypothetical future bytes. Native wire bytes and helper identity
did not change. Final owner check/release before exposing consumer data remains
mandatory.

## Before and after checks

The author copied the independent complete graph without changing its driver.
The before rerun passed five of seven: it reproduced the partial-tail defect and
additionally observed one actual `finished: true`/`:absent` result among ten
terminal timing attempts. This later observation does not alter the independent
review's earlier ten false observations. The original logs remain preserved.

After repair, the unchanged driver passed six of seven. Its sole failure was a
diagnostic `:sys.get_state` call after the repaired controller had already closed
on the malformed frame. A separate companion catches only that diagnostic
`{:noproc, _}` exit. Its strict result assertions are unchanged; the exact diff
is retained. The companion passed all seven. This is an author-run closure using
independent tests, not a fresh independent audit of the repair.

The maintained focused suite passed **43 tests**: the original optional-read 12,
Transaction 20 and protected-helper two, plus nine new framing controls. Actual
native fault controls cover `A/P/G/H/W/D/E/R`, refusal before a later switch,
retained partial writes without replay, and positive lock reacquisition after
cleanup. Source-derived parser fixtures separately cover full/fragmented terminal
frames, extra replies, terminal-plus-tail refusal and valid coalesced/fragmented
outer data. Those pure fixtures are not evidence of actual native timing.

Initial verifier failures are preserved. The new pure parser fixture was first
loaded too late, producing undefined-module compile diagnostics; moving its
source-derived compilation before the test module repaired that harness.
Running the existing separate-VM test from the repository directory then returned
`transaction_unavailable`, including in a quiet isolated rerun. Bounded diagnostics
showed the child resolved `Application.app_dir(:ipse)` to the repository's shared
108c helper while its Runner BEAM required private 6f. Its identity refusal was
correct. Running from the frozen private project's directory repaired only that
verifier binding; no timeout, identity check or test expectation changed. A
diagnostic script's initial syntax typo and a later unquoted `-pa` glob invocation
also failed before verification; both logs are retained.

Actual Elixir **1.18.5** compilation returned no compile/runtime diagnostics;
format checks found zero differences in the two edited Elixir files. The normal
toolchain formatting and documentation link checks also passed. No Rust rebuild,
PTY suite, model call, live account, macOS execution or full source suite was run
for this host-only repair. Earlier Rust evidence belongs to its original source
checkpoint and is not relabelled as a new run.

## Exact source and durable reproduction

Final Transaction source SHA256:
`8c769af647054df7d5cf3d468ed3dfd4666d3130d84d9855e6b77195272ea3ef`.
The framing test SHA256 is
`a70474f8749f9b5c27a0269f2a1c0b6fac47cb3b79b4e08c216580fac7851d4e`.
Native transaction source remains
`4a4d0a52a590e37c7e899f200e2e4ecf24392e768df0035ae0b072f36d54eef2`.
The executed private helper remains
`6f431b5aedde35ecb6f8737e7714dbd197df83c7e8d52e909243e0a39152a55d`;
the shared helper remains
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.

The new [source manifest](native-framing-sources.sha256) and
[runtime manifest](native-framing-runtime.sha256) bind the final private graph,
including every executed application/dependency BEAM and private helper. The
older `author-executed-*` files copied into that graph are historical inherited
manifests, not the final repair binding. A final focused rerun and companion run
use the new manifests, checked before and after execution.

| Binding | SHA256 |
| --- | --- |
| Final runtime manifest, 595 files | `657dda51879eaf2d59d3c6746c3b28b1692467fe1a33a2798387826e6397dd4d` |
| Final project source/test/native manifest, 450 files | `1d090fe86d176ae0791633d4b88a210f8cbfc37bd5b5b4e1bd09e1adf2d6a84a` |
| Unchanged independent driver | `9a01106fc3316dbe4d8d87adc7aa573e7252f6a0edc920804064457b96f2d1da` |
| Diagnostic-only companion | `dfac8c633dbfe1bff4ffed9c8ce71a6d283c2b455c57b273671dce24f75788cb` |
| Exact companion diff | `766c0c89b731dd2e0288a99ce92eb32d58acee7002d4254475e6b1f05b798447` |
| Original-driver before rerun, five/seven | `f0f6e980c01ab203730ff56ba0e1e855e353c5d7ef2fa76f259f5cf16f4864bd` |
| Original-driver after rerun, six/seven | `5d1486f51ffc8809060344d9213fe50b74b04d247c3c296bc5778a316a70e78a` |
| Final manifest-bound maintained 43-test run | `bbef90f47d5d369fbd9ee37c16486d9e2138ecf91c5e6a88d8b58eebc16091d4` |
| Final manifest-bound companion seven-test run | `1a5dc7d9db07152d8bfe235c4e7850c0cfc1812c5fd3105bccea66dffd980e34` |

Durable evidence lives under
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/native-framing-repair`.
It retains complete before/after graphs, diagnostic graph, generated fault
artifacts, logs, recipes and canonical relative-path checksums with original
source-path provenance. Directories are 0700 and all files 0600; helper images
are data. Copy a graph into a new private working directory and chmod only its
working executable copies to 0700. Never alter the preserved evidence in place.
Use the copied private project as the working directory. Recipes that retain
historical absolute paths must be adjusted in the working copy; the independent
driver's `IPSE_OPTIONAL_AUDIT_ROOT` supports relocating its complete graph.

Preservation verified **3,478 payload files**, all original/copy bytes and final
runtime/source manifests before and after copying. Three nonruntime telemetry
source aliases were explicitly recorded and not followed. The payload manifest
`files.sha256` has SHA256
`74bf63d5caca30a71d5bafeb280ea9150165dc00b16e9e9e519f77aa0d2b2eeb`;
the separately hashed `provenance.json` has SHA256
`b23c2661fd170382cc8b8d513d3ede3ceeb2339718f4bb750ba8ed04643b1724`.
The completion receipt `PRESERVATION.txt` has SHA256
`b0f6e3f359a4c85b2b6a878d484c8313211f65ef16b7ab4b757c2e2747464da6`.
The latter two metadata files and the manifest are not recursively included as
payload in their own checksum list.

The cooperative protected-storage/trusted-Core boundary is unchanged. These
checks reject already observed framing damage; they do not predict later bytes
or remote process behavior. A fresh independent review of the repaired host
remains a separate acceptance step.
