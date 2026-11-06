# Bounded terminal input buffering

Engineering evidence dated 2026-11-06. The [plan](../../plan.md) owns acceptance;
[terminal verification](../../developer/testing.md#check-filesystem-and-terminal-ownership)
owns the contributor procedure. This record does not establish a current macOS
or whole-source baseline.

The macOS native operator job in
[run 42171506872](https://github.com/lexlapax/ipse/actions/runs/42171506872)
passed its build and earlier native checks but timed out in both 1-MiB input
controls. Its probe retained the existing 30-second response bound. The reader
polled, read and echoed one byte at a time. This is a concrete avoidable cost;
the hosted timeout alone does not identify every contributing macOS condition.

The reader now takes at most 4 KiB per read and accumulates escaped echo within
that chunk. It flushes echo before editing keys, EOF and line completion. UTF-8
pending state survives chunk boundaries; backspace removes the same complete
code point, and control-U redraws the current line. Bytes after the first
completed line are discarded. Restoration and the existing input flush still
precede another prompt. The 1-MiB line ceiling and all deadlines remain unchanged.

Owner, guardian, watched-descriptor and deadline checks remain in the input
poll and checked output writes. Work between those checks is bounded by one
input chunk. The output path still checks at most every 4 KiB. An independent
source review accepted these ownership, cancellation and input boundaries.

On Linux, the prior native suite passed 21 tests with one subprocess entry point
ignored, in 10.56 seconds. The changed suite passed 22 with the same ignored
entry point, in 4.32 seconds. The additional test covers pasted Unicode and
editing across a chunk-sized input, plus rejection of a second pasted answer.
These are single development runs, not a cross-platform performance benchmark.
An initial timing launcher failed before executing tests because its external
timing utility was absent; the subsequent Bash-timed runs are retained separately.

The normal offline build passed with 199 host files and four bundles, with its
tracked runtime/build inputs unchanged. Before later document-migration source
work, the resulting compiled host and buffered helper passed nine existing
operator, Session input and leased-deadline tests in 5.8 seconds. Those selected
test inputs and the compiled runtime inventory remained unchanged. They do not
qualify the later migration changes. All controls used synthetic private PTYs
or temporary homes, without a model or the original notebook.

The relevant operator usage and contributor testing manuals were reviewed as
whole documents. Their input limits, fresh-code approvals, cancellation and
independent-platform limitations remain applicable. Hosted macOS, complete source
and installed checks remain open; no timeout or test was weakened to obtain a
passing result.
