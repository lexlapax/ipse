# Inference transport fixture checks in the CLI

Historical component evidence, 2026-10-27. The uncommitted, unwired inference
transport candidate compiled with the working tree in the isolated build
described in the [P30 component check](../p30-cli-check/README.md). This
[manifest](SHA256SUMS) records selected provider, inference-wire, HTTP, test
and Mix files; it does not freeze every dependency or test support input.

Seven focused files ran under `mix test --no-compile` using seed 20261108 and
`--max-cases 1`: `egress_gate_test.exs`, `mint_embedding_test.exs`,
`mint_owned_dispatch_test.exs`, `mint_owned_test.exs`,
`mint_text_decision_test.exs`, `mint_transport_test.exs` and
`inference_wire_test.exs`. The result was 54 passing tests with the standard
platform tags excluded. Tests used local loopback fixtures; the TLS hostname
failure notice was produced by a negative certificate check. The run explicitly
reported `registered owned dispatch: unsupported filesystem; positive path NOT
RUN`. The result is from the tool transcript, not an archived raw log.

The candidate still requires actual Session wiring, positive protected
dispatch, supported TLS cleanup, policy and source freshness enforcement,
same-process authority review, live routes and full baseline verification. No
live inference, protected dispatch success, platform qualification or P31
acceptance is established by this fixture run.
