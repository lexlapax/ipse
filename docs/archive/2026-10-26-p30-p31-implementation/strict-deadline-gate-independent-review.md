# Independent review of the strict-deadline containment gate

2026-10-29. This scoped review covers the frozen
[Collection deadline interposition and interim gate](strict-deadline-interposition.md),
not a complete P31 safety review. The reviewer verified all 38 manifest entries,
209 runtime BEAM hashes and the helper hash. The recorded ptrace fixture stops
the matched helper at `renameat` after its userspace clock check and verifies a
late root switch. The retained diagnostic executable itself was not located for
independent hash verification; its provenance needs follow-up.

The inspected Collection entry points refuse the selected deadline-bearing
publication paths, and the trusted low-level `Transaction.switch_before` API
explicitly disclaims a strict guarantee. The gate is containment, not an
enforceable timed rename or P31 completion.

The review identified additional boundaries requiring follow-up:

- Native reviewed forgetting remains enabled. Its one-use Review permit has a
  30-second lifetime, but the forget normalization does not carry a deadline to
  the final switch. A stopped-after-consume control is needed to determine
  whether deletion can happen after permit expiry before an unknown result.
- The separate State backend checks `write_before_ms` before `File.rename`.
  State-backed document drafts may have the same scheduling gap; this backend
  is not covered by the Collection gate.
- Document-stage deadline refusals are normalized to a generic store refusal,
  so the caller does not receive the specific temporary fence diagnosis.
- A trusted nested `DocumentStage` call can overwrite an earlier inherited
  deadline with a later value or nil. No current worker-accessible nesting path
  was established, but the host API needs minimum-preserving or explicit
  reentry-refusal behavior.

The milestone ledger was corrected during this review to say the actual
interposition was already reproduced. The other findings remain open until
their own repairs and focused controls are complete. No broad tests were rerun.
