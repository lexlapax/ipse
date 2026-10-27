# Native profile after the interrupted SDK verification

Recorded 2026-10-27. After the application was restarted, the temporary test
graphs were absent and the host reported `7.2.11-arch1-1`. The earlier native
evidence in this archive was collected on `7.2.10-arch1-1`; it does not qualify
the new kernel. The protected-storage profile in this source admits only
`7.2.10` and `7.2.10-*`, so refusing native write admission on the new kernel
is its intended fail-closed behavior. Neither the kernel allowlist nor the
shared public helper was modified to make tests pass.

## Reconstructed test graph

The checkout was based on commit `cd8913a61878a3e959d8cb0627a65ec56debc5bf`
with seven uncommitted SDK and reference files listed below. A private graph at
`/tmp/ipse-recovered-20261027` copied the current source and the previously
preserved dependency build. Its private helper was copied as data from the
preserved actual Normalizer integration graph, then made executable only in
the new graph; its SHA-256 was
`d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`.
The shared helper was only hashed, with value
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
The graph used Elixir 1.20.4, OTP 29, `MIX_ENV=test`, private application
build outputs, and the host's tmpfs and Btrfs mounts. Strict compilation of
134 source files passed; see [compile output](kernel-7.2.11/compile.log).

| Source in the reconstructed graph | SHA-256 |
| --- | --- |
| `lib/ipse/extension/managed_collection_call.ex` | `4505870c4a2353a9afdbc4dab3fdf6080f8c51315df202d5717137aa99c630ea` |
| `lib/ipse/session/managed_reference.ex` | `a7f7e01eebd87154ec3bcd717bbcc0910ac915b9ac0877419b493671c641fb15` |
| `extensions/knowledge/src/knowledge.ex` | `4ec407941fa9d2bd11a3a9126e9e7f6b4a1cf28bfdf3d7e76557a4541a7bee4b` |
| `test/ipse/session/managed_reference_test.exs` | `33bf56a50c3d1889e9d759c0179ffda32d0cb3e9e0cd79a6ff2e06decbcc7352` |
| `test/ipse/extension/managed_collection_call_test.exs` | `5201bdaae1191714b6ca5c7b4b958f42d47ec418920bd521a53f4e44bd2248` |
| `test/ipse/extension/managed_collection_call_session_test.exs` | `e37d0bd4a007e0bc624dd9eb20301afa201a94b7d4b21e3bebe62736bb2c5f70` |
| `test/extensions/knowledge/knowledge_session_test.exs` | `4ddb1ec84cb472e6a102797064be2deb60ad9cc7e44a02435c8bd86bc89236ce` |

The graph's 15-suite combined run used seed 20261214 and max-cases 2. It
finished with **133/172 passed and 39 failed**. All 39 top-level failures
contained the native filesystem-unsupported refusal, including a PTY child;
the full [original output](kernel-7.2.11/combined-tests.log.gz) is retained in
lossless gzip form, preserving terminal control bytes.
This is a failed test run, not a passing native regression suite. The earlier
interrupted broad run had no final summary and is not counted as a pass.

A separately selected pure run of managed-reference tests and the explicit SDK
version/reservation control used seed 20261215 and max-cases 1: **26 passed,
5 excluded**. Its [output](kernel-7.2.11/pure-tests.log) does not qualify
native publication or a full SDK integration. The seven changed SDK/reference
files also passed `mix format --check-formatted` in the private graph.

| Output | SHA-256 |
| --- | --- |
| Combined test output | `34cd8c136c54c09aa7a86f04187bafa03b5bf245ae41ba88d0a63fabe843d8b1` |
| Compressed combined output | `2f302acbee8d491cc6a04fdbf04f37f8b7c4a90fa2af51b811e0bda9d64c835d` |
| Pure test output | `2d58ef316166e7619f6994ea2461c7778fc1060d4dca13f4ef45b9d8557f3376` |
| Strict compile output | `ca1b9db5e63797031532138c8bf0dee3265d319811b9d7f17ebc411651d80a28` |

## Open work

The uncommitted SDK-v3 consumer and root-observation dependency remain under
development. Their native integration needs a supported host or a separately
reviewed and qualified profile for the new kernel. No capacity workload was
started after the restart; inspect its original plan and pending-operation
markers before starting or resuming one. Current recall, complete Session
dependency propagation and the final inference egress barrier remain open.
Human and macOS journeys remain prepared rather than executed. The
[plan](../../plan.md) retains the full P30/P31 acceptance criteria.
