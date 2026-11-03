# Traced retained-cohort worker handoff — 2026-11-03

This is a distinct read-only synthetic diagnostic of the retained 2,000-note
cohort, not a replay of the [failed full-day turn](integrated-full-day-failure-20261103.md)
or the [earlier retained-cohort probe](retained-probe-20261103.md). It used a
fresh Session and a different prompt, the cohort's original runtime at commit
`b10df4a556c097b686eecba1267e3d6425f0f8bc`, and its actual retained source
owners. The test-only tracer was supplied separately. This is not an integrated
day, semantic-quality evaluation or release qualification.

## Observation

The child process exited 1 after its diagnostic request or completion deadline.
Its new Session journal records eight delivered Worker inputs and a ninth input
intent without a result; no inference dispatch was recorded. That ninth input
is unconfirmed and must not be automatically replayed. No model call or paid
service was used.

The redacted trace retained 504 events, reported no dropped events and left two
outer Worker calls unmatched. For the ninth input, two successful
`ManagedUse.observe/5` spans in the same tracked caller took 2.141458 and
2.456134 seconds. `SessionSource.with_sources/5` then returned unknown before
any traced Writer, Session or source imports. A Worker timeout-message handler
was observed during that handoff. Its redacted arguments and return do not
establish that the message matched this pending input or caused the unknown
outcome. Tracing itself can alter timing. These observations identify a concrete
performance hypothesis for a fresh test; they do not establish the cause of
either earlier failure or a general latency bound.

## Preservation and evidence

Before this diagnostic, all 97 entries in the original and forensic-backup
manifest matched. The post-run file comparison reported no changed or missing
pre-existing cohort files, four unchanged external seed-audit files, and exactly two added
files for the new Session: its journal and retained lock. Before/after state
reports had identical SHA-256
`042652b346b52a4f62364c364fc0a36ddc865b60e01aa8b2aec664f506290fb8`.
The separate verification command exited 0; its log nevertheless contains
compile-time warnings about the separately loaded tracer module. Those warnings
are not a warnings-as-errors pass. Two focused tracer tests passed in a separate
`b6d667a` build; that build is not a rebuild of the tested `b10df4a` runtime.

The evidence manifest, SHA-256
`93699b8ff298809df634bfeaeeb6414432bb77e0628268625c7fcf8ad3df8ab2`,
was checked after the run and all 18 entries matched. It identifies the exact
driver, tracer, focused-test log, run log, intent, trace, verifier output,
state comparisons and new Session journal. The trace summary SHA-256 is
`b5fe3216df7186754faccf8c269f2376584706bd9a76722292d9c649f187f460`;
the post-run file comparison SHA-256 is
`58eebde9f2c88e6155f548c56fd3b575687a1c2de51a37d99821acfa7000b785`.
The manifest was retained at
`.recall-worker-b6.xG61xIua/retained-trace-evidence.sha256`; its driver snapshot
is `.recall-worker-b6.xG61xIua/scratch/retained-trace/native_notes_retained_probe.ex`.
The synthetic trace
and comparison records were retained under
`/tmp/ipse-retained-readonly-traced-b10-20261103-01`. These temporary locations
may be cleaned up; hashes do not replace the underlying evidence.
