# Experimental Mint text request-contract follow-up

2026-10-27. The experimental Mint text path remains unwired. This local change
is not a live model, protected egress, native cleanup, platform or P30/P31 pass.
See [the earlier investigation](mint-owned-experiment.md) for the outstanding
current-root, permission, wire-binding and ownership boundaries.

The normal `Ipse.Provider.complete/4` entry validates response schema selection,
provider request policy, reasoning and output-token limits before dispatch.
The experimental Mint text entry had performed only part of that validation.
It now applies those checks before calling the owned transport. The existing
response-contract function is shared with the host-derived wire prototype so
that the normal and experimental paths use the same schema rule.

Synthetic tests assert that invalid reasoning, out-of-range output limits,
invalid extension schema and conflicting schema selections refuse before
connection or admission. The normal provider, experimental text/decision and
wire-binding suites passed 21 tests (seed 20270407) in the existing dirty working
tree using loopback fixtures. They made no external inference requests. This is
not a clean whole-source build or an independent audit. The earlier test run
also passed 13 cases before the response-contract function was shared.

Current SHA-256 values:

- `lib/ipse/provider.ex`: `580837572c01fc82487098fed45b4ebf72b9686c791abd275094071529049f02`
- `lib/ipse/provider/mint_text.ex`: `6f26bb089656346224b01f7b6649e6ffcbb86a0000cb5c0c6f99ee981769891e`
- `lib/ipse/session/inference_wire.ex`: `342be6fbec5c99578c621098691135599b62fde1170e2122292bec4a8ae28690`
- `test/ipse/provider/mint_text_decision_test.exs`: `c0ea37bea34732569e6497ca44d496fc3ca68e63df0e3400504de4ef3aa2bc01`

The Mint and wire files and their tests were pre-existing untracked experiments;
the provider file was tracked and clean before this continuation. All remain
uncommitted. Wire equality still does not bind phase, response parsing limits,
current policy or source roots, and no lock or current authority is held through
a production inference send. Do not wire this path into Session until those
contracts and cleanup behavior are implemented and independently reviewed.

## Subsequent execution-fact experiment

The unwired prototype now compares a closed set of execution facts as well as
wire target/body hashes: phase, timeout, response-byte ceiling, embedding
dimensions and dimension mode, and decision expected model. The experimental
text caller must supply an explicit phase; compaction and helper phases reject
tool declarations. Host preparation and experimental adapters build their
facts separately from their selected runtime and serialized request. Tests
show identical bytes can accompany different phases, limits, dimensions or
expected models and that those facts no longer compare equal. Invalid phase
and helper-tool inputs refuse before connection.

The focused inference/provider run passed 44 tests, seed 20270409, in the dirty
working tree with synthetic loopback fixtures. The registered owned-dispatch
positive path explicitly did not run because the filesystem is unsupported.
The TLS hostname-mismatch notice belongs to a negative fixture. No live model or
external endpoint was used. This comparison does not authenticate the claimed
phase or runtime, bind request/service identity, validate current source roots or
policy, hold authority through send, or prove cleanup. The prototype remains
unwired and is not a substitute for those barriers or their adversarial review.
The corrected full regression runs on its earlier frozen tree and does not cover
this change.

New untracked `lib/ipse/provider/inference_facts.ex` hashes to
`fc1405f90d0e7102efe7c5b4f9361b780ea3d48b4a64554adfd30421571b6501`.
The updated experimental `lib/ipse/session/inference_wire.ex` hashes to
`658bb1efe6b560fe9085c967d36ca5c3fed8af0a7ee38773689f4c2148ea64fa`;
`mint_buffered.ex`, `mint_text.ex`, `mint_embedding.ex`, and `mint_decision.ex`
hash respectively to `528d23cb74c8bc372cf682404520e7aecd4437b0738506f7a09771af311e7502`,
`2c6c2794f24159449f3fc8a1b558bab7c82e32d47e9d89f7bd54d08cdfc3b83a`,
`4e365aca72fbcbfd792e26f74d3cba99418a40c406bf5624ca32d3b8c91a20aa`, and
`40444ec9826154364f4130b722e423792a056eed3e7c50cae30d7c16ca82dd02`.
The updated wire, embedding and text/decision test hashes are respectively
`0524e72ba8c1bd23ff2a4201d381655c65ecfd11b479d1e205f6767a194bd1b1`,
`27552b0ad62649c1b6f2e8f8cdf99a26481110c9102433d943ffc773526d440f`, and
`0609046ac2e214816ba60554438d61b3f1abb09888c74a66f9c46c2a0b9b6c43`.

A later isolated graph was reconstructed from `668e6a3` with the explicitly
selected provider/transport experiments, `mix.exs`, wire code and their tests;
it excluded the unrelated knowledge, CLI and capacity work. Its private index
tree was `2182bf5d96f84f91bf0227ad92082501cf2c54ff`, and tracked bytes matched
the index after the run. The copied production helper SHA-256 was
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`.
Eight synthetic suites passed 63 tests with seed 20270419; the log
`_build/inference-facts-validation-20261027.log` hashes to
`acfdfb0a3b6293263d3caf9ff37a9bcb5d434d87f6bded43583fa9e2db8917a4`.
Formatting and a forced strict compile of 150 project files passed. The run
includes a deliberately passing reproduction of the old gate's TLS-wait race;
it is evidence of the defect, not a security pass. The registered protected
positive path explicitly did not run. No live model request was made. Current
root/consent and send-time authority, TLS cleanup, platform qualification and
full independent review remain open.

## Pre-connection refusal classification

The experimental buffered adapter previously pattern-matched execution facts
before starting the owned request. An oversized body or inconsistent bounds
could raise there and be reported by its outer adapter as unknown even though no
connection or admission occurred. It now returns a known unstarted refusal for
those fact failures. A synthetic listener test verifies oversized body and
mismatched timeout refuse before connection or admission.

The updated isolated source tree is
`74ee4f4c6df3a84b3f3cfb799521383b89724ed4`. The eight selected suites passed
64 tests, seed 20270421. The retained log
`_build/inference-facts-validation-20261027-r2.log` hashes to
`fec9d130210d8bf2b36491b79ce30a9692439d20187cc4095b494a1831b4c02b`.
It still includes the deliberately reproduced old gate race, and the registered
protected positive path did not run. Updated buffered source and test hashes are
`ee57e72c2b38df731428b8a1579ba90ec552c21132d3d65a76257a80fb9d6764` and
`f586478cf9da05728121d820b4d546462a5d0ab09578102f12be1a6661f0b949`.
No live model request or protected storage operation was performed.
