# Private management display deadline repair — 2026-10-29

This narrowly repairs the two source findings in the [independent review](management-full-facts-display-independent-review.md) of the frozen [private full-facts candidate](management-full-facts-display.md). The original evidence remains unchanged. No public output, management, input or Review gate is opened.

A successful `{:closed, {:ok, receipt}}` is now sampled against the original operation wall and monotonic deadlines only after the nested Collection/Consent/Identity callbacks have returned and released, the management Writer and guard have closed, and the tracked Resources scope has finished. The monotonic clock is sampled again after the wall check. If either budget has elapsed at that final admission, the result becomes `{:unknown, :management_display_unconfirmed}`; existing refusal and unknown results retain their original classifications. These are discrete checks, not an atomic promise against a clock change or process scheduling after the final sample.

The native R/H/L/C status-frame writer now checks monotonic time immediately before and after readiness and after the bounded write. Once the initial request supplies wall expiry, H/L/C also check that wall expiry at those boundaries; R is emitted before wall expiry is supplied and is monotonic-bounded only. The existing D writer retains its own matching wall/monotonic checks. The reader-command paths also recheck monotonic time after polling, and activation checks it again before signaling the native writer. An already admitted syscall can finish or queue bytes after a concurrent loss; the caller must still classify a late, partial or lost response as unknown.

The [repair evidence](management-display-deadline-repair/) retains exact final source, production/test-hook helpers, two fixture binaries, full runtime inventory, relevant BEAMs, logs and test-only late-return instrumentation. Focused controls passed:

- One pure ExUnit control checks timely completion, elapsed wall, elapsed monotonic, invalid deadlines and preservation of an earlier unknown outcome.
- A real signed-target PTY display completed native closure and all caller cleanup, then a test-only source interposition substituted an already elapsed wall value immediately before the final classifier. The actual result was unknown. This tests the post-cleanup classification; it does not change the host clock or prove a real forward clock jump.
- Separate real native PTY controls stopped the guardian after close-status readiness and resumed it after the original monotonic or wall deadline. Neither emitted C or a successful close. A test-hook-only derivative with the post-readiness frame check removed emitted late C in the same monotonic control and failed as intended.
- The affected native 65,536-byte positive and the final signed-target PTY positive passed. Earlier owner-loss controls remain scoped to their earlier helper cohort; they were not rerun here.

The native v1 fixture predates the separate wall case and is retained; the v2 fixture adds that case without changing the monotonic control. The first final-classifier BEAM and late-return instrumented copy preceded the added second monotonic sample; their logs and instrumented copy are retained, but an exact uninstrumented whole-source snapshot of that intermediate was not kept. The final compile, pure control, actual late-return and final signed-target positive use the final source. The full prior selected-artifact and loss evidence remains in the original candidate archive. No model, aggregate, production Review input, live effect or non-Linux backend was exercised.

Reproduction uses the retained source tar and a new private directory per native fixture run:

```sh
rustc --edition=2021 -D warnings -O native/ipse-runner.rs -o /tmp/ipse-management-deadline-v1-helper
rustc --edition=2021 -D warnings -O --cfg ipse_terminal_display_test_hook native/ipse-runner.rs -o /tmp/ipse-management-deadline-v1-hook-helper
rustc --edition=2021 -D warnings -O dev/fixtures/terminal_lease_probe.rs -o /tmp/ipse-management-deadline-v2-fixture
rustc --edition=2021 -D warnings -O --cfg ipse_terminal_display_test_hook NEGATIVE_SOURCE/native/ipse-runner.rs -o /tmp/ipse-management-status-negative-helper
/tmp/ipse-management-deadline-v2-fixture PRIVATE_DIR /tmp/ipse-management-deadline-v1-hook-helper display-management-close-mono
/tmp/ipse-management-deadline-v2-fixture PRIVATE_DIR /tmp/ipse-management-deadline-v1-hook-helper display-management-close-wall
/tmp/ipse-management-deadline-v2-fixture PRIVATE_DIR /tmp/ipse-management-status-negative-helper display-management-close-mono
```

The final `_build/management-deadline-v1-sol-20261029/lib` graph copied the original candidate's final graph, replaced its own helper, recompiled the exact Runner pin and Management, then recompiled Management after the second monotonic sample. The captured compile diagnostics are empty. PTY/Unix descriptor controls ran with authorized isolated access. Actual input, fresh effect-side fact revalidation, one-use permit consumption and complete management acceptance remain open.
