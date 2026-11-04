# Synthetic listener lifecycle controls, 2026-11-03

This record concerns a synthetic loopback fixture used by the integrated notes
workload. It does not qualify a populated day, notes recall, quality, resource
peaks, or P31. The [full-cohort failed day](integrated-full-day-failure-20261103.md)
and its unresolved turn remain preserved and are not replayed. The
[plan](../../plan.md) owns current status.

The prior fixture began a linked listener before the Session could dispatch
inference. Its 30-second accept timeout could terminate the turn owner while
the runner was still waiting. The repaired fixture gives the listener ownership
of its socket in an unlinked, owner-monitored task and reports fixture failures
to the runner. Explicit shutdown and owner death close the listener. The
runner's 120-second wait for a request, its 30-second completion wait, and
product/provider deadlines remain unchanged. The fixture's 30-second request
read allowance is now a **total** deadline for reading one request, rather than
a fresh 30 seconds for each receive; this is a stricter fixture bound.

The integrated runners create turn intent and in-flight markers before
`Session.prompt`, leave the in-flight marker in place on a failure, and
remove it after a successful result. A typed listener failure or monitored task
death stops the runner with a do-not-replay direction. This marker behavior is
source review, not a newly executed failure-and-reopen control.

The focused offline ExUnit control used real loopback sockets and passed all
six tests in 30.5 seconds, with zero failures and no skipped tests. It covered
one observed request and listener closure; malformed-request reporting without
owner death; monitored, unlinked listener death; explicit shutdown; normal owner
death during a partial request; and survival past the former 30-second idle
accept deadline. Its source and the referenced `Ipse.JSON` and `Jason` BEAM
files passed pre/post SHA-256 checks. The control was standalone, using the
already-built modules; a raw execution log was not retained.

An independent, fresh synthetic real-Session control passed one loopback
request and one successful turn, then reopened the idle Session without a
second dispatch. It used the exact fixture hash below; source, runtime, helper,
and entry checks passed before and after execution. Its synthetic Session had
no protected notes, and the request correctly reported
`reference_observed=false`. This establishes fixture/Session compatibility,
not populated recall or a successful full-day run.

The following SHA-256 values bind the reviewed sources and synthetic controls:

| Item | SHA-256 |
| --- | --- |
| `dev/fixtures/synthetic_ollama.exs` | `84dd9da5b470cf9775e66487a6c85f43c911760b16dcb6b6104ecb2a4aa38879` |
| `dev/knowledge/native_notes_integrated.ex` | `3fa298f77bd91be336145911f5703098a2073cdd612bf77dc65d6d4796abdf17` |
| `dev/knowledge/native_notes_integrated_full.ex` | `ceec5fde9ca063d4bf7ef42806fc1e3071e47835ab969ef8e2dc51e216057ce2` |
| `test/dev/knowledge/synthetic_ollama_lifecycle_test.exs` | `c85e702a88ea30d2cd2e778f6621770e344049c334f712e2297835f67f3fe2bc` |
| Standalone lifecycle test entry | `92651d757a2837456bf9eeb605208cffd5cc7554b285bf69fcc245d94cf22fe2` |
| Real-Session control entry | `a14bce5f1d018b5c62b44dadd9ae97ed471d7ec3104c1645a9d0db7c0e024043` |
| Real-Session control launcher | `0054b10922a6f74bf0f9546bcba735e13211518c6bdb0a68424d7500fdfd7e0a` |
| Real-Session pre-checksum manifest | `954aa3e06c50c791ec02d8e5ecae9c0b83ac7d4e43880f36ab12bf73fcb0a7bb` |
| Real-Session exit and post-check status | `49a2b7566a1347aca8976a38251cd3bcc0c7fd74e6f2d6184a6eae77f900f18d` |

The independent control's [sanitized entries, launcher, status and smoke log](workload-listener-20261103/)
are preserved with a [checksum manifest](workload-listener-20261103/SHA256SUMS).
The archived launcher retains historical temporary paths and is not a portable
command. The retained full-cohort evidence is unchanged. A separate diagnostic with a longer
fixture idle allowance still failed before inference dispatch, so the listener
repair is not established as the cause or cure of the unresolved recall
failure.
